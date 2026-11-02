-- Kahoof Core/Names.lua: player names, and player-written text on screen

local _, KHF = ...

--------------------------------------------------------------------------------
-- Names (clients.md): the one place that calls UnitName. Forever names carry a
-- surname in the realm slot ("Mango", "Thellama"), sometimes already joined;
-- Retail gives a realm only for players from another one.
--   KHF.UnitNameRealm(unit) -> name, realm   (Forever: "Mango Thellama", own realm)
--   KHF.UnitKey(unit)       -> one string    (Forever "Mango Thellama", Retail "Mango-Realm")
-- Ported from BNB.UnitNameRealm. How CHAT_MSG_ADDON names a Forever sender is
-- still open (FOR-01): network keys may need a second helper then.
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
    return name .. "-" .. realm
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
