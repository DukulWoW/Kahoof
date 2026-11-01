-- Kahoof Init.lua: bootstrap namespace
-- This file loads FIRST. Creates the addon namespace and version constants.

local ADDON_NAME, KHF = ...

Kahoof = KHF

KHF.ADDON_NAME = ADDON_NAME
KHF.ADDON_VERSION = "0.1.0"

-- Forever is the Mainline client on Interface 16001: detect it by interface
-- range only, never by WOW_PROJECT_ID (Forever got its own id, 18, in 2026-10)
local interface = select(4, GetBuildInfo()) or 0
KHF.IsForever = interface >= 16000 and interface < 20000

-- Chat line prefixed with the addon name in color
function KHF:Print(msg)
    print("|cffffd100Kahoof|r: " .. tostring(msg))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    KHF:Print("v" .. KHF.ADDON_VERSION .. " loaded" .. (KHF.IsForever and " (Forever)" or ""))
end)
