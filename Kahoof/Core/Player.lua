-- Kahoof Core/Player.lua: the player side of a quiz (S5a: the question round; joining is S9)
--
-- The player draws what the host's last message said and sends one thing:
-- its answer. It never decides whether an answer was right or what it scored
-- before the host's REVEAL / BOARD (game-engine.md). Ranks and the biggest
-- climber ARE worked out here, from BOARD, by the same Core/Scoring.lua the
-- host uses (networking.md: BOARD carries the numbers, each player ranks).
--
-- Every message must name this session's id and come from its host; START is
-- taken only when expected (Player.Expect: practice now, the joined lobby in
-- S9) and only when you are in its roster.
--
-- The UI follows the message bus (Core/Events.lua): SessionState,
-- QuestionShown, AnswerCount, Revealed, BoardUpdated, QuizEnded; the
-- session table holds everything it draws (s.q, s.my, s.reveal, s.board,
-- s.final, s.roster).
--
--   Player.Expect(id, host, loopback)   take a START for this id from this host
--   Player.Answer(pos)                  -> true when sent
--   Player.Leave()                      drop the session
--   Player.OnMessage(msg)               from Comms
--   Player.Get()

local _, KHF = ...
local S, Scoring, Comms = KHF.Session, KHF.Scoring, KHF.Comms

local Player = {}
KHF.Player = Player

local session   -- the quiz you play in (one at a time)
local expect    -- { id, host, loopback }: the START we wait for

function Player.Get() return session end

function Player.Expect(id, host, loopback)
    expect = { id = id, host = host, loopback = loopback and true or false }
end

function Player.Leave()
    if session then S.StopTimer(session) end
    session, expect = nil, nil
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

function Player.Answer(pos)
    local s = session
    if not s or s.state ~= "ANSWERING" or not s.q or s.my then return false end
    if type(pos) ~= "number" or pos < 1 or pos > #s.q.answers then return false end
    s.my = { pos = pos, t = S.Now() - s.openAt }
    Comms.ToHost(s, "A", { qid = s.q.qid, answer = pos })
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
    -- only the next question is kept: a newer pre-send replaces an older one
    s.pending = { qid = m.qid, limit = m.limit, read = m.read, text = m.text, answers = m.answers }
end

function H.GO(s, m)
    if m.phase == 2 then
        -- the host started the clock (read time "the host starts it")
        if s.state == "READING" and s.q and s.q.qid == m.qid then Open(s) end
        return
    end
    local q = s.pending
    if not q or q.qid ~= m.qid then
        KHF:Debug("GO for a question that never arrived: " .. tostring(m.qid))   -- S10: SYNC
        return
    end
    s.pending = nil
    s.q, s.qi, s.my, s.reveal, s.inCount = q, q.qid, nil, nil, 0
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
    if m.correct < 1 or m.correct > #s.q.answers then return end
    local mine = s.my and s.my.pos
    s.reveal = {
        qid = m.qid, correct = m.correct, void = m.void == 1, counts = m.counts,
        why = (m.why ~= "") and m.why or nil,
        mine = mine, right = mine ~= nil and mine == m.correct and m.void ~= 1,
    }
    -- the board screen follows after REVEAL_TIME when BOARD says so (it
    -- arrives right behind this message)
    S.SetState(s, "REVEAL", { after = S.REVEAL_TIME, fn = ToBoard })
    KHF.SendMessage("Revealed", s, s.reveal)
end

function H.BOARD(s, m)
    if m.qid ~= s.qi then return end
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
        s.shownRanks = b.ranks
    end
    s.board = b
    KHF.SendMessage("BoardUpdated", s, b)
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
    if not mySlot or m.count < 1 then return end
    if session then S.StopTimer(session) end
    local s = S.New("player", m.sid)
    s.host, s.loopback = m.sender, expect.loopback
    s.title, s.count, s.read, s.boardEvery, s.shuffle = m.title, m.count, m.read, m.board, m.shuffle == 1
    s.roster, s.rosterSize, s.slot = roster, n, mySlot
    s.qi = 0
    session, expect = s, nil
    S.SetState(s, "STARTING")
end

function Player.OnMessage(m)
    if m.type == "START" then return OnStart(m) end
    local s = session
    if not s or m.sid ~= s.id or m.sender ~= s.host then return end
    if s.state == "FINAL" or s.state == "ENDED" then return end
    local h = H[m.type]
    if h then h(s, m) end
end
