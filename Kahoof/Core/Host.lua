-- Kahoof Core/Host.lua: the host side of a quiz (S5a: the question round; the lobby is S9)
--
-- THE HOST IS THE AUTHORITY (game-engine.md). It owns the clock, the
-- questions, the correct answer and every score. Players are told what to
-- show and send one thing back: their answer. The host runs the quiz and does
-- not play (practice is the exception only in that the one player is you, on
-- the loopback).
--
-- A question, as the host runs it:
--   Q pre-sent (while the last reveal / leaderboard shows, or with START)
--   Next -> GO: everyone shows the question at the same moment
--   READING (the read time; or until the host starts the clock; or none)
--   ANSWERING: a 0.25 s ticker (the session's one timer) closes the
--     question at limit + LATE and sends the IN bitmap at most every 2 s
--   Close: points (Core/Scoring.lua), IN, REVEAL, BOARD, the next Q
--   REVEAL (-> BOARD after REVEAL_TIME when this question shows a board)
--   Next (in BOARD, or in REVEAL when no board follows) -> the next GO, or FINAL
-- Timing is the host's clock alone: an answer's time is when it ARRIVED here
-- minus when answers opened here (networking.md, Known limits: the grace
-- second absorbs most of the latency).
--
--   Host.Start(quiz, opts, players, o) -> session | nil, msg
--        opts: read (0 / -1 / 2-10), board (1 / 5 / 0), shuffle, auto
--        players: player keys (Name-Realm); o: { id, loopback }
--   Host.Next() / Host.StartClock() / Host.Skip() / Host.End() -> true when done
--   Host.Cancel(reason)                 ends it for everyone, drops the session
--   Host.Dismiss()                      drops a finished session
--   Host.RecordAnswer(slot, qid, pos)   one answer (OnMessage; the dev bots, S6)
--   Host.OnMessage(msg)                 from Comms (A)
--   Host.Get()                          the hosted session or nil

local _, KHF = ...
local L = KHF.L
local S, Scoring, Comms = KHF.Session, KHF.Scoring, KHF.Comms

local Host = {}
KHF.Host = Host

Host.TICK     = 0.25   -- the ANSWERING ticker
Host.IN_EVERY = 2      -- the IN bitmap at most this often (networking.md budget)

local READ_OK  = { [-1] = true, [0] = true }
for t = 2, 10 do READ_OK[t] = true end
local BOARD_OK = { [0] = true, [1] = true, [5] = true }

local session   -- one hosted quiz at a time

function Host.Get() return session end

local function Running(s)
    return s and s.state ~= "FINAL" and s.state ~= "CANCELLED"
end
Host.IsRunning = function() return Running(session) and true or false end

local function Tenths(t) return math.floor(t * 10 + 0.5) end

--------------------------------------------------------------------------------
-- QUESTIONS OUT
--------------------------------------------------------------------------------
-- Builds the question as shown (answers shuffled once when the host turned
-- shuffle on, the same order for everyone) and pre-sends it. The correct
-- answer stays here until the reveal.
local function Prepare(s, qi)
    local q = s.quiz.questions[qi]
    local n = #q.answers
    local order = {}
    for i = 1, n do order[i] = i end
    if s.opts.shuffle then
        for i = n, 2, -1 do
            local j = math.random(1, i)
            order[i], order[j] = order[j], order[i]
        end
    end
    local shown, correct = {}, nil
    for pos, orig in ipairs(order) do
        shown[pos] = q.answers[orig]
        if orig == q.correct then correct = pos end
    end
    s.next = { qid = qi, limit = q.time or s.quiz.time, read = s.opts.read,
               text = q.text, answers = shown, correct = correct, why = q.why }
    Comms.ToAudience(s, "Q", { qid = qi, limit = s.next.limit, read = s.opts.read,
                               text = q.text, answers = shown })
end

local function SendIn(s)
    local set = {}
    for slot in pairs(s.answers) do set[slot] = true end
    Comms.ToAudience(s, "IN", { qid = s.qi, bits = KHF.Protocol.EncodeBits(set) })
    s.lastIn, s.inDirty = S.Now(), false
end

local Close   -- below; the ticker calls it

local function Tick(s)
    if S.Now() >= s.deadline then
        Close(s, false)
    elseif s.inDirty and S.Now() - s.lastIn >= Host.IN_EVERY then
        SendIn(s)
    end
end

local function OpenAnswers(s)
    s.openAt = S.Now()
    s.deadline = s.openAt + s.cur.limit + Scoring.LATE
    S.SetState(s, "ANSWERING", { every = Host.TICK, fn = Tick })
end

local function Go(s, qi)
    s.qi, s.cur, s.next = qi, s.next, nil
    s.answers, s.inDirty, s.lastIn = {}, false, 0
    -- who this question counts for: everyone in the session at GO
    s.inQuestion = {}
    for slot, p in ipairs(s.players) do
        if not p.left then s.inQuestion[slot] = true end
    end
    Comms.ToAudience(s, "GO", { qid = qi, phase = 1 })
    local read = s.opts.read
    if read > 0 then
        S.SetState(s, "READING", { after = read, fn = OpenAnswers })
    elseif read < 0 then
        S.SetState(s, "READING")   -- until the host starts the clock
    else
        OpenAnswers(s)
    end
    KHF.SendMessage("QuestionShown", s, s.cur)
end

--------------------------------------------------------------------------------
-- ANSWERS IN
--------------------------------------------------------------------------------
local function CountIn(s)
    local n, total = 0, 0
    for slot in pairs(s.inQuestion) do
        total = total + 1
        if s.answers[slot] then n = n + 1 end
    end
    return n, total
end

-- First answer counts; an answer after the close (limit + LATE) is refused.
-- Returns true when the answer was taken.
function Host.RecordAnswer(slot, qid, pos)
    local s = session
    if not s or s.state ~= "ANSWERING" or qid ~= s.qi then return false end
    if not s.inQuestion[slot] or s.answers[slot] then return false end
    if type(pos) ~= "number" or pos < 1 or pos > #s.cur.answers then return false end
    local t = S.Now() - s.openAt
    if t > s.cur.limit + Scoring.LATE then return false end
    s.answers[slot] = { pos = pos, t = t }
    s.inDirty = true
    local n, total = CountIn(s)
    KHF.SendMessage("AnswerCount", s, n, total)
    if n >= total then
        Close(s, false)   -- everyone answered: no point waiting out the clock
    elseif S.Now() - s.lastIn >= Host.IN_EVERY then
        SendIn(s)
    end
    return true
end

function Host.OnMessage(msg)
    local s = session
    if not s or msg.sid ~= s.id then return end
    if msg.type == "A" then
        local slot = s.bySender[msg.sender]
        if slot then Host.RecordAnswer(slot, msg.qid, msg.answer) end
    end
end

--------------------------------------------------------------------------------
-- CLOSE, REVEAL, BOARD
--------------------------------------------------------------------------------
-- A board screen after this question? Every question; every fifth (not the
-- last: the results come next); or only the results at the end.
local function ShowsBoard(s)
    local b = s.opts.board
    if b == 1 then return true end
    if b == 5 then return s.qi % 5 == 0 and s.qi < s.count end
    return false
end

local function Ranked(s)
    local rows = {}
    for slot, p in ipairs(s.players) do rows[slot] = { slot = slot, total = p.total, ctime = p.ctime } end
    return Scoring.Rank(rows)
end

local function ToBoard(s)
    local b = s.board
    b.ranks, b.order = Ranked(s)
    b.climber, b.climbUp = Scoring.Climber(s.shownRanks, b.ranks)
    s.shownRanks = b.ranks
    S.SetState(s, "BOARD", s.opts.auto and { after = S.AUTO_NEXT, fn = function() Host.Next() end } or nil)
end

-- void = Skip: the question ends now and pays nothing; it does not count as
-- played, answered or correct for anyone (accuracy stays fair)
Close = function(s, void)
    if s.state ~= "ANSWERING" and s.state ~= "READING" then return end
    S.StopTimer(s)
    local counts = {}
    for i = 1, #s.cur.answers do counts[i] = 0 end
    local rows = {}
    for slot, p in ipairs(s.players) do
        local a = s.answers[slot]
        local points, time = 0, nil
        if a then counts[a.pos] = counts[a.pos] + 1 end
        if s.inQuestion[slot] and not void then
            p.played = p.played + 1
            if a then
                time = Tenths(a.t)
                p.answered, p.tsum = p.answered + 1, p.tsum + time
                if a.pos == s.cur.correct then
                    points = Scoring.Points(a.t, s.cur.limit, true)
                    p.correct, p.ctime = p.correct + 1, p.ctime + time
                end
            end
        end
        p.total = p.total + points
        rows[#rows + 1] = { slot = slot, points = points, time = time, total = p.total, ctime = p.ctime }
    end
    if not void then s.closed = s.closed + 1 end

    if s.inDirty then SendIn(s) end
    Comms.ToAudience(s, "REVEAL", { qid = s.qi, correct = s.cur.correct, void = void and 1 or 0,
                                    why = s.cur.why, counts = counts })
    local show = ShowsBoard(s)
    Comms.ToAudience(s, "BOARD", { qid = s.qi, show = show and 1 or 0, rows = rows })
    if s.qi < s.count then Prepare(s, s.qi + 1) end

    s.reveal = { qid = s.qi, correct = s.cur.correct, void = void, counts = counts }
    s.board = { qid = s.qi, show = show, rows = rows }
    KHF.SendMessage("Revealed", s, s.reveal)
    KHF.SendMessage("BoardUpdated", s, s.board)
    if show then
        S.SetState(s, "REVEAL", { after = S.REVEAL_TIME, fn = ToBoard })
    else
        S.SetState(s, "REVEAL", s.opts.auto and { after = S.AUTO_NEXT, fn = function() Host.Next() end } or nil)
    end
end

--------------------------------------------------------------------------------
-- THE END
--------------------------------------------------------------------------------
local function Final(s)
    local rows = {}
    for slot, p in ipairs(s.players) do
        rows[slot] = { slot = slot, total = p.total, correct = p.correct, answered = p.answered,
                       played = p.played, tsum = p.tsum, ctime = p.ctime }
    end
    Comms.ToAudience(s, "FINAL", { played = s.closed, rows = rows })
    local ranks, order = Ranked(s)
    s.final = { played = s.closed, rows = rows, ranks = ranks, order = order }
    S.SetState(s, "FINAL")
    KHF.SendMessage("QuizEnded", s, "final")
end

--------------------------------------------------------------------------------
-- THE HOST'S BUTTONS
--------------------------------------------------------------------------------
function Host.Start(quiz, opts, players, o)
    if Running(session) then return nil, L["ENG_ERR_RUNNING"] end
    o, opts = o or {}, opts or {}
    if type(quiz) ~= "table" or type(quiz.questions) ~= "table" or #quiz.questions == 0 then
        return nil, L["QZ_ERR_NO_QUESTIONS"]
    end
    if #players == 0 or #players > KHF.Protocol.MAX_SLOTS then return nil, L["ENG_ERR_PLAYERS"] end
    local s = S.New("host", o.id or KHF.Protocol.NewSessionId())
    s.loopback = o.loopback and true or false
    s.quiz, s.count = quiz, #quiz.questions
    s.opts = {
        read = READ_OK[opts.read] and opts.read or 0,
        board = BOARD_OK[opts.board] and opts.board or 1,
        shuffle = opts.shuffle and true or false,
        auto = opts.auto and true or false,
    }
    s.players, s.bySender = {}, {}
    local roster = {}
    for slot, key in ipairs(players) do
        s.players[slot] = { slot = slot, key = key, total = 0, correct = 0, answered = 0,
                            played = 0, tsum = 0, ctime = 0 }
        s.bySender[key] = slot
        roster[slot] = { slot = slot, name = key }
    end
    s.qi, s.closed = 0, 0
    session = s

    Comms.ToAudience(s, "START", { title = quiz.title, count = s.count, read = s.opts.read,
                                   board = s.opts.board, shuffle = s.opts.shuffle and 1 or 0,
                                   roster = roster })
    Prepare(s, 1)
    S.SetState(s, "STARTING", { after = S.START_DELAY, fn = function() Go(s, 1) end })
    return s
end

-- Next: in BOARD, or in REVEAL when no board follows
function Host.Next()
    local s = session
    if not s then return false end
    local ok = s.state == "BOARD" or (s.state == "REVEAL" and s.board and not s.board.show)
    if not ok then return false end
    if s.qi < s.count then Go(s, s.qi + 1) else Final(s) end
    return true
end

-- Read time "the host starts it": the click that opens the answers
function Host.StartClock()
    local s = session
    if not s or s.state ~= "READING" or s.opts.read >= 0 then return false end
    Comms.ToAudience(s, "GO", { qid = s.qi, phase = 2 })
    OpenAnswers(s)
    return true
end

function Host.Skip()
    local s = session
    if not s or (s.state ~= "READING" and s.state ~= "ANSWERING") then return false end
    Close(s, true)
    return true
end

-- Results now; a question still running is dropped unscored
function Host.End()
    local s = session
    if not Running(s) or s.state == "STARTING" then return false end
    S.StopTimer(s)
    Final(s)
    return true
end

function Host.Cancel(reason)
    local s = session
    if not s then return end
    if Running(s) then
        Comms.ToAudience(s, "CANCEL", { reason = reason or "cancelled" })
        S.SetState(s, "CANCELLED")
        KHF.SendMessage("QuizEnded", s, reason or "cancelled")
    end
    S.StopTimer(s)
    session = nil
end

function Host.Dismiss()
    if session and not Running(session) then
        S.StopTimer(session)
        session = nil
    end
end
