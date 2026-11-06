-- Kahoof Core/Channels.lua: which chat channel an audience is, who is in it, and whether we may send (S8)
-- networking.md (Channel choice, Restrictions). The one place that names a
-- channel string: no other code writes "PARTY" or "GUILD".
--
-- Two audiences (game-engine.md): "group" (party, raid or instance group) and
-- "guild". A group's channel is read again at every send, so a party turned
-- into a raid mid-quiz keeps playing. Never CHANNEL (Forever drops it).
--
--   Channels.ForAudience(audience) -> "INSTANCE_CHAT" | "RAID" | "PARTY" | "GUILD" | nil
--   Channels.GroupKeys()           -> the player keys in your group, you included
--   Channels.Locked()              -> true while the game blocks addon messages
--                                     (an encounter, Mythic+, a PvP match)
--   Channels.CanSend()             -> true | false, "trial"
--
-- Bus message (Core/Events.lua): ChatLockdown (locked), when the lockdown
-- starts or ends. ADDON_RESTRICTION_STATE_CHANGED fires for other things too
-- (type 0 came on its own on Forever, likely combat), and Retail's type
-- numbers are not measured yet: so the state is read from
-- InChatMessagingLockdown on every such event, never from its payload.

local _, KHF = ...

local Channels = {}
KHF.Channels = Channels

function Channels.ForAudience(audience)
    if audience == "guild" then
        return IsInGuild() and "GUILD" or nil
    elseif audience == "group" then
        -- an LFG / LFR / battleground group: PARTY and RAID do not reach it
        if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
        -- in a raid, RAID only: a PARTY send from a raid is never delivered (W10)
        if IsInRaid() then return "RAID" end
        if IsInGroup() then return "PARTY" end
    end
    return nil
end

function Channels.GroupKeys()
    local out = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            out[#out + 1] = KHF.UnitKey("raid" .. i)   -- the raid units include you
        end
    else
        out[1] = KHF.UnitKey("player")
        for i = 1, GetNumSubgroupMembers() do
            out[#out + 1] = KHF.UnitKey("party" .. i)
        end
    end
    return out
end

-- One value on Forever, (locked, reason) on Retail since 12.0.5
function Channels.Locked()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, locked = pcall(f)
    return ok and locked == true
end

-- Trial (and Veteran) accounts cannot send addon messages on either client
function Channels.CanSend()
    if (IsTrialAccount and IsTrialAccount()) or (IsVeteranTrialAccount and IsVeteranTrialAccount()) then
        return false, "trial"
    end
    return true
end

local wasLocked = false
local function OnRestriction()
    local now = Channels.Locked()
    if now ~= wasLocked then
        wasLocked = now
        KHF.SendMessage("ChatLockdown", now)
    end
end
-- a /reload inside an encounter starts locked: read it once at login, no message
KHF.RegisterEvent("PLAYER_LOGIN", function() wasLocked = Channels.Locked() end)
pcall(KHF.RegisterEvent, "ADDON_RESTRICTION_STATE_CHANGED", OnRestriction)
