-- Kahoof UI/Launchers.lua: ways to open the main window besides /kahoof
-- The Addon Compartment (the game's addon button by the minimap), and a
-- LibDataBroker launcher (Titan Panel and every other broker display; Dukul:
-- "Also needs to work with databrokers like titan panel etc.") shown as a
-- LibDBIcon minimap button (S5b; Dukul, 2026-11-02: "left click opens right
-- click goes to settings"). The button's place and hidden flag are LibDBIcon's
-- own table, KahoofDB.minimapIcon; /kahoof minimap shows / hides it (a Settings
-- switch comes with the Settings tab).
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

--------------------------------------------------------------------------------
-- BROKER + MINIMAP BUTTON
--------------------------------------------------------------------------------
local BROKER_NAME = KHF.NAME   -- broker bars list it by this name

local function OnBrokerClick(_, button)
    if button == "RightButton" then
        KHF.ShowMainWindow("TAB_SETTINGS")
    else
        KHF.ToggleMainWindow()
    end
end

-- The broker object is made at file load, as BNB's, so every broker display
-- sees it from the start, and it is a "data source" (ALL-60: XIV Databar
-- lists launchers only behind its own "Show launchers" filter; BNB's data
-- source shows). With no text of its own a bar shows the label.
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local brokerObj = LDB and LDB:NewDataObject(BROKER_NAME, {
    type = "data source",
    tocname = KHF.ADDON_NAME,
    icon = KHF.ADDON_PATH .. "Assets\\logo-minimap",
    label = L["ADDON_NAME"],
    text = "",
    OnClick = OnBrokerClick,
    OnTooltipShow = function(tip)
        tip:AddLine(L["ADDON_NAME"], 0.910, 0.486, 0.129)
        tip:AddLine(L["MINIMAP_LEFT"], 1, 1, 1)
        tip:AddLine(L["MINIMAP_RIGHT"], 1, 1, 1)
    end,
})

-- The minimap button needs the saved settings: at PLAYER_LOGIN
local function RegisterMinimapButton()
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if DBIcon and brokerObj and KHF.db then DBIcon:Register(BROKER_NAME, brokerObj, KHF.db.minimapIcon) end
end

-- /kahoof minimap
function KHF.ToggleMinimapButton()
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (DBIcon and KHF.db) then return end
    local icon = KHF.db.minimapIcon
    icon.hide = not icon.hide
    if icon.hide then DBIcon:Hide(BROKER_NAME) else DBIcon:Show(BROKER_NAME) end
    KHF:Print(icon.hide and L["MINIMAP_HIDDEN"] or L["MINIMAP_SHOWN"])
end

local function OnLogin()
    KHF.UnregisterEvent("PLAYER_LOGIN", OnLogin)
    local ok, err = pcall(RegisterCompartment)
    if not ok then KHF:Debug("Addon Compartment: " .. tostring(err)) end
    ok, err = pcall(RegisterMinimapButton)
    if not ok then KHF:Debug("Minimap button: " .. tostring(err)) end
end
KHF.RegisterEvent("PLAYER_LOGIN", OnLogin)
