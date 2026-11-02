-- Kahoof UI/MainWindow.lua: the main window
-- Tabs Play / My Quizzes / History / Settings. My Quizzes is UI/QuizzesTab.lua
-- (S3); the others are empty pages for now, filled in by later sessions
-- (architecture.md section 9). Resizable, its place and size saved
-- (KahoofDB.windows.main).
--
-- The logo (Assets/logo.tga, the whole name) sits centered on the title bar,
-- its horns above the frame, as in Dukul's mockup; the tabs start top left
-- (Dukul, 2026-11-02, B3: "move the centered logo to the top on the title bar").
--
--   KHF.ToggleMainWindow() / ShowMainWindow() / HideMainWindow()

local _, KHF = ...
local L = KHF.L

local DEF_W, DEF_H = 720, 540
local MIN_W, MIN_H = 560, 516   -- 516: the quiz editor's question pane fits (S4, ALL-41)
local LOGO = KHF.ADDON_PATH .. "Assets\\logo"

local TABS = { "TAB_PLAY", "TAB_QUIZZES", "TAB_HISTORY", "TAB_SETTINGS" }

local mw   -- the window, built on first open

-- Page builders by tab key: a UI file that fills a tab sets
-- KHF.PageBuilders[key] = function(page) (UI/QuizzesTab.lua: TAB_QUIZZES).
-- A tab without one shows the placeholder line.
KHF.PageBuilders = {}
-- ESC asks the shown tab first: KHF.PageEscHandlers[key] = function() that
-- returns true when it took the key (the quiz editor going back to the list;
-- windows-widgets.md: "Esc goes back first"). Out of combat only: in combat
-- the game's UISpecialFrames closes the window, the page stays as it was.
KHF.PageEscHandlers = {}

-- logo.tga is 256 x 128, its art on rows 23-107 (horn tips to letter feet).
-- Drawn at 144 x 72 (Dukul's screenshot), its top 42 above the window: the
-- horns reach ~29 above the window edge, the letters end ~18 below it, inside
-- the title band (24).
local LOGO_W, LOGO_H, LOGO_UP = 144, 72, 42
local LOGO_OUT = LOGO_UP - 23 * LOGO_H / 128   -- how far the art reaches above the window
local TABS_TOP = 28                             -- tab row top, under the title band

local function PageEsc()
    local idx = KHF.GetSetting("mainTab")
    local h = TABS[idx] and KHF.PageEscHandlers[TABS[idx]]
    return h and h() or false
end

local function SelectTab(idx)
    if not mw then return end
    for i, tab in ipairs(mw._tabs) do
        if i == idx then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
        mw._pages[i]:SetShown(i == idx)
    end
    KHF.SetSetting("mainTab", idx)
end

--------------------------------------------------------------------------------
-- LOCK / RESET (BNB's main window, ALL-39; Dukul, 2026-11-02: "left clicking
-- locks the window resizing, and right clicking resets the window to it's
-- center position"). Left of the red X. Locked = no resize grip, not
-- resizable (it still moves). Right click = the default size, centered.
--------------------------------------------------------------------------------
local function ApplyLock()
    if not mw then return end
    local locked = KHF.GetSetting("mainLocked") and true or false
    mw:SetResizable(not locked)
    if mw._grip then mw._grip:SetShown(not locked) end
    if mw._lockBtn then mw._lockBtn:SetSymbol(locked and "lock" or "unlock") end
end

local function LockTip()
    local reset = L["MW_RESET_TIP"]
    if KHF.GetSetting("mainLocked") then return L["MW_LOCKED"], L["MW_LOCKED_SUB"], reset end
    return L["MW_UNLOCKED"], L["MW_UNLOCKED_SUB"], reset
end

local function BuildLock()
    local close = mw.CloseButton
    local size = math.floor(close:GetHeight() - 2 + 0.5)
    local b = KHF.Theme.CreateIconButton(mw, size, "unlock", LockTip)
    b:SetPoint("RIGHT", close, "LEFT", -4, 0)
    b:SetFrameLevel(close:GetFrameLevel())
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            KHF.db.windows.main = {}
            KHF.RestoreWindowPos(mw)
        else
            KHF.SetSetting("mainLocked", not KHF.GetSetting("mainLocked"))
            ApplyLock()
            self:RefreshTip()
        end
    end)
    mw._lockBtn = b
end

local function LayoutHeader()
    local pad = KHF.Theme.PAD
    local tab1 = mw._tabs[1]
    tab1:SetPoint("TOPLEFT", mw, "TOPLEFT", pad, -TABS_TOP)
    -- The pages start under the tabs, the full width of the window
    local area = mw._pageArea
    area:SetPoint("TOPLEFT", mw, "TOPLEFT", pad, -(TABS_TOP + tab1:GetHeight() - 2))
    area:SetPoint("BOTTOMRIGHT", mw, "BOTTOMRIGHT", -pad, pad)
end

local function Build()
    mw = KHF.CreateWindow({
        name = "KahoofMainWindow",
        w = DEF_W, h = DEF_H, minW = MIN_W, minH = MIN_H,
        resizable = true, posKey = "main",
        onEsc = PageEsc,
    })
    -- 95 % solid, like BNB's main window (Dukul, 2026-11-02: "the same
    -- transparency to the window like we have in BNB")
    mw:SetAlpha(0.95)

    -- The logo over the frame art (its own frame, one level up; no mouse, so
    -- the title bar under it still drags the window)
    local holder = CreateFrame("Frame", nil, mw)
    holder:SetAllPoints()
    holder:SetFrameLevel(mw:GetFrameLevel() + 5)
    local logo = holder:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO)
    logo:SetSize(LOGO_W, LOGO_H)
    logo:SetPoint("TOP", mw, "TOP", 0, LOGO_UP)
    -- The clamp keeps the horns on screen too (the theme set the frame art's)
    local il, ir, it, ib = mw:GetClampRectInsets()
    mw:SetClampRectInsets(il, ir, math.max(it or 0, LOGO_OUT), ib)

    -- Page area: a dark shade with the glow over it (BNB's panes), so the
    -- pages stand out from the wood
    local area = CreateFrame("Frame", nil, mw)
    local shade = area:CreateTexture(nil, "BACKGROUND", nil, 0)
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.3)
    KHF.Theme.AddGlow(area)
    mw._pageArea = area

    -- Tabs (PanelTopTabButtonTemplate is on Retail and Forever). Named, as the
    -- template's resize looks parts up by name on some clients (BNB's tabs are too)
    mw._tabs, mw._pages = {}, {}
    for i, key in ipairs(TABS) do
        local tab = CreateFrame("Button", "KahoofMainWindowTab" .. i, mw, "PanelTopTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(L[key])
        pcall(PanelTemplates_TabResize, tab, 15, nil, 70)
        if i > 1 then tab:SetPoint("LEFT", mw._tabs[i - 1], "RIGHT", 4, 0) end
        tab:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
        mw._tabs[i] = tab

        local page = CreateFrame("Frame", nil, area)
        page:SetAllPoints()
        page:Hide()
        mw._pages[i] = page
        local build = KHF.PageBuilders[key]
        if build then
            build(page)
        else
            local fs = page:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
            fs:SetPoint("CENTER")
            fs:SetText(string.format(L["PAGE_PLACEHOLDER"], L[key]))
        end
    end

    LayoutHeader()
    BuildLock()
    ApplyLock()
    local idx = KHF.GetSetting("mainTab")
    if type(idx) ~= "number" or not TABS[idx] then idx = 1 end
    SelectTab(idx)
end

function KHF.ShowMainWindow()
    if not mw then Build() end
    mw:Show()
    mw:Raise()
end

function KHF.HideMainWindow()
    if mw then mw:Hide() end
end

function KHF.ToggleMainWindow()
    if mw and mw:IsShown() then KHF.HideMainWindow() else KHF.ShowMainWindow() end
end

KHF.RegisterMessage("MainWindow", "WindowsReset", function()
    if mw and mw:IsShown() then KHF.RestoreWindowPos(mw) end
end)
