-- Kahoof UI/MainWindow.lua: the main window
-- Tabs Play / Host / My Quizzes / History / Settings (Host: ALL-72, S9).
-- Play is UI/PlayTab.lua, Host UI/HostTab.lua, My Quizzes is UI/QuizzesTab.lua
-- (S3); the others are empty pages for now, filled in by later sessions
-- (architecture.md section 9). Resizable, its place and size saved
-- (KahoofDB.windows.main).
--
-- The logo (Assets/logo.tga, the whole name) sits centered on the title bar,
-- its horns above the frame, as in Dukul's mockup; the tabs start top left
-- (Dukul, 2026-11-02, B3: "move the centered logo to the top on the title bar").
--
--   KHF.ToggleMainWindow() / ShowMainWindow(tab) / HideMainWindow()

local _, KHF = ...
local L = KHF.L

local DEF_W, DEF_H = 720, 540
local MIN_W, MIN_H = 560, 516   -- 516: the quiz editor's question pane fits (S4, ALL-41)
local LOGO = KHF.ADDON_PATH .. "Assets\\logo"

local TABS = { "TAB_PLAY", "TAB_HOST", "TAB_QUIZZES", "TAB_HISTORY", "TAB_SETTINGS" }

-- The last tab is saved by its key (mainTabKey), so a tab added later never
-- shifts which page opens
local function TabIndex(key)
    for i, k in ipairs(TABS) do
        if k == key then return i end
    end
    return nil
end

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
-- A tab selected (its own button included) calls KHF.PageTabHandlers[key]()
-- first: a page with sub-pages goes back to its top (UI/SettingsTab.lua, BNB's
-- sub-pages: "any tab select returns to the tab").
KHF.PageTabHandlers = {}

-- logo.tga is 256 x 128, its art on rows 23-107 (horn tips to letter feet).
-- Drawn at 144 x 72 (Dukul's screenshot), its top 42 above the window: the
-- horns reach ~29 above the window edge, the letters end ~18 below it, inside
-- the title band (24).
local LOGO_W, LOGO_H, LOGO_UP = 144, 72, 42
local LOGO_OUT = LOGO_UP - 23 * LOGO_H / 128   -- how far the art reaches above the window
KHF.LOGO_W = LOGO_W

-- The logo on a window's title bar, as on the main window: point "TOP" (the
-- main window, centered) or "TOPLEFT" (the quiz window, Dukul, 2026-11-04:
-- "just add it like the main window, but to the left"), x from that point.
-- Its own frame, one level up, no mouse, so the title bar under it still drags.
function KHF.AddTitleLogo(win, point, x)
    local holder = CreateFrame("Frame", nil, win)
    holder:SetAllPoints()
    holder:SetFrameLevel(win:GetFrameLevel() + 5)
    local logo = holder:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(LOGO)
    logo:SetSize(LOGO_W, LOGO_H)
    logo:SetPoint(point, win, point, x or 0, LOGO_UP)
    -- the clamp keeps the horns on screen too (the theme set the frame art's)
    local il, ir, it, ib = win:GetClampRectInsets()
    win:SetClampRectInsets(il, ir, math.max(it or 0, LOGO_OUT), ib)
    return logo
end
local TABS_TOP = 28                             -- tab row top, under the title band

local function PageEsc()
    local h = KHF.PageEscHandlers[KHF.GetSetting("mainTabKey")]
    return h and h() or false
end

local function SelectTab(idx)
    if not mw then return end
    local h = KHF.PageTabHandlers[TABS[idx]]
    if h then h() end
    for i, tab in ipairs(mw._tabs) do
        if i == idx then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
        mw._pages[i]:SetShown(i == idx)
    end
    KHF.SetSetting("mainTabKey", TABS[idx])
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

-- /kahoof lock | unlock (ALL-53): the same as the button's left click
function KHF.SetMainLocked(on)
    KHF.SetSetting("mainLocked", on and true or false)
    ApplyLock()
    if mw and mw._lockBtn then mw._lockBtn:RefreshTip() end
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
            KHF.SetMainLocked(not KHF.GetSetting("mainLocked"))
        end
    end)
    mw._lockBtn = b
end

local function LayoutHeader()
    local pad = KHF.Theme.PAD
    local tab1 = mw._tabs[1]
    tab1:SetPoint("TOPLEFT", mw, "TOPLEFT", pad, -TABS_TOP)
    -- Help on the far right (ALL-73), Settings left of it
    mw._helpTab:SetPoint("TOPRIGHT", mw, "TOPRIGHT", -pad, -TABS_TOP)
    mw._tabs[#TABS]:SetPoint("RIGHT", mw._helpTab, "LEFT", -4, 0)   -- Settings
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

    KHF.AddTitleLogo(mw, "TOP", 0)

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
        -- Settings stands alone on the right (Dukul, 2026-11-02, ALL-59); LayoutHeader places it
        if i > 1 and key ~= "TAB_SETTINGS" then tab:SetPoint("LEFT", mw._tabs[i - 1], "RIGHT", 4, 0) end
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

    -- Help: a tab that is a button (Dukul, 2026-11-04: "add a help button to the
    -- right of the settings tab"); it opens the help book, never a page
    local help = CreateFrame("Button", "KahoofMainWindowHelpTab", mw, "PanelTopTabButtonTemplate")
    help:SetText(L["TAB_HELP"])
    pcall(PanelTemplates_TabResize, help, 15, nil, 50)
    pcall(PanelTemplates_DeselectTab, help)
    help:SetScript("OnClick", function(self)
        pcall(PanelTemplates_DeselectTab, self)
        KHF.HelpBook.Toggle()
    end)
    mw._helpTab = help

    LayoutHeader()
    BuildLock()
    ApplyLock()
    SelectTab(TabIndex(KHF.GetSetting("mainTabKey")) or 1)
end

-- The tab button for a tab key, or nil before the window is built. The game
-- disables a selected tab; a sub-page enables it so a click on it goes back.
function KHF.MainTabButton(key)
    if not mw then return nil end
    for i, k in ipairs(TABS) do
        if k == key then return mw._tabs[i] end
    end
end

-- tab, optional: a tab key ("TAB_SETTINGS") to show it on
function KHF.ShowMainWindow(tab)
    if not mw then Build() end
    for i, key in ipairs(TABS) do
        if key == tab then SelectTab(i) end
    end
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
