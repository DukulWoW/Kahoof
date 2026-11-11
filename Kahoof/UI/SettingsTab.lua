-- Kahoof UI/SettingsTab.lua: the main window's Settings tab (ALL-23, ALL-20)
-- BNB's settings layout: the tab holds General (switches, the quiz window's
-- scale) and one overview row per larger section, [x] Title ... [Settings]
-- with a gray line under it. Settings opens that section's sub-page over the
-- tab: a back arrow and the title on top. The back arrow, ESC, a click on the
-- Settings tab, another tab or closing the window go back to the tab.
-- Sounds is the first sub-page (on / off, the channel, one sound per moment
-- with a play button). Every control writes KahoofDB at once; the windows
-- follow through SettingChanged. The list of sound moments is UI/Sounds.lua's
-- (MOMENTS): a new moment there is a new row here by itself.

local _, KHF = ...
local L = KHF.L

local LABEL_X, CTRL_X = 10, 200
local DD_W, PLAY_W = 220, 60
local ROW = 30
local BAR_ROOM = 22   -- the scroll bar
-- Wrapped text gets a fixed width: measured on a page still 1 px wide it
-- came out one line high and the rows under it ran over it (2026-11-10).
-- 470 fits the main window at its smallest (560).
local TEXT_W = 470

local tabPage          -- the Settings tab's frame
local main             -- the tab's own panel { scroll, child }
local subs = {}        -- every sub-page panel
local openSub          -- the sub-page that shows, or nil
local checks = {}      -- { cb, get } to refresh on show
local refreshers = {}  -- function() run on refresh
local scaleSlider, chanDD
local soundRows = {}   -- { dd, play, moment }

--------------------------------------------------------------------------------
-- CONTROLS (ct = the scroll child they go on)
--------------------------------------------------------------------------------
local function Header(ct, text, y)
    local fs = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", ct, "TOPLEFT", LABEL_X, y)
    fs:SetText(text)
    return y - 28
end

local function SubHeader(ct, text, y)
    local fs = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", ct, "TOPLEFT", LABEL_X, y - 4)
    fs:SetText(text)
    return y - 24
end

local function Note(ct, text, y, x)
    local fs = ct:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", ct, "TOPLEFT", x or LABEL_X, y)
    fs:SetWidth(TEXT_W - ((x or LABEL_X) - LABEL_X))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    return y - math.max(14, fs:GetStringHeight()) - 8
end

local function Label(ct, text, y)
    local fs = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", ct, "TOPLEFT", LABEL_X + 10, y)
    fs:SetPoint("RIGHT", ct, "TOPLEFT", CTRL_X - 6, y)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(text)
    return fs
end

-- A check box whose label is part of the click area (BNB's checkbox rule).
-- get() -> the current value; set(on). Returns y, cb.
local function Check(ct, text, tip, y, get, set)
    local cb = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("LEFT", ct, "TOPLEFT", LABEL_X + 4, y)
    local fs = ct:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 4), 0, 0)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    KHF.SetTooltip(cb, text, tip)
    checks[#checks + 1] = { cb = cb, get = get }
    return y - 28, cb
end

local function SettingCheck(ct, key, text, tip, y)
    return (Check(ct, text, tip, y, function() return KHF.GetSetting(key) and true or false end,
        function(on) KHF.SetSetting(key, on) end))
end

local function Dropdown(ct, y, width)
    local dd = CreateFrame("DropdownButton", nil, ct, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetPoint("LEFT", ct, "TOPLEFT", CTRL_X, y)
    return dd
end

--------------------------------------------------------------------------------
-- PANELS AND SUB-PAGES (BNB UI/ConfigWindow.lua: NewSubPage, AddOverviewRow)
--------------------------------------------------------------------------------
local function NewPanel()
    local scroll = CreateFrame("ScrollFrame", nil, tabPage)
    scroll:SetPoint("TOPLEFT", tabPage, "TOPLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", tabPage, "BOTTOMRIGHT", -BAR_ROOM, 6)
    local ct = CreateFrame("Frame", nil, scroll)
    ct:SetSize(1, 1)
    scroll:SetScrollChild(ct)
    KHF.Theme.AttachScrollBar(scroll)
    scroll:HookScript("OnSizeChanged", function(self, w) ct:SetWidth(w or self:GetWidth()) end)
    return { scroll = scroll, child = ct }
end

-- The selected tab button is disabled by the game; while a sub-page shows it
-- takes clicks, and a click goes back (MainWindow's PageTabHandlers).
local function TabClickable(on)
    local btn = KHF.MainTabButton("TAB_SETTINGS")
    if not btn then return end
    if on then btn:Enable() else pcall(PanelTemplates_SelectTab, btn) end
end

local function CloseSub()
    if not openSub then return false end
    openSub.scroll:Hide()
    openSub = nil
    main.scroll:Show()
    if KHF.GetSetting("mainTabKey") == "TAB_SETTINGS" then TabClickable(false) end
    return true
end

local function OpenSub(sub)
    CloseSub()
    main.scroll:Hide()
    sub.scroll:SetVerticalScroll(0)
    sub.scroll:Show()
    openSub = sub
    TabClickable(true)
end

-- A sub-page: its own panel, hidden, a back arrow and the title on top.
-- build(ct, y, sub) fills it from y down and returns the last y.
local function NewSubPage(title, build)
    local sub = NewPanel()
    sub.scroll:Hide()
    local ct = sub.child
    local back = KHF.Theme.CreateIconButton(ct, 22, "left",
        function() return L["SET_SUBPAGE_BACK"] end)
    back:SetPoint("TOPLEFT", ct, "TOPLEFT", LABEL_X, -2)
    back:SetScript("OnClick", CloseSub)
    local fs = ct:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("LEFT", back, "RIGHT", 8, 0)
    fs:SetText(title)
    ct:SetHeight(-build(ct, -36, sub) + 10)
    function sub.Open() OpenSub(sub) end
    subs[#subs + 1] = sub
    return sub
end

-- One overview row for a sub-page: [x] Title ... [Settings], the gray line
-- under it. The box is a twin of the page's sub.enableCb (it runs that box's
-- own click, so the two never disagree); Settings grays while it is off
-- (BNB: a module that is off has nothing to set, Dukul 2026-10-07).
local function OverviewRow(ct, y, sub, title, desc)
    local TEXT_X = LABEL_X + 32
    local cb = sub.enableCb
    local ov
    if cb then
        ov = CreateFrame("CheckButton", nil, ct, "UICheckButtonTemplate")
        ov:SetSize(26, 26)
        ov:SetPoint("TOPLEFT", ct, "TOPLEFT", LABEL_X + 4, y + 3)
        ov:SetScript("OnClick", function(self)
            cb:SetChecked(self:GetChecked())
            local fn = cb:GetScript("OnClick")
            if fn then fn(cb, "LeftButton") end
        end)
        ov:SetScript("OnEnter", cb:GetScript("OnEnter"))
        ov:SetScript("OnLeave", cb:GetScript("OnLeave"))
    end

    local open = KHF.CreateButton(ct, L["SET_SUBPAGE_OPEN"], 90, 22)
    open:SetPoint("TOPRIGHT", ct, "TOPLEFT", LABEL_X + TEXT_W, y)
    open:SetScript("OnClick", sub.Open)

    local lbl = ct:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", ct, "TOPLEFT", TEXT_X, y - 10)
    lbl:SetPoint("RIGHT", open, "LEFT", -8, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(title)
    if ov then ov:SetHitRectInsets(0, -(lbl:GetStringWidth() + 8), 0, 0) end

    refreshers[#refreshers + 1] = function()
        if not ov then return end
        local on = cb:GetChecked() and true or false
        ov:SetChecked(on)
        open:SetEnabled(on)
    end
    return Note(ct, desc, y - 24, TEXT_X) - 4
end

--------------------------------------------------------------------------------
-- GENERAL
--------------------------------------------------------------------------------
local function BuildGeneral(ct, y)
    y = Header(ct, L["SET_GENERAL"], y)
    y = Check(ct, L["SET_MINIMAP"], L["SET_MINIMAP_TIP"], y,
        function() return not (KHF.db and KHF.db.minimapIcon.hide) end,
        function(on) KHF.SetMinimapButton(on) end)
    y = SettingCheck(ct, "answerKeys", L["SET_KEYS"], L["SET_KEYS_TIP"], y)
    y = SettingCheck(ct, "toastGroup", L["SET_TOAST"], L["SET_TOAST_TIP"], y)
    y = SettingCheck(ct, "boardFull", L["SET_BOARD_FULL"], L["SET_BOARD_FULL_TIP"], y)
    y = SettingCheck(ct, "reduceMotion", L["SET_MOTION"], L["SET_MOTION_TIP"], y)

    y = y - 6
    scaleSlider = KHF.Theme.CreateSlider(ct, 300, {
        label = L["SET_SCALE"], min = 0.5, max = 1.5, step = 0.05,
        value = KHF.GetSetting("quizScale") or 1, default = KHF.DEFAULTS.quizScale,
        onChange = function(v) KHF.SetSetting("quizScale", v) end,
    })
    scaleSlider:SetPoint("TOPLEFT", ct, "TOPLEFT", LABEL_X + 10, y)
    return y - 48 - 16
end

--------------------------------------------------------------------------------
-- SOUNDS (a sub-page)
--------------------------------------------------------------------------------
local Sounds = function() return KHF.Sounds end

local function SoundRow(ct, m, y)
    local label = Label(ct, L[m.label], y)
    local dd = Dropdown(ct, y, DD_W)
    local moment = m.key
    dd:SetupMenu(function(_, root)
        if root.SetScrollMode then root:SetScrollMode(20 * 20) end
        for _, name in ipairs(Sounds().List()) do
            local text = name
            if name == "None" then text = L["SND_NONE"] end
            if name == Sounds().Default(moment) then text = text .. "  |cff888888" .. L["SND_DEFAULT_MARK"] .. "|r" end
            root:CreateRadio(text, function() return Sounds().Get(moment) == name end,
                function() Sounds().Set(moment, name) end)
        end
    end)
    local def = Sounds().Default(moment)
    if def == "None" then def = L["SND_NONE"] end
    local tip = L[m.tip] .. "\n\n" .. string.format(L["SND_DEFAULT_IS"], def)
    KHF.SetTooltip(dd, L[m.label], tip)
    -- the label tells the same as the dropdown
    local hit = CreateFrame("Frame", nil, ct)
    hit:SetAllPoints(label)
    hit:EnableMouse(true)
    KHF.SetTooltip(hit, L[m.label], tip)

    local play = KHF.CreateButton(ct, L["SND_PLAY"], PLAY_W, 22)
    play:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    play:SetScript("OnClick", function() Sounds().Preview(Sounds().Get(moment)) end)
    KHF.SetTooltip(play, L["SND_PLAY"], L["SND_PLAY_TIP"])
    soundRows[#soundRows + 1] = { dd = dd, play = play, moment = moment }
    return y - ROW
end

local function BuildSounds(ct, y, sub)
    local cb
    y, cb = Check(ct, L["SND_ON"], L["SND_ON_TIP"], y,
        function() return KHF.db and KHF.db.sounds.on end,
        function(on) Sounds().SetOn(on) end)
    sub.enableCb = cb

    y = y - 4
    Label(ct, L["SND_CHANNEL"], y)
    chanDD = Dropdown(ct, y, DD_W)
    chanDD:SetupMenu(function(_, root)
        for _, c in ipairs(Sounds().CHANNELS) do
            root:CreateRadio(L[c.label], function() return (KHF.db and KHF.db.sounds.channel) == c.key end,
                function() Sounds().SetChannel(c.key) end)
        end
    end)
    KHF.SetTooltip(chanDD, L["SND_CHANNEL"], L["SND_CHANNEL_TIP"])
    y = y - ROW
    y = Note(ct, L["SND_VOLUME_NOTE"], y + 8)

    for _, m in ipairs(Sounds().MOMENTS) do
        if m.group then
            y = SubHeader(ct, L[m.group], y)
            if m.group == "SND_GROUP_MUSIC" then y = Note(ct, L["SND_MUSIC_NOTE"], y) end
        else
            y = SoundRow(ct, m, y)
        end
    end
    return y
end

--------------------------------------------------------------------------------
-- THE PAGE
--------------------------------------------------------------------------------
local function Refresh()
    if not main then return end
    for _, c in ipairs(checks) do c.cb:SetChecked(c.get() and true or false) end
    for _, fn in ipairs(refreshers) do fn() end
    if scaleSlider then scaleSlider:SetValue(KHF.GetSetting("quizScale") or 1) end
    local on = KHF.db and KHF.db.sounds.on
    if chanDD then chanDD:GenerateMenu() end
    for _, r in ipairs(soundRows) do
        r.dd:GenerateMenu()
        r.play:SetEnabled(on and KHF.Sounds.IsSet(r.moment) or false)
    end
end

local function Build(page)
    tabPage = page
    main = NewPanel()
    local sounds = NewSubPage(L["SET_SOUNDS"], BuildSounds)

    local ct = main.child
    local y = -6
    y = BuildGeneral(ct, y)
    y = Header(ct, L["SET_MORE"], y)
    y = OverviewRow(ct, y, sounds, L["SET_SOUNDS"], L["SET_SOUNDS_DESC"])
    ct:SetHeight(-y + 10)

    page:HookScript("OnShow", Refresh)
    page:HookScript("OnHide", CloseSub)   -- another tab, or the window closed
    Refresh()
end
KHF.PageBuilders.TAB_SETTINGS = Build

-- ESC and a click on the Settings tab go back from a sub-page first
KHF.PageEscHandlers.TAB_SETTINGS = function() return CloseSub() end
KHF.PageTabHandlers.TAB_SETTINGS = function() if main then CloseSub() end end

-- A setting changed somewhere else (/kahoof minimap, the board's toggle)
KHF.RegisterMessage("SettingsTab", "SettingChanged", function()
    if tabPage and tabPage:IsVisible() then Refresh() end
end)
