-- Kahoof Core/Names.lua: player names, and player-written text on screen

local _, KHF = ...

--------------------------------------------------------------------------------
-- Names (clients.md): the one place that calls UnitName. Forever names carry a
-- surname in the realm slot ("Mango", "Thellama"), sometimes already joined;
-- Retail gives a realm only for players from another one.
--   KHF.UnitNameRealm(unit) -> name, realm   (Forever: "Mango Thellama", own realm)
--   KHF.UnitKey(unit)       -> one string    (Forever "Mango Thellama", Retail "Mango-Realm")
--   KHF.SenderKey(sender)   -> the same form, from CHAT_MSG_ADDON's sender
-- Ported from BNB.UnitNameRealm.
--------------------------------------------------------------------------------
function KHF.UnitNameRealm(unit)
    local name, second = UnitName(unit)
    if not name then return nil end
    local ownRealm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    if KHF.IsForever then
        if second and second ~= "" then name = name .. " " .. second end
        return name, ownRealm
    end
    return name, (second and second ~= "") and second or ownRealm
end

function KHF.UnitKey(unit)
    local name, realm = KHF.UnitNameRealm(unit)
    if not name then return nil end
    if KHF.IsForever or not realm or realm == "" then return name end
    -- the realm as the game writes it in a sender name ("Aerie Peak" ->
    -- "AeriePeak"), so a group member's key matches their messages' sender
    return name .. "-" .. (realm:gsub("[%s%-]", ""))
end

-- CHAT_MSG_ADDON's sender as a key that equals KHF.UnitKey for the same
-- player (networking.md, measured on Forever 2026-11-06): Forever sends
-- "First Last" with no realm, kept as it is; Retail sends "Name-Realm", the
-- realm added here when it is missing. Every network name goes through this
-- once, at arrival; nothing compares raw sender names.
function KHF.SenderKey(sender)
    if type(sender) ~= "string" or sender == "" then return nil end
    if KHF.IsForever or sender:find("-", 1, true) then return sender end
    return sender .. "-" .. (GetNormalizedRealmName and GetNormalizedRealmName() or "")
end

-- Player-written text (quiz titles, questions, answers, names from the network)
-- drawn on screen: every | doubled, so WoW shows it as a plain | and nobody's
-- quiz can put colors, textures or links on other players' screens (Dukul,
-- 2026-11-02: literal until the graphics tokens, ALL-26)
function KHF.EscapeText(s)
    return (tostring(s or ""):gsub("|", "||"))
end

-- The other way, for text read from an edit box: a pipe the player types is
-- held as "||" by the box itself, so the editor turns it back into one before
-- saving. Saved quizzes hold plain text; the screens escape it once (a title
-- typed "| test |" showed as "|| test ||", 2026-11-02).
function KHF.UnescapeText(s)
    return (tostring(s or ""):gsub("||", "|"))
end
