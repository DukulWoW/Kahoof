-- Kahoof_Dev Probe.lua: addon message probes for RET-01 / FOR-01
-- Proves on each client what networking.md marks (verify): that a message
-- sent on a channel really arrives (a Success result is not proof: Forever's
-- CHANNEL returns 0 and delivers nothing), the per-prefix throttle, the
-- chat messaging lockdown, a whisper to an offline player, and how sender
-- names look (Forever: "First Last"?).
--
-- Its own prefix (KHFPROBE), so it never mixes with Kahoof's messages.
-- Everyone with Kahoof_Dev loaded answers a probe by itself: the tester
-- types one command, the others only need the addon on.
--
--   /khfdev ping <chan> [name]           one PING; each receiver prints it and
--                                        whispers PONG back (round trip in ms)
--   /khfdev burst <chan> [name] [n] [s]  n messages (20), s seconds apart (0);
--                                        prints the results, each receiver
--                                        whispers back how many arrived
--   /khfdev lock [on|off]                lockdown / trial state; on|off sets
--                                        the CVar addonChatRestrictionsForced
-- <chan>: party, raid, instance, guild, officer, whisper <name>, channel <name>
--
-- Always on while Kahoof_Dev is loaded: ADDON_RESTRICTION_STATE_CHANGED is
-- printed, and system lines in the 3 s after a whisper probe (offline player).

local _, D = ...
local KHF = Kahoof

local Probe = {}
D.Probe = Probe
-- Other Dev files' message kinds on this prefix (NetTest.lua: NETP, NETF):
-- kind -> fn(sender, ...the fields after the kind)
Probe.handlers = {}

local PREFIX = "KHFPROBE"
local SEP = "~"
local CHANS = {
    party = "PARTY", raid = "RAID", instance = "INSTANCE_CHAT", guild = "GUILD",
    officer = "OFFICER", whisper = "WHISPER", channel = "CHANNEL",
}

local function Say(msg) KHF:Print("|cffff9900Probe:|r " .. msg) end

local function Now() return debugprofilestop() end   -- ms

-- A value Midnight hands us as a secret cannot be compared or matched
local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function ResultName(r)
    if r == nil then return "nil" end
    if type(r) == "boolean" then return tostring(r) end
    if Enum and Enum.SendAddonMessageResult then
        for k, v in pairs(Enum.SendAddonMessageResult) do
            if v == r then return k .. " (" .. tostring(r) .. ")" end
        end
    end
    return tostring(r)
end

local function Lockdown()
    if not (C_ChatInfo.InChatMessagingLockdown) then return "n/a" end
    local ok, a, b = pcall(C_ChatInfo.InChatMessagingLockdown)
    if not ok then return "error: " .. tostring(a) end
    return tostring(a) .. (b ~= nil and (", reason " .. tostring(b)) or "")
end

local function Restricted()
    local f = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    if not f then return "n/a" end
    local ok, a = pcall(f)
    return ok and tostring(a) or ("error: " .. tostring(a))
end

--------------------------------------------------------------------------------
-- SENDING
--------------------------------------------------------------------------------
local seq = 0
local pings = {}          -- id -> sent time (ms)
local watchUntil = 0      -- system lines are printed until this GetTime()

-- Parse "<chan> [name...] [n] [s]": numbers come off the end, the rest after
-- the channel word is the target (a Forever whisper name has a space)
local function ParseTarget(rest, wantNumbers)
    local words = {}
    for w in (rest or ""):gmatch("%S+") do words[#words + 1] = w end
    local chanType = CHANS[(words[1] or ""):lower()]
    if not chanType then return nil end
    table.remove(words, 1)
    local nums = {}
    while wantNumbers and #words > 0 and #nums < 2 and tonumber(words[#words]) do
        table.insert(nums, 1, tonumber(table.remove(words)))
    end
    local target = #words > 0 and table.concat(words, " ") or nil
    return chanType, target, nums
end

-- One raw send; returns the result name and whether it counts as sent
local function Send(chanType, target, msg)
    local dest = target
    if chanType == "CHANNEL" then
        dest = target and GetChannelName(target) or 0
        if not dest or dest == 0 then return "not in channel " .. tostring(target), false end
    end
    if chanType == "WHISPER" then watchUntil = GetTime() + 3 end
    local ok, r = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, chanType, dest)
    if not ok then return "error: " .. tostring(r), false end
    return ResultName(r), (r == nil or r == true or r == 0)
end

local function NeedsTarget(chanType)
    return chanType == "WHISPER" or chanType == "CHANNEL"
end

function Probe.Ping(rest)
    local chanType, target = ParseTarget(rest, false)
    if not chanType or (NeedsTarget(chanType) and not target) then
        return Say("/khfdev ping party|raid|instance|guild|officer | whisper <name> | channel <name>")
    end
    seq = seq + 1
    local id = tostring(seq)
    pings[id] = Now()
    local res = Send(chanType, target, "PING" .. SEP .. id)
    Say(string.format("PING %s on %s%s: %s | lockdown %s", id, chanType,
        target and (" " .. target) or "", res, Lockdown()))
end

function Probe.Burst(rest)
    local chanType, target, nums = ParseTarget(rest, true)
    if not chanType or (NeedsTarget(chanType) and not target) then
        return Say("/khfdev burst <chan> [name] [count 20] [seconds apart 0]")
    end
    local n = math.max(1, math.min(math.floor(nums[1] or 20), 60))
    local gap = math.max(0, math.min(nums[2] or 0, 5))
    seq = seq + 1
    local id = tostring(seq)
    local counts, firstFail, sent = {}, nil, 0
    local function Finish()
        local parts = {}
        for k, v in pairs(counts) do parts[#parts + 1] = k .. " x" .. v end
        table.sort(parts)
        Say(string.format("BURST %s on %s: %d sent, %s%s", id, chanType, sent,
            table.concat(parts, ", "), firstFail and (" | first refused: #" .. firstFail) or ""))
    end
    local i = 0
    local function One()
        i = i + 1
        local res, ok = Send(chanType, target, table.concat({ "B", id, i, n }, SEP))
        counts[res] = (counts[res] or 0) + 1
        if ok then sent = sent + 1 elseif not firstFail then firstFail = i end
        if i < n then
            if gap > 0 then C_Timer.After(gap, One) else One() end
        else
            Finish()
        end
    end
    Say(string.format("BURST %s: %d on %s, %.1f s apart", id, n, chanType, gap))
    One()
end

function Probe.Lock(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        local ok, err = pcall(C_CVar.SetCVar, "addonChatRestrictionsForced", arg == "on" and "1" or "0")
        if not ok then Say("SetCVar failed: " .. tostring(err)) end
    end
    local cvar = C_CVar.GetCVar("addonChatRestrictionsForced")
    Say(string.format("lockdown %s | outgoing restricted %s | CVar addonChatRestrictionsForced %s",
        Lockdown(), Restricted(), tostring(cvar)))
    Say(string.format("trial %s, veteran %s | me %s",
        tostring(IsTrialAccount and IsTrialAccount()), tostring(IsVeteranTrialAccount and IsVeteranTrialAccount()),
        tostring(KHF.UnitKey("player"))))
end

--------------------------------------------------------------------------------
-- RECEIVING
--------------------------------------------------------------------------------
local bursts = {}         -- sender .. id -> { got, total, sender }

local function Reply(sender, msg)
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "WHISPER", sender)
end
Probe.Whisper = Reply

local lastSecretSay = 0

local function OnAddon(_, prefix, msg, chanType, sender)
    if Secret(prefix) or Secret(msg) or Secret(sender) then
        -- every addon's messages come through here: say it once per 10 s
        if GetTime() - lastSecretSay > 10 then
            lastSecretSay = GetTime()
            Say("addon messages arrive with secret values (lockdown " .. Lockdown() .. ")")
        end
        return
    end
    if prefix ~= PREFIX then return end
    local kind, id, a, b, c, d = strsplit(SEP, msg)
    local tag = string.format("from \"%s\" via %s", tostring(sender), tostring(chanType))
    local locked = Lockdown()
    if locked ~= "false" then tag = tag .. " | my lockdown " .. locked end
    if kind == "PING" then
        Say("PING " .. tostring(id) .. " " .. tag)
        Reply(sender, "PONG" .. SEP .. tostring(id))
    elseif kind == "PONG" then
        local t = pings[id]
        Say(string.format("PONG %s %s%s", tostring(id), tag,
            t and string.format(", %.0f ms", Now() - t) or ""))
    elseif kind == "B" then
        local key = tostring(sender) .. SEP .. tostring(id)
        local rec = bursts[key]
        if not rec then
            rec = { got = 0, total = tonumber(b) or 0 }
            bursts[key] = rec
        end
        rec.got = rec.got + 1
        rec.last = GetTime()
        -- report once 3 s have passed with nothing new
        C_Timer.After(3, function()
            if bursts[key] ~= rec or GetTime() - rec.last < 2.9 then return end
            bursts[key] = nil
            Say(string.format("BURST %s %s: got %d of %d", tostring(id), tag, rec.got, rec.total))
            Reply(sender, table.concat({ "GOT", id, rec.got, rec.total }, SEP))
        end)
    elseif kind == "GOT" then
        Say(string.format("BURST %s arrived %s of %s at \"%s\"", tostring(id), tostring(a), tostring(b), tostring(sender)))
    elseif Probe.handlers[kind] then
        Probe.handlers[kind](sender, id, a, b, c, d)
    end
end

local function OnSystem(_, text)
    if GetTime() > watchUntil then return end
    if Secret(text) then return Say("system line (secret)") end
    Say("system line: " .. tostring(text))
end

local function OnRestriction(_, ...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    Say("ADDON_RESTRICTION_STATE_CHANGED " .. table.concat(parts, ", ") .. " | lockdown " .. Lockdown())
end

function Probe.Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    KHF.RegisterEvent("CHAT_MSG_ADDON", OnAddon)
    KHF.RegisterEvent("CHAT_MSG_SYSTEM", OnSystem)
    pcall(KHF.RegisterEvent, "ADDON_RESTRICTION_STATE_CHANGED", OnRestriction)
end
