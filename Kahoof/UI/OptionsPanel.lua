-- Kahoof UI/OptionsPanel.lua: the entry in the game's Options > AddOns (S5b)
-- Like BNB's (UI/OptionsPanel.lua): the logo, the version, "by Dukul" and a
-- button that opens Kahoof's own Settings tab (windows-widgets.md: settings
-- live in the main window, the game's Options only point there). The logo is
-- Assets/logo.tga, the whole name (Dukul, 2026-11-02: "use the logo not
-- logo-icon"), so no title line under it.
-- Registered at Kahoof's ADDON_LOADED, so it is there before Options opens.

local ADDON_NAME, KHF = ...
local L = KHF.L

local LOGO_W, LOGO_H = 256, 128

local function Build()
    local panel = CreateFrame("Frame", nil, UIParent)
    panel.name = L["ADDON_NAME"]

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_W, LOGO_H)
    logo:SetPoint("CENTER", panel, "CENTER", 0, 90)
    logo:SetTexture(KHF.ADDON_PATH .. "Assets\\logo")

    local version = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    version:SetPoint("TOP", logo, "BOTTOM", 0, -4)
    version:SetText(string.format(L["OPT_VERSION"], KHF.ADDON_VERSION))
    version:SetTextColor(0.7, 0.7, 0.7)

    local author = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    author:SetPoint("TOP", version, "BOTTOM", 0, -2)
    author:SetText(L["OPT_AUTHOR"])
    author:SetTextColor(0.55, 0.55, 0.55)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    hint:SetPoint("TOP", author, "BOTTOM", 0, -10)
    hint:SetText(L["OPT_HINT"])

    -- the large panel button (on Retail and Forever, CLAUDE.md)
    local btn = CreateFrame("Button", nil, panel, "SharedButtonLargeTemplate")
    btn:SetSize(300, 60)
    btn:SetPoint("TOP", hint, "BOTTOM", 0, -16)
    btn:SetText(L["OPT_OPEN"])
    pcall(DynamicResizeButton_Resize, btn)
    btn:SetScript("OnClick", function()
        -- the game's Settings panel sits above our window: close it first
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        KHF.ShowMainWindow("TAB_SETTINGS")
    end)

    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(cat)
end

local function OnLoaded(_, name)
    if name ~= ADDON_NAME then return end
    KHF.UnregisterEvent("ADDON_LOADED", OnLoaded)
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local ok, err = pcall(Build)
    if not ok then KHF:Debug("Options panel: " .. tostring(err)) end
end
KHF.RegisterEvent("ADDON_LOADED", OnLoaded)
