-- Kahoof Locales/enUS.lua: every player-facing string, English (the default)
-- The proxy KHF.L is made in Init.lua. A key exists here before any code uses
-- it. Translations come after 1.0 (BNB's route): a later locale file sets only
-- the keys it translates.

local _, KHF = ...
local L = KHF.L

-- Addon identity
L["ADDON_NAME"]         = "Kahoof"
L["LOADED_MSG"]         = "v%s loaded (%s). Type /kahoof to open it."   -- %s = version, client name
L["CLIENT_RETAIL"]      = "Retail"
L["CLIENT_FOREVER"]     = "WoW Forever"

-- Shared
L["CLOSE"]              = "Close"

-- Main window tabs
L["TAB_PLAY"]           = "Play"
L["TAB_QUIZZES"]        = "My Quizzes"
L["TAB_HISTORY"]        = "History"
L["TAB_SETTINGS"]       = "Settings"
L["PAGE_PLACEHOLDER"]   = "%s: nothing here yet."   -- %s = tab name

-- Slash commands
L["SLASH_HELP_TITLE"]   = "Commands:"
L["SLASH_HELP_TOGGLE"]  = "  /kahoof - open or close the window"
L["SLASH_HELP_RESET"]   = "  /kahoof reset - put every window back in the middle of the screen"
L["SLASH_HELP_DEBUG"]   = "  /kahoof debug on | off - debug mode until you reload or log out"
L["SLASH_HELP_VERSION"] = "  /kahoof version - show the version"
L["SLASH_UNKNOWN"]      = "Unknown command: %s. Type /kahoof help."
L["RESET_DONE"]         = "Every window is back in the middle of the screen."
L["DEBUG_ON"]           = "Debug mode on until you reload or log out."
L["DEBUG_OFF"]          = "Debug mode off."
L["VERSION_MSG"]        = "Version %s on %s."   -- %s = version, client name

-- Launchers
L["COMPARTMENT_TIP"]    = "Click to open or close the window."
