-- Kahoof Core/SlashCommands.lua: /kahoof and /khf
-- SLASH_KAHOOF1 / 2 are globals by the game's design (the slash command table
-- reads them); that is the only way to register a command.

local _, KHF = ...
local L = KHF.L

local function ClientName()
    return KHF.IsForever and L["CLIENT_FOREVER"] or L["CLIENT_RETAIL"]
end

local function PrintHelp()
    KHF:Print(L["SLASH_HELP_TITLE"])
    print(L["SLASH_HELP_TOGGLE"])
    print(L["SLASH_HELP_RESET"])
    print(L["SLASH_HELP_MINIMAP"])
    print(L["SLASH_HELP_LOCK"])
    print(L["SLASH_HELP_DEBUG"])
    print(L["SLASH_HELP_VERSION"])
end

--------------------------------------------------------------------------------
-- /kahoof version [guild]: who has the addon (Core/VersionCheck.lua, S8)
--------------------------------------------------------------------------------
local ASK_FAIL = {
    soon = "VER_TOO_SOON", lockdown = "COMMS_LOCKED", trial = "COMMS_TRIAL",
}

local function Entry(key, r)
    local s = KHF.EscapeText(key) .. " " .. KHF.EscapeText(r.ver)
    if (r.proto or 0) < KHF.Protocol.VERSION then s = string.format(L["VER_ENTRY_OLD"], s) end
    return s
end

-- Everyone who answered counts, roster or not: a name that shows under both
-- "have" and "without" is a key that does not match (a test signal, S8)
local function Report(audience, replies)
    local me = KHF.UnitKey("player")
    local have = {}
    for key, r in pairs(replies) do
        if key ~= me then have[#have + 1] = Entry(key, r) end
    end
    table.sort(have)
    table.insert(have, 1, Entry(me, { ver = KHF.ADDON_VERSION, proto = KHF.Protocol.VERSION }))
    if audience == "guild" then
        KHF:Print(string.format(L["VER_GUILD_RESULT"], #have, table.concat(have, ", ")))
        return
    end
    local members, without = KHF.Channels.GroupKeys(), {}
    for _, key in ipairs(members) do
        if key ~= me and not replies[key] then without[#without + 1] = KHF.EscapeText(key) end
    end
    table.sort(without)
    KHF:Print(string.format(L["VER_GROUP_RESULT"], #have, #members, table.concat(have, ", ")))
    if #without > 0 then print(string.format(L["VER_WITHOUT"], table.concat(without, ", "))) end
end

local function Version(arg)
    KHF:Print(string.format(L["VERSION_MSG"], KHF.ADDON_VERSION, ClientName()))
    local audience = (arg == "guild") and "guild" or "group"
    local ok, why = KHF.VersionCheck.Ask(audience, function(replies) Report(audience, replies) end)
    if ok then
        print(audience == "guild" and L["VER_ASK_GUILD"] or L["VER_ASK_GROUP"])
    elseif why == "nogroup" then
        print(audience == "guild" and L["VER_NO_GUILD"] or L["VER_HINT"])
    else
        print(ASK_FAIL[why] and L[ASK_FAIL[why]] or string.format(L["COMMS_FAILED"], tostring(why)))
    end
end

-- Command words are ASCII, so lower() is safe here (never on player text)
local COMMANDS = {
    help = PrintHelp,
    reset = function()
        KHF.ResetWindows()
        KHF:Print(L["RESET_DONE"])
    end,
    minimap = function() KHF.ToggleMinimapButton() end,
    lock = function()
        KHF.SetMainLocked(true)
        KHF:Print(L["LOCK_DONE"])
    end,
    unlock = function()
        KHF.SetMainLocked(false)
        KHF:Print(L["UNLOCK_DONE"])
    end,
    debug = function(arg)
        local on
        if arg == "on" then on = true
        elseif arg == "off" then on = false
        else on = not KHF.IsDebug() end
        KHF.SetDebug(on)
        KHF:Print(on and L["DEBUG_ON"] or L["DEBUG_OFF"])
    end,
    version = Version,
}

SLASH_KAHOOF1 = "/" .. KHF.SLASH   -- the name in one place (Init.lua)
SLASH_KAHOOF2 = "/khf"
SlashCmdList["KAHOOF"] = function(msg)
    local cmd, arg = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        KHF.ToggleMainWindow()
        return
    end
    local fn = COMMANDS[cmd]
    if fn then
        fn((arg or ""):lower())
    else
        KHF:Print(string.format(L["SLASH_UNKNOWN"], cmd))
    end
end
