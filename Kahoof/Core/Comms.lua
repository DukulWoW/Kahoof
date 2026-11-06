-- Kahoof Core/Comms.lua: how game messages leave and arrive (S5a loopback, S8 network)
-- architecture.md section 7, networking.md. Two ways out:
--   LOOPBACK  a message handed to the local receiver on the next frame.
--             Practice runs the host and the player in one client this way,
--             with the real wire messages (Dukul, 2026-11-02: "Real wire
--             messages"). A whisper to yourself goes this way too (ALL-74).
--   NETWORK   C_ChatInfo.SendAddonMessage on prefix KAHOOF, through ONE send
--             queue. The server allows each prefix a burst of 10 messages, then
--             1 a second (measured on Forever 1.60.1: paced at 1/s nothing is
--             ever throttled); a throttled send is not sent at all, so trying
--             it again can never deliver it twice. Nothing else in Kahoof
--             calls SendAddonMessage.
--
-- Sending: a message over 255 bytes goes as parts (Protocol.SplitParts). Every
-- send result is read by its enum name: throttled = wait for the refill and
-- try again; offline (a whisper) = WhisperBounced; anything else (lockdown,
-- not in a group, ...) = SendFailed and every queued message of that session
-- is dropped (Dukul, 2026-11-06: stale once the lockdown lifts; what the game
-- does about it is S10). A queued IN is replaced by a newer one of the same
-- session: only the latest bitmap matters, and the host's budget is small.
--
-- Arriving (CHAT_MSG_ADDON): secret values dropped, the sender made a key
-- (KHF.SenderKey), our own broadcast echo dropped, parts put together (capped:
-- MAX_PARTS per message, OPEN_PER_SENDER / OPEN_MAX open at once, dropped
-- PART_TTL s after the last part came), then decoded like a loopback message.
-- A and VER count only as whispers. Arrivals go by type: A to the host
-- (Core/Host.lua), HI / VER to Core/VersionCheck.lua, everything else to the
-- player (Core/Player.lua); each checks the session id and the sender.
--
-- A whisper to an offline player is not refused (Success on Forever); the
-- sign is the system line "No player named 'X' is currently playing." For a
-- name we whispered in the last BOUNCE_TIME s it means WhisperBounced, and the
-- line is kept out of the chat frame.
--
--   Comms.ToAudience(s, type, data)       host -> everyone in the session (s.audience)
--   Comms.ToHost(s, type, data)           player -> the host (a whisper)
--   Comms.ToPlayer(s, key, type, data)    host -> one player (a whisper: DENY, SYNC)
--   Comms.SendTo(dest, type, sid, data)   no session: dest = { audience = "group" | "guild" }
--                                         or { whisper = key } -> true | false, kind
--   Comms.Receive(str, sender, channel)   one whole message (channel nil = loopback)
--   Comms.Backlog()                       messages waiting in the queue (S10: "Sending...")
--   Comms.Reset()                         drops the queue and every half-received message
--
-- Bus messages (Core/Events.lua): SendFailed (sid, kind), WhisperBounced (key).
-- Kahoof_Dev sees every message through KHF.Dev.CommsTap(info) (nil without it).

local _, KHF = ...
local Protocol, Channels = KHF.Protocol, KHF.Channels

local Comms = {}
KHF.Comms = Comms

Comms.PREFIX = "KAHOOF"
local BURST           = 10    -- messages the server lets a prefix send at once...
local REGEN           = 1     -- ...then this many a second
local TICK            = 0.1   -- the queue's ticker, running only while something waits
local MAX_TRIES       = 30    -- throttled tries on one message before the send fails
local PART_TTL        = 30    -- seconds a half-received message waits for its next part
local OPEN_PER_SENDER = 4     -- messages being put together from one sender
local OPEN_MAX        = 40    -- ... from everyone
local BOUNCE_TIME     = 5     -- seconds after a whisper that "No player named" is ours

local HOST_BOUND    = { A = true }
local VERSION_BOUND = { HI = true, VER = true }
local WHISPER_ONLY  = { A = true, VER = true }
local REPLACE       = { IN = true }

-- A value Midnight hands over as a secret cannot be compared: drop it
local function Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Tap(way, info)
    local dev = KHF.Dev
    if dev and dev.CommsTap then
        info.way = way
        pcall(dev.CommsTap, info)
    end
end

--------------------------------------------------------------------------------
-- ARRIVING: one whole message
--------------------------------------------------------------------------------
local function Route(msg)
    if HOST_BOUND[msg.type] then
        KHF.Host.OnMessage(msg)
    elseif VERSION_BOUND[msg.type] then
        KHF.VersionCheck.OnMessage(msg)
    else
        KHF.Player.OnMessage(msg)
    end
end

-- parts: how many parts it came in (nil = one)
function Comms.Receive(str, sender, channel, parts)
    local msg, why = Protocol.Decode(str)
    if msg and channel and WHISPER_ONLY[msg.type] and channel ~= "WHISPER" then
        msg, why = nil, "not a whisper"
    end
    local info = { who = sender, chan = channel or "loopback", bytes = #tostring(str or ""), total = parts }
    if not msg then
        info.why = why
        Tap("drop", info)
        KHF:Debug("Dropped a message from " .. tostring(sender) .. ": " .. tostring(why))
        return
    end
    msg.sender, msg.channel = sender, channel
    info.type, info.sid, info.msg = msg.type, msg.sid, msg
    Tap("in", info)
    Route(msg)
end

-- Next frame, in send order (C_Timer callbacks due at the same time run in
-- the order they were made); the sender is you
local function Loopback(str, msgType, sid)
    local me = KHF.UnitKey("player")
    Tap("out", { type = msgType, sid = sid, chan = "loopback", who = me, bytes = #str })
    C_Timer.After(0, function() Comms.Receive(str, me, nil) end)
end

--------------------------------------------------------------------------------
-- THE SEND QUEUE
--------------------------------------------------------------------------------
local queue = {}            -- { str, dest, sid, type, n, total, tries }, in send order
local ticker
local tokens, refillAt = BURST, 0
local nextMid = 0           -- our message ids for parts, 1-999
local whispered = {}        -- target key -> { t = GetTime() of the last whisper, bounced }

function Comms.Backlog() return #queue end

local function DropWhere(test)
    for i = #queue, 1, -1 do
        if test(queue[i]) then table.remove(queue, i) end
    end
end

local function Fail(sid, kind)
    DropWhere(function(it) return it.sid == sid end)
    KHF:Debug("Send failed (" .. tostring(kind) .. "), session " .. tostring(sid))
    Tap("fail", { sid = sid, why = kind })
    KHF.SendMessage("SendFailed", sid, kind)
end

local function Bounce(target)
    local w = whispered[target]
    if w then w.bounced = true end
    DropWhere(function(it) return it.dest.whisper == target end)
    Tap("bounce", { who = target, chan = "WHISPER" })
    KHF.SendMessage("WhisperBounced", target)
end

-- SendAddonMessage returns an Enum.SendAddonMessageResult (BNB's
-- ClassifyResult): read by name, so a code added later needs no change here
local RESULT_NAMES
local function ResultName(res)
    if type(res) ~= "number" then return tostring(res) end
    if not RESULT_NAMES then
        RESULT_NAMES = {}
        local enum = Enum and Enum.SendAddonMessageResult
        if type(enum) == "table" then
            for k, v in pairs(enum) do RESULT_NAMES[v] = tostring(k) end
        end
    end
    return RESULT_NAMES[res] or tostring(res)
end

-- -> "ok" | "throttle" | "lockdown" | "offline" | "nogroup" | another enum name
local function Classify(res)
    if res == nil or res == true or res == 0 then return "ok" end
    if res == false then return "throttle" end
    local name = ResultName(res):lower()
    if name == "success" then return "ok" end
    if name:find("throttle", 1, true) then return "throttle" end
    if name:find("lockdown", 1, true) then return "lockdown" end
    if name:find("offline", 1, true) then return "offline" end
    if name:find("notin", 1, true) then return "nogroup" end   -- NotInGroup, NotInGuild
    if res == 3 or res == 8 then return "throttle" end           -- no enum: the known codes
    return name
end

local function NoteWhisper(target)
    local now = GetTime()
    for k, w in pairs(whispered) do
        if now - w.t > BOUNCE_TIME then whispered[k] = nil end
    end
    local w = whispered[target]
    if w then w.t = now else whispered[target] = { t = now } end
end

-- One queued message out; the channel is picked now, not when it was queued
local function SendOne(it)
    local chan, target
    if it.dest.whisper then
        chan, target = "WHISPER", it.dest.whisper
    else
        chan = Channels.ForAudience(it.dest.audience)
        if not chan then return "nogroup" end
    end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, Comms.PREFIX, it.str, chan, target)
    local kind = ok and Classify(res) or "error"
    Tap("out", { type = it.type, sid = it.sid, chan = chan, who = target, bytes = #it.str,
                 part = it.n, total = it.total, result = ok and ResultName(res) or tostring(res) })
    if kind == "ok" and target then NoteWhisper(target) end
    return kind
end

local function SendTick()
    local now = GetTime()
    tokens = math.min(BURST, tokens + (now - refillAt) * REGEN)
    refillAt = now
    -- (a hair under 1: ten 0.1 s refills add up to 0.99999...)
    while tokens >= 0.999 and queue[1] do
        local it = queue[1]
        local kind = SendOne(it)
        if kind == "ok" then
            table.remove(queue, 1)
            tokens = tokens - 1
        elseif kind == "throttle" then
            -- the server's allowance is lower than we counted: wait for a refill
            tokens = 0
            it.tries = it.tries + 1
            if it.tries > MAX_TRIES then Fail(it.sid, "throttle") end
            break
        elseif kind == "offline" and it.dest.whisper then
            Bounce(it.dest.whisper)
        else
            Fail(it.sid, kind)
        end
        if queue[1] == it then table.remove(queue, 1) end   -- never stuck on one
    end
    if not queue[1] and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Kick()
    if ticker then return end
    SendTick()   -- the refill for the idle time, and what the allowance takes now
    if queue[1] and not ticker then ticker = C_Timer.NewTicker(TICK, SendTick) end
end

local function SameDest(a, b)
    return a.whisper == b.whisper and a.audience == b.audience
end

function Comms.SendTo(dest, msgType, sid, data)
    local can, why = Channels.CanSend()
    if not can then
        Fail(sid, why)
        return false, why
    end
    local str = Protocol.Encode(msgType, sid, data)
    if dest.whisper and dest.whisper == KHF.UnitKey("player") then
        Loopback(str, msgType, sid)
        return true
    end
    if dest.audience and not Channels.ForAudience(dest.audience) then
        Fail(sid, "nogroup")
        return false, "nogroup"
    end
    nextMid = nextMid % 999 + 1
    local parts = Protocol.SplitParts(str, sid, nextMid)
    if not parts then
        Fail(sid, "toolong")
        return false, "toolong"
    end
    if REPLACE[msgType] and #parts == 1 then
        for _, it in ipairs(queue) do
            if it.type == msgType and it.sid == sid and it.total == 1 and SameDest(it.dest, dest) then
                it.str = parts[1]
                return true
            end
        end
    end
    for i, p in ipairs(parts) do
        queue[#queue + 1] = { str = p, dest = dest, sid = sid, type = msgType, n = i, total = #parts, tries = 0 }
    end
    Kick()
    return true
end

local function SessionSend(s, dest, msgType, data)
    if s.loopback then
        Loopback(Protocol.Encode(msgType, s.id, data), msgType, s.id)
        return true
    end
    return Comms.SendTo(dest, msgType, s.id, data)
end

function Comms.ToAudience(s, msgType, data) return SessionSend(s, { audience = s.audience }, msgType, data) end
function Comms.ToHost(s, msgType, data) return SessionSend(s, { whisper = s.host }, msgType, data) end
function Comms.ToPlayer(s, key, msgType, data) return SessionSend(s, { whisper = key }, msgType, data) end

--------------------------------------------------------------------------------
-- ARRIVING FROM THE NETWORK: parts put together
--------------------------------------------------------------------------------
local open, openCount = {}, 0   -- "sender SEP sid SEP mid" -> { sender, total, pieces, got, t }

local function Close(key)
    open[key] = nil
    openCount = openCount - 1
end

local function OnPart(sender, channel, sid, mid, n, total, piece)
    local now = GetTime()
    for k, e in pairs(open) do
        if now - e.t > PART_TTL then Close(k) end
    end
    local key = sender .. "\031" .. sid .. "\031" .. mid
    local e = open[key]
    if not e then
        local mine = 0
        for _, x in pairs(open) do
            if x.sender == sender then mine = mine + 1 end
        end
        if openCount >= OPEN_MAX or mine >= OPEN_PER_SENDER then
            Tap("drop", { who = sender, chan = channel, sid = sid, why = "too many open", part = n, total = total })
            return
        end
        e = { sender = sender, total = total, pieces = {}, got = 0 }
        open[key] = e
        openCount = openCount + 1
    end
    e.t = now
    if e.total ~= total then
        Close(key)
        Tap("drop", { who = sender, chan = channel, sid = sid, why = "part count changed" })
        return
    end
    if not e.pieces[n] then
        e.pieces[n] = piece
        e.got = e.got + 1
    end
    if e.got < e.total then return end
    Close(key)
    Comms.Receive(table.concat(e.pieces), sender, channel, total)
end

local function OnAddon(_, prefix, text, channel, sender)
    if Secret(prefix) or Secret(text) or Secret(channel) or Secret(sender) then return end
    if prefix ~= Comms.PREFIX or type(text) ~= "string" then return end
    local who = KHF.SenderKey(sender)
    if not who then return end
    if who == KHF.UnitKey("player") then
        Tap("echo", { who = who, chan = channel, bytes = #text })
        return
    end
    local sid, mid, n, total, piece = Protocol.ParsePart(text)
    if sid then
        OnPart(who, channel, sid, mid, n, total, piece)
    else
        Comms.Receive(text, who, channel)
    end
end

--------------------------------------------------------------------------------
-- A WHISPER TO SOMEONE OFFLINE
--------------------------------------------------------------------------------
local notFound   -- ERR_CHAT_PLAYER_NOT_FOUND_S as a pattern, made on first use

-- -> the target key and its record when the line is about a recent whisper of ours
local function Bounced(text)
    if not ERR_CHAT_PLAYER_NOT_FOUND_S or type(text) ~= "string" or Secret(text) or not next(whispered) then
        return nil
    end
    if not notFound then
        local p = ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
        notFound = "^" .. p:gsub("%%%%s", "(.+)") .. "$"
    end
    local name = text:match(notFound)
    if not name then return nil end
    local now = GetTime()
    for target, w in pairs(whispered) do
        -- Retail may name the player without the realm
        if now - w.t <= BOUNCE_TIME and (name == target or name == target:match("^(.-)%-")) then
            return target, w
        end
    end
    return nil
end

local function OnSystem(_, text)
    local target, w = Bounced(text)
    if target and not w.bounced then Bounce(target) end
end

local function HideBounce(_, _, text)
    return Bounced(text) ~= nil
end

function Comms.Reset()
    queue, open, openCount, whispered = {}, {}, 0, {}
    if ticker then ticker:Cancel() end
    ticker, tokens, refillAt = nil, BURST, 0
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(Comms.PREFIX)
end
KHF.RegisterEvent("CHAT_MSG_ADDON", OnAddon)
KHF.RegisterEvent("CHAT_MSG_SYSTEM", OnSystem)
local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
if addFilter then pcall(addFilter, "CHAT_MSG_SYSTEM", HideBounce) end
