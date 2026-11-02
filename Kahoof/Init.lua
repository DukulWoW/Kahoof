-- Kahoof Init.lua: bootstrap namespace
-- Loads FIRST. Creates the addon namespace, version, client check, chat print,
-- debug flag and the locale proxy, so every later file can use them.

local ADDON_NAME, KHF = ...

-- The one global (slash commands, other addons, /run probes)
Kahoof = KHF

KHF.ADDON_NAME    = ADDON_NAME
KHF.ADDON_VERSION = "0.1.0"
KHF.ADDON_PATH    = "Interface\\AddOns\\" .. ADDON_NAME .. "\\"

-- THE NAME PLAYERS SEE, in one place (Dukul, 2026-11-02: "if Kahoots lawyers
-- do come knocking, make it an easy change, so basically one string for the
-- name"). Every player-facing string takes it from here: locale strings write
-- {name} and {cmd} (filled in by the locale proxy below), code uses KHF.NAME.
-- A rename = these two lines + the TOC titles (Kahoof.toc, Kahoof_DB.toc),
-- the category in Bindings.xml and the logo art. The folder, the
-- SavedVariables, the globals and the frame names stay "Kahoof": players never
-- see them, and renaming them would lose everyone's saved quizzes.
KHF.NAME  = "Kahoof"   -- the addon's name on screen
KHF.SLASH = "kahoof"   -- the slash command, without the / (/khf stays as the short one)

-- Forever is the Mainline client on Interface 16001: detect it by interface
-- range only, never by WOW_PROJECT_ID (Forever got its own id, 18, in 2026-10).
-- Set once here; nothing else checks the client (clients.md)
local interface = select(4, GetBuildInfo()) or 0
KHF.IsForever = interface >= 16000 and interface < 20000

-- Chat line prefixed with the addon name in Kahoof's color (#e87c21, Dukul, 2026-11-02)
function KHF:Print(msg)
    print("|cffe87c21" .. KHF.NAME .. "|r: " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Debug mode: in memory only, so it is off again after every reload or login
-- (BNB cleared its saved flag at load for the same reason). Turns on the
-- !!KEY marker for missing locale keys and the KHF:Debug lines.
--------------------------------------------------------------------------------
KHF._debug = false
function KHF.IsDebug() return KHF._debug == true end
function KHF.SetDebug(on) KHF._debug = on and true or false end

-- A gray chat line, debug mode only
function KHF:Debug(msg)
    if KHF._debug then print("|cff888888" .. KHF.NAME .. " debug:|r " .. tostring(msg)) end
end

-- Full recursive copy of a value; non-tables come back as they are
function KHF.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = KHF.DeepCopy(x) end
    return out
end

--------------------------------------------------------------------------------
-- Locale proxy (BNB's pattern). L_DATA holds the strings, KHF.L is a proxy:
-- a missing key returns its own name ("!!KEY" in debug mode), never nil, so a
-- forgotten key shows on screen instead of erroring. Code that must know
-- whether a key exists asks KHF.HasL(key). Locales/enUS.lua fills it.
-- A string set here has {name} replaced by KHF.NAME and {cmd} by the slash
-- command ("/kahoof"), so translations never spell the name out.
--------------------------------------------------------------------------------
local L_DATA = {}
KHF.L = setmetatable({}, {
    __index = function(_, key)
        local v = L_DATA[key]
        if v == nil then
            if type(key) ~= "string" then return nil end
            return KHF._debug and ("!!" .. key) or key
        end
        return v
    end,
    __newindex = function(_, key, value)
        if type(value) == "string" then
            value = value:gsub("{name}", KHF.NAME):gsub("{cmd}", "/" .. KHF.SLASH)
        end
        L_DATA[key] = value
    end,
})
function KHF.HasL(key) return L_DATA[key] ~= nil end
