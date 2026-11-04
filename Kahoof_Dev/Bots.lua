-- Kahoof_Dev Bots.lua: simulated players for practice (ALL-30, S6)
-- Extra players on the practice loopback (architecture.md section 7): the
-- host puts them in the roster and they answer with real A messages through
-- Comms.Receive, a bot as the sender, so the protocol, the host's checks,
-- scoring and the leaderboard see them exactly as they will see guildies.
--
-- Each bot gets a skill when the quiz starts: an accuracy (30-95 %) and a
-- speed (how far into the time limit it usually answers), so the board has a
-- shape and players climb. A share of answers is skipped (D.db.skip). Two
-- pairs of twins (bots 1 + 2, 3 + 4) answer alike at the same moment: they
-- always tie, so ties get tested every game.
--
-- Pure logic: Kahoof_Dev.lua wires it (the hooks, the bus, the slash
-- command). Offline tested: _work/tools/tests/test_bots.lua.
--
--   Bots.Players(me)           -> the bot keys for a practice run (D.db.bots of them)
--   Bots.OnHostState(s, state)  the host's SessionState: skills at STARTING,
--                               answers at ANSWERING

local _, D = ...
local KHF = Kahoof

local Bots = {}
D.Bots = Bots

-- Invented names, 12 letters at most (a WoW name's limit); plain ASCII
Bots.NAMES = {
    "Ashbrook", "Bramblewick", "Cindermoor", "Dawnfeather", "Emberly", "Frostquill",
    "Glimmerhoof", "Hollowbrew", "Ironsprig", "Jadewhisk", "Kettleburn", "Lumenroot",
    "Mossbeard", "Nettlefoot", "Oakenshade", "Pebbleton", "Quillmarch", "Rustbuckle",
    "Sablethorn", "Thistlewane", "Umberfen", "Vellowmist", "Wickerjaw", "Yarrowind",
    "Zephyrine", "Amberlyn", "Brindlecap", "Copperpot", "Driftmallow", "Elderglen",
    "Fennelwick", "Gorsehollow", "Hazelnook", "Inkwhistle", "Juniperose", "Knottlebee",
    "Larkspurr", "Marrowind", "Nimblethorn",
}
Bots.MAX = #Bots.NAMES   -- 39: you + 39 = the 40 slots
Bots.TWINS = { [2] = 1, [4] = 3 }   -- follower -> leader (bot numbers)

local keys = {}    -- the last Players() list, in bot order
local skill = {}   -- bot number -> { acc, speed }

-- Bots are on your realm, so the screens show their names bare (QuizUI.ShortName);
-- Forever keys have no realm part (Core/Names.lua)
function Bots.Players(me)
    local n = math.max(0, math.min(math.floor(tonumber(D.db and D.db.bots) or 0), Bots.MAX))
    local suffix = (me or ""):match("(%-[^%-]+)$") or ""
    keys = {}
    for i = 1, n do
        local key = Bots.NAMES[i] .. suffix
        if key ~= me then keys[#keys + 1] = key end
    end
    return keys
end

local function NewSkills()
    skill = {}
    for i = 1, #keys do
        skill[i] = { acc = 0.30 + 0.65 * math.random(), speed = 0.15 + 0.60 * math.random() }
    end
end

-- n distinct random positions out of 1..total
local function RandomSet(n, total)
    local all = {}
    for i = 1, total do all[i] = i end
    for i = total, 2, -1 do
        local j = math.random(1, i)
        all[i], all[j] = all[j], all[i]
    end
    local out = {}
    for i = 1, n do out[i] = all[i] end
    return out
end

local function SameSet(list, set, nSet)
    if #list ~= nSet then return false end
    for _, p in ipairs(list) do if not set[p] then return false end end
    return true
end

-- One bot's answer to the host's current question: { delay, mask }, or
-- false for no answer. The host's own question (s.cur) says which shown
-- positions are right; a dev bot may peek.
local function Decide(sk, cur)
    local skip = tonumber(D.db and D.db.skip) or 0.1
    if math.random() < skip then return false end
    local total = #cur.answers
    local right, wrong = {}, {}
    for pos = 1, total do
        if cur.correct[pos] then right[#right + 1] = pos else wrong[#wrong + 1] = pos end
    end
    local picks
    if math.random() < sk.acc and #right > 0 then
        if cur.pick == 1 then
            picks = { right[math.random(1, #right)] }   -- one right answer (any one counts)
        else
            picks = right                               -- pick all: every right one
        end
    elseif cur.pick == 1 then
        local pool = (#wrong > 0) and wrong or right
        picks = { pool[math.random(1, #pool)] }
    else
        -- pick all, missed: a random set of the asked size (partial points happen)
        for _ = 1, 5 do
            picks = RandomSet(cur.pick, total)
            if not SameSet(picks, cur.correct, #right) then break end
        end
    end
    local limit = cur.limit
    local delay = limit * sk.speed * (0.6 + 0.8 * math.random())
    delay = math.max(0.4, math.min(delay, limit - 0.2))
    return { delay = delay, mask = KHF.Protocol.Mask(picks) }
end

-- A real A message, as a guildie's would arrive (Core/Comms.lua); the host
-- would refuse a stale one anyway, this just keeps it quiet
local function Send(sid, qid, key, plan)
    C_Timer.After(plan.delay, function()
        local h = KHF.Host.Get()
        if not h or h.id ~= sid or h.qi ~= qid or h.state ~= "ANSWERING" then return end
        KHF.Comms.Receive(KHF.Protocol.Encode("A", sid, { qid = qid, picks = plan.mask }), key)
    end)
end

local function AnswerAll(s)
    local plan = {}
    for i, key in ipairs(keys) do
        local slot = s.bySender[key]
        if slot and s.inQuestion[slot] then
            local lead = Bots.TWINS[i]
            if lead and plan[lead] ~= nil then
                plan[i] = plan[lead]   -- the twin: the same picks at the same moment
            else
                plan[i] = Decide(skill[i] or { acc = 0.5, speed = 0.5 }, s.cur)
            end
            if plan[i] then Send(s.id, s.qi, key, plan[i]) end
        end
    end
end

-- Practice only: a hosted quiz on the network (S8) never gets bots
function Bots.OnHostState(s, state)
    if not s or s.role ~= "host" or not s.loopback or #keys == 0 then return end
    if state == "STARTING" then
        NewSkills()
    elseif state == "ANSWERING" then
        AnswerAll(s)
    end
end
