-- Kahoof Core/Comms.lua: how game messages leave and arrive (S5a: the loopback only)
-- architecture.md section 7: Comms has two ways out, the network (prefix,
-- send queue, parts: S8) and a LOOPBACK that hands a message to the local
-- receiver on the next frame. Practice mode runs the host and the player in
-- one client over the loopback, with the real wire messages (Dukul,
-- 2026-11-02: "Real wire messages"), so the protocol, the state machine and
-- scoring are proven alone, before the network code exists.
--
-- Messages are encoded here and decoded on arrival, the loopback included.
-- Arrivals go by type: A to the host (Core/Host.lua), everything else to the
-- player (Core/Player.lua); each checks the session id and the sender.
--
--   Comms.ToAudience(s, type, data)   host -> everyone in the session
--   Comms.ToHost(s, type, data)       player -> the host (a whisper on the network)
--   Comms.Receive(str, sender)        one arrived message

local _, KHF = ...

local Comms = {}
KHF.Comms = Comms

local HOST_BOUND = { A = true }

function Comms.Receive(str, sender)
    local msg = KHF.Protocol.Decode(str)
    if not msg then
        KHF:Debug("Dropped a message from " .. tostring(sender))
        return
    end
    msg.sender = sender
    if HOST_BOUND[msg.type] then
        KHF.Host.OnMessage(msg)
    else
        KHF.Player.OnMessage(msg)
    end
end

-- Next frame, in send order (C_Timer callbacks due at the same time run in
-- the order they were made); the sender is you
local function Loopback(str)
    local me = KHF.UnitKey("player")
    C_Timer.After(0, function() Comms.Receive(str, me) end)
end

local function Send(s, msgType, data)
    local str = KHF.Protocol.Encode(msgType, s.id, data)
    if s.loopback then
        Loopback(str)
    else
        -- The network path (prefix, queue, parts, channels) is S8 (ALL-07)
        KHF:Debug("No network path yet: " .. msgType .. " not sent")
    end
end

function Comms.ToAudience(s, msgType, data) Send(s, msgType, data) end
function Comms.ToHost(s, msgType, data) Send(s, msgType, data) end
