-- Kahoof Core/SoundCues.lua: when the countdown ticks and the music parts play (ALL-80, ALL-81)
-- Pure timing, no sound calls: UI/Sounds.lua feeds it the clock every frame
-- and plays what it returns. Offline tested (test_sounds.lua).
--
-- THE MUSIC (ALL-81, Dukul 2026-11-10: "have one be the loop, and one sound be
-- the ending that mixes with the loop"). WoW cannot start a sound at an exact
-- time (a frame late at best) nor loop without a gap, so each part is a file
-- of SEG seconds of music plus a tail (reverb, a fade) after it. A new part
-- starts every SEG seconds and the tail of the last one covers its start.
-- Every time limit is a multiple of 5 (QuizStore.TIMES), so with SEG = 5 a
-- part always starts exactly 5 s before time is up: that part is the ending.
-- Counted back from the end, the loop parts fill the rest. A clock that does
-- not land on a boundary (after a pause) waits in silence for the next one.
--
--   Cues.NewMusic(left)        -> cue state for a clock with left seconds
--   Cues.StepMusic(c, left)    -> "loop" / "ending" / nil (call every frame)
--   Cues.Tick(last, left)      -> the second to tick now, or nil (5 .. 1)

local _, KHF = ...

local Cues = {}
KHF.SoundCues = Cues

Cues.SEG      = 5      -- one music part, seconds (the time limits are multiples of it)
Cues.TICK_MAX = 5      -- the countdown ticks from this second down (Dukul: "only at 5 seconds or lower")
local EARLY   = 0.1    -- a boundary this close above the clock still plays now

-- The first boundary to play: the clock's own when it sits on one (a fresh
-- question: left = the limit), else the next one down
function Cues.NewMusic(left)
    return { nextB = Cues.SEG * math.floor((left + EARLY) / Cues.SEG) }
end

function Cues.StepMusic(c, left)
    if not c or c.nextB < Cues.SEG or left > c.nextB then return nil end
    -- a long frame may pass several boundaries: play only the latest
    while c.nextB - Cues.SEG >= left and c.nextB - Cues.SEG >= Cues.SEG do
        c.nextB = c.nextB - Cues.SEG
    end
    local b = c.nextB
    c.nextB = b - Cues.SEG
    return (b == Cues.SEG) and "ending" or "loop"
end

-- last = the second ticked before (nil = none yet)
function Cues.Tick(last, left)
    if left <= 0 then return nil end
    local secs = math.ceil(left)
    if secs > Cues.TICK_MAX or secs == last then return nil end
    return secs
end
