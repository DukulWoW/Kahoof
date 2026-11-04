-- Kahoof Core/Practice.lua: play a quiz alone (ALL-28, S5a)
-- The full engine with a group of one (ALL-01 Q24): you host it and you play
-- it, in one client, over the loopback (Core/Comms.lua), with the real wire
-- messages. Practice scores you (architecture.md A10) and takes the same
-- start options as a real host (read time, leaderboard timing, shuffle,
-- auto-advance, pick one / all of several correct answers). Nothing goes over the network.
--
--   Practice.Start(quizId, opts) -> true | nil, msg
--   Practice.Stop()               cancel (or close a finished one) and drop both sides
--   Practice.IsRunning()

local _, KHF = ...
local L = KHF.L

local Practice = {}
KHF.Practice = Practice

-- Start options a practice run gets when the caller leaves them out: the
-- Settings defaults (data.md)
local function Defaults(opts, quiz)
    opts = opts or {}
    local o = {}
    o.read = opts.read
    if o.read == nil then o.read = KHF.GetSetting("readTime") end
    o.board = opts.board or 1
    -- the quiz's own "Randomize answers" (ALL-40) unless the caller says
    if opts.shuffle == nil then o.shuffle = quiz.shuffle == true else o.shuffle = opts.shuffle and true or false end
    o.pick = (opts.pick == "one") and "one" or "all"   -- several correct answers (ALL-33)
    if opts.auto == nil then o.auto = KHF.GetSetting("autoAdvance") and true or false else o.auto = opts.auto end
    return o
end

function Practice.IsRunning()
    local p = KHF.Player.Get()
    return KHF.Host.IsRunning() or (p ~= nil and p.state ~= "FINAL" and p.state ~= "ENDED")
end

function Practice.Start(quizId, opts)
    if Practice.IsRunning() then return nil, L["ENG_ERR_RUNNING"] end
    local quiz = KHF.QuizStore.Get(quizId)
    if not quiz then return nil, L["QZ_ERR_NOT_FOUND"] end
    KHF.Host.Dismiss()
    KHF.Player.Leave()
    local me = KHF.UnitKey("player")
    -- Kahoof_Dev's bots (S6): extra players in the roster; KHF.Dev is nil without it
    local players = { me }
    local dev = KHF.Dev
    if dev and dev.PracticePlayers then
        for _, key in ipairs(dev.PracticePlayers(me) or {}) do
            if #players < KHF.Protocol.MAX_SLOTS and key ~= me then players[#players + 1] = key end
        end
    end
    local id = KHF.Protocol.NewSessionId()
    KHF.Player.Expect(id, me, true)
    local s, msg = KHF.Host.Start(quiz, Defaults(opts, quiz), players, { id = id, loopback = true })
    if not s then
        KHF.Player.Leave()
        return nil, msg
    end
    return true
end

function Practice.Stop()
    KHF.Host.Cancel("stopped")
    KHF.Player.Leave()
end
