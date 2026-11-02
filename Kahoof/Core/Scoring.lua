-- Kahoof Core/Scoring.lua: points, ranks, the biggest climber, final stats (S5a)
-- Pure functions, no WoW API: offline tested (_work/tools/tests/test_scoring.lua).
-- The rules are game-engine.md (ALL-01 part 1, Dukul, 2026-11-01). The host
-- computes points; ranks and the climber are worked out the same way by the
-- host and by every player from the BOARD data, so this one file is the rule.
--
--   Scoring.Points(elapsed, limit, share)      -> points
--   Scoring.Share(right, wrong, nCorrect)      -> 0..1 (several correct answers)
--   Scoring.Rank(rows)                         -> ranks { [slot] = rank }, order { slot, ... }
--   Scoring.Climber(before, after)             -> slot, places | nil
--   Scoring.Average(sum, n)                    -> the average, or nil when n is 0

local _, KHF = ...

local Scoring = {}
KHF.Scoring = Scoring

Scoring.BASE  = 400   -- for being right
Scoring.SPEED = 600   -- the most for speed
Scoring.GRACE = 1.0   -- seconds of full speed points after the clock starts
Scoring.LATE  = 0.5   -- an answer this long after time out still counts, as a last-second one

-- Wrong or no answer: 0. Right: 400 + speed points, the full 600 inside the
-- grace second (it absorbs the question's arrival and most latency), then
-- falling in a straight line to 0 at time out. A late answer (inside LATE)
-- counts as time out: 400. share: true = right (1), false / nil = 0, or the
-- part of a several-correct question earned (Share): the points are that
-- part of the full ones. Rounded to whole points.
function Scoring.Points(elapsed, limit, share)
    if share == true then share = 1 elseif type(share) ~= "number" then share = 0 end
    if share <= 0 or type(elapsed) ~= "number" or type(limit) ~= "number" or limit <= 0 then
        return 0
    end
    local t = math.max(0, math.min(elapsed, limit))
    local speed
    if t <= Scoring.GRACE or limit <= Scoring.GRACE then
        speed = Scoring.SPEED
    else
        speed = Scoring.SPEED * (limit - t) / (limit - Scoring.GRACE)
    end
    return math.floor(math.min(share, 1) * (Scoring.BASE + speed) + 0.5)
end

-- "Pick all correct" (ALL-33, Dukul 2026-11-02: "Right minus wrong ticks"):
-- (right ticks - wrong ticks) / correct answers, never below 0, so ticking
-- everything never pays. All 4 correct, 1 ticked: 0.25. A and C correct:
-- A + C = 1, A = 0.5, A + B = 0.
function Scoring.Share(right, wrong, nCorrect)
    if not nCorrect or nCorrect <= 0 then return 0 end
    return math.max(0, math.min(1, (right - wrong) / nCorrect))
end

-- rows: { { slot = n, total = points, ctime = tenths }, ... }; ctime = the
-- summed answer time of the player's correct answers. More points rank
-- higher; equal points: the lower ctime ranks higher; both equal: the same
-- rank (1, 2, 2, 4). order lists the slots best first (slot number last, so
-- the order never jumps).
function Scoring.Rank(rows)
    local list = {}
    for _, r in ipairs(rows) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        if (a.ctime or 0) ~= (b.ctime or 0) then return (a.ctime or 0) < (b.ctime or 0) end
        return a.slot < b.slot
    end)
    local ranks, order = {}, {}
    for i, r in ipairs(list) do
        local prev = list[i - 1]
        if prev and prev.total == r.total and (prev.ctime or 0) == (r.ctime or 0) then
            ranks[r.slot] = ranks[prev.slot]
        else
            ranks[r.slot] = i
        end
        order[i] = r.slot
    end
    return ranks, order
end

-- The player who rose the most places between two rankings, among players
-- in both. Equal rises: the better new rank, then the lower slot. nil when
-- nobody rose (and on the first board, before = nil).
function Scoring.Climber(before, after)
    if type(before) ~= "table" or type(after) ~= "table" then return nil end
    local best, bestUp
    for slot, rank in pairs(after) do
        local old = before[slot]
        local up = old and (old - rank)
        if up and up > 0 then
            local better = not best or up > bestUp
                or (up == bestUp and (rank < after[best] or (rank == after[best] and slot < best)))
            if better then best, bestUp = slot, up end
        end
    end
    return best, bestUp
end

function Scoring.Average(sum, n)
    if not n or n <= 0 then return nil end
    return sum / n
end
