-- Kahoof UI/Toast.lua: the invite toast and the ready check (S9)
-- windows-widgets.md (Invite toast); Dukul, 2026-11-09: "Toast: Join / Not now".
-- One small window near the top of the screen (the one window builder), two
-- uses:
--   invite       "<host> opened a quiz: <title>"  Join / Not now
--                (a new lobby in your group you can join: LobbyOpened)
--   ready check  "<host> asks: are you ready?"   Ready / Not ready
--                (the lobby you are in: ReadyCheck)
-- It hides by itself after SHOW_TIME s; the lobby stays on the Play tab.
-- Never in combat: one that comes in a fight waits until it ends, and shows
-- then if it still stands (the lobby still open, the check still running).
-- No invite while you host, play or wait in a lobby. Setting toastGroup
-- turns invites off (its switch is on the Settings tab, ALL-23).
-- Each plays its sound when it shows (KHF.PlaySound, UI/Sounds.lua): the
-- invite and ready check moments, picked on the Settings tab (ALL-20).

local _, KHF = ...
local L = KHF.L

local SHOW_TIME = 30

local win, text, yesBtn, noBtn, hideTimer
local current    -- { kind = "invite" | "ready", entry | s, at }
local waiting    -- the same, held until combat ends

local function ShortName(key)
    return KHF.EscapeText(KHF.QuizUI.ShortName(key))
end

local function Hide()
    if hideTimer then hideTimer:Cancel() end
    hideTimer, current = nil, nil
    if win then win:Hide() end
end

-- Does this toast still stand?
local function Stands(t)
    if GetTime() - t.at > SHOW_TIME then return false end
    if t.kind == "invite" then
        local e = KHF.Lobbies.Get(t.entry.host)
        if not e or e.sid ~= t.entry.sid or KHF.Host.IsRunning() then return false end
        local s = KHF.Player.Get()
        return s == nil or s.state == "ENDED" or s.state == "FINAL"
    end
    local s = KHF.Player.Get()
    return s == t.s and s.state == "JOINED" and s.check ~= nil and s.check.answer == nil
end

local function Build()
    win = KHF.CreateWindow({ name = "KahoofToast", w = 380, h = 112, strata = "DIALOG",
                             title = KHF.NAME, onClose = Hide })
    win:ClearAllPoints()
    win:SetPoint("TOP", UIParent, "TOP", 0, -140)
    text = win.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", win.content, "TOPLEFT", 6, -4)
    text:SetPoint("TOPRIGHT", win.content, "TOPRIGHT", -6, -4)
    text:SetJustifyH("CENTER")
    yesBtn = KHF.CreateButton(win.content, L["TOAST_JOIN"], 120, 24)
    yesBtn:SetPoint("BOTTOMRIGHT", win.content, "BOTTOM", -6, 4)
    noBtn = KHF.CreateButton(win.content, L["TOAST_LATER"], 120, 24)
    noBtn:SetPoint("BOTTOMLEFT", win.content, "BOTTOM", 6, 4)
    yesBtn:SetScript("OnClick", function()
        local t = current
        Hide()
        if not t then return end
        if t.kind == "invite" then
            local ok, msg = KHF.Player.Join(t.entry)
            if ok then KHF.ShowMainWindow("TAB_PLAY") elseif msg then KHF:Print(msg) end
        else
            KHF.Player.Ready(true)
        end
    end)
    noBtn:SetScript("OnClick", function()
        local t = current
        Hide()
        if t and t.kind == "ready" then KHF.Player.Ready(false) end
    end)
end

local function Show(t)
    if InCombatLockdown() then
        waiting = t
        return
    end
    if not Stands(t) then return end
    if not win then Build() end
    current = t
    if t.kind == "invite" then
        text:SetText(string.format(L["TOAST_LOBBY"], ShortName(t.entry.host), KHF.EscapeText(t.entry.title)))
        yesBtn:SetText(L["TOAST_JOIN"])
        noBtn:SetText(L["TOAST_LATER"])
    else
        text:SetText(string.format(L["PL_READY_Q"], ShortName(t.s.host)))
        yesBtn:SetText(L["PL_READY"])
        noBtn:SetText(L["PL_NOT_READY"])
    end
    win:Show()
    win:Raise()
    KHF.PlaySound(t.kind == "invite" and "invite" or "readyCheck")
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(math.max(1, SHOW_TIME - (GetTime() - t.at)), Hide)
end

KHF.RegisterMessage("Toast", "LobbyOpened", function(_, e)
    if not KHF.GetSetting("toastGroup") then return end
    Show({ kind = "invite", entry = e, at = GetTime() })
end)

KHF.RegisterMessage("Toast", "ReadyCheck", function(_, s)
    Show({ kind = "ready", s = s, at = GetTime() })
end)

-- The toast goes when what it asks about is gone (the lobby closed, you
-- joined from the Play tab, the quiz started)
KHF.RegisterMessage("Toast", "LobbiesChanged", function()
    if current and not Stands(current) then Hide() end
end)
KHF.RegisterMessage("Toast", "SessionState", function()
    if current and not Stands(current) then Hide() end
end)
KHF.RegisterMessage("Toast", "RosterChanged", function()
    if current and not Stands(current) then Hide() end
end)

KHF.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    local t = waiting
    waiting = nil
    if t then Show(t) end
end)
