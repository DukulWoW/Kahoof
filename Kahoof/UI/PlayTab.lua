-- Kahoof UI/PlayTab.lua: the Play tab of the main window (S5b)
-- Where a quiz is started (Dukul, 2026-11-02: "Play tab"): the quiz, the
-- start options and Practice. S9 adds "Open lobby" beside Practice and the
-- open lobbies above it; the options are the same for both.
--
-- Start options (game-engine.md): read time (none / 2-10 s / you start the
-- clock), leaderboard timing (every question / every 5 / only at the end),
-- several correct answers (pick all / any one counts), randomize answers
-- (starts as the quiz's own setting, ALL-40) and auto-advance. The read time
-- and auto-advance begin at their Settings defaults; the choices stay for
-- the session.

local _, KHF = ...
local L = KHF.L
local QuizStore = KHF.QuizStore

local LABEL_X, CTRL_X = 10, 200
local ROW_Y0, ROW_STEP = -80, 36

local page, quizDD, readDD, boardDD, pickDD, shuffleCB, autoCB, startBtn, err
local sel      -- the chosen quiz id
local opts     -- the start options as chosen

local READ_CHOICES = { 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, -1 }
local BOARD_CHOICES = { { 1, "PT_BOARD_EACH" }, { 5, "PT_BOARD_FIVE" }, { 0, "PT_BOARD_END" } }
local PICK_CHOICES = { { "all", "PT_PICK_ALL" }, { "one", "PT_PICK_ONE" } }

local function ReadLabel(t)
    if t == 0 then return L["PT_READ_NONE"] end
    if t < 0 then return L["PT_READ_MANUAL"] end
    return string.format(L["PT_SECONDS"], t)
end

local function Options()
    if not opts then
        opts = { read = KHF.GetSetting("readTime"), board = 1, pick = "all",
                 shuffle = false, auto = KHF.GetSetting("autoAdvance") and true or false }
    end
    return opts
end

-- A new quiz chosen: Randomize starts as that quiz's own setting
local function Choose(id)
    sel = id
    local quiz = id and QuizStore.Get(id)
    Options().shuffle = quiz and quiz.shuffle == true or false
    if shuffleCB then shuffleCB:SetChecked(opts.shuffle) end
    if err then err:SetText("") end
end

--------------------------------------------------------------------------------
-- CONTROLS
--------------------------------------------------------------------------------
local function Label(text, y)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("LEFT", page, "TOPLEFT", LABEL_X, y)
    fs:SetText(text)
    return fs
end

local function Dropdown(y, width)
    local dd = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dd:SetWidth(width)
    dd:SetPoint("LEFT", page, "TOPLEFT", CTRL_X, y)
    return dd
end

-- A check box whose label is part of the click area (BNB's checkbox rule)
local function Check(text, y, tip, onClick)
    local cb = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("LEFT", page, "TOPLEFT", CTRL_X - 4, y)
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetHitRectInsets(0, -(fs:GetStringWidth() + 4), 0, 0)
    cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    KHF.SetTooltip(cb, text, tip)
    return cb
end

local function BuildQuizDropdown(y)
    Label(L["PT_QUIZ"], y)
    quizDD = Dropdown(y, 320)
    -- SetupMenu runs this at once (CLAUDE.md): the store is ready by then
    quizDD:SetupMenu(function(_, root)
        if root.SetScrollMode then root:SetScrollMode(20 * 20) end
        for _, q in ipairs(QuizStore.List()) do
            local id = q.id
            local text = KHF.EscapeText(q.title)
            if q.count == 1 then text = text .. "  |cff888888" .. L["QUIZ_COUNT_ONE"] .. "|r"
            else text = text .. "  |cff888888" .. string.format(L["QUIZ_COUNT"], q.count) .. "|r" end
            root:CreateRadio(text, function() return sel == id end, function() Choose(id) end)
        end
    end)
end

local function BuildOptions()
    local y = ROW_Y0 - ROW_STEP
    Label(L["PT_READ"], y)
    readDD = Dropdown(y, 200)
    readDD:SetupMenu(function(_, root)
        for _, t in ipairs(READ_CHOICES) do
            root:CreateRadio(ReadLabel(t), function() return Options().read == t end,
                function() Options().read = t end)
        end
    end)

    y = y - ROW_STEP
    Label(L["PT_BOARD"], y)
    boardDD = Dropdown(y, 200)
    boardDD:SetupMenu(function(_, root)
        for _, c in ipairs(BOARD_CHOICES) do
            root:CreateRadio(L[c[2]], function() return Options().board == c[1] end,
                function() Options().board = c[1] end)
        end
    end)

    y = y - ROW_STEP
    Label(L["PT_PICK"], y)
    pickDD = Dropdown(y, 200)
    pickDD:SetupMenu(function(_, root)
        for _, c in ipairs(PICK_CHOICES) do
            root:CreateRadio(L[c[2]], function() return Options().pick == c[1] end,
                function() Options().pick = c[1] end)
        end
    end)
    KHF.SetTooltip(pickDD, L["PT_PICK"], L["PT_PICK_TIP"])

    y = y - ROW_STEP
    shuffleCB = Check(L["ED_SHUFFLE"], y, L["PT_SHUFFLE_TIP"], function(on) Options().shuffle = on end)
    y = y - 30
    autoCB = Check(L["PT_AUTO"], y, L["PT_AUTO_TIP"], function(on) Options().auto = on end)
    return y
end

local function StartPractice()
    if not sel then return end
    local o = KHF.DeepCopy(Options())
    local ok, msg = KHF.Practice.Start(sel, o)
    if not ok then
        err:SetText(msg)
        return
    end
    err:SetText("")
    KHF.QuizUI.lastStart = { id = sel, opts = KHF.DeepCopy(o) }
    KHF.HideMainWindow()   -- the quiz window takes the stage; /kahoof brings this back
end

-- The list may have changed (a quiz deleted, renamed, added)
local function Refresh()
    if not page then return end
    local found = false
    local list = QuizStore.List()
    for _, q in ipairs(list) do
        if q.id == sel then found = true end
    end
    if not found then Choose(list[1] and list[1].id or nil) end
    quizDD:GenerateMenu()
    shuffleCB:SetChecked(Options().shuffle)
    autoCB:SetChecked(Options().auto)
    startBtn:SetEnabled(sel ~= nil)
end

--------------------------------------------------------------------------------
-- THE PAGE (built by UI/MainWindow.lua on the window's first open)
--------------------------------------------------------------------------------
local function Build(p)
    page = p
    local head = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", p, "TOPLEFT", LABEL_X, -12)
    head:SetText(L["PT_HEAD"])
    local intro = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    intro:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText(L["PT_INTRO"])

    -- the quiz row sits under the intro, the options under it
    BuildQuizDropdown(ROW_Y0)
    local y = BuildOptions()

    startBtn = KHF.CreateButton(p, L["PT_PRACTICE"], 140, 26)
    startBtn:SetPoint("TOPLEFT", p, "TOPLEFT", CTRL_X, y - 40)
    startBtn:SetScript("OnClick", StartPractice)
    KHF.SetTooltip(startBtn, L["PT_PRACTICE"], L["PT_PRACTICE_TIP"])

    err = p:CreateFontString(nil, "OVERLAY", "GameFontRed")
    err:SetPoint("LEFT", startBtn, "RIGHT", 12, 0)
    err:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    err:SetJustifyH("LEFT")

    local later = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    later:SetPoint("TOPLEFT", startBtn, "BOTTOMLEFT", -(CTRL_X - LABEL_X), -24)
    later:SetPoint("RIGHT", p, "RIGHT", -10, 0)
    later:SetJustifyH("LEFT")
    later:SetText(L["PT_HOST_LATER"])

    -- Kahoof_Dev's controls (the bots, S6); nothing without it
    if KHF.Dev and KHF.Dev.PlayTabRow then pcall(KHF.Dev.PlayTabRow, p, later) end

    p:HookScript("OnShow", Refresh)
    Refresh()
end
KHF.PageBuilders.TAB_PLAY = Build

KHF.RegisterMessage("PlayTab", "QuizzesChanged", function()
    if page and page:IsVisible() then Refresh() end
end)
