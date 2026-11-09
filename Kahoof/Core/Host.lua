-- Kahoof Core/Host.lua: the host side of a quiz (S5a: the question round; S9: the lobby)
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
-- players see, with the host bar (the host's own view is ALL-62).
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
--   Host.Cancel(reason)                 ends it for everyone, drops the session
--   Host.Dismiss()                      drops a finished session
--   Host.RecordAnswer(slot, qid, picks) one answer: a mask of shown positions
--                                       (OnMessage; the dev bots, S6)
--   Host.OnMessage(msg)                 from Comms (A, WHO, JOIN, LEAVE, READY)
--   Host.Get()                          the hosted session or nil

local _, KHF = ...
local L = KHF.L
local S, Scoring, Comms = KHF.Session, KHF.Scoring, KHF.Comms

local Host = {}
KHF.Host = Host

Host.TICK     = 0.25   -- the ANSWERING ticker
Host.IN_EVERY = 2      -- the IN bitmap at most this often (networking.md budget)
Host.LOBBY_EVERY  = 60   -- LOBBY again while open (late log-ins; the lobby heartbeat)
Host.ROSTER_EVERY = 2    -- ROSTER changes at most this often
Host.WHO_EVERY    = 5    -- one LOBBY answers every WHO in this window
Host.CHECK_TIME   = 30   -- a ready check lasts this long

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
    Comms.ToAudience(s, "Q", { qid = qi, limit = s.next.limit, read = s.opts.read, pick = pick,
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

-- First answer counts; an answer after the close (limit + LATE) is refused,
-- and so is one with more picks than the question asks for.
-- Returns true when the answer was taken.
function Host.RecordAnswer(slot, qid, picks)
    local s = session
    if not s or s.state ~= "ANSWERING" or qid ~= s.qi then return false end
    if not s.inQuestion[slot] or s.answers[slot] then return false end
    local list = KHF.Protocol.Unmask(picks, #s.cur.answers)
    if not list or #list > s.cur.pick then return false end
    local t = S.Now() - s.openAt
    if t > s.cur.limit + Scoring.LATE then return false end
    s.answers[slot] = { picks = list, t = t }
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

local function ToBoard(s)
    local b = s.board
    b.ranks, b.order = Ranked(s)
    b.climber, b.climbUp = Scoring.Climber(s.shownRanks, b.ranks)
    s.shownRanks = b.ranks
    S.SetState(s, "BOARD", s.opts.auto and { after = S.AUTO_NEXT, fn = function() Host.Next() end } or nil)
end

-- void = Skip: the question ends now and pays nothing; it does not count as
-- played, answered or correct for anyone (accuracy stays fair).
-- One pick: right when it is one of the correct answers. Several (pick all):
-- Scoring.Share, right minus wrong ticks. "correct" in the stats and the tie
-- break time count full marks only.
Close = function(s, void)
    if s.state ~= "ANSWERING" and s.state ~= "READING" then return end
    S.StopTimer(s)
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
    Comms.ToAudience(s, "REVEAL", { qid = s.qi, correct = s.cur.mask, void = void and 1 or 0,
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
local function CleanOpts(opts)
    return {
        read = READ_OK[opts.read] and opts.read or 0,
        board = BOARD_OK[opts.board] and opts.board or 1,
        shuffle = opts.shuffle and true or false,
        auto = opts.auto and true or false,
        pick = (opts.pick == "one") and "one" or "all",
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
    Comms.ToAudience(s, "START", { title = s.quiz.title, count = s.count, read = s.opts.read,
                                   board = s.opts.board, shuffle = s.opts.shuffle and 1 or 0,
                                   mode = (s.opts.pick == "one") and 1 or 2, roster = roster })
    Prepare(s, 1)
    S.SetState(s, "STARTING", { after = S.START_DELAY, fn = function() Go(s, 1) end })
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
local Roster, Channels = KHF.Roster, KHF.Channels

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
    -- the host watches its own quiz (no slot, no answers): the player side
    -- takes this START from the mirror
    s.mirror = true
    KHF.Player.Leave()
    KHF.Player.Expect(s.id, KHF.UnitKey("player"), false, true)
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
            if slot and s.players[slot] then s.players[slot].left = true end
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
        if InLobby(s) then Host.Cancel("closed") end
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
        for _, p in ipairs(s.players) do
            if not inGroup[p.key] then p.left = true end
        end
    end
end
KHF.RegisterEvent("GROUP_ROSTER_UPDATE", OnGroupChanged)

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
    if not Running(s) or s.state == "STARTING" or s.state == "LOBBY" then return false end
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
