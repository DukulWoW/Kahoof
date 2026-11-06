-- Kahoof Core/VersionCheck.lua: who has Kahoof, and which version (HI / VER; S8, moved from S9)
-- networking.md (Protocol, HI / VER). HI goes to the audience ("who has it?");
-- every client with Kahoof answers with one VER whisper to the asker, so a
-- 40-player raid costs each player one message and the asker one. HI and VER
-- are read from every protocol version (Core/Protocol.lua): an old client still
-- answers and shows as "needs an update". The id in their header is a fresh
-- random one per ask, so a reply belongs to exactly one ask.
--
--   VersionCheck.Ask(audience, done) -> true | nil, why ("soon", "nogroup",
--                                       "lockdown", "trial"); done(replies)
--                                       runs WAIT s later, replies =
--                                       { [key] = { ver = "0.1.0", proto = 1 } }
--   VersionCheck.OnMessage(msg)         from Comms (HI, VER)
--   VersionCheck.Compare(a, b)          -> -1 / 0 / 1 for "x.y.z", nil if unreadable
--
-- A version newer than ours, seen in any HI or VER, gets one chat line per
-- login ("A newer version is out").

local _, KHF = ...
local L = KHF.L

local VC = {}
KHF.VersionCheck = VC

VC.WAIT         = 3    -- seconds the replies are collected
VC.ASK_EVERY    = 10   -- seconds between two asks of ours
VC.ANSWER_EVERY = 10   -- one sender's HI is answered at most this often

local pending          -- { sid, replies } while an ask collects
local lastAsk = nil    -- GetTime() of our last ask
local answered = {}    -- sender key -> GetTime() of our last VER to them
local toldNewer = false

local function Numbers(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) }
end

function VC.Compare(a, b)
    local x, y = Numbers(a), Numbers(b)
    if not x or not y then return nil end
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] > y[i] and 1 or -1 end
    end
    return 0
end

local function NoteVersion(v)
    if toldNewer or VC.Compare(v, KHF.ADDON_VERSION) ~= 1 then return end
    toldNewer = true
    KHF:Print(string.format(L["VER_NEWER"], KHF.EscapeText(v), KHF.ADDON_VERSION))
end

function VC.Ask(audience, done)
    local now = GetTime()
    if pending or (lastAsk and now - lastAsk < VC.ASK_EVERY) then return nil, "soon" end
    local can, why = KHF.Channels.CanSend()
    if not can then return nil, why end
    if not KHF.Channels.ForAudience(audience) then return nil, "nogroup" end
    if KHF.Channels.Locked() then return nil, "lockdown" end
    local sid = KHF.Protocol.NewSessionId()
    local p = { sid = sid, replies = {} }
    local ok, kind = KHF.Comms.SendTo({ audience = audience }, "HI", sid, { ver = KHF.ADDON_VERSION })
    if not ok then return nil, kind end
    pending, lastAsk = p, now
    C_Timer.After(VC.WAIT, function()
        if pending == p then pending = nil end
        if done then done(p.replies) end
    end)
    return true
end

function VC.OnMessage(m)
    NoteVersion(m.ver)
    if m.type == "HI" then
        local now = GetTime()
        local last = answered[m.sender]
        if last and now - last < VC.ANSWER_EVERY then return end
        answered[m.sender] = now
        KHF.Comms.SendTo({ whisper = m.sender }, "VER", m.sid, { ver = KHF.ADDON_VERSION })
    elseif m.type == "VER" and pending and m.sid == pending.sid then
        pending.replies[m.sender] = { ver = m.ver, proto = m.proto }
    end
end
