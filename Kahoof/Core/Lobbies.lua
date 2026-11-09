-- Kahoof Core/Lobbies.lua: the open lobbies you can join (S9)
-- The player's side before joining: no session, just a list. Each host has
-- at most one open lobby, so the list is keyed by the host. A lobby comes in
-- with LOBBY (sent when it opens, every 60 s, and after a WHO); its player
-- count follows the host's ROSTER; it goes on CANCEL or START (closed to
-- joining: late join is ALL-16), when its host leaves your group, or after
-- STALE s without a LOBBY (two heartbeats missed).
--
-- LOBBY is read from every protocol version (Core/Protocol.lua), so a lobby
-- from an older or newer Kahoof is listed with its version and cannot be
-- joined ("needs an update"). A lobby is taken from a group channel only,
-- never from a whisper.
--
-- WHO ("any lobbies?") goes to your group when the Play tab opens, when you
-- join a group and a few seconds after login; at most one every WHO_EVERY s.
--
--   Lobbies.List()        -> { entry, ... } (newest first); entry = { host, sid,
--                            title, count, read, late, aud, players, proto, heard }
--   Lobbies.Get(host)     -> entry
--   Lobbies.Ask()         -> true when a WHO went out
--   Lobbies.OnMessage(m)  from Comms (LOBBY, ROSTER, CANCEL, START)
--
-- Bus messages (Core/Events.lua): LobbiesChanged (), LobbyOpened (entry): a
-- lobby you had not seen before, one you can join (the invite toast).

local _, KHF = ...
local S = KHF.Session

local Lobbies = {}
KHF.Lobbies = Lobbies

Lobbies.STALE     = 150   -- seconds without a LOBBY before a lobby is dropped
Lobbies.WHO_EVERY = 10

local list = {}       -- host key -> entry
local lastWho

local function Changed() KHF.SendMessage("LobbiesChanged") end

local function Prune()
    local now, gone = S.Now(), false
    for host, e in pairs(list) do
        if now - e.heard > Lobbies.STALE then
            list[host] = nil
            gone = true
        end
    end
    return gone
end

function Lobbies.List()
    if Prune() then Changed() end
    local out = {}
    for _, e in pairs(list) do out[#out + 1] = e end
    table.sort(out, function(a, b) return a.heard > b.heard end)
    return out
end

function Lobbies.Get(host) return list[host] end

function Lobbies.Ask()
    local now = S.Now()
    if lastWho and now - lastWho < Lobbies.WHO_EVERY then return false end
    if not KHF.Channels.ForAudience("group") or KHF.Channels.Locked() or not KHF.Channels.CanSend() then
        return false
    end
    lastWho = now
    return KHF.Comms.SendTo({ audience = "group" }, "WHO", KHF.Protocol.NewSessionId(), {}) and true or false
end

local function Players(e)
    local n = 0
    for _ in pairs(e.list or {}) do n = n + 1 end
    return n
end

function Lobbies.OnMessage(m)
    if m.channel == "WHISPER" then return end
    local e = list[m.sender]
    if m.type == "LOBBY" then
        local fresh = not e or e.sid ~= m.sid
        if fresh then
            e = { host = m.sender, sid = m.sid }
            list[m.sender] = e
        end
        e.title, e.count, e.read, e.late, e.aud = m.title, m.count, m.read, m.late, m.aud
        e.proto, e.heard = m.proto, S.Now()
        if not e.list then e.players = m.players end
        Changed()
        if fresh and m.proto == KHF.Protocol.VERSION then KHF.SendMessage("LobbyOpened", e) end
    elseif not e or e.sid ~= m.sid then
        return
    elseif m.type == "ROSTER" then
        local l = KHF.Roster.Apply(e.list, m.full, m.rows)
        if l then
            e.list = l
            e.players = Players(e)
            Changed()
        end
    elseif m.type == "CANCEL" or m.type == "START" then
        list[m.sender] = nil
        Changed()
    end
end

-- A host who left your group (or you left it) takes their lobby along
local function OnGroupChanged()
    local inGroup = {}
    for _, k in ipairs(KHF.Channels.ForAudience("group") and KHF.Channels.GroupKeys() or {}) do inGroup[k] = true end
    local gone = false
    for host, e in pairs(list) do
        if e.aud ~= 2 and not inGroup[host] then
            list[host] = nil
            gone = true
        end
    end
    if gone then Changed() end
end
KHF.RegisterEvent("GROUP_ROSTER_UPDATE", OnGroupChanged)

-- Joined a group: ask who has a lobby open (after the roster settles)
KHF.RegisterEvent("GROUP_JOINED", function()
    C_Timer.After(2, function() Lobbies.Ask() end)
end)

-- A login or /reload while a lobby is open in your group: ask once
local function OnLogin()
    KHF.UnregisterEvent("PLAYER_LOGIN", OnLogin)
    C_Timer.After(5, function() Lobbies.Ask() end)
end
KHF.RegisterEvent("PLAYER_LOGIN", OnLogin)
