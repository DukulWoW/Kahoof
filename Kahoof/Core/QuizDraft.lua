-- Kahoof Core/QuizDraft.lua: the quiz editor's working copy (S4, ALL-08)
--
-- The editor (UI/QuizEditor.lua) changes a draft, never a stored quiz. The
-- store sees the quiz only when Save runs, through QuizStore.Clean like
-- everything else from outside. Pure logic, no frames: the offline tests
-- cover it (_work/tools/tests/test_quizdraft.lua).
--
-- A draft holds what the boxes hold, as typed: text fields are strings ("" =
-- empty), every question has MAX_ANSWERS answer slots, correct = the set of
-- slots ticked as correct ({ [slot] = true }, several allowed: ALL-33), time
-- nil = the quiz's time.
--
-- Saving: Check turns the draft into a raw quiz. Questions with nothing typed
-- in them are left out, and empty answer slots close up (a gap at answer 2
-- moves 3 and 4 up, the correct ticks moving with their answers). An error comes
-- back with a path in DRAFT terms (the question and slot on screen), not in
-- the cleaned quiz's numbering.
--
--   QuizDraft.New(time)                 -> draft with one empty question
--   QuizDraft.FromQuiz(quiz)            -> draft of a stored quiz (id kept)
--   QuizDraft.AddQuestion(d, after)     -> index of the new question | nil (full)
--   QuizDraft.DeleteQuestion(d, i)      -> the index to show next (never empty)
--   QuizDraft.MoveQuestion(d, i, delta) -> the question's new index | nil
--   QuizDraft.IsBlank(q) / IsComplete(q)
--   QuizDraft.Same(a, b)                -> true when nothing differs
--   QuizDraft.Check(d)                  -> raw quiz | nil, msg, path

local _, KHF = ...
local L = KHF.L
local QuizStore = KHF.QuizStore

local QuizDraft = {}
KHF.QuizDraft = QuizDraft

local SLOTS = QuizStore.MAX_ANSWERS

local function ValidTime(t)
    for _, v in ipairs(QuizStore.TIMES) do
        if v == t then return t end
    end
    return QuizStore.DEFAULT_TIME
end

-- Has the player typed anything that stays after the store's trim?
local function Filled(s)
    return type(s) == "string" and QuizStore.Trim((s:gsub("\t", " "))) ~= ""
end
QuizDraft.Filled = Filled

local function BlankQuestion()
    local answers = {}
    for s = 1, SLOTS do answers[s] = "" end
    return { text = "", answers = answers, correct = {}, time = nil, why = "" }
end

function QuizDraft.New(time)
    return {
        title = "", about = "", tag = "", time = ValidTime(time),
        questions = { BlankQuestion() },
    }
end

function QuizDraft.FromQuiz(quiz)
    local d = {
        id = quiz.id, author = quiz.author,
        title = quiz.title or "", about = quiz.about or "", tag = quiz.tag or "",
        time = ValidTime(quiz.time), questions = {},
    }
    for i, q in ipairs(quiz.questions or {}) do
        local answers = {}
        for s = 1, SLOTS do answers[s] = (q.answers and q.answers[s]) or "" end
        local correct = {}
        local list = type(q.correct) == "table" and q.correct or { q.correct }
        for _, s in ipairs(list) do correct[s] = true end
        d.questions[i] = { text = q.text or "", answers = answers, correct = correct,
                           time = q.time, why = q.why or "" }
    end
    if #d.questions == 0 then d.questions[1] = BlankQuestion() end
    return d
end

--------------------------------------------------------------------------------
-- QUESTIONS
--------------------------------------------------------------------------------
function QuizDraft.AddQuestion(d, after)
    local n = #d.questions
    if n >= QuizStore.MAX_QUESTIONS then return nil end
    local i = math.min(math.max((after or n) + 1, 1), n + 1)
    table.insert(d.questions, i, BlankQuestion())
    return i
end

-- The last question is never removed: it is emptied instead, so the editor
-- always has one to show
function QuizDraft.DeleteQuestion(d, i)
    if d.questions[i] then table.remove(d.questions, i) end
    if #d.questions == 0 then d.questions[1] = BlankQuestion() end
    return math.min(math.max(i, 1), #d.questions)
end

function QuizDraft.MoveQuestion(d, i, delta)
    local j = i + delta
    local qs = d.questions
    if not qs[i] or j < 1 or j > #qs then return nil end
    qs[i], qs[j] = qs[j], qs[i]
    return j
end

-- Nothing typed: a question added and left empty is not saved
function QuizDraft.IsBlank(q)
    if Filled(q.text) or Filled(q.why) then return false end
    for s = 1, SLOTS do
        if Filled(q.answers[s]) then return false end
    end
    return true
end

-- Ready to play: text, two answers, at least one ticked correct, and no tick
-- on an empty answer. (Lengths are capped by the boxes; Check has the last word.)
function QuizDraft.IsComplete(q)
    if not Filled(q.text) then return false end
    local n, ticks = 0, 0
    for s = 1, SLOTS do
        local filled = Filled(q.answers[s])
        if filled then n = n + 1 end
        if q.correct[s] then
            if not filled then return false end
            ticks = ticks + 1
        end
    end
    return n >= QuizStore.MIN_ANSWERS and ticks > 0
end

-- The first slot ticked correct but left empty, or nil
local function EmptyTick(q)
    for s = 1, SLOTS do
        if q.correct[s] and not Filled(q.answers[s]) then return s end
    end
end

--------------------------------------------------------------------------------
-- UNSAVED CHANGES: a draft against the copy taken when it was opened or saved
--------------------------------------------------------------------------------
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not Same(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end
QuizDraft.Same = Same

--------------------------------------------------------------------------------
-- CHECK: draft -> raw quiz for QuizStore.Create / Save, or the first problem
--------------------------------------------------------------------------------
-- The first empty slot of a draft question, for "needs 2 to 4 answers"
local function FirstEmptySlot(q)
    for s = 1, SLOTS do
        if not Filled(q.answers[s]) then return s end
    end
    return 1
end

function QuizDraft.Check(d)
    local raw = { id = d.id, title = d.title, about = d.about, tag = d.tag, time = d.time,
                  questions = {} }
    -- qMap[raw question] = draft question; aMap[raw question][raw answer] = slot
    local qMap, aMap = {}, {}
    local tickQ, tickSlot   -- the first question with a tick on an empty answer
    for i, q in ipairs(d.questions) do
        if not QuizDraft.IsBlank(q) then
            local answers, slots, correct = {}, {}, {}
            for s = 1, SLOTS do
                if Filled(q.answers[s]) then
                    answers[#answers + 1] = q.answers[s]
                    slots[#answers] = s
                    if q.correct[s] then correct[#correct + 1] = #answers end
                end
            end
            if not tickQ then
                tickSlot = EmptyTick(q)
                if tickSlot then tickQ = i end
            end
            local n = #raw.questions + 1
            raw.questions[n] = { text = q.text, answers = answers, correct = correct,
                                 time = q.time, why = q.why }
            qMap[n], aMap[n] = i, slots
        end
    end

    local quiz, msg, path = QuizStore.Clean(raw)
    -- A tick on an empty answer would vanish when the answers close up: it
    -- is a problem of its own, reported in question order with Clean's
    local function TickProblem()
        return nil, L["ED_ERR_CORRECT_EMPTY"], { q = tickQ, a = tickSlot, field = "correct" }
    end
    if quiz then
        if tickQ then return TickProblem() end
        return raw
    end

    -- The path back in draft terms
    path = path or {}
    -- Clean's problem is later than the tick's, or it is that same question
    -- having no correct answer left (its only tick was on an empty answer)
    if tickQ and path.q then
        local at = qMap[path.q] or math.huge
        if at > tickQ or (at == tickQ and path.field == "correct") then return TickProblem() end
    end
    local out = { field = path.field }
    if path.q then
        local qi = qMap[path.q]
        local dq = qi and d.questions[qi]
        out.q = qi
        if dq then
            if path.a then
                out.a = aMap[path.q][path.a]
            elseif path.field == "answers" then
                out.a = FirstEmptySlot(dq)
            end
        end
    end
    return nil, msg, out
end
