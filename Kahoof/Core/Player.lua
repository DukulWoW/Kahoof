-- Kahoof Core/Player.lua: the player side of a quiz (S5a: the question round; S9: joining; S10: the network round)
--
-- The player draws what the host's last message said and sends one thing:
-- its answer. It never decides whether an answer was right or what it scored
-- before the host's REVEAL / BOARD (game-engine.md). Ranks and the biggest
-- climber ARE worked out here, from BOARD, by the same Core/Scoring.lua the
-- host uses (networking.md: BOARD carries the numbers, each player ranks).
--
-- Every message must name this session's id and come from its host; START is
-- taken only when expected (Player.Expect: practice, the lobby you joined, the
-- host watching its own quiz) and only when you are in its roster (a watching
-- host has no slot and cannot answer).
--
-- Joining (S9): Join whispers JOIN to the host; the session waits in JOINING
-- until a ROSTER with you in it (JOINED), a DENY, or JOIN_WAIT s with no word
-- from the host at all ("No answer from the host"; any ROSTER from the host
-- restarts the wait, so a busy host's 40-player lobby does not time anyone
-- out). In JOINED the session holds the lobby's list (s.list) and the ready
-- check; START begins the round. Until START, s.prestart is true: the quiz
-- window draws nothing for it.
--
-- The network round (S10):
--   Repeats are dropped: a REVEAL or BOARD for a question that already has
--     one (the host sends them again after its lockdown).
--   A GO for a question that never arrived (missed in your lockdown) = SITOUT:
--     "Waiting for the next question" (Dukul, 2026-11-09: "Sit out until the
--     next one"); its BOARD still shows. Catch-up (SYNC) is ALL-16.
--   A GO for the question already shown, with its Q again = Redo (ALL-67):
--     it plays again from scratch; the climber compares with the board before.
--   PAUSE / RESUME (ALL-66): the clock stops (Session.Hold), no answers; on
--     RESUME the clocks follow the host's time left.
--   Host lost: no host message for HOST_LOST s (the host sends ALIVE when it
--     has nothing else to say), or a whisper to the host bounced = the quiz
--     ends ("hostlost"). Not counted while you are locked down yourself.
--   Your lockdown (s.locked): you hear nothing and cannot answer; one line
--     says why. A send that fails for another reason: s.sendError.
--
-- The UI follows the message bus (Core/Events.lua): SessionState,
-- QuestionShown, AnswerCount, Revealed, BoardUpdated, QuizEnded; the
-- session table holds everything it draws (s.q, s.my, s.reveal, s.board,
-- s.final, s.roster).
--
--   Player.Expect(id, host, loopback, watch)  take a START for this id from this
--                                       host (watch = the host itself, no slot)
--   Player.Join(lobby)                  -> true | nil, msg  (a Core/Lobbies.lua entry)
--   Player.Ready(on)                    the answer to the host's ready check
--   Player.Answer(picks)                -> true when sent; picks = one position
--                                       or a list of them (q.pick at most)
--   Player.Leave()                      drop the session (the host is told: LEAVE)
--   Player.CanAnswer(s)                 -> true while an answer would be taken
--   Player.OnMessage(msg)               from Comms
--   Player.OnLockdown(locked) / OnSendFailed(sid, kind) / OnBounce(key)
--                                       from Core/Channels.lua and Core/Comms.lua
--   Player.Get()

local _, KHF = ...
local S, Scoring, Comms = KHF.Session, KHF.Scoring, KHF.Comms

local Player = {}
KHF.Player = Player

local session   -- the quiz you play in (one at a time)
local expect    -- { id, host, loopback }: the START we wait for

function Player.Get() return session end

Player.JOIN_WAIT = 5   -- seconds without a word from the host: "No answer"
Player.HOST_LOST = 30  -- seconds without a word from the host mid-quiz: lost (S10)

function Player.Expect(id, host, loopback, watch)
    expect = { id = id, host = host, loopback = loopback and true or false, watch = watch and true or false }
end

local function Live(s)
    return s and s.state ~= "FINAL" and s.state ~= "ENDED"
end

function Player.Leave()
    local s = session
    if Live(s) and not s.loopback and not s.watch and s.host ~= KHF.UnitKey("player") then
        Comms.ToHost(s, "LEAVE", {})
    end
    if s then
        S.StopTimer(s)
        S.StopBeat(s)
    end
    session, expect = nil, nil
end

-- The quiz (or the lobby) is over for this player, with a reason code
local function End(s, reason)
    s.endReason = reason
    S.SetState(s, "ENDED")
    KHF.SendMessage("QuizEnded", s, reason)
end

--------------------------------------------------------------------------------
-- THE ROUND
--------------------------------------------------------------------------------
local function Close(s)
    S.SetState(s, "CLOSED")   -- time is up here; the host's REVEAL follows
end

local function Open(s)
    s.openAt = S.Now()
    S.SetState(s, "ANSWERING", { after = s.q.limit + Scoring.LATE, fn = Close })
end

-- Not while paused or locked down (S10)
function Player.CanAnswer(s)
    return (s and not s.watch and s.state == "ANSWERING" and s.q and not s.my
            and not S.Held(s) and not s.locked) and true or false
end

function Player.Answer(picks)
    local s = session
    if not Player.CanAnswer(s) then return false end
    if type(picks) == "number" then picks = { picks } end
    if type(picks) ~= "table" then return false end
    local mask = KHF.Protocol.Mask(picks)
    local list = KHF.Protocol.Unmask(mask, #s.q.answers)
    if not list or #list ~= #picks or #list > s.q.pick then return false end
    local set = {}
    for _, p in ipairs(list) do set[p] = true end
    s.my = { picks = list, set = set, t = S.Now() - s.openAt }
    s.sendError = nil
    Comms.ToHost(s, "A", { qid = s.q.qid, picks = mask })
    S.SetState(s, "ANSWERED")
    return true
end

local function ToBoard(s)
    if s.board and s.board.qid == s.qi and s.board.show then S.SetState(s, "BOARD") end
end

--------------------------------------------------------------------------------
-- MESSAGES
--------------------------------------------------------------------------------
local H = {}

function H.Q(s, m)
    if m.qid < 1 or m.qid > s.count or m.limit <= 0 then return end
    if m.pick < 1 or m.pick > #m.answers then return end
    -- only the next question is kept: a newer pre-send replaces an older one
    s.pending = { qid = m.qid, limit = m.limit, read = m.read, pick = m.pick,
                  text = m.text, answers = m.answers }
end

function H.GO(s, m)
    if m.phase == 2 then
        -- the host started the clock (read time "the host starts it")
        if s.state == "READING" and s.q and s.q.qid == m.qid then Open(s) end
        return
    end
    local q = s.pending
    if not q or q.qid ~= m.qid then
        if m.qid == s.qi or m.qid < 1 or m.qid > s.count then return end   -- a repeat
        -- missed in a lockdown: sit this one out (catch-up is ALL-16)
        KHF:Debug("GO for a question that never arrived: " .. tostring(m.qid))
        s.q, s.qi, s.my, s.reveal, s.board, s.inCount, s.sendError = nil, m.qid, nil, nil, nil, 0, nil
        S.SetState(s, "SITOUT")
        return
    end
    -- the question already shown, again: Redo (ALL-67). Its board no longer counts
    if s.q and q.qid == s.qi and s.shownQid == q.qid then
        s.shownRanks, s.shownQid = s.prevShown, nil
    end
    s.pending = nil
    s.q, s.qi, s.my, s.reveal, s.board, s.inCount, s.sendError = q, q.qid, nil, nil, nil, 0, nil
    if q.read > 0 then
        S.SetState(s, "READING", { after = q.read, fn = Open })
    elseif q.read < 0 then
        S.SetState(s, "READING")
    else
        Open(s)
    end
    KHF.SendMessage("QuestionShown", s, q)
end

function H.IN(s, m)
    if m.qid ~= s.qi then return end
    local _, n = KHF.Protocol.DecodeBits(m.bits)
    if not n then return end
    s.inCount = n
    KHF.SendMessage("AnswerCount", s, n, s.rosterSize)
end

function H.REVEAL(s, m)
    if m.qid ~= s.qi or not s.q or #m.counts ~= #s.q.answers then return end
    if s.reveal and s.reveal.qid == m.qid then return end   -- a repeat
    local list = KHF.Protocol.Unmask(m.correct, #s.q.answers)
    if not list then return end
    local correct = {}
    for _, p in ipairs(list) do correct[p] = true end
    -- right / partly right / wrong, for the reveal screen only (the points
    -- come from the host's BOARD)
    local right, wrong = 0, 0
    for _, p in ipairs(s.my and s.my.picks or {}) do
        if correct[p] then right = right + 1 else wrong = wrong + 1 end
    end
    local share = 0
    if s.my and m.void ~= 1 then
        if s.q.pick == 1 then share = (right > 0) and 1 or 0
        else share = Scoring.Share(right, wrong, #list) end
    end
    s.reveal = {
        qid = m.qid, correct = correct, correctList = list, void = m.void == 1, counts = m.counts,
        why = (m.why ~= "") and m.why or nil,
        mine = s.my and s.my.set, right = share >= 1, partial = share > 0 and share < 1, share = share,
    }
    -- the board screen follows after REVEAL_TIME when BOARD says so (it
    -- arrives right behind this message)
    S.SetState(s, "REVEAL", { after = S.REVEAL_TIME, fn = ToBoard })
    KHF.SendMessage("Revealed", s, s.reveal)
end

function H.BOARD(s, m)
    if m.qid ~= s.qi then return end
    if s.board and s.board.qid == m.qid then return end   -- a repeat
    local rows, mine = {}, nil
    for _, r in ipairs(m.rows) do
        if s.roster[r.slot] then
            rows[#rows + 1] = r
            if r.slot == s.slot then mine = r end
        end
    end
    local b = { qid = m.qid, show = m.show == 1, rows = rows, mine = mine }
    b.ranks, b.order = Scoring.Rank(rows)
    if b.show then
        b.climber, b.climbUp = Scoring.Climber(s.shownRanks, b.ranks)
        s.prevShown, s.shownQid = s.shownRanks, m.qid   -- for a Redo
        s.shownRanks = b.ranks
    end
    s.board = b
    KHF.SendMessage("BoardUpdated", s, b)
    if b.show and s.state == "SITOUT" then return ToBoard(s) end
    -- BOARD later than the reveal time (a slow network): show it now
    if b.show and s.state == "REVEAL" and S.Now() - s.stateAt >= S.REVEAL_TIME then ToBoard(s) end
end

function H.FINAL(s, m)
    local rows = {}
    for _, r in ipairs(m.rows) do
        if s.roster[r.slot] then
            r.avg = Scoring.Average(r.tsum, r.answered)   -- tenths
            rows[#rows + 1] = r
        end
    end
    local ranks, order = Scoring.Rank(rows)
    s.final = { played = m.played, rows = rows, ranks = ranks, order = order }
    S.SetState(s, "FINAL")
    KHF.SendMessage("QuizEnded", s, "final")
end

function H.CANCEL(s, m)
    s.endReason = m.reason
    S.SetState(s, "ENDED")
    KHF.SendMessage("QuizEnded", s, m.reason)
end

-- Pause (ALL-66): the clock stops, the screen is covered, no answers
function H.PAUSE(s)
    if S.Held(s, "pause") then return end
    S.Hold(s, "pause")
    KHF.SendMessage("QuizPaused", s)
end

-- Resume: the clocks follow the time the host had left (tenths)
function H.RESUME(s, m)
    if not S.Held(s, "pause") then return end
    local q, st, left = s.q, s.state, m.left / 10
    if st == "ANSWERING" and q then
        S.Release(s, "pause", left + Scoring.LATE)
    elseif st == "READING" and q and q.read > 0 then
        S.Release(s, "pause", left)
    else
        S.Release(s, "pause")
    end
    if q and (st == "ANSWERING" or st == "ANSWERED" or st == "CLOSED") then
        s.openAt = S.Now() - (q.limit - left)
    elseif q and st == "READING" and q.read > 0 then
        s.stateAt = S.Now() - (q.read - left)
    end
    KHF.SendMessage("QuizPaused", s)
end

function H.ALIVE() end   -- only that the host is there (OnMessage notes it)

local function OnStart(m)
    if not expect or expect.id ~= m.sid or expect.host ~= m.sender then return end
    local me = KHF.UnitKey("player")
    local roster, mySlot, n = {}, nil, 0
    for _, r in ipairs(m.roster) do
        if r.slot >= 1 and r.slot <= KHF.Protocol.MAX_SLOTS and not roster[r.slot] then
            roster[r.slot] = r.name
            n = n + 1
            if r.name == me then mySlot = r.slot end
        end
    end
    if (not mySlot and not expect.watch) or m.count < 1 then return end
    if session then S.StopTimer(session) end
    local s = S.New("player", m.sid)
    s.host, s.loopback, s.watch = m.sender, expect.loopback, expect.watch
    s.started = true
    s.title, s.count, s.read, s.boardEvery, s.shuffle = m.title, m.count, m.read, m.board, m.shuffle == 1
    s.pickAll = m.mode ~= 1
    s.roster, s.rosterSize, s.slot = roster, n, mySlot
    s.qi = 0
    s.lastHeard = S.Now()
    session, expect = s, nil
    S.SetState(s, "STARTING")
    if not s.loopback and not s.watch then S.StartBeat(s, S.BEAT, Player.Watch) end
end

-- The host-lost watch (S10), on the beat
function Player.Watch(s)
    if s.locked or not Live(s) then return end
    if S.Now() - (s.lastHeard or 0) > Player.HOST_LOST then End(s, "hostlost") end
end

--------------------------------------------------------------------------------
-- THE LOBBY (S9)
--------------------------------------------------------------------------------
local function WaitForHost(s)
    S.SetState(s, "JOINING", { after = Player.JOIN_WAIT, fn = function() End(s, "nohost") end })
end

function Player.Join(lobby)
    local L = KHF.L
    if type(lobby) ~= "table" or not lobby.sid or not lobby.host then return nil end
    if KHF.Host.IsRunning() then return nil, L["ENG_ERR_RUNNING"] end
    if Live(session) and session.started then return nil, L["ENG_ERR_RUNNING"] end
    if lobby.proto ~= KHF.Protocol.VERSION then return nil, L["LB_ERR_VERSION"] end
    if not KHF.Channels.CanSend() then return nil, L["COMMS_TRIAL"] end
    if KHF.Channels.Locked() then return nil, L["COMMS_LOCKED"] end
    Player.Leave()   -- one session at a time: the lobby you were in is left
    local s = S.New("player", lobby.sid)
    s.host, s.prestart = lobby.host, true
    s.title, s.count, s.read, s.aud = lobby.title, lobby.count, lobby.read, lobby.aud
    session = s
    Player.Expect(lobby.sid, lobby.host, false)
    Comms.ToHost(s, "JOIN", {})
    WaitForHost(s)
    return true
end

function Player.Ready(on)
    local s = session
    if not s or s.state ~= "JOINED" or not s.check then return false end
    s.check.answer = on and true or false
    Comms.ToHost(s, "READY", { ready = on and 1 or 0 })
    KHF.SendMessage("RosterChanged", s)
    return true
end

-- Messages while you wait in a lobby
local LH = {}

function LH.ROSTER(s, m)
    local list = KHF.Roster.Apply(s.list, m.full, m.rows)
    if not list then return end
    s.list = list
    local me, mySlot = KHF.UnitKey("player"), nil
    for slot, p in pairs(list) do
        if p.name == me then mySlot = slot end
    end
    if mySlot then
        s.lobbySlot = mySlot
        if s.state == "JOINING" then S.SetState(s, "JOINED") end
    elseif s.state == "JOINED" then
        return End(s, "removed")   -- out of the list with no DENY: it was lost
    elseif s.state == "JOINING" then
        WaitForHost(s)   -- the host is there and busy: wait on
    end
    KHF.SendMessage("RosterChanged", s)
end

function LH.DENY(s, m) End(s, m.reason) end
function LH.CANCEL(s, m) End(s, m.reason) end

function LH.CHECK(s)
    if s.state ~= "JOINED" then return end
    s.check = { at = S.Now() }
    KHF.SendMessage("ReadyCheck", s)
end

function Player.OnMessage(m)
    if m.type == "START" then return OnStart(m) end
    local s = session
    if not s or m.sid ~= s.id or m.sender ~= s.host then return end
    if not Live(s) then return end
    s.lastHeard = S.Now()
    local h = (s.prestart and LH or H)[m.type]
    if h then h(s, m) end
end

-- The group changed: a host who left it ends the quiz (or the lobby) for you
-- (game-engine.md: "The host leaving the group ends the quiz for everyone")
local function OnGroupChanged()
    local s = session
    if not Live(s) or s.loopback or s.watch or s.aud == 2 then return end
    if not KHF.Channels.ForAudience("group") then return End(s, "nogroup") end
    for _, k in ipairs(KHF.Channels.GroupKeys()) do
        if k == s.host then return end
    end
    End(s, "hostleft")
end
KHF.RegisterEvent("GROUP_ROSTER_UPDATE", OnGroupChanged)

--------------------------------------------------------------------------------
-- THE NETWORK (S10)
--------------------------------------------------------------------------------
-- Your lockdown: you hear nothing and cannot answer until it lifts; the
-- host-lost watch starts again from then
function Player.OnLockdown(locked)
    local s = session
    if not Live(s) or s.loopback or s.prestart then return end
    s.locked = locked and true or nil
    if not locked then s.lastHeard = S.Now() end
    KHF.SendMessage("QuizPaused", s)
end

function Player.OnSendFailed(sid, kind)
    local s = session
    if not Live(s) or s.id ~= sid or s.loopback then return end
    if kind == "lockdown" then
        if KHF.Channels.Locked() then return Player.OnLockdown(true) end
        return
    end
    s.sendError = kind
    KHF.SendMessage("QuizPaused", s)
end

-- A whisper to the host bounced: the host is offline
function Player.OnBounce(key)
    local s = session
    if not Live(s) or s.loopback or s.watch or s.host ~= key then return end
    End(s, s.started and "hostlost" or "nohost")
end
