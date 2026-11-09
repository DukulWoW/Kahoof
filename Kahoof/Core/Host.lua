-- Kahoof Core/Host.lua: the host side of a quiz (S5a: the question round; S9: the lobby; S10: the network round)
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
-- The lobby (S9), before the round: OpenLobby sends LOBBY to the audience
-- (again every LOBBY_EVERY s, and after a WHO), takes JOINs from players in
-- the audience (Core/Roster.lua gives the slots), and sends the ROSTER at most
-- every ROSTER_EVERY s, only while the send queue is empty. StartLobby sends
-- START with the players numbered 1..n and the round runs as below. The
-- lobby's one timer is a 1 s ticker (heartbeat, roster batch, ready check);
-- it stops with the lobby. A network host also watches its own quiz: every
-- message to the audience is handed to this client's player side too
-- (s.mirror, Core/Comms.lua), so the quiz window shows the host what the
-- players see; the host's own window (UI/HostWindow.lua, ALL-62) has the
-- buttons. With "I play too" (opts.play, ALL-74) the host is a player as
-- well: a slot of its own (the last), its answers whispered to itself (the
-- loopback).
--
-- The network round (S10):
--   Next (and Redo) wait while the send queue has a backlog: the pre-sent
--     question must be out before its GO ("Sending..."; auto-advance waits
--     for the queue to drain, then goes).
--   Pause (ALL-66): the clock stops (Session.Hold), PAUSE to everyone; an
--     answer that arrives while paused was sent before it: taken, with the
--     time at the pause. Resume sends RESUME with the time left.
--   Redo (ALL-67): only the question that just ended, in its reveal or
--     board: its points are taken back (the snapshot Close keeps) and it is
--     played again from scratch (its Q again, then GO).
--   Lockdown (an encounter, M+, PvP): nothing can be sent, so the quiz holds
--     ("lock"). Held mid-question = that question is void for everyone once
--     the lockdown ends (REVEAL void); held anywhere else = what went out
--     just before is sent again (players drop repeats). Next, End, Pause and
--     the clock wait for it to lift; Stop always works.
--   A send that fails for good for any other reason ends the quiz with one
--     line (Dukul, 2026-11-09: "End the quiz with one line").
--   ALIVE when nothing else went to the audience for ALIVE_AFTER s (the
--     players' host-lost watch is 30 s).
--   A player who leaves (LEAVE, or the group) is marked left; when everyone
--     still there has answered, the question closes.
--
--   Host.OpenLobby(quiz, opts, o) -> session | nil, msg     o: { audience }
--   Host.StartLobby() -> true | nil, msg
--   Host.Remove(key)  / Host.ReadyCheck()  -> true when done
--   Host.Start(quiz, opts, players, o) -> session | nil, msg  (practice: no lobby)
--        opts: read (0 / -1 / 2-10), board (1 / 5 / 0), shuffle, auto,
--              pick ("all" = several correct answers: pick all of them, the
--              default; "one" = any one of them counts; ALL-33)
--        players: player keys (Name-Realm); o: { id, loopback, audience }
--        (audience "group" | "guild": the channel the broadcasts go on, S8)
--   Host.Next() / Host.StartClock() / Host.Skip() / Host.End() -> true when done
--   Host.Pause() / Host.Resume() / Host.Redo()                 -> true when done
--   Host.Blocked() -> nil | "sending" | "locked" | "paused"   why Next waits
--   Host.CanNext() / Host.CanRedo() -> true when the button would work now
--   Host.OnLockdown(locked) / OnSendFailed(sid, kind) / OnQueueEmpty()
--                                       from Core/Channels.lua and Core/Comms.lua
--   Host.Cancel(reason)                 ends it for everyone, drops the session
--   Host.Dismiss()                      drops a finished session
--   Host.RecordAnswer(slot, qid, picks) one answer: a mask of shown positions
--                                       (OnMessage; the dev bots, S6)
--   Host.OnMessage(msg)                 from Comms (A, WHO, JOIN, LEAVE, READY)
--   Host.Get()                          the hosted session or nil

local _, KHF = ...
local L = KHF.L
local S, Scoring, Comms, Channels = KHF.Session, KHF.Scoring, KHF.Comms, KHF.Channels

local Host = {}
KHF.Host = Host

Host.TICK     = 0.25   -- the ANSWERING ticker
Host.IN_EVERY = 2      -- the IN bitmap at most this often (networking.md budget)
Host.LOBBY_EVERY  = 60   -- LOBBY again while open (late log-ins; the lobby heartbeat)
Host.ROSTER_EVERY = 2    -- ROSTER changes at most this often
Host.WHO_EVERY    = 5    -- one LOBBY answers every WHO in this window
Host.CHECK_TIME   = 30   -- a ready check lasts this long
Host.ALIVE_AFTER  = 20   -- ALIVE when nothing went to the audience this long (S10)

local READ_OK  = { [-1] = true, [0] = true }
for t = 2, 10 do READ_OK[t] = true end
local BOARD_OK = { [0] = true, [1] = true, [5] = true }

local session   -- one hosted quiz at a time

function Host.Get() return session end

local function Running(s)
    return s and s.state ~= "FINAL" and s.state ~= "CANCELLED"
end
local function InLobby(s) return s and s.state == "LOBBY" end
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
    local isRight = {}
    for _, i in ipairs(q.correct) do isRight[i] = true end
    local shown, correct, list = {}, {}, {}
    for pos, orig in ipairs(order) do
        shown[pos] = q.answers[orig]
        if isRight[orig] then correct[pos] = true; list[#list + 1] = pos end
    end
    -- How many to pick: one click when one answer is right or any one counts;
    -- otherwise all of them, and the screen says how many (Dukul: "The number")
    local pick = (#list == 1 or s.opts.pick == "one") and 1 or #list
    s.next = { qid = qi, limit = q.time or s.quiz.time, read = s.opts.read, pick = pick,
               text = q.text, answers = shown, correct = correct, nCorrect = #list,
               mask = KHF.Protocol.Mask(list), why = q.why }
    s.out.Q = { qid = qi, limit = s.next.limit, read = s.opts.read, pick = pick,
                text = q.text, answers = shown }
    Comms.ToAudience(s, "Q", s.out.Q)
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
-- Players marked left during the question no longer count (S10)
local function CountIn(s)
    local n, total = 0, 0
    for slot in pairs(s.inQuestion) do
        local p = s.players[slot]
        if s.answers[slot] then
            n, total = n + 1, total + 1
        elseif not (p and p.left) then
            total = total + 1
        end
    end
    return n, total
end
Host.CountIn = CountIn

-- First answer counts; an answer after the close (limit + LATE) is refused,
-- and so is one with more picks than the question asks for.
-- Returns true when the answer was taken.
function Host.RecordAnswer(slot, qid, picks)
    local s = session
    if not s or s.state ~= "ANSWERING" or qid ~= s.qi then return false end
    if not s.inQuestion[slot] or s.answers[slot] then return false end
    if S.Held(s, "lock") then return false end   -- the question is void
    local list = KHF.Protocol.Unmask(picks, #s.cur.answers)
    if not list or #list > s.cur.pick then return false end
    -- paused: it was sent before the pause, so it counts at the pause's time
    local now = s.hold and s.hold.at or S.Now()
    local t = now - s.openAt
    if t > s.cur.limit + Scoring.LATE then return false end
    s.answers[slot] = { picks = list, t = t }
    s.inDirty = true
    local n, total = CountIn(s)
    KHF.SendMessage("AnswerCount", s, n, total)
    if n >= total then
        Close(s, false)   -- everyone answered: no point waiting out the clock
    elseif not s.hold and S.Now() - s.lastIn >= Host.IN_EVERY then
        SendIn(s)
    end
    return true
end

-- A player left: when everyone still there has answered, the question closes
local function PlayerLeft(s, slot)
    local p = s.players[slot]
    if not p or p.left then return end
    p.left = true
    KHF.SendMessage("PlayersChanged", s)
    if s.state == "ANSWERING" and not S.Held(s, "lock") then
        local n, total = CountIn(s)
        if n >= total then Close(s, false) end
    end
end

local OnLobbyMessage   -- below, with the lobby

function Host.OnMessage(msg)
    local s = session
    if not Running(s) then return end
    if msg.type == "WHO" then
        -- a WHO has its own random id: answered while the lobby is open
        if InLobby(s) and not s.loopback then s.lobby.whoOwed = true end
        return
    end
    if msg.sid ~= s.id then return end
    if msg.type == "A" then
        local slot = s.bySender and s.bySender[msg.sender]
        if slot then Host.RecordAnswer(slot, msg.qid, msg.picks) end
    elseif s.lobby then
        OnLobbyMessage(s, msg)
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

-- Auto-advance: Next by itself; while the queue still sends, as soon as it
-- has drained (OnQueueEmpty)
local function AutoNext()
    local s = session
    if s and not Host.Next() then s.nextOwed = true end
end
local AUTO = { after = S.AUTO_NEXT, fn = AutoNext }

local function ToBoard(s)
    local b = s.board
    b.ranks, b.order = Ranked(s)
    b.climber, b.climbUp = Scoring.Climber(s.shownRanks, b.ranks)
    s.shownRanks = b.ranks
    S.SetState(s, "BOARD", s.opts.auto and AUTO or nil)
end

-- void = Skip: the question ends now and pays nothing; it does not count as
-- played, answered or correct for anyone (accuracy stays fair).
-- One pick: right when it is one of the correct answers. Several (pick all):
-- Scoring.Share, right minus wrong ticks. "correct" in the stats and the tie
-- break time count full marks only.
Close = function(s, void)
    if s.state ~= "ANSWERING" and s.state ~= "READING" then return end
    S.StopTimer(s)
    s.voidOwed = nil
    -- Redo (ALL-67) puts everything back as it was before this question
    local snap = {}
    for slot, p in ipairs(s.players) do
        snap[slot] = { total = p.total, correct = p.correct, answered = p.answered,
                       played = p.played, tsum = p.tsum, ctime = p.ctime }
    end
    s.undo = { qi = s.qi, closed = s.closed, stats = snap, shownRanks = s.shownRanks }
    local counts = {}
    for i = 1, #s.cur.answers do counts[i] = 0 end
    local rows = {}
    for slot, p in ipairs(s.players) do
        local a = s.answers[slot]
        local points, time = 0, nil
        local right, wrong = 0, 0
        if a then
            for _, pos in ipairs(a.picks) do
                counts[pos] = counts[pos] + 1
                if s.cur.correct[pos] then right = right + 1 else wrong = wrong + 1 end
            end
        end
        if s.inQuestion[slot] and not void then
            p.played = p.played + 1
            if a then
                time = Tenths(a.t)
                p.answered, p.tsum = p.answered + 1, p.tsum + time
                local share
                if s.cur.pick == 1 then
                    share = (right > 0) and 1 or 0
                else
                    share = Scoring.Share(right, wrong, s.cur.nCorrect)
                end
                points = Scoring.Points(a.t, s.cur.limit, share)
                if share >= 1 then p.correct, p.ctime = p.correct + 1, p.ctime + time end
            end
        end
        p.total = p.total + points
        rows[#rows + 1] = { slot = slot, points = points, time = time, total = p.total, ctime = p.ctime }
    end
    if not void then s.closed = s.closed + 1 end

    if s.inDirty then SendIn(s) end
    s.out.REVEAL = { qid = s.qi, correct = s.cur.mask, void = void and 1 or 0, why = s.cur.why, counts = counts }
    Comms.ToAudience(s, "REVEAL", s.out.REVEAL)
    local show = ShowsBoard(s)
    s.out.BOARD = { qid = s.qi, show = show and 1 or 0, rows = rows }
    Comms.ToAudience(s, "BOARD", s.out.BOARD)
    s.next = nil
    if s.qi < s.count then Prepare(s, s.qi + 1) end

    s.reveal = { qid = s.qi, correct = s.cur.correct, void = void, counts = counts }
    s.board = { qid = s.qi, show = show, rows = rows }
    KHF.SendMessage("Revealed", s, s.reveal)
    KHF.SendMessage("BoardUpdated", s, s.board)
    if show then
        S.SetState(s, "REVEAL", { after = S.REVEAL_TIME, fn = ToBoard })
    else
        S.SetState(s, "REVEAL", s.opts.auto and AUTO or nil)
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
local function CleanOpts(opts)
    return {
        read = READ_OK[opts.read] and opts.read or 0,
        board = BOARD_OK[opts.board] and opts.board or 1,
        shuffle = opts.shuffle and true or false,
        auto = opts.auto and true or false,
        pick = (opts.pick == "one") and "one" or "all",
        play = opts.play and true or false,   -- I play too (ALL-74): lobbies only
    }
end

local function QuizOk(quiz)
    return type(quiz) == "table" and type(quiz.questions) == "table" and #quiz.questions > 0
end

-- The round begins: players = keys in slot order (slots 1..n), START with
-- every one of them, the first question pre-sent, "Get ready"
local function Begin(s, players)
    s.players, s.bySender = {}, {}
    local roster = {}
    for slot, key in ipairs(players) do
        s.players[slot] = { slot = slot, key = key, total = 0, correct = 0, answered = 0,
                            played = 0, tsum = 0, ctime = 0 }
        s.bySender[key] = slot
        roster[slot] = { slot = slot, name = key }
    end
    s.qi, s.closed = 0, 0
    s.out = {}
    s.out.START = { title = s.quiz.title, count = s.count, read = s.opts.read,
                    board = s.opts.board, shuffle = s.opts.shuffle and 1 or 0,
                    mode = (s.opts.pick == "one") and 1 or 2, roster = roster }
    Comms.ToAudience(s, "START", s.out.START)
    Prepare(s, 1)
    S.SetState(s, "STARTING", { after = S.START_DELAY, fn = function() Go(s, 1) end })
    if not s.loopback then S.StartBeat(s, S.BEAT, Host.Beat) end
end

-- The heartbeat (S10): ALIVE only when nothing else went out for a while
function Host.Beat(s)
    if s.loopback or Channels.Locked() or Comms.Backlog() > 0 then return end
    if S.Now() - (s.lastOut or 0) >= Host.ALIVE_AFTER then Comms.ToAudience(s, "ALIVE", {}) end
end

function Host.Start(quiz, opts, players, o)
    if Running(session) then return nil, L["ENG_ERR_RUNNING"] end
    o, opts = o or {}, opts or {}
    if not QuizOk(quiz) then return nil, L["QZ_ERR_NO_QUESTIONS"] end
    if #players == 0 or #players > KHF.Protocol.MAX_SLOTS then return nil, L["ENG_ERR_PLAYERS"] end
    local s = S.New("host", o.id or KHF.Protocol.NewSessionId())
    s.loopback = o.loopback and true or false
    s.audience = (o.audience == "guild") and "guild" or "group"
    s.quiz, s.count = quiz, #quiz.questions
    s.opts = CleanOpts(opts)
    session = s
    Begin(s, players)
    return s
end

--------------------------------------------------------------------------------
-- THE LOBBY (S9)
--------------------------------------------------------------------------------
local Roster = KHF.Roster

-- Is this player in the session's audience? (a JOIN whispered by someone
-- outside the group is not taken)
local function InAudience(s, key)
    if s.audience ~= "group" then return true end   -- guild lobbies: ALL-15
    for _, k in ipairs(Channels.GroupKeys()) do
        if k == key then return true end
    end
    return false
end

local function SendLobby(s)
    local lb = s.lobby
    lb.lastLobby, lb.whoOwed = S.Now(), false
    Comms.ToAudience(s, "LOBBY", { title = s.quiz.title, count = s.count, read = s.opts.read, late = 0,
                                   aud = (s.audience == "guild") and 2 or 1,
                                   players = Roster.Count(lb.roster) })
end

local function RosterChanged(s)
    KHF.SendMessage("RosterChanged", s)
end

-- "6 of 9 have Kahoof": the version ping, asked again after the group changed
local function AskVersions(s)
    local lb = s.lobby
    local ok, why = KHF.VersionCheck.Ask(s.audience, function(replies)
        if session ~= s or not s.lobby then return end
        for key, info in pairs(replies) do lb.have[key] = info end
        RosterChanged(s)
    end)
    lb.askOwed = (not ok) and why == "soon"
end

-- The lobby's one timer, every second while it is open. Nothing is sent
-- while the game blocks addon messages: it all waits for the lockdown to end.
local function LobbyTick(s)
    local lb, now = s.lobby, S.Now()
    if lb.checkUntil and now >= lb.checkUntil then
        lb.checkUntil = nil
        Roster.EndCheck(lb.roster)
        RosterChanged(s)
    end
    if Channels.Locked() then return end
    if Roster.Dirty(lb.roster) and now - lb.lastRoster >= Host.ROSTER_EVERY and Comms.Backlog() == 0 then
        local full, rows = Roster.Flush(lb.roster)
        lb.lastRoster = now
        Comms.ToAudience(s, "ROSTER", { full = full, rows = rows })
    end
    if (lb.whoOwed and now - lb.lastLobby >= Host.WHO_EVERY) or now - lb.lastLobby >= Host.LOBBY_EVERY then
        SendLobby(s)
    end
    if lb.askOwed then AskVersions(s) end
end

function Host.OpenLobby(quiz, opts, o)
    if Running(session) then return nil, L["ENG_ERR_RUNNING"] end
    o, opts = o or {}, opts or {}
    if not QuizOk(quiz) then return nil, L["QZ_ERR_NO_QUESTIONS"] end
    local audience = (o.audience == "guild") and "guild" or "group"
    if not Channels.CanSend() then return nil, L["COMMS_TRIAL"] end
    if not Channels.ForAudience(audience) then return nil, L["LB_ERR_NOGROUP"] end
    if Channels.Locked() then return nil, L["COMMS_LOCKED"] end
    if session then S.StopTimer(session) end
    local s = S.New("host", o.id or KHF.Protocol.NewSessionId())
    s.audience, s.loopback = audience, false
    s.quiz, s.count = quiz, #quiz.questions
    s.opts = CleanOpts(opts)
    s.lobby = { roster = Roster.New(KHF.Protocol.MAX_SLOTS), have = {}, lastRoster = 0, lastLobby = 0 }
    session = s
    SendLobby(s)
    S.SetState(s, "LOBBY", { every = 1, fn = LobbyTick })
    AskVersions(s)
    return s
end

function Host.StartLobby()
    local s = session
    if not InLobby(s) then return nil end
    local players = Roster.Keys(s.lobby.roster)
    if #players == 0 then return nil, L["LB_ERR_EMPTY"] end
    if Channels.Locked() then return nil, L["COMMS_LOCKED"] end
    Roster.EndCheck(s.lobby.roster)
    s.lobby.checkUntil = nil
    -- the host watches its own quiz (no slot, no answers), or plays it too
    -- (ALL-74: the last slot); the player side takes this START from the mirror
    local me = KHF.UnitKey("player")
    if s.opts.play and #players < KHF.Protocol.MAX_SLOTS then players[#players + 1] = me end
    s.mirror = true
    KHF.Player.Leave()
    KHF.Player.Expect(s.id, me, false, not s.opts.play)
    Begin(s, players)
    return true
end

-- Removed: told so, and never let back into this session
function Host.Remove(key)
    local s = session
    if not InLobby(s) or not Roster.Slot(s.lobby.roster, key) then return false end
    Roster.Remove(s.lobby.roster, key, true)
    Comms.ToPlayer(s, key, "DENY", { reason = "removed" })
    RosterChanged(s)
    return true
end

function Host.ReadyCheck()
    local s = session
    if not InLobby(s) or s.lobby.checkUntil or Roster.Count(s.lobby.roster) == 0 then return false end
    if Channels.Locked() then return false end
    Roster.StartCheck(s.lobby.roster)
    s.lobby.checkUntil = S.Now() + Host.CHECK_TIME
    Comms.ToAudience(s, "CHECK", {})
    RosterChanged(s)
    return true
end

-- Lobby messages from players (A is the round's: Host.OnMessage)
OnLobbyMessage = function(s, m)
    local lb = s.lobby
    if m.type == "JOIN" then
        if not InLobby(s) then
            -- late join is ALL-16: for now a started quiz says so
            if not s.bySender[m.sender] then Comms.ToPlayer(s, m.sender, "DENY", { reason = "started" }) end
            return
        end
        if not InAudience(s, m.sender) then return end
        local slot, why = Roster.Add(lb.roster, m.sender)
        if not slot then
            Comms.ToPlayer(s, m.sender, "DENY", { reason = why })
            return
        end
        lb.have[m.sender] = lb.have[m.sender] or { proto = m.proto }
        RosterChanged(s)
    elseif m.type == "LEAVE" then
        if InLobby(s) then
            if Roster.Remove(lb.roster, m.sender, false) then RosterChanged(s) end
        else
            local slot = s.bySender and s.bySender[m.sender]
            if slot then PlayerLeft(s, slot) end
        end
    elseif m.type == "READY" then
        if InLobby(s) and Roster.SetReady(lb.roster, m.sender, m.ready == 1) then RosterChanged(s) end
    end
end

-- The group changed: players who left it leave the lobby (or are marked
-- "left" in a running quiz); a host who left the group closes the lobby
local function OnGroupChanged()
    local s = session
    if not Running(s) or s.loopback or s.audience ~= "group" then return end
    if not Channels.ForAudience("group") then
        -- the host left the group: the lobby closes, a running quiz ends
        Host.Cancel(InLobby(s) and "closed" or "nogroup")
        return
    end
    local inGroup = {}
    for _, k in ipairs(Channels.GroupKeys()) do inGroup[k] = true end
    if InLobby(s) then
        local gone = false
        for _, key in ipairs(Roster.Keys(s.lobby.roster)) do
            if not inGroup[key] then
                Roster.Remove(s.lobby.roster, key, false)
                gone = true
            end
        end
        s.lobby.askOwed = true
        if gone then RosterChanged(s) end
    else
        for slot, p in ipairs(s.players) do
            if not inGroup[p.key] then PlayerLeft(s, slot) end
        end
    end
end
KHF.RegisterEvent("GROUP_ROSTER_UPDATE", OnGroupChanged)

-- Why the host's buttons wait (nil = they do not): the game blocks addon
-- messages, the quiz is paused, or the queue is still sending (the
-- pre-sent question must be out before its GO)
local function Blocked(s)
    if not s then return nil end
    if S.Held(s, "lock") or (not s.loopback and Channels.Locked()) then return "locked" end
    if S.Held(s, "pause") then return "paused" end
    if not s.loopback and Comms.Backlog() > 0 then return "sending" end
    return nil
end
function Host.Blocked() return Blocked(session) end

-- Next: in BOARD, or in REVEAL when no board follows
local function NextState(s)
    return s and (s.state == "BOARD" or (s.state == "REVEAL" and s.board and not s.board.show)) or false
end

function Host.CanNext()
    local s = session
    return NextState(s) and not Blocked(s)
end

function Host.Next()
    local s = session
    if not Host.CanNext() then return false end
    s.nextOwed = nil
    if s.qi < s.count then Go(s, s.qi + 1) else Final(s) end
    return true
end

-- Redo (ALL-67): the question that just ended, while its reveal or board shows
function Host.CanRedo()
    local s = session
    if not s or (s.state ~= "REVEAL" and s.state ~= "BOARD") then return false end
    return s.undo ~= nil and s.undo.qi == s.qi and not Blocked(s)
end

function Host.Redo()
    local s = session
    if not Host.CanRedo() then return false end
    local u = s.undo
    for slot, st in pairs(u.stats) do
        local p = s.players[slot]
        if p then
            p.total, p.correct, p.answered = st.total, st.correct, st.answered
            p.played, p.tsum, p.ctime = st.played, st.tsum, st.ctime
        end
    end
    s.closed, s.shownRanks, s.undo, s.nextOwed = u.closed, u.shownRanks, nil, nil
    s.reveal, s.board = nil, nil
    Prepare(s, s.qi)   -- the pre-sent next question is dropped; Close sends it again
    Go(s, s.qi)
    return true
end

-- Pause (ALL-66): in a question, its reveal or its board
local PAUSABLE = { READING = true, ANSWERING = true, REVEAL = true, BOARD = true }

-- The time the held state's clock had left, as players count it
local function LeftNow(s)
    if not s.hold then return 0 end
    if s.state == "ANSWERING" then return math.max(0, s.deadline - s.hold.at - Scoring.LATE) end
    return s.hold.left or 0
end

function Host.Pause()
    local s = session
    if not s or not PAUSABLE[s.state] or S.Held(s, "pause") or Blocked(s) == "locked" then return false end
    S.Hold(s, "pause")
    Comms.ToAudience(s, "PAUSE", { qid = s.qi })
    KHF.SendMessage("QuizPaused", s)
    return true
end

function Host.Resume()
    local s = session
    if not s or not S.Held(s, "pause") or Blocked(s) == "locked" then return false end
    local left = LeftNow(s)
    S.Release(s, "pause")
    Comms.ToAudience(s, "RESUME", { qid = s.qi, left = Tenths(left) })
    KHF.SendMessage("QuizPaused", s)
    return true
end

-- Read time "the host starts it": the click that opens the answers
function Host.StartClock()
    local s = session
    if not s or s.state ~= "READING" or s.opts.read >= 0 or Blocked(s) == "locked" then return false end
    if S.Held(s, "pause") then return false end
    Comms.ToAudience(s, "GO", { qid = s.qi, phase = 2 })
    OpenAnswers(s)
    return true
end

function Host.Skip()
    local s = session
    if not s or (s.state ~= "READING" and s.state ~= "ANSWERING") or Blocked(s) == "locked" then return false end
    Close(s, true)
    return true
end

-- Results now; a question still running is dropped unscored
function Host.End()
    local s = session
    if not Running(s) or s.state == "STARTING" or s.state == "LOBBY" or Blocked(s) == "locked" then return false end
    S.StopTimer(s)
    Final(s)
    return true
end

--------------------------------------------------------------------------------
-- THE NETWORK (S10): lockdown, failed sends, the drained queue
--------------------------------------------------------------------------------
local ROUND = { STARTING = true, READING = true, ANSWERING = true, REVEAL = true, BOARD = true }

-- What went out just before a lockdown may have been dropped with the queue:
-- send it again (players drop what they already have)
local function Resend(s)
    if s.state == "STARTING" then
        Comms.ToAudience(s, "START", s.out.START)
        if s.out.Q then Comms.ToAudience(s, "Q", s.out.Q) end
    elseif s.state == "REVEAL" or s.state == "BOARD" then
        if s.out.REVEAL then Comms.ToAudience(s, "REVEAL", s.out.REVEAL) end
        if s.out.BOARD then Comms.ToAudience(s, "BOARD", s.out.BOARD) end
        if s.next and s.out.Q then Comms.ToAudience(s, "Q", s.out.Q) end
    end
    if S.Held(s, "pause") then Comms.ToAudience(s, "PAUSE", { qid = s.qi }) end
end

local function Lock(s)
    if S.Held(s, "lock") then return end
    if s.state == "READING" or s.state == "ANSWERING" then s.voidOwed = true end
    S.Hold(s, "lock")
    KHF:Print(L["HOST_LOCK_PAUSE"])
    KHF.SendMessage("QuizPaused", s)
end

local function Unlock(s)
    if not S.Held(s, "lock") then return end
    if s.voidOwed then
        Close(s, true)   -- void for everyone: the REVEAL ends any pause too
    else
        S.Release(s, "lock")
        Resend(s)
    end
    KHF:Print(L["HOST_LOCK_OVER"])
    KHF.SendMessage("QuizPaused", s)
end

function Host.OnLockdown(locked)
    local s = session
    if not Running(s) or s.loopback or not ROUND[s.state] then return end
    if locked then Lock(s) else Unlock(s) end
end

function Host.OnSendFailed(sid, kind)
    local s = session
    if not Running(s) or s.id ~= sid or s.loopback then return end
    if kind == "lockdown" then
        if not ROUND[s.state] then return end   -- the lobby waits by itself
        -- the lockdown may already be over (this comes a frame late)
        if Channels.Locked() then Lock(s) elseif not S.Held(s, "lock") then Resend(s) end
        return
    end
    KHF:Print(string.format(L["HOST_SEND_FAILED"], tostring(kind)))
    Host.Cancel("sendfail")
end

function Host.OnQueueEmpty()
    local s = session
    if s and s.nextOwed then
        s.nextOwed = nil
        Host.Next()
    end
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
    S.StopBeat(s)
    session = nil
end

function Host.Dismiss()
    if session and not Running(session) then
        S.StopTimer(session)
        S.StopBeat(session)
        session = nil
    end
end
