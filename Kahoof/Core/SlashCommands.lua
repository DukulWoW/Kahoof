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
    print(L["SLASH_HELP_DEBUG"])
    print(L["SLASH_HELP_VERSION"])
end

-- Command words are ASCII, so lower() is safe here (never on player text)
local COMMANDS = {
    help = PrintHelp,
    reset = function()
        KHF.ResetWindows()
        KHF:Print(L["RESET_DONE"])
    end,
    debug = function(arg)
        local on
        if arg == "on" then on = true
        elseif arg == "off" then on = false
        else on = not KHF.IsDebug() end
        KHF.SetDebug(on)
        KHF:Print(on and L["DEBUG_ON"] or L["DEBUG_OFF"])
    end,
    version = function()
        KHF:Print(string.format(L["VERSION_MSG"], KHF.ADDON_VERSION, ClientName()))
    end,
}

SLASH_KAHOOF1 = "/kahoof"
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
