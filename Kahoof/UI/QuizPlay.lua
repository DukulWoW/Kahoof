-- Kahoof UI/QuizPlay.lua: the quiz window's question screen (S5b)
-- Get ready, the question (read time), the four answers (2 x 2, Dukul,
-- 2026-11-02: "2 x 2 grid"), answer sent / time's up, and the reveal. Drawn
-- from the player's session table (Core/Player.lua): s.q, s.my, s.reveal,
-- s.board; never decides what is right (game-engine.md: the host does).
--
-- One pick: a click (or key 1-4) answers. Several (ALL-33, "Pick 2
-- answers"): clicks / keys tick, at most q.pick, and Answer (or Space) sends.
-- The countdown is one OnUpdate on one frame, set only while a clock runs
-- (CLAUDE.md: nothing polls while no quiz runs). It moves the bar every frame
-- (smooth, ALL-56), shakes the seconds from 10 (ALL-54) and drives the raid
-- countdown numbers of Get ready and the read time (ALL-55). Those pieces and
-- the game art are UI/QuizCountdown.lua.
--
--   KHF.QuizUI.BuildPlay(area) -> screen
--   screen:Draw(s) / Hide() / StopTicking()
--   screen:Pick(s, n) -> true when the key / click was taken
--   screen:Send(s)    -> true when ticked answers were sent

local _, KHF = ...
local L = KHF.L
local QuizUI = KHF.QuizUI
local S = KHF.Session

-- Layout, from the top of the area (UI units; the area is ~612 x 380)
local Y_Q, Q_H       = -24, 70
local LINE_PAD       = 22        -- the shadow band behind the question: the text's height + this (ALL-58)
local Y_CLOCK, CLK_H = -116, 24  -- the time bar, border included (here when no question shows)
local Y_GRID, ANS_H, GAP = -172, 76, 8
local Y_FOOT, FOOT_H = -338, 40
local Y_IN, Y_NUM    = -184, -258   -- "Answers in" and the raid number, centered on the grid's place
local Y_READY, READY_W, READY_H = -60, 560, 58   -- the Get ready bar (N1: bigger, room to spare)
local TIMER_X, TIMER_Y = -2, 0      -- the seconds, top right (they shake from 10)

local CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"
local RIGHT_TEX = "Interface\\RaidFrame\\ReadyCheck-Ready"
local WRONG_TEX = "Interface\\RaidFrame\\ReadyCheck-NotReady"
-- The time bar, the Get ready bar and the line under the question are our own
-- art (UI/QuizCountdown.lua, Kahoof/Assets/Quiz; ALL-56 to ALL-58, after M8-M11).
local GREEN, RED, GRAY = { 0.3, 1, 0.3 }, { 1, 0.3, 0.3 }, { 0.6, 0.6, 0.6 }

local P = {}   -- the screen's methods
local ticks, tickKey = {}, nil   -- answers ticked on a several-pick question

local function TickCount()
    local n = 0
    for _ in pairs(ticks) do n = n + 1 end
    return n
end

-- Ticks belong to one question of one session
local function SyncTicks(s)
    local key = tostring(s.id) .. ":" .. tostring(s.qi)
    if key ~= tickKey then
        wipe(ticks)
        tickKey = key
    end
end

-- Text that must fit its box steps down through these sizes until it does
-- (Dukul, 2026-11-02: "With really long answers, it cuts off the text ...
-- Should probably shrink text to fit?")
local Q_FONTS = { "GameFontHighlightHuge", "GameFontHighlightLarge", "GameFontHighlightMedium", "GameFontHighlight" }
local A_FONTS = { "GameFontHighlightLarge", "GameFontHighlightMedium", "GameFontHighlight", "GameFontHighlightSmall" }
local A_TEXT_PAD = 22   -- an answer button's height minus the room for its text

-- Sets text in the biggest size that is neither cut short nor taller than maxH
local function FitText(fs, text, fonts, maxH)
    for _, name in ipairs(fonts) do
        local fo = _G[name]
        if fo then
            fs:SetFontObject(fo)
            fs:SetText(text)
            if not fs:IsTruncated() and fs:GetStringHeight() <= maxH then return end
        end
    end
end

--------------------------------------------------------------------------------
-- ANSWER BUTTONS (pooled: four, reused for every question; the click reads
-- the button's own _i). The look is Dukul's button art (QuizUI.SkinAnswer,
-- UI/QuizCountdown.lua); marker, text, key, count and check sit on top of it,
-- inside its frame.
--------------------------------------------------------------------------------
local function CreateAnswer(parent, i)
    local b = CreateFrame("Button", nil, parent)
    b:SetScript("OnClick", function(self) QuizUI.AnswerKey(self._i) end)
    QuizUI.SkinAnswer(b, i)
    -- Inside the frame: at 76 px high the art's fill runs from x 20 to w - 21
    -- and y 8 to 68, its bevel a few px more; everything sits inside that
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(32, 32)
    b.icon:SetPoint("LEFT", b, "LEFT", 30, 0)
    b.icon:SetTexture(QuizUI.MARKER_TEX .. i)
    -- the key that answers it (ALL-49): a small badge on the marker's corner,
    -- like an action bar's hotkey
    b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.key:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 5, -3)
    b.mark = b:CreateTexture(nil, "OVERLAY")
    b.mark:SetSize(22, 22)
    b.mark:SetPoint("TOPRIGHT", b, "TOPRIGHT", -26, -14)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 12, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -50, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetMaxLines(5)
    b.count = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -28, 14)
    return b
end

-- The key shown on answer i: its Key Binding when one is set, else the number
-- key when the answer keys are on (out of combat), else nothing
local function KeyText(i)
    local key = GetBindingKey and GetBindingKey("KAHOOF_ANSWER" .. i)
    if key then return GetBindingText(key, true) end
    if KHF.GetSetting("answerKeys") then return tostring(i) end
    return ""
end

-- look: "open", "ticked", "dim", "right", "wrong" (your wrong pick), "faded"
local function Paint(b, look)
    QuizUI.PaintAnswer(b, look)
    local tex = (look == "ticked" and CHECK_TEX) or (look == "right" and RIGHT_TEX)
        or (look == "wrong" and WRONG_TEX) or nil
    if tex then b.mark:SetTexture(tex); b.mark:Show() else b.mark:Hide() end
end

--------------------------------------------------------------------------------
-- THE COUNTDOWN
--------------------------------------------------------------------------------
local function Remaining(s)
    local now = S.Now()
    if s.state == "STARTING" then return S.START_DELAY - (now - s.stateAt), S.START_DELAY end
    local q = s.q
    if not q then return nil end
    if s.state == "READING" and q.read > 0 then return q.read - (now - s.stateAt), q.read end
    if (s.state == "ANSWERING" or s.state == "ANSWERED") and s.openAt then
        return q.limit - (now - s.openAt), q.limit
    end
    return nil
end

function P:Tick()
    local s = KHF.Player.Get()
    local left, total
    if s then left, total = Remaining(s) end
    if not left then
        self:StopTicking()
        return
    end
    left = math.max(0, left)
    local counting = s.state == "STARTING" or s.state == "READING"
    self.clock:SetFraction(total > 0 and left / total or 0)
    local secs = math.ceil(left)
    if counting then
        self.bigNum:SetNumber(secs)
        return
    end
    if secs ~= self._secs then
        self._secs = secs
        self.timer:SetText(secs)
        if left <= 5 then self.timer:SetTextColor(RED[1], RED[2], RED[3]) else self.timer:SetTextColor(1, 1, 1) end
    end
    QuizUI.Shake(self.timer, TIMER_X, TIMER_Y, left)
end

-- Every frame while a clock runs: the bar moves smoothly (ALL-56)
function P:StartTicking()
    if self._ticking then return end
    self._ticking = true
    self._secs = nil
    self.ticker:SetScript("OnUpdate", function() self:Tick() end)
    self:Tick()
end

function P:StopTicking()
    if not self._ticking then return end
    self._ticking = false
    self.ticker:SetScript("OnUpdate", nil)
    QuizUI.Shake(self.timer, TIMER_X, TIMER_Y, 99)   -- back in place
end

-- The shadow band sits BEHIND the question text, centered on it (Dukul,
-- 2026-11-02: "The black shadow thing behind text still isn't dead center
-- with text"), as tall as the text plus LINE_PAD; the time bar follows the
-- text's last line ("Follow the text"). With no question (Get ready, ended)
-- the bar sits at Y_CLOCK. The status line stays under the bar; the answers
-- never move.
function P:Flow(question)
    local y = Y_CLOCK
    if question then
        local h = math.min(self.qtext:GetStringHeight() or Q_H, Q_H)
        local mid = Y_Q - h / 2
        self.line:ClearAllPoints()
        self.line:SetPoint("LEFT", self, "TOPLEFT", 10, mid)
        self.line:SetPoint("RIGHT", self, "TOPRIGHT", -10, mid)
        self.line:SetHeight(h + LINE_PAD)
        y = Y_Q - h - LINE_PAD / 2 - 2
    end
    self.clock:ClearAllPoints()
    self.clock:SetPoint("TOPLEFT", self, "TOPLEFT", 10, y)
    self.clock:SetPoint("TOPRIGHT", self, "TOPRIGHT", -10, y)
    self.status:ClearAllPoints()
    self.status:SetPoint("TOPLEFT", self, "TOPLEFT", 10, y - CLK_H - 8)
    self.status:SetPoint("TOPRIGHT", self, "TOPRIGHT", -10, y - CLK_H - 8)
end

-- The time bar's first look (each frame's Tick moves it on)
function P:ClockLook()
    self.clock:SetFraction(1)
    self.clock:Show()
end

-- "Answers in" / "Starting in" over the raid number (ALL-55)
function P:ShowCount(label)
    self.inLabel:SetText(label)
    self.inLabel:Show()
    self.bigNum:Show()
end

--------------------------------------------------------------------------------
-- DRAWING, by state
--------------------------------------------------------------------------------
-- a long question steps down a size or more rather than spill out of its box
local function SetQuestionText(fs, text)
    FitText(fs, text, Q_FONTS, Q_H)
end

local function ResultLine(s)
    local r = s.reveal
    if r.void then return L["QW_RES_VOID"], GRAY end
    if not r.mine then return L["QW_RES_NONE"], RED end
    local b = s.board
    local mine = b and b.qid == s.qi and b.mine
    local text, color
    if r.right then text, color = L["QW_RES_RIGHT"], GREEN
    elseif r.partial then text, color = L["QW_RES_PARTIAL"], { 1, 0.82, 0 }
    else text, color = L["QW_RES_WRONG"], RED end
    if mine then
        if mine.points and mine.points > 0 then text = text .. string.format(L["QW_RES_POINTS"], mine.points) end
        if mine.time then text = text .. string.format(L["QW_RES_TIME"], mine.time / 10) end
    end
    return text, color
end

-- The grid for n answers (Dukul, 2026-11-02): four = 2 x 2; three = the same
-- size, the third centered on the bottom row; two = side by side, each the
-- full height of the grid ("the "big" version of button that fills the empty
-- area"). The art is 3-sliced, so the tall buttons keep their shape.
function P:LayoutGrid(n)
    if n == self._gridN then return end
    self._gridN = n
    local g = self.grid
    local half = (g:GetWidth() - GAP) / 2
    if half <= 0 then
        self._gridN = nil   -- not laid out yet: try again on the next draw
        half = 300
    end
    for i, b in ipairs(self.answers) do
        b:ClearAllPoints()
        local h = (n == 2) and (ANS_H * 2 + GAP) or ANS_H
        b:SetHeight(h)
        -- the art's bevel grows with the height: the insides keep clear of it
        local side, edge = h * 0.3, h * 0.13
        b.icon:SetPoint("LEFT", b, "LEFT", side + 8, 0)
        b.text:SetPoint("RIGHT", b, "RIGHT", -(side + 28), 0)
        b.mark:SetPoint("TOPRIGHT", b, "TOPRIGHT", -(side + 4), -(edge + 4))
        b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -(side + 6), edge + 4)
        local y = (i <= 2) and 0 or -(ANS_H + GAP)
        if n == 3 and i == 3 then
            b:SetPoint("TOP", g, "TOP", 0, y)
            b:SetWidth(half)
        elseif i % 2 == 1 then
            b:SetPoint("TOPLEFT", g, "TOPLEFT", 0, y)
            b:SetPoint("TOPRIGHT", g, "TOP", -GAP / 2, y)
        else
            b:SetPoint("TOPLEFT", g, "TOP", GAP / 2, y)
            b:SetPoint("TOPRIGHT", g, "TOPRIGHT", 0, y)
        end
    end
end

-- The four buttons for the shown state
function P:DrawAnswers(s)
    local q, st = s.q, s.state
    self:LayoutGrid(#q.answers)
    local r = (st == "REVEAL") and s.reveal or nil
    local mine = s.my and s.my.set or {}
    for i, b in ipairs(self.answers) do
        local a = q.answers[i]
        if a then
            FitText(b.text, KHF.EscapeText(a), A_FONTS, b:GetHeight() - A_TEXT_PAD)
            b.key:SetText((st == "ANSWERING" and not s.my) and KeyText(i) or "")
            b:SetEnabled(st == "ANSWERING" and not s.my)
            b.count:SetText("")
            if r then
                local n = r.counts[i] or 0
                local picked = string.format(L["QW_PICKED"], n)
                if r.mine and r.mine[i] then picked = L["QW_YOUR_PICK"] .. picked end
                b.count:SetText(picked)
                if r.void then Paint(b, "faded")
                elseif r.correct[i] then Paint(b, "right")
                elseif r.mine and r.mine[i] then Paint(b, "wrong")
                else Paint(b, "faded") end
            elseif s.my then
                Paint(b, mine[i] and "ticked" or "dim")
            elseif st == "ANSWERING" then
                Paint(b, ticks[i] and "ticked" or "open")
            else
                Paint(b, "dim")   -- CLOSED: time ran out, nothing sent
            end
            b:Show()
        else
            b:Hide()
        end
    end
    self.grid:Show()
end

function P:Draw(s)
    self:Show()
    SyncTicks(s)
    local st, q = s.state, s.q
    self.timer:SetText("")
    self.timer:SetTextColor(1, 1, 1)
    self.status:SetTextColor(1, 0.82, 0)
    self.status:SetText("")
    self.grid:Hide()
    self.clock:Hide()
    self.why:Hide()
    self.send:Hide()
    self.hint:Hide()
    self.inLabel:Hide()
    self.bigNum:Hide()   -- keeps its number: a redraw does not pop the same one again
    self.ready.box:Hide()
    self.line:Hide()

    if st == "STARTING" then
        if s.count == 1 then
            self.head:SetText(L["QW_ONE_QUESTION"])
        else
            self.head:SetText(string.format(L["QW_N_QUESTIONS"], s.count))
        end
        -- "Get ready!" big, inside the Get ready bar (ALL-57, N1)
        self.qtext:SetText("")
        self.ready.text:SetText(L["QW_GET_READY"])
        self.ready.box:Show()
        self:Flow(false)
        self:ShowCount(L["QW_STARTS_IN"])
        self:ClockLook()
        self:StartTicking()
        return
    end
    if st == "ENDED" or not q then
        self:StopTicking()
        self.head:SetText("")
        SetQuestionText(self.qtext, L["QW_ENDED"])
        self:Flow(false)
        self.status:SetText(L["QW_ENDED_HOST"])
        return
    end

    self.head:SetText(string.format(L["QW_QUESTION_N"], s.qi, s.count))
    SetQuestionText(self.qtext, KHF.EscapeText(q.text))
    self:Flow(true)
    self.line:Show()   -- the line under the question (ALL-58)

    if st == "READING" then
        if q.read > 0 then
            self:ShowCount(L["QW_ANSWERS_IN"])
            self:ClockLook()
            self:StartTicking()
        else
            self:StopTicking()
            self.status:SetText(L["QW_WAIT_CLOCK"])
        end
        return
    end

    self:DrawAnswers(s)
    if st == "ANSWERING" or st == "ANSWERED" then
        self:ClockLook()
        self:StartTicking()
    else
        self:StopTicking()
    end

    if st == "ANSWERING" then
        local keys = KHF.GetSetting("answerKeys")
        if q.pick > 1 then
            self.status:SetText(string.format(L["QW_PICK_N"], q.pick))
            self.send:SetEnabled(TickCount() > 0)
            self.send:Show()
            if keys then self.hint:SetText(L["QW_KEYS_MANY"]); self.hint:Show() end
        elseif keys then
            self.hint:SetText(L["QW_KEYS_ONE"])
            self.hint:Show()
        end
    elseif st == "ANSWERED" then
        self.status:SetText(L["QW_SENT"])
    elseif st == "CLOSED" then
        self.timer:SetText("0")
        self.status:SetText(L["QW_TIMES_UP"])
    elseif st == "REVEAL" and s.reveal then
        local text, color = ResultLine(s)
        self.status:SetText(text)
        self.status:SetTextColor(color[1], color[2], color[3])
        if s.reveal.why then
            self.why:SetText(string.format(L["QW_WHY"], KHF.EscapeText(s.reveal.why)))
            self.why:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- INPUT
--------------------------------------------------------------------------------
function P:Pick(s, n)
    local q = s.q
    if s.state ~= "ANSWERING" or not q or s.my or not q.answers[n] then return false end
    if q.pick == 1 then return KHF.Player.Answer(n) end
    SyncTicks(s)
    if ticks[n] then
        ticks[n] = nil
    elseif TickCount() < q.pick then
        ticks[n] = true
    end
    if self:IsShown() then self:Draw(s) end
    return true
end

function P:Send(s)
    local q = s.q
    if s.state ~= "ANSWERING" or not q or s.my or q.pick == 1 then return false end
    SyncTicks(s)
    local list = {}
    for i = 1, #q.answers do
        if ticks[i] then list[#list + 1] = i end
    end
    if #list == 0 then return false end
    return KHF.Player.Answer(list)
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------
function QuizUI.BuildPlay(area)
    local f = CreateFrame("Frame", nil, area)
    f:SetAllPoints()
    f:Hide()
    for k, fn in pairs(P) do f[k] = fn end
    f.ticker = CreateFrame("Frame", nil, f)

    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    f.timer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.timer:SetPoint("TOPRIGHT", f, "TOPRIGHT", TIMER_X, TIMER_Y)

    -- The Get ready bar (ALL-57, N1), between the top line and the time bar
    local box = CreateFrame("Frame", nil, f)
    box:SetSize(READY_W, READY_H)
    box:SetPoint("CENTER", f, "TOP", 0, Y_READY)
    f.ready = QuizUI.CreateReadyArt(box)
    box:Hide()

    f.qtext = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.qtext:SetPoint("TOPLEFT", f, "TOPLEFT", 10, Y_Q)
    f.qtext:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, Y_Q)
    f.qtext:SetHeight(Q_H)
    f.qtext:SetJustifyH("CENTER")
    f.qtext:SetJustifyV("TOP")

    -- the soft shadow line under the question (ALL-58)
    f.line = f:CreateTexture(nil, "BACKGROUND")
    f.line:SetTexture(QuizUI.ART.line)
    -- placed and sized by P:Flow
    f.line:Hide()

    f.clock = QuizUI.CreateClockBar(f, CLK_H)
    f.clock:SetHeight(CLK_H)   -- placed by P:Flow

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    -- placed by P:Flow, under the time bar
    f.status:SetJustifyH("CENTER")

    f.grid = CreateFrame("Frame", nil, f)
    f.grid:SetPoint("TOPLEFT", f, "TOPLEFT", 0, Y_GRID)
    f.grid:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, Y_GRID)
    f.grid:SetHeight(ANS_H * 2 + GAP)
    f.answers = {}
    for i = 1, 4 do
        f.answers[i] = CreateAnswer(f.grid, i)   -- placed by P:LayoutGrid
    end

    -- "Answers in" / "Starting in" and the raid number, where the grid goes (ALL-55)
    f.inLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.inLabel:SetPoint("TOP", f, "TOP", 0, Y_IN)
    f.inLabel:Hide()
    f.bigNum = QuizUI.CreateBigNumber(f)
    f.bigNum:SetPoint("CENTER", f, "TOP", 0, Y_NUM)
    f.bigNum:Hide()

    -- Under the grid: the explanation at the reveal, or Answer + the key hint
    f.why = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.why:SetPoint("TOPLEFT", f, "TOPLEFT", 10, Y_FOOT)
    f.why:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, Y_FOOT)
    f.why:SetHeight(FOOT_H)
    f.why:SetJustifyH("CENTER")
    f.why:SetJustifyV("TOP")
    f.send = KHF.CreateButton(f, L["QW_ANSWER"], 140, 26)
    f.send:SetPoint("TOP", f, "TOP", 0, Y_FOOT - 4)
    f.send:SetScript("OnClick", function() QuizUI.SendKey() end)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 2)
    f:Flow(false)   -- the bar and the status line get their first place
    return f
end
