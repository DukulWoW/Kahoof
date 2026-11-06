-- Kahoof Core/Events.lua: game events (one dispatcher) and the message bus
-- Ported from BNB's Core/Events.lua.

local _, KHF = ...
local L = KHF.L

--------------------------------------------------------------------------------
-- GAME EVENTS
-- Modules register with KHF.RegisterEvent(event, fn); fn(event, ...). One frame
-- for the whole addon. Each handler runs through securecallfunction: an error
-- is reported (BugSack / script errors) and the other handlers still run.
--------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function KHF.RegisterEvent(event, fn)
    eventFrame:RegisterEvent(event)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
end

-- Removes one handler; the frame event goes when none are left. The list is
-- replaced, not edited in place, so a dispatch running over it is not disturbed
function KHF.UnregisterEvent(event, fn)
    local list = handlers[event]
    if not list then return end
    local kept = {}
    for _, h in ipairs(list) do
        if h ~= fn then kept[#kept + 1] = h end
    end
    if #kept == 0 then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
    else
        handlers[event] = kept
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        securecallfunction(list[i], event, ...)
    end
end)

--------------------------------------------------------------------------------
-- MESSAGE BUS (CallbackHandler, as BNB)
-- Things that happen inside Kahoof. The engine never calls UI code: it sends a
-- message and the UI listens (architecture.md section 4).
--   KHF.RegisterMessage(owner, "SettingChanged", fn)   owner = a string or table
--   KHF.UnregisterMessage(owner, "SettingChanged")
--   KHF.UnregisterAllMessages(owner)
--   KHF.SendMessage("SettingChanged", key, value)
-- fn gets the message name first: fn("SettingChanged", key, value). One owner
-- holds one handler per message, so each subscriber uses its own owner.
-- A new message is listed here, with who sends it.
-- Sent now:
--   SettingChanged (key, value)   Core/Database.lua KHF.SetSetting
--   WindowsReset ()               Core/Database.lua KHF.ResetWindows (/kahoof reset)
--   QuizzesChanged (id, what)     Core/QuizStore.lua, what = created | saved | deleted
-- The quiz engine (S5a); s = the session table, s.role = "host" | "player",
-- so one listener can tell the host's screens from the player's:
--   SessionState (s, state, old)  Core/Session.lua SetState
--   QuestionShown (s, q)          Core/Host.lua, Core/Player.lua: GO, the question shows
--   AnswerCount (s, n, total)     Host: each answer; Player: each IN
--   Revealed (s, reveal)          the correct answer, counts, why, your pick
--   BoardUpdated (s, board)       points, ranks, climber (every question)
--   QuizEnded (s, reason)         "final", or a CANCEL reason ("stopped", ...)
-- The network path (S8):
--   ChatLockdown (locked)         Core/Channels.lua: the game started / stopped
--                                 blocking addon messages (encounter, M+, PvP)
--   SendFailed (sid, kind)        Core/Comms.lua: a send failed for good (lockdown,
--                                 nogroup, trial, throttle, toolong, an enum name);
--                                 that session's queued messages are dropped
--   WhisperBounced (key)          Core/Comms.lua: a whisper went to someone offline
-- Planned (architecture.md section 4, not sent yet): RosterChanged, LobbiesChanged
--------------------------------------------------------------------------------
KHF.callbacks = LibStub("CallbackHandler-1.0"):New(KHF,
    "RegisterMessage", "UnregisterMessage", "UnregisterAllMessages")

function KHF.SendMessage(msg, ...)
    KHF.callbacks:Fire(msg, ...)
end

--------------------------------------------------------------------------------
-- STARTUP
-- ADDON_LOADED: the SavedVariables exist, set them up before anything reads them.
-- PLAYER_LOGIN: the world is up; UI files hook it for anything that needs it.
--------------------------------------------------------------------------------
local function OnAddonLoaded(_, name)
    if name ~= KHF.ADDON_NAME then return end
    KHF.UnregisterEvent("ADDON_LOADED", OnAddonLoaded)
    KHF.InitializeDB()
end
KHF.RegisterEvent("ADDON_LOADED", OnAddonLoaded)

local function OnLogin()
    KHF.UnregisterEvent("PLAYER_LOGIN", OnLogin)
    local client = KHF.IsForever and L["CLIENT_FOREVER"] or L["CLIENT_RETAIL"]
    KHF:Print(string.format(L["LOADED_MSG"], KHF.ADDON_VERSION, client))
end
KHF.RegisterEvent("PLAYER_LOGIN", OnLogin)
