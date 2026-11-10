-- Kahoof UI/SettingsTab.lua: the main window's Settings tab (ALL-23, ALL-20)
-- One scrolling page: General (switches, the quiz window's scale) and Sounds
-- (on / off, the channel, one sound per moment with a play button). Every
-- control writes KahoofDB at once; the windows follow through SettingChanged.
-- The list of sound moments is UI/Sounds.lua's (MOMENTS): a new moment there
-- is a new row here by itself.

local _, KHF = ...
local L = KHF.L

local LABEL_X, CTRL_X = 10, 200
local DD_W, PLAY_W = 220, 60
local ROW = 30
local BAR_ROOM = 22   -- the scroll bar

local child            -- the scroll child, every control on it
local checks = {}      -- { cb, get } to refresh on show
local scaleSlider, chanDD
local soundRows = {}   -- { dd, moment }

--------------------------------------------------------------------------------
-- CONTROLS
--------------------------------------------------------------------------------
local function Header(text, y)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", LABEL_X, y)
    fs:SetText(text)
    return y - 28
end

local function SubHeader(text, y)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", LABEL_X, y - 4)
    fs:SetText(text)
    return y - 24
end

local function Note(text, y)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", LABEL_X, y)
    fs:SetPoint("RIGHT", child, "RIGHT", -10, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return y - math.max(14, fs:GetStringHeight()) - 8
end

local function Label(text, y)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", child, "TOPLEFT", LABEL_X + 10, y)
    fs:SetPoint("RIGHT", child, "TOPLEFT", CTRL_X - 6, y)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(text)
    return fs
end

-- A check box whose label is part of the click area (BNB's checkbox rule).
-- get() -> the current value; set(on)
local function Check(text, tip, y, get, set)
    local cb = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("LEFT", child, "TOPLEFT", LABEL_X + 4, y)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 4), 0, 0)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    KHF.SetTooltip(cb, text, tip)
    checks[#checks + 1] = { cb = cb, get = get }
    return y - 28
end

local function SettingCheck(key, text, tip, y)
    return Check(text, tip, y, function() return KHF.GetSetting(key) and true or false end,
        function(on) KHF.SetSetting(key, on) end)
end

local function Dropdown(y, width)
    local dd = CreateFrame("DropdownButton", nil, child, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetPoint("LEFT", child, "TOPLEFT", CTRL_X, y)
    return dd
end

--------------------------------------------------------------------------------
-- GENERAL
--------------------------------------------------------------------------------
local function BuildGeneral(y)
    y = Header(L["SET_GENERAL"], y)
    y = Check(L["SET_MINIMAP"], L["SET_MINIMAP_TIP"], y,
        function() return not (KHF.db and KHF.db.minimapIcon.hide) end,
        function(on) KHF.SetMinimapButton(on) end)
    y = SettingCheck("answerKeys", L["SET_KEYS"], L["SET_KEYS_TIP"], y)
    y = SettingCheck("toastGroup", L["SET_TOAST"], L["SET_TOAST_TIP"], y)
    y = SettingCheck("boardFull", L["SET_BOARD_FULL"], L["SET_BOARD_FULL_TIP"], y)
    y = SettingCheck("reduceMotion", L["SET_MOTION"], L["SET_MOTION_TIP"], y)

    y = y - 6
    scaleSlider = KHF.Theme.CreateSlider(child, 300, {
        label = L["SET_SCALE"], min = 0.5, max = 1.5, step = 0.05,
        value = KHF.GetSetting("quizScale") or 1, default = KHF.DEFAULTS.quizScale,
        onChange = function(v) KHF.SetSetting("quizScale", v) end,
    })
    scaleSlider:SetPoint("TOPLEFT", child, "TOPLEFT", LABEL_X + 10, y)
    return y - 48 - 16
end

--------------------------------------------------------------------------------
-- SOUNDS
--------------------------------------------------------------------------------
local Sounds = function() return KHF.Sounds end

local function SoundRow(m, y)
    local label = Label(L[m.label], y)
    local dd = Dropdown(y, DD_W)
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
    local hit = CreateFrame("Frame", nil, child)
    hit:SetAllPoints(label)
    hit:EnableMouse(true)
    KHF.SetTooltip(hit, L[m.label], tip)

    local play = KHF.CreateButton(child, L["SND_PLAY"], PLAY_W, 22)
    play:SetPoint("LEFT", dd, "RIGHT", 6, 0)
    play:SetScript("OnClick", function() Sounds().Preview(Sounds().Get(moment)) end)
    KHF.SetTooltip(play, L["SND_PLAY"], L["SND_PLAY_TIP"])
    soundRows[#soundRows + 1] = { dd = dd, play = play, moment = moment }
    return y - ROW
end

local function BuildSounds(y)
    y = Header(L["SET_SOUNDS"], y)
    y = Check(L["SND_ON"], L["SND_ON_TIP"], y,
        function() return KHF.db and KHF.db.sounds.on end,
        function(on) Sounds().SetOn(on) end)

    y = y - 4
    Label(L["SND_CHANNEL"], y)
    chanDD = Dropdown(y, DD_W)
    chanDD:SetupMenu(function(_, root)
        for _, c in ipairs(Sounds().CHANNELS) do
            root:CreateRadio(L[c.label], function() return (KHF.db and KHF.db.sounds.channel) == c.key end,
                function() Sounds().SetChannel(c.key) end)
        end
    end)
    KHF.SetTooltip(chanDD, L["SND_CHANNEL"], L["SND_CHANNEL_TIP"])
    y = y - ROW
    y = Note(L["SND_VOLUME_NOTE"], y + 8)

    for _, m in ipairs(Sounds().MOMENTS) do
        if m.group then
            y = SubHeader(L[m.group], y)
            if m.group == "SND_GROUP_MUSIC" then y = Note(L["SND_MUSIC_NOTE"], y) end
        else
            y = SoundRow(m, y)
        end
    end
    return y - 10
end

--------------------------------------------------------------------------------
-- THE PAGE
--------------------------------------------------------------------------------
local function Refresh()
    if not child then return end
    for _, c in ipairs(checks) do c.cb:SetChecked(c.get() and true or false) end
    if scaleSlider then scaleSlider:SetValue(KHF.GetSetting("quizScale") or 1) end
    local on = KHF.db and KHF.db.sounds.on
    if chanDD then chanDD:GenerateMenu() end
    for _, r in ipairs(soundRows) do
        r.dd:GenerateMenu()
        r.play:SetEnabled(on and KHF.Sounds.IsSet(r.moment) or false)
    end
end

local function Build(page)
    local scroll = CreateFrame("ScrollFrame", nil, page)
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -BAR_ROOM, 6)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    KHF.Theme.AttachScrollBar(scroll)
    scroll:HookScript("OnSizeChanged", function(self, w) child:SetWidth(w or self:GetWidth()) end)

    local y = -6
    y = BuildGeneral(y)
    y = BuildSounds(y)
    child:SetHeight(-y)

    page:HookScript("OnShow", Refresh)
    Refresh()
end
KHF.PageBuilders.TAB_SETTINGS = Build

-- A setting changed somewhere else (/kahoof minimap, the board's toggle)
KHF.RegisterMessage("SettingsTab", "SettingChanged", function()
    if child and child:IsVisible() then Refresh() end
end)
