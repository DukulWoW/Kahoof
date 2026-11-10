-- Kahoof UI/Sounds.lua: every sound Kahoof plays, picked per moment (ALL-20, ALL-79, ALL-80, ALL-81)
-- Each moment plays one LibSharedMedia sound (ALL-79, Dukul 2026-11-10: "so
-- people have a lot more to choose from"), "None" for silence. Ours are
-- registered with LSM too ("Kahoof: Invite" ...), so other addons can use
-- them. A sound pack removed later: its moment falls back to our default.
--
-- Volume: addons get no volume of their own, PlaySoundFile plays at the
-- volume of one game channel. The channel is a setting (default Master), so a
-- player who finds us loud picks Ambience or Dialog and turns that one down
-- (Dukul, 2026-11-10: "Ok"). Settings: KahoofDB.sounds = { on, channel, pick = {
-- [moment] = LSM name } }; a moment not in pick plays its default.
--
-- The clock (ticks and music) runs on one OnUpdate frame of its own, only
-- while a clock shows AND a tick or music sound is picked: the quiz window
-- may be hidden (ESC) and its own ticker with it, the sounds go on.
--
--   KHF.PlaySound(moment)        plays that moment's sound (nothing when off / "None")
--   KHF.Sounds.MOMENTS           { { key, label, tip, def } or { group }, ... } in Settings order
--   KHF.Sounds.CHANNELS          { { key, label }, ... }
--   KHF.Sounds.Get(moment) / Set(moment, name) / Preview(name) / List()
--   KHF.Sounds.SetOn(on) / SetChannel(key)

local _, KHF = ...
local S, Cues = KHF.Session, KHF.SoundCues

local Sounds = {}
KHF.Sounds = Sounds

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local NONE = "None"   -- LSM's own silent entry; also ours without LSM

-- Our sounds in LSM. The names are saved in KahoofDB, so they stay English
-- and never change (a new name = a new entry)
local DIR = KHF.ADDON_PATH .. "Assets\\Sounds\\"
local OWN = {
    INVITE = KHF.NAME .. ": Invite",
    READY  = KHF.NAME .. ": Ready check",
    CLICK  = KHF.NAME .. ": Answer click",
    TICK   = KHF.NAME .. ": Countdown tick",
}
local OWN_DATA = {
    [OWN.INVITE] = DIR .. "invite.ogg",
    [OWN.READY]  = DIR .. "ready-check.ogg",
    [OWN.CLICK]  = DIR .. "answer-click.ogg",
    -- the game's own UI_BattlegroundCountdown_Timer (Dukul, 2026-11-10), a file id
    [OWN.TICK]   = 567474,
}
if LSM then
    for name, data in pairs(OWN_DATA) do LSM:Register("sound", name, data) end
end

-- In Settings order. def = the default; NONE = an empty slot for Dukul to
-- fill (Dukul, 2026-11-10: "add settings for sounds that we haven't
-- implemented as blank so I can see what I need to look for")
Sounds.MOMENTS = {
    { group = "SND_GROUP_LOBBY" },
    { key = "invite",       label = "SND_INVITE",        tip = "SND_INVITE_TIP",        def = OWN.INVITE },
    { key = "readyCheck",   label = "SND_READY",         tip = "SND_READY_TIP",         def = OWN.READY },
    { key = "playerJoined", label = "SND_JOINED",        tip = "SND_JOINED_TIP",        def = NONE },
    { group = "SND_GROUP_QUIZ" },
    { key = "getReady",     label = "SND_GET_READY",     tip = "SND_GET_READY_TIP",     def = NONE },
    { key = "readyCount",   label = "SND_READY_COUNT",   tip = "SND_READY_COUNT_TIP",   def = OWN.TICK },
    { key = "question",     label = "SND_QUESTION",      tip = "SND_QUESTION_TIP",      def = NONE },
    { key = "answer",       label = "SND_ANSWER",        tip = "SND_ANSWER_TIP",        def = OWN.CLICK },
    { key = "countdown",    label = "SND_COUNTDOWN",     tip = "SND_COUNTDOWN_TIP",     def = OWN.TICK },
    { key = "timesUp",      label = "SND_TIMES_UP",      tip = "SND_TIMES_UP_TIP",      def = NONE },
    { key = "correct",      label = "SND_CORRECT",       tip = "SND_CORRECT_TIP",       def = NONE },
    { key = "wrong",        label = "SND_WRONG",         tip = "SND_WRONG_TIP",         def = NONE },
    { key = "leaderboard",  label = "SND_BOARD",         tip = "SND_BOARD_TIP",         def = NONE },
    { key = "climber",      label = "SND_CLIMBER",       tip = "SND_CLIMBER_TIP",       def = NONE },
    { key = "results",      label = "SND_RESULTS",       tip = "SND_RESULTS_TIP",       def = NONE },
    { key = "paused",       label = "SND_PAUSED",        tip = "SND_PAUSED_TIP",        def = NONE },
    { key = "resumed",      label = "SND_RESUMED",       tip = "SND_RESUMED_TIP",       def = NONE },
    { group = "SND_GROUP_MUSIC" },
    { key = "musicLoop",    label = "SND_MUSIC_LOOP",    tip = "SND_MUSIC_LOOP_TIP",    def = NONE },
    { key = "musicEnding",  label = "SND_MUSIC_ENDING",  tip = "SND_MUSIC_ENDING_TIP",  def = NONE },
    { key = "musicEarly",   label = "SND_MUSIC_EARLY",   tip = "SND_MUSIC_EARLY_TIP",   def = NONE },
}
local DEF = {}
for _, m in ipairs(Sounds.MOMENTS) do
    if m.key then
        DEF[m.key] = m.def
    end
end

Sounds.CHANNELS = {
    { key = "Master",   label = "SND_CH_MASTER" },
    { key = "SFX",      label = "SND_CH_SFX" },
    { key = "Music",    label = "SND_CH_MUSIC" },
    { key = "Ambience", label = "SND_CH_AMBIENCE" },
    { key = "Dialog",   label = "SND_CH_DIALOG" },
}

local function DB() return KHF.db and KHF.db.sounds or KHF.DEFAULTS.sounds end

--------------------------------------------------------------------------------
-- PICKING AND PLAYING
--------------------------------------------------------------------------------
-- Every sound name to pick from, "None" first, then A-Z
function Sounds.List()
    local out = { NONE }
    if LSM then
        for _, name in ipairs(LSM:List("sound")) do
            if name ~= NONE then out[#out + 1] = name end
        end
    else
        for name in pairs(OWN_DATA) do out[#out + 1] = name end
        table.sort(out, function(a, b) return a ~= NONE and (b == NONE or a < b) end)
    end
    return out
end

local function Fetch(name)
    if name == NONE then return nil end
    if LSM then return LSM:Fetch("sound", name, true) end
    return OWN_DATA[name]
end

-- The name picked for a moment; one that no longer exists (a removed sound
-- pack) reads as the default
function Sounds.Get(moment)
    local name = DB().pick and DB().pick[moment]
    if name == nil or (name ~= NONE and not Fetch(name)) then return DEF[moment] or NONE end
    return name
end

function Sounds.IsSet(moment) return Sounds.Get(moment) ~= NONE end
function Sounds.IsDefault(moment) return Sounds.Get(moment) == DEF[moment] end
function Sounds.Default(moment) return DEF[moment] or NONE end

local function Channel()
    local ch = DB().channel
    for _, c in ipairs(Sounds.CHANNELS) do
        if c.key == ch then return ch end
    end
    return "Master"
end

-- -> the sound handle, or nil
local function PlayName(name)
    local data = Fetch(name)
    if not data then return nil end
    local ok, willPlay, handle = pcall(PlaySoundFile, data, Channel())
    return ok and willPlay and handle or nil
end

function KHF.PlaySound(moment)
    if not DB().on then return nil end
    return PlayName(Sounds.Get(moment))
end

-- The Settings page's play button: plays even with sounds off
function Sounds.Preview(name) PlayName(name) end

local Refresh   -- the clock driver, below

function Sounds.Set(moment, name)
    if not KHF.db then return end
    if name == DEF[moment] then name = nil end   -- the default is no entry
    KHF.db.sounds.pick[moment] = name
    KHF.SendMessage("SettingChanged", "sounds")
    Refresh()
end

function Sounds.SetOn(on)
    if not KHF.db then return end
    KHF.db.sounds.on = on and true or false
    KHF.SendMessage("SettingChanged", "sounds")
    Refresh()
end

function Sounds.SetChannel(key)
    if not KHF.db then return end
    KHF.db.sounds.channel = key
    KHF.SendMessage("SettingChanged", "sounds")
end

--------------------------------------------------------------------------------
-- THE CLOCK: countdown ticks (ALL-80) and the music parts (ALL-81)
--------------------------------------------------------------------------------
local ANSWER = { ANSWERING = true, ANSWERED = true }
local CLOCK  = { STARTING = true, READING = true, ANSWERING = true, ANSWERED = true }
local FADE_MS = 300

local driver = CreateFrame("Frame")
local lastTick, cue = nil, nil
local music = {}   -- handles of the music parts still sounding

local function StopMusic()
    for i = #music, 1, -1 do
        pcall(StopSound, music[i], FADE_MS)
        music[i] = nil
    end
    cue = nil
end

local function OnUpdate()
    local s = KHF.Player.Get()
    local left = s and S.Remaining(s)
    if not left then return Refresh() end
    if S.Held(s) then
        if #music > 0 then StopMusic() end   -- the clock stands: so does the music
        return
    end
    local t = Cues.Tick(lastTick, left)
    if t then
        lastTick = t
        KHF.PlaySound(ANSWER[s.state] and "countdown" or "readyCount")
    end
    if ANSWER[s.state] then
        cue = cue or Cues.NewMusic(left)
        local part = Cues.StepMusic(cue, left)
        if part then
            local h = KHF.PlaySound(part == "ending" and "musicEnding" or "musicLoop")
            if h then music[#music + 1] = h end
        end
    end
end

-- Runs the driver only when it has something to play
Refresh = function()
    local s = KHF.Player.Get()
    local need = DB().on and s and CLOCK[s.state] and (Sounds.IsSet("countdown") or Sounds.IsSet("readyCount")
        or Sounds.IsSet("musicLoop") or Sounds.IsSet("musicEnding"))
    if not DB().on then StopMusic() end
    driver:SetScript("OnUpdate", need and OnUpdate or nil)
end

--------------------------------------------------------------------------------
-- THE MOMENTS: the player's side only (the host's session sends the same
-- messages; a host who does not play still has the player session that
-- shows the quiz, without a slot)
--------------------------------------------------------------------------------
local function Mine(s) return s and s == KHF.Player.Get() end

local pausedS, paused     -- the session and its last pause, for paused / resumed
local rosterS, rosterN    -- the host's lobby and its last count, for playerJoined

KHF.RegisterMessage("Sounds", "SessionState", function(_, s, state, old)
    if not Mine(s) then return end
    lastTick = nil
    if ANSWER[old] and not ANSWER[state] then
        -- closed early (everyone answered): the music fades and the early
        -- ending plays; at time up the ending part plays out with its tail
        local q = s.q
        local left = (q and s.openAt) and (q.limit - (S.Now() - s.openAt)) or 0
        if left > 0.5 then
            if #music > 0 then StopMusic(); KHF.PlaySound("musicEarly") end
        end
        cue = nil
    end
    if state == "STARTING" then KHF.PlaySound("getReady")
    elseif state == "CLOSED" and ANSWER[old] then KHF.PlaySound("timesUp")
    elseif state == "BOARD" then
        local b = s.board
        if s.slot and b and b.climber == s.slot and Sounds.IsSet("climber") then KHF.PlaySound("climber")
        else KHF.PlaySound("leaderboard") end
    elseif state == "FINAL" then KHF.PlaySound("results")
    end
    if not CLOCK[state] and state ~= "CLOSED" and state ~= "REVEAL" then StopMusic() end
    Refresh()
end)

KHF.RegisterMessage("Sounds", "QuestionShown", function(_, s)
    if not Mine(s) then return end
    StopMusic()   -- a tail from the last question
    KHF.PlaySound("question")
end)

KHF.RegisterMessage("Sounds", "Revealed", function(_, s, r)
    if not Mine(s) or not s.slot or not r or r.void then return end
    KHF.PlaySound((r.right or r.partial) and "correct" or "wrong")
end)

KHF.RegisterMessage("Sounds", "QuizPaused", function(_, s)
    if not Mine(s) then return end
    local p = S.Held(s, "pause")
    if pausedS ~= s then pausedS, paused = s, false end
    if p ~= paused then
        paused = p
        KHF.PlaySound(p and "paused" or "resumed")
    end
end)

KHF.RegisterMessage("Sounds", "RosterChanged", function(_, s)
    if not s or s.role ~= "host" or not s.lobby then return end
    local n = KHF.Roster.Count(s.lobby.roster)
    if rosterS == s and n > (rosterN or 0) then KHF.PlaySound("playerJoined") end
    rosterS, rosterN = s, n
end)
