-- Kahoof UI/Launchers.lua: ways to open the main window besides /kahoof
-- Now: the Addon Compartment (the game's addon button by the minimap).
-- ALL-23 adds the LibDataBroker launcher (Titan Panel etc.) and the LibDBIcon
-- minimap button.
--
-- Registered from Lua rather than the TOC's AddonCompartmentFunc lines: those
-- need global functions, and Kahoof keeps one global. Capability-checked, so a
-- client without the compartment just has no entry.

local _, KHF = ...
local L = KHF.L

local function OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(L["ADDON_NAME"], 1, 1, 1)
    GameTooltip:AddLine(L["COMPARTMENT_TIP"], nil, nil, nil, true)
    GameTooltip:Show()
end

local function RegisterCompartment()
    local cf = AddonCompartmentFrame
    if not (cf and cf.RegisterAddon) then return end
    cf:RegisterAddon({
        text = L["ADDON_NAME"],
        icon = KHF.ADDON_PATH .. "Assets\\logo-minimap",
        notCheckable = true,
        func = function() KHF.ToggleMainWindow() end,
        funcOnEnter = OnEnter,
        funcOnLeave = function() GameTooltip:Hide() end,
    })
end

local function OnLogin()
    KHF.UnregisterEvent("PLAYER_LOGIN", OnLogin)
    local ok, err = pcall(RegisterCompartment)
    if not ok then KHF:Debug("Addon Compartment: " .. tostring(err)) end
end
KHF.RegisterEvent("PLAYER_LOGIN", OnLogin)
