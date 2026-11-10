-- Kahoof Core/Session.lua: the session table, its one state change and its one timer (S5a)
-- game-engine.md: a session is keyed by its id and holds all of its state;
-- one function changes state; one running timer per session, cancelled on
-- every state change; nothing ticks while no quiz runs. The host and the
-- player each have their own session table (practice: both in one client,
-- two tables with the same id).
--
-- The engine never calls UI code: every state change sends
--   SessionState (session, state, oldState)     on the message bus.
--
--   Session.New(role, id)               role = "host" | "player"
--   Session.SetState(s, state, timer)   timer: nil, { after = sec, fn = f(s) } or
--                                       { every = sec, fn = f(s) } (a ticker)
--   Session.StopTimer(s)
--   Session.Hold(s, why) / Release(s, why, left) / Held(s, why)
--                                       stop the clock without a state change (S10)
--   Session.StartBeat(s, every, fn) / StopBeat(s)
--                                       the network heartbeat (S10)
--   Session.Now()                       GetTime(): the clock every timing uses
--
-- Holding (S10): the host's pause (ALL-66) and the host's lockdown stop the
-- state's timer and keep what was left of it. Release starts it again with
-- that time (or the time given) and moves stateAt / openAt / deadline on by
-- the time held, so a held second never counts as reading or answering time.
-- A hold has reasons ("pause", "lock"); the clock runs again only when the
-- last one goes. A state change ends every hold.
--
-- The beat (S10) is the one exception to "one timer per session": a steady
-- ticker on a network session only (the host's ALIVE, the player's host-lost
-- watch). It never changes state by itself except to end the session, and it
-- stops when the session ends (FINAL, ENDED, CANCELLED).

local _, KHF = ...

local Session = {}
KHF.Session = Session

-- Host:   (LOBBY ->) STARTING -> [ READING -> ANSWERING -> REVEAL -> (BOARD) ] x N -> FINAL
-- Player: (JOINING -> JOINED ->) STARTING -> [ READING -> ANSWERING -> (ANSWERED) -> CLOSED
--         -> REVEAL -> (BOARD) ] x N -> FINAL
-- Both:   -> CANCELLED (host) / ENDED (player) from any state.
-- LOBBY / JOINING / JOINED: the lobby (S9); practice starts at STARTING.
-- Browsing the open lobbies is no session (Core/Lobbies.lua).
-- SITOUT (player, S10): a GO came for a question that never arrived (missed
-- in a lockdown); the player waits for the next one.
Session.STATES = {
    LOBBY = true, JOINING = true, JOINED = true,
    STARTING = true, READING = true, ANSWERING = true, ANSWERED = true, CLOSED = true,
    REVEAL = true, BOARD = true, FINAL = true, CANCELLED = true, ENDED = true, SITOUT = true,
}
local OVER = { FINAL = true, CANCELLED = true, ENDED = true }

-- Pacing shared by the host and the player (both run it from the same message)
Session.START_DELAY = 3   -- START -> the first question ("Get ready")
Session.REVEAL_TIME = 5   -- the reveal shows this long before the leaderboard
Session.AUTO_NEXT   = 6   -- auto-advance: seconds on the last screen before Next
Session.BEAT        = 5   -- the network heartbeat ticker (S10)

function Session.Now()
    return GetTime()
end

function Session.New(role, id)
    return { role = role, id = id, state = nil, timer = nil }
end

function Session.StopTimer(s)
    if s.timer then
        s.timer:Cancel()
        s.timer = nil
    end
end

-- A timer callback runs only while it is still the session's timer: a state
-- change in between makes it a no-op even if Cancel came too late.
local function StartTimer(s, spec, after)
    local t
    local function Fire()
        if s.timer == t then
            if not spec.every then s.timer = nil end
            spec.fn(s)
        end
    end
    if spec.every then
        t = C_Timer.NewTicker(spec.every, Fire)
    else
        t = C_Timer.NewTimer(after, Fire)
        s.timerDue = Session.Now() + after
    end
    s.timer, s.timerSpec = t, spec
end

function Session.SetState(s, state, timer)
    assert(Session.STATES[state], "Session: unknown state")
    Session.StopTimer(s)
    s.hold, s.timerSpec, s.timerDue = nil, nil, nil
    local old = s.state
    s.state = state
    s.stateAt = Session.Now()
    if timer then StartTimer(s, timer, timer.after) end
    if OVER[state] then Session.StopBeat(s) end
    KHF.SendMessage("SessionState", s, state, old)
end

--------------------------------------------------------------------------------
-- THE CLOCK AS SHOWN (moved from UI/QuizPlay.lua for UI/Sounds.lua, ALL-80)
--------------------------------------------------------------------------------
-- -> seconds left, total, for the player's clock: Get ready (STARTING), the
-- read time (READING) or the answer time (ANSWERING / ANSWERED); nil in any
-- other state. Paused (ALL-66): the clock stands still at the pause.
function Session.Remaining(s)
    local now = (s.hold and s.hold.at) or Session.Now()
    if s.state == "STARTING" then return Session.START_DELAY - (now - s.stateAt), Session.START_DELAY end
    local q = s.q
    if not q then return nil end
    if s.state == "READING" and q.read > 0 then return q.read - (now - s.stateAt), q.read end
    if (s.state == "ANSWERING" or s.state == "ANSWERED") and s.openAt then
        return q.limit - (now - s.openAt), q.limit
    end
    return nil
end

--------------------------------------------------------------------------------
-- HOLDING (S10)
--------------------------------------------------------------------------------
function Session.Held(s, why)
    if not s or not s.hold then return false end
    if why then return s.hold.why[why] == true end
    return true
end

-- -> the seconds the state's timer had left (nil = it had none or a ticker)
function Session.Hold(s, why)
    if s.hold then
        s.hold.why[why] = true
        return s.hold.left
    end
    local now = Session.Now()
    local spec = s.timer and s.timerSpec or nil
    local left = (spec and not spec.every and s.timerDue) and math.max(0, s.timerDue - now) or nil
    Session.StopTimer(s)
    s.hold = { at = now, why = { [why] = true }, spec = spec, left = left }
    return left
end

-- left: the time to run the timer for (nil = what it had). -> true, the
-- seconds held, when the clock runs again
function Session.Release(s, why, left)
    local h = s.hold
    if not h or not h.why[why] then return false end
    h.why[why] = nil
    if next(h.why) then return false end
    s.hold = nil
    local dur = Session.Now() - h.at
    s.stateAt = s.stateAt + dur
    if s.openAt then s.openAt = s.openAt + dur end
    if s.deadline then s.deadline = s.deadline + dur end
    if h.spec then StartTimer(s, h.spec, math.max(0, left or h.left or 0)) end
    return true, dur
end

--------------------------------------------------------------------------------
-- THE BEAT (S10): network sessions only
--------------------------------------------------------------------------------
function Session.StartBeat(s, every, fn)
    Session.StopBeat(s)
    local t
    t = C_Timer.NewTicker(every, function()
        if s.beat == t then fn(s) end
    end)
    s.beat = t
end

function Session.StopBeat(s)
    if s.beat then
        s.beat:Cancel()
        s.beat = nil
    end
end
