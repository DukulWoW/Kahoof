-- Kahoof UI/QuizWindow.lua: the quiz window, shared by players and the host (S5b)
-- One window (windows-widgets.md): fixed layout, no grip, scaled by the
-- quizScale setting, its place saved. The screens are drawn by
-- UI/QuizPlay.lua (get ready, question, answers, reveal) and UI/QuizBoard.lua
-- (leaderboard, results); this file is the frame, the bottom bar (Leave, the
-- host's buttons, Close), the "Quiz running" button, the answer keys and the
-- key bindings.
--
-- The engine never calls this file: it follows the message bus
-- (SessionState, QuestionShown, AnswerCount, Revealed, BoardUpdated,
-- QuizEnded) and draws what the session tables hold. It draws the PLAYER's
-- session; the host bar reads the host's session when this client hosts it
-- (practice: you are both). A network host's buttons are in its own window
-- (UI/HostWindow.lua, ALL-62, S10): here it keeps Stop quiz.
--
-- S10: Stop quiz (host) and Leave quiz (player) ask "Are you sure?" first in
-- a network quiz, never in practice (Dukul, 2026-11-02: "Yes."). While the
-- host has paused, a dark cover with "Paused by host" hides the screen
-- (ALL-66: no free reading time).
--
-- ESC (and the red X) only hide the window: the quiz keeps running and the
-- small "Quiz running" button brings it back. Leaving is its own button.
--
-- Answer keys (Dukul, 2026-11-02: "Yes, a setting, on by default"; Space
-- sends: "make Space be the "answer" so you can play with one hand"): while
-- you can answer and out of combat, 1-4 (and the number pad) tick or answer
-- and Space sends ticked answers. Any other key, a key with a modifier, and
-- Space with nothing ticked go on to the game. In combat the window takes no
-- keys at all (KHF.AttachEscClose); the Key Bindings entries work there.
--
--   KHF.QuizUI.Show() / Hide() / Frame()
--   KHF.QuizUI.AnswerKey(n) -> true when taken    (keys, bindings, clicks)
--   KHF.QuizUI.SendKey()    -> true when sent
--   KHF.QuizUI.lastStart    { id, opts } of the last practice (Play again)
--   Kahoof.BindAnswer(n) / Kahoof.BindSend()      called by Bindings.xml

local _, KHF = ...
local L = KHF.L

local QuizUI = {}
KHF.QuizUI = QuizUI

local WIN_W, WIN_H = 640, 460
local BAR_H = 28

-- Shared by the screen files
QuizUI.BRAND = { 0.910, 0.486, 0.129 }   -- #e87c21, Kahoof's color (Dukul, 2026-11-02)
QuizUI.MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- Star, Circle, Diamond, Triangle, each in its marker's color (CLAUDE.md)
QuizUI.MARKER_COLOR = {
    { 1.00, 0.85, 0.10 },
    { 1.00, 0.50, 0.10 },
    { 0.75, 0.35, 1.00 },
    { 0.25, 0.85, 0.25 },
}

local win, area, bar, play, board, runBtn, cover

-- The name as shown: your own realm left out (Retail keys are Name-Realm;
-- Forever keys are the full name already)
function QuizUI.ShortName(key)
    key = tostring(key or "?")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and realm ~= "" then
        local tail = "-" .. realm
        if key:sub(-#tail) == tail then key = key:sub(1, -#tail - 1) end
    end
    return KHF.EscapeText(key)
end

-- The player's session once its quiz began (a lobby you wait in is the
-- Play tab's, S9: s.prestart)
local function PS()
    local s = KHF.Player.Get()
    if s and not s.prestart then return s end
    return nil
end

-- The host session that belongs to the shown quiz (practice: the same id)
local function HS(ps)
    local hs = KHF.Host.Get()
    if hs and ps and hs.id == ps.id and KHF.Host.IsRunning() then return hs end
    return nil
end

local function Done(ps)
    return ps.state == "FINAL" or ps.state == "ENDED"
end

-- The network host of the shown quiz (watching or playing): its buttons are
-- in the host window
local function NetHost(ps)
    local hs = HS(ps)
    return hs and not hs.loopback and hs or nil
end
QuizUI.NetHost = function() return NetHost(PS()) end

--------------------------------------------------------------------------------
-- LEAVING
--------------------------------------------------------------------------------
-- Leave mid-quiz, or close a finished one. Practice, and a host watching or
-- playing its own quiz: both sides go (the host's Stop cancels it for everyone).
local function LeaveQuiz()
    local ps = PS()
    if ps and (ps.loopback or ps.watch or HS(ps)) then KHF.Practice.Stop() else KHF.Player.Leave() end
    QuizUI.Refresh()
end

-- Stop mid-quiz: back to the main window (Dukul, 2026-11-02, ALL-48)
local function DoStop()
    local ps = PS()
    local mine = ps and (ps.loopback or ps.watch or HS(ps)) and true or false
    LeaveQuiz()
    if mine then KHF.ShowMainWindow() end
end

StaticPopupDialogs["KAHOOF_STOP_QUIZ"] = {
    text = L["QW_STOP_CONFIRM"], button1 = L["QW_YES"], button2 = L["QW_NO"],
    OnAccept = function() DoStop() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
StaticPopupDialogs["KAHOOF_LEAVE_QUIZ"] = {
    text = L["QW_LEAVE_CONFIRM"], button1 = L["QW_YES"], button2 = L["QW_NO"],
    OnAccept = function() DoStop() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Practice stops at once; a network quiz asks first
local function StopOrLeave()
    local ps = PS()
    if not ps or ps.loopback then return DoStop() end
    StaticPopup_Show(NetHost(ps) and "KAHOOF_STOP_QUIZ" or "KAHOOF_LEAVE_QUIZ")
end

-- The end page's Main Menu (ALL-50)
local function ToMainMenu()
    LeaveQuiz()
    KHF.ShowMainWindow()
end

local function PlayAgain()
    local last = QuizUI.lastStart
    if not last then return end
    KHF.Practice.Stop()
    local ok, msg = KHF.Practice.Start(last.id, KHF.DeepCopy(last.opts))
    if not ok then KHF:Print(msg) end
    QuizUI.Refresh()
end

--------------------------------------------------------------------------------
-- THE BOTTOM BAR: Leave + the host's buttons; at the end Play again, Main
-- Menu (bigger, in the middle) and Close, centered (Dukul, 2026-11-02, ALL-50)
-- Page fades (Dukul, 2026-11-04: "add some fades between pages, right now
-- it's very jarring"): a new page (Get ready, each question, each
-- leaderboard, the results) fades in from the window's background. The
-- changes inside one question (the clock starting, the reveal) do not.
local FADE = 0.3

local function MakeFade(f)
    local ag = f:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(FADE)
    a:SetSmoothing("OUT")
    f._fade = ag
end

local function PageKey(ps)
    if ps.state == "FINAL" then return ":final" end
    if ps.state == "STARTING" then return ":ready" end
    if ps.state == "BOARD" then return ":board" .. tostring(ps.qi) end
    return ":q" .. tostring(ps.qi)
end

--------------------------------------------------------------------------------
local function BuildBar()
    bar = CreateFrame("Frame", nil, win.content)
    bar:SetHeight(BAR_H)
    bar:SetPoint("BOTTOMLEFT", win.content, "BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", win.content, "BOTTOMRIGHT", 0, 0)

    bar.leave = KHF.CreateButton(bar, L["QW_LEAVE"], 120, 24)
    bar.leave:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.leave:SetScript("OnClick", StopOrLeave)

    bar.count = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.count:SetPoint("LEFT", bar.leave, "RIGHT", 12, 0)

    bar.next = KHF.CreateButton(bar, L["QW_NEXT"], 100, 24)
    bar.next:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.next:SetScript("OnClick", function() KHF.Host.Next() end)
    KHF.SetTooltip(bar.next, L["QW_NEXT"], L["QW_NEXT_TIP"])

    bar.stop = KHF.CreateButton(bar, L["QW_END"], 80, 24)
    bar.stop:SetPoint("RIGHT", bar.next, "LEFT", -6, 0)
    bar.stop:SetScript("OnClick", function() KHF.Host.End() end)
    KHF.SetTooltip(bar.stop, L["QW_END"], L["QW_END_TIP"])

    bar.skip = KHF.CreateButton(bar, L["QW_SKIP"], 80, 24)
    bar.skip:SetPoint("RIGHT", bar.stop, "LEFT", -6, 0)
    bar.skip:SetScript("OnClick", function() KHF.Host.Skip() end)
    KHF.SetTooltip(bar.skip, L["QW_SKIP"], L["QW_SKIP_TIP"])

    bar.clock = KHF.CreateButton(bar, L["QW_START_CLOCK"], 130, 24)
    bar.clock:SetPoint("RIGHT", bar.skip, "LEFT", -6, 0)
    bar.clock:SetScript("OnClick", function() KHF.Host.StartClock() end)
    KHF.SetTooltip(bar.clock, L["QW_START_CLOCK"], L["QW_START_CLOCK_TIP"])

    bar.menu = KHF.CreateButton(bar, L["QW_MAIN_MENU"], 150, 28)
    bar.menu:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.menu:SetScript("OnClick", ToMainMenu)

    bar.again = KHF.CreateButton(bar, L["QW_AGAIN"], 110, 24)
    bar.again:SetPoint("RIGHT", bar.menu, "LEFT", -10, 0)
    bar.again:SetScript("OnClick", PlayAgain)

    bar.close = KHF.CreateButton(bar, L["CLOSE"], 110, 24)
    bar.close:SetPoint("LEFT", bar.menu, "RIGHT", 10, 0)
    bar.close:SetScript("OnClick", LeaveQuiz)
end

local function CountIn(hs)
    local n, total = 0, 0
    for slot in pairs(hs.inQuestion or {}) do
        total = total + 1
        if hs.answers and hs.answers[slot] then n = n + 1 end
    end
    return n, total
end

local QUESTION_UP = { READING = true, ANSWERING = true, REVEAL = true }

local function UpdateBar(ps)
    local done = Done(ps)
    local net = NetHost(ps)
    if ps.loopback then bar.leave:SetText(L["QW_STOP"])
    elseif net then bar.leave:SetText(L["QW_STOP_QUIZ"])
    else bar.leave:SetText(L["QW_LEAVE"]) end
    bar.leave:SetShown(not done)
    bar.close:SetShown(done)
    bar.menu:SetShown(done)
    bar.again:SetShown(done and ps.loopback and QuizUI.lastStart ~= nil)

    -- a network host's buttons are in the host window (ALL-62)
    local hs = not done and not net and HS(ps)
    for _, b in ipairs({ bar.next, bar.stop, bar.skip }) do b:SetShown(hs and true or false) end
    bar.clock:SetShown(hs and hs.state == "READING" and hs.opts.read < 0 or false)
    if not hs then
        bar.count:SetText("")
        return
    end
    if QUESTION_UP[hs.state] then
        bar.count:SetText(string.format(L["QW_IN_COUNT"], CountIn(hs)))
    else
        bar.count:SetText("")
    end
    bar.skip:SetEnabled(hs.state == "READING" or hs.state == "ANSWERING")
    bar.stop:SetEnabled(hs.state ~= "STARTING")
    bar.next:SetEnabled(hs.state == "BOARD" or (hs.state == "REVEAL" and hs.board ~= nil and not hs.board.show))
    bar.next:SetText((hs.qi >= hs.count) and L["QW_RESULTS"] or L["QW_NEXT"])
end

--------------------------------------------------------------------------------
-- "QUIZ RUNNING": brings the hidden window back. Draggable, its place saved
-- (center in screen px, as the windows); empty = top center.
--------------------------------------------------------------------------------
local function PlaceRunButton()
    local pos = KHF.db and KHF.db.windows and KHF.db.windows.quizButton
    runBtn:ClearAllPoints()
    if pos and pos.x and pos.y then
        local s = runBtn:GetEffectiveScale()
        runBtn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / s, pos.y / s)
    else
        runBtn:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function BuildRunButton()
    runBtn = KHF.CreateButton(UIParent, L["QW_RUNNING"], 130, 26)
    runBtn:Hide()
    runBtn:SetFrameStrata("MEDIUM")
    runBtn:SetMovable(true)
    runBtn:SetClampedToScreen(true)
    runBtn:RegisterForDrag("LeftButton")
    runBtn:SetScript("OnDragStart", function(self) KHF.StartDragMoving(self) end)
    runBtn:SetScript("OnDragStop", function(self)
        KHF.StopDragMoving(self)
        if not (KHF.db and KHF.db.windows) then return end
        local s = self:GetEffectiveScale()
        local x, y = self:GetCenter()
        if x and y then KHF.db.windows.quizButton = { x = x * s, y = y * s } end
    end)
    runBtn:SetScript("OnClick", function() QuizUI.Show() end)
    KHF.SetTooltip(runBtn, L["QW_RUNNING"], L["QW_RUNNING_TIP"])
    PlaceRunButton()
end

local function UpdateRunButton()
    runBtn:SetShown(PS() ~= nil and not win:IsShown())
end

--------------------------------------------------------------------------------
-- KEYS (out of combat; the wrapper hands over no key in combat)
--------------------------------------------------------------------------------
local KEY_N = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4,
                NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4 }

local function OnKey(_, key)
    if not KHF.GetSetting("answerKeys") or IsModifierKeyDown() then return false end
    local n = KEY_N[key]
    if n then return QuizUI.AnswerKey(n) end
    if key == "SPACE" then return QuizUI.SendKey() end
    return false
end

-- answer-click.ogg on every answer, tick and send that is taken (S9, Dukul:
-- "convert answer-click.mp3 to .ogg and add that too")
function QuizUI.AnswerKey(n)
    local ps = PS()
    local ok = (play and ps and play:Pick(ps, n)) or false
    if ok then KHF.PlaySound("answer-click") end
    return ok
end

function QuizUI.SendKey()
    local ps = PS()
    local ok = (play and ps and play:Send(ps)) or false
    if ok then KHF.PlaySound("answer-click") end
    return ok
end

-- Bindings.xml (they work in combat too: answering is no protected action)
function KHF.BindAnswer(n) QuizUI.AnswerKey(n) end
function KHF.BindSend() QuizUI.SendKey() end

-- The Key Bindings names: globals the game reads, like SLASH_KAHOOF1
BINDING_NAME_KAHOOF_ANSWER1 = L["BIND_ANSWER_1"]
BINDING_NAME_KAHOOF_ANSWER2 = L["BIND_ANSWER_2"]
BINDING_NAME_KAHOOF_ANSWER3 = L["BIND_ANSWER_3"]
BINDING_NAME_KAHOOF_ANSWER4 = L["BIND_ANSWER_4"]
BINDING_NAME_KAHOOF_SEND    = L["BIND_SEND"]

--------------------------------------------------------------------------------
-- THE WINDOW
--------------------------------------------------------------------------------
local function Build()
    win = KHF.CreateWindow({
        name = "KahoofQuizWindow",
        w = WIN_W, h = WIN_H,
        posKey = "quiz",
        onKey = OnKey,
    })
    win:SetScale(KHF.GetSetting("quizScale") or 1)
    -- The logo top left; the quiz title keeps the same inset on both sides,
    -- so it stays centered and a long one ends in "..." before the logo
    -- (Dukul, 2026-11-04: "make sure that the quiz name can't be obscured")
    local LOGO_X = 10
    KHF.AddTitleLogo(win, "TOPLEFT", LOGO_X)
    win._titleText:SetWidth(WIN_W - 2 * (LOGO_X + KHF.LOGO_W + 6))
    win._titleText:SetWordWrap(false)
    BuildBar()
    -- The screens' area: the content above the bar
    area = CreateFrame("Frame", nil, win.content)
    area:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, 0)
    area:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 6)
    play = QuizUI.BuildPlay(area)
    board = QuizUI.BuildBoard(area)
    MakeFade(play)
    MakeFade(board)
    -- "Paused by host" (ALL-66): a dark cover over the screens, not the bar
    cover = CreateFrame("Frame", nil, area)
    cover:SetAllPoints()
    cover:SetFrameLevel(area:GetFrameLevel() + 20)
    cover:EnableMouse(true)   -- no clicks on the answers underneath
    local dark = cover:CreateTexture(nil, "BACKGROUND")
    dark:SetAllPoints()
    dark:SetColorTexture(0, 0, 0, 0.92)
    local ct = cover:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    ct:SetPoint("CENTER", cover, "CENTER", 0, 20)
    ct:SetText(L["QW_PAUSED"])
    local cs = cover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cs:SetPoint("TOP", ct, "BOTTOM", 0, -10)
    cs:SetText(L["QW_PAUSED_SUB"])
    cover:Hide()
    BuildRunButton()
    win:HookScript("OnShow", function()
        QuizUI.Refresh()
        if KHF.HostWindow then KHF.HostWindow.Refresh(true) end   -- back with it, even after its X
    end)
    win:HookScript("OnHide", function()
        play:StopTicking()
        UpdateRunButton()
        if KHF.HostWindow then KHF.HostWindow.Refresh() end
    end)
end

function QuizUI.Frame() return win end

-- Draws the shown session; hides everything when there is none
local lastPage   -- the page last shown: a new one fades in
function QuizUI.Refresh()
    if not win then return end
    local ps = PS()
    if not ps then
        play:StopTicking()
        win:Hide()
        runBtn:Hide()
        return
    end
    UpdateRunButton()
    if not win:IsShown() then return end
    win:SetWindowTitle(KHF.EscapeText(ps.title))
    local shown
    if ps.state == "BOARD" or ps.state == "FINAL" then
        play:Hide()
        board:Draw(ps)
        shown = board
    else
        board:Hide()
        play:Draw(ps)
        shown = play
    end
    local page = ps.id .. PageKey(ps)
    if page ~= lastPage then
        lastPage = page
        shown._fade:Stop()
        shown._fade:Play()
    end
    cover:SetShown(KHF.Session.Held(ps, "pause") and not Done(ps))
    UpdateBar(ps)
end

function QuizUI.Show()
    if not win then Build() end
    -- reopened mid-count: the board jumps to the end (ALL-65, Dukul: "Jump to the end")
    if not win:IsShown() then board:FinishAnim() end
    win:Show()
    win:Raise()
end

function QuizUI.Hide()
    if win then win:Hide() end
end

--------------------------------------------------------------------------------
-- THE BUS
--------------------------------------------------------------------------------
local function OnState(_, s, state)
    -- a new quiz you play in: the window comes up by itself
    if s.role == "player" and state == "STARTING" then QuizUI.Show() end
    QuizUI.Refresh()
end

KHF.RegisterMessage("QuizWindow", "SessionState", OnState)
for _, m in ipairs({ "QuestionShown", "AnswerCount", "Revealed", "BoardUpdated", "QuizEnded",
                    "QuizPaused", "SendQueueEmpty" }) do
    KHF.RegisterMessage("QuizWindow", m, function() QuizUI.Refresh() end)
end

KHF.RegisterMessage("QuizWindow", "SettingChanged", function(_, key)
    if not win then return end
    if key == "quizScale" then win:SetScale(KHF.GetSetting("quizScale") or 1) end
    if key == "boardFull" then QuizUI.Refresh() end
end)

KHF.RegisterMessage("QuizWindow", "WindowsReset", function()
    if not win then return end
    if win:IsShown() then KHF.RestoreWindowPos(win) end
    PlaceRunButton()
end)
