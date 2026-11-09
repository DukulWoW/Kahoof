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
--   Session.Now()                       GetTime(): the clock every timing uses

local _, KHF = ...

local Session = {}
KHF.Session = Session

-- Host:   (LOBBY ->) STARTING -> [ READING -> ANSWERING -> REVEAL -> (BOARD) ] x N -> FINAL
-- Player: (JOINING -> JOINED ->) STARTING -> [ READING -> ANSWERING -> (ANSWERED) -> CLOSED
--         -> REVEAL -> (BOARD) ] x N -> FINAL
-- Both:   -> CANCELLED (host) / ENDED (player) from any state.
-- LOBBY / JOINING / JOINED: the lobby (S9); practice starts at STARTING.
-- Browsing the open lobbies is no session (Core/Lobbies.lua).
Session.STATES = {
    LOBBY = true, JOINING = true, JOINED = true,
    STARTING = true, READING = true, ANSWERING = true, ANSWERED = true, CLOSED = true,
    REVEAL = true, BOARD = true, FINAL = true, CANCELLED = true, ENDED = true,
}

-- Pacing shared by the host and the player (both run it from the same message)
Session.START_DELAY = 3   -- START -> the first question ("Get ready")
Session.REVEAL_TIME = 5   -- the reveal shows this long before the leaderboard
Session.AUTO_NEXT   = 6   -- auto-advance: seconds on the last screen before Next

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
function Session.SetState(s, state, timer)
    assert(Session.STATES[state], "Session: unknown state")
    Session.StopTimer(s)
    local old = s.state
    s.state = state
    s.stateAt = Session.Now()
    if timer then
        local t
        local function Fire()
            if s.timer == t then
                if timer.after then s.timer = nil end
                timer.fn(s)
            end
        end
        if timer.every then
            t = C_Timer.NewTicker(timer.every, Fire)
        else
            t = C_Timer.NewTimer(timer.after, Fire)
        end
        s.timer = t
    end
    KHF.SendMessage("SessionState", s, state, old)
end
