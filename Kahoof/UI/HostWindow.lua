-- Kahoof UI/HostWindow.lua: the host's own window (S10; ALL-62, ALL-74)
-- Dukul, 2026-11-02: "The host needs a way to see the next question, their
-- hud shouldn't be like the hud of the players, they need info"; inbox
-- 2026-11-04: "a separate window attached to the main window like BNB (that
-- you can drag wherever you want)". Decided 2026-11-09: docked right of the
-- quiz window, a drag detaches it (its place saved), the dock button snaps it
-- back; only while you host a network quiz (practice keeps the quiz bar).
--
-- What it shows, top to bottom: the question number, the state and the
-- clock; this question with its correct answers ticked (and how many picked
-- each at the reveal); the next question; every player (answered or not,
-- their time, their total, a "left" mark); the host's buttons (Pause /
-- Resume, Skip, Redo, End, Start the clock, Next) and why they wait.
-- With I play too (ALL-74) the question and the next one stay hidden until
-- the reveal (only the buttons are left).
--
-- It follows the quiz window: shown with it, hidden with it. Its X hides it
-- until the quiz window opens again. It draws the host's session only and
-- never calls the engine except through the buttons.
--
--   KHF.HostWindow.Refresh(reopen)    reopen = the quiz window just opened

local _, KHF = ...
local L = KHF.L
local S = KHF.Session

local HostWindow = {}
KHF.HostWindow = HostWindow

local WIN_W, WIN_H = 300, 460   -- the quiz window's height: docked, they line up
local DOCK_GAP = 4
local ROW_H = 16
local ANS_H = 18
local TICK_OK  = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TICK_NO  = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local win, dock, head, stateFS, qtext, hiddenFS, nextFS, countFS, blockFS
local ans = {}
local sf, child, rows = nil, nil, {}
local btn = {}
local ticker
local userHidden = false

-- The hosted network quiz while its round runs (not the lobby, not practice)
local function HS()
    local hs = KHF.Host.Get()
    if not hs or hs.loopback or not KHF.Host.IsRunning() or hs.state == "LOBBY" then return nil end
    return hs
end

local function Marker(pos, size)
    return string.format("|T%s%d:%d|t", KHF.QuizUI.MARKER_TEX, pos, size or 12)
end

--------------------------------------------------------------------------------
-- PLACE: docked to the quiz window, or where it was dragged
--------------------------------------------------------------------------------
local function Pos()
    local w = KHF.db and KHF.db.windows
    if not w then return {} end
    w.host = w.host or {}
    return w.host
end

local function Place()
    local pos = Pos()
    local qw = KHF.QuizUI.Frame()
    win:ClearAllPoints()
    if not pos.detached and qw then
        win:SetPoint("TOPLEFT", qw, "TOPRIGHT", DOCK_GAP, 0)
    elseif pos.x and pos.y then
        local sc = win:GetEffectiveScale()
        win:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / sc, pos.y / sc)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end
    dock:SetSymbol(pos.detached and "unlock" or "lock")
end

local function DockTip()
    if Pos().detached then return L["HW_DOCK"], L["HW_UNDOCKED_TIP"] end
    return L["HW_DOCK"], L["HW_DOCKED_TIP"]
end

--------------------------------------------------------------------------------
-- THE CLOCK: a light ticker while a question's clock runs (only the state line)
--------------------------------------------------------------------------------
local ST_KEYS = { STARTING = "HW_ST_STARTING", READING = "HW_ST_READING", ANSWERING = "HW_ST_ANSWERING",
                  REVEAL = "HW_ST_REVEAL", BOARD = "HW_ST_BOARD" }

local function Left(hs)
    local now = (hs.hold and hs.hold.at) or S.Now()
    if hs.state == "ANSWERING" and hs.openAt and hs.cur then return hs.cur.limit - (now - hs.openAt) end
    if hs.state == "READING" and hs.opts.read > 0 then return hs.opts.read - (now - hs.stateAt) end
    if hs.state == "STARTING" then return S.START_DELAY - (now - hs.stateAt) end
    return nil
end

local function StateLine(hs)
    local text
    if S.Held(hs, "lock") then text = L["HW_ST_LOCKED"]
    elseif S.Held(hs, "pause") then text = L["HW_ST_PAUSED"]
    else
        local key = ST_KEYS[hs.state] or ST_KEYS.REVEAL
        text = L[key]
    end
    local left = Left(hs)
    if left then text = text .. "  " .. string.format(L["HW_CLOCK"], math.max(0, math.ceil(left))) end
    stateFS:SetText(text)
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function SyncTicker(hs)
    local runs = hs and win:IsShown() and not hs.hold and Left(hs) ~= nil
    if runs and not ticker then
        ticker = C_Timer.NewTicker(0.25, function()
            local h = HS()
            if not h or not win:IsShown() then return StopTicker() end
            StateLine(h)
        end)
    elseif not runs then
        StopTicker()
    end
end

--------------------------------------------------------------------------------
-- DRAWING
--------------------------------------------------------------------------------
local QUESTION_UP = { READING = true, ANSWERING = true }

local function DrawQuestion(hs)
    local st = hs.state
    if st == "STARTING" then
        head:SetText(L["QW_GET_READY"])
    else
        head:SetText(string.format(L["QW_QUESTION_N"], hs.qi, hs.count))
    end
    StateLine(hs)

    -- I play too: nothing the players have not seen yet (ALL-74)
    local hide = hs.opts.play and (QUESTION_UP[st] or st == "STARTING")
    local cur = (st ~= "STARTING") and hs.cur or nil
    hiddenFS:SetShown(hide and true or false)
    qtext:SetShown(not hide)
    qtext:SetText(cur and KHF.EscapeText(cur.text) or "")
    local revealed = (st == "REVEAL" or st == "BOARD") and hs.reveal and hs.reveal.qid == hs.qi
    for i = 1, 4 do
        local r = ans[i]
        local a = cur and not hide and cur.answers[i]
        if a then
            r.icon:SetTexture(KHF.QuizUI.MARKER_TEX .. i)
            r.text:SetText(KHF.EscapeText(a))
            r.tick:SetShown(cur.correct[i] == true)
            r.count:SetText(revealed and string.format(L["QW_PICKED"], hs.reveal.counts[i] or 0) or "")
            r:Show()
        else
            r:Hide()
        end
    end

    -- The next question: its correct answers once it is prepared (pre-sent)
    local text
    if hs.opts.play then
        text = L["HW_NEXT_HIDDEN"]
    elseif hs.next then
        local marks = {}
        for pos in pairs(hs.next.correct) do marks[#marks + 1] = pos end
        table.sort(marks)
        for i, pos in ipairs(marks) do marks[i] = Marker(pos) end
        text = string.format(st == "STARTING" and L["HW_FIRST"] or L["HW_NEXT"], KHF.EscapeText(hs.next.text))
        if #marks > 0 then text = text .. "  " .. table.concat(marks, " ") end
    elseif hs.qi < hs.count then
        local q = hs.quiz.questions[hs.qi + 1]
        text = string.format(L["HW_NEXT"], KHF.EscapeText(q and q.text or ""))
    else
        text = L["HW_NEXT_RESULTS"]
    end
    nextFS:SetText(text)
end

local function NewRow(i)
    local r = CreateFrame("Frame", nil, child)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", child, "RIGHT", 0, 0)
    if i % 2 == 0 then
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.04)
    end
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.name:SetWidth(130)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.mark = r:CreateTexture(nil, "ARTWORK")
    r.mark:SetSize(12, 12)
    r.mark:SetPoint("LEFT", r, "LEFT", 136, 0)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("LEFT", r.mark, "RIGHT", 3, 0)
    r.info:SetJustifyH("LEFT")
    r.total = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.total:SetPoint("RIGHT", r, "RIGHT", -2, 0)
    r.total:SetJustifyH("RIGHT")
    return r
end

local function DrawPlayers(hs)
    local st = hs.state
    local list = {}
    for slot, p in ipairs(hs.players) do list[#list + 1] = p end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.slot < b.slot
    end)
    if QUESTION_UP[st] then
        countFS:SetText(string.format(L["HW_ANSWERED"], KHF.Host.CountIn(hs)))
    else
        countFS:SetText(string.format(L["HW_PLAYERS"], #list))
    end
    local me = KHF.UnitKey("player")
    local showAnswers = st ~= "STARTING"
    for i, p in ipairs(list) do
        local r = rows[i] or NewRow(i)
        rows[i] = r
        local name = KHF.QuizUI.ShortName(p.key)
        if p.key == me then name = name .. " " .. L["HW_YOU"] end
        r.name:SetText(name)
        r.total:SetText(tostring(p.total))
        local a = showAnswers and hs.answers and hs.answers[p.slot]
        if p.left then
            r.mark:Hide()
            r.info:SetText("|cff888888" .. L["HW_LEFT"] .. "|r")
        elseif a then
            r.mark:SetTexture(TICK_OK)
            r.mark:Show()
            r.info:SetText(string.format(L["QW_SECONDS"], a.t))
        elseif showAnswers and hs.inQuestion and hs.inQuestion[p.slot] and not QUESTION_UP[st] then
            r.mark:SetTexture(TICK_NO)   -- no answer, after the question closed
            r.mark:Show()
            r.info:SetText("")
        else
            r.mark:Hide()
            local waiting = showAnswers and QUESTION_UP[st]
            if waiting then r.info:SetText(L["HW_WAITING"]) else r.info:SetText("") end
        end
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    child:SetHeight(math.max(1, #list * ROW_H))
end

local PAUSABLE = { READING = true, ANSWERING = true, REVEAL = true, BOARD = true }
local BLOCK_KEYS = { sending = "HW_BLOCK_sending", locked = "HW_BLOCK_locked", paused = "HW_BLOCK_paused" }

local function DrawButtons(hs)
    local st = hs.state
    local why = KHF.Host.Blocked()
    local locked = why == "locked"
    local paused = S.Held(hs, "pause")
    btn.pause:SetText(paused and L["HW_RESUME"] or L["HW_PAUSE"])
    btn.pause:SetEnabled(not locked and (paused or PAUSABLE[st] == true))
    btn.skip:SetEnabled(not locked and QUESTION_UP[st] == true)
    btn.redo:SetEnabled(KHF.Host.CanRedo())
    btn.stop:SetEnabled(not locked and st ~= "STARTING")
    btn.clock:SetShown(st == "READING" and hs.opts.read < 0)
    btn.clock:SetEnabled(not locked and not paused)
    local nextState = st == "BOARD" or (st == "REVEAL" and hs.board ~= nil and not hs.board.show)
    btn.next:SetEnabled(KHF.Host.CanNext())
    if nextState and why == "sending" then
        btn.next:SetText(L["HW_SENDING"])
    else
        btn.next:SetText((hs.qi >= hs.count) and L["QW_RESULTS"] or L["QW_NEXT"])
    end
    -- why the buttons wait ("sending" only matters when Next is next)
    if BLOCK_KEYS[why] and (why ~= "sending" or nextState) then
        blockFS:SetText(L[BLOCK_KEYS[why]])
    else
        blockFS:SetText("")
    end
end

local function Draw(hs)
    DrawQuestion(hs)
    DrawPlayers(hs)
    DrawButtons(hs)
    SyncTicker(hs)
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------
StaticPopupDialogs["KAHOOF_END_QUIZ"] = {
    text = L["QW_END_CONFIRM"], button1 = L["QW_YES"], button2 = L["QW_NO"],
    OnAccept = function() KHF.Host.End() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function Button(text, w, tip, tipText, onClick)
    local b = KHF.CreateButton(win.content, text, w, 24)
    b:SetScript("OnClick", onClick)
    if tip then KHF.SetTooltip(b, tip, tipText) end
    return b
end

local function BuildButtons(c)
    btn.stop = Button(L["QW_END"], 76, L["QW_END"], L["QW_END_TIP"], function() StaticPopup_Show("KAHOOF_END_QUIZ") end)
    btn.stop:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 0, 0)
    btn.next = Button(L["QW_NEXT"], 84, L["QW_NEXT"], L["QW_NEXT_TIP"], function() KHF.Host.Next() end)
    btn.next:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, 0)
    btn.clock = Button(L["QW_START_CLOCK"], 100, L["QW_START_CLOCK"], L["QW_START_CLOCK_TIP"],
        function() KHF.Host.StartClock() end)
    btn.clock:SetPoint("RIGHT", btn.next, "LEFT", -6, 0)

    btn.pause = Button(L["HW_PAUSE"], 90, nil, nil, function()
        if S.Held(KHF.Host.Get(), "pause") then KHF.Host.Resume() else KHF.Host.Pause() end
    end)
    local function Paused() return S.Held(KHF.Host.Get(), "pause") end
    KHF.SetTooltip(btn.pause,
        function() if Paused() then return L["HW_RESUME"] end return L["HW_PAUSE"] end,
        function() if Paused() then return L["HW_RESUME_TIP"] end return L["HW_PAUSE_TIP"] end)
    btn.pause:SetPoint("BOTTOMLEFT", btn.stop, "TOPLEFT", 0, 6)
    btn.skip = Button(L["QW_SKIP"], 80, L["QW_SKIP"], L["QW_SKIP_TIP"], function() KHF.Host.Skip() end)
    btn.skip:SetPoint("LEFT", btn.pause, "RIGHT", 6, 0)
    btn.redo = Button(L["HW_REDO"], 80, L["HW_REDO"], L["HW_REDO_TIP"], function() KHF.Host.Redo() end)
    btn.redo:SetPoint("LEFT", btn.skip, "RIGHT", 6, 0)

    blockFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blockFS:SetPoint("BOTTOMLEFT", btn.pause, "TOPLEFT", 0, 6)
    blockFS:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    blockFS:SetJustifyH("LEFT")
    blockFS:SetHeight(26)
    blockFS:SetJustifyV("BOTTOM")
end

local function BuildTop(c)
    head = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -2)
    stateFS = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    stateFS:SetPoint("TOPRIGHT", c, "TOPRIGHT", 0, -2)

    qtext = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qtext:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -22)
    qtext:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    qtext:SetHeight(42)
    qtext:SetJustifyH("LEFT")
    qtext:SetJustifyV("TOP")
    hiddenFS = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hiddenFS:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -22)
    hiddenFS:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    hiddenFS:SetJustifyH("LEFT")
    hiddenFS:SetText(L["HW_HIDDEN"])
    hiddenFS:Hide()

    for i = 1, 4 do
        local r = CreateFrame("Frame", nil, c)
        r:SetHeight(ANS_H)
        r:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -68 - (i - 1) * ANS_H)
        r:SetPoint("RIGHT", c, "RIGHT", 0, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14)
        r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.tick = r:CreateTexture(nil, "ARTWORK")
        r.tick:SetSize(14, 14)
        r.tick:SetPoint("RIGHT", r, "RIGHT", -60, 0)
        r.tick:SetTexture(TICK_OK)
        r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.count:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        r.count:SetJustifyH("RIGHT")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.text:SetPoint("RIGHT", r.tick, "LEFT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:Hide()
        ans[i] = r
    end

    nextFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nextFS:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -68 - 4 * ANS_H - 6)
    nextFS:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    nextFS:SetHeight(28)
    nextFS:SetJustifyH("LEFT")
    nextFS:SetJustifyV("TOP")

    local line = c:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", nextFS, "BOTTOMLEFT", 0, -4)
    line:SetPoint("RIGHT", c, "RIGHT", 0, 0)

    countFS = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countFS:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -6)
    return countFS
end

local function Build()
    win = KHF.CreateWindow({
        name = "KahoofHostWindow",
        w = WIN_W, h = WIN_H,
        title = L["HW_TITLE"],
        onClose = function(f)
            userHidden = true
            f:Hide()
        end,
    })
    win:SetScale(KHF.GetSetting("quizScale") or 1)
    -- a drag detaches it; its place is saved (CreateWindow's own save needs a posKey)
    win:SetScript("OnDragStop", function(self)
        KHF.StopDragMoving(self)
        local pos = Pos()
        local sc = self:GetEffectiveScale()
        local x, y = self:GetCenter()
        if x and y then pos.x, pos.y = x * sc, y * sc end
        pos.detached = true
        Place()
    end)
    local close = win.CloseButton
    local size = math.floor(close:GetHeight() - 2 + 0.5)
    dock = KHF.Theme.CreateIconButton(win, size, "lock", DockTip)
    dock:SetPoint("RIGHT", close, "LEFT", -4, 0)
    dock:SetFrameLevel(close:GetFrameLevel())
    dock:SetScript("OnClick", function(self)
        Pos().detached = false
        Place()
        self:RefreshTip()
    end)

    local c = win.content
    local top = BuildTop(c)
    BuildButtons(c)
    sf = CreateFrame("ScrollFrame", nil, c)
    sf:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -4)
    sf:SetPoint("BOTTOMRIGHT", blockFS, "TOPRIGHT", -(KHF.Theme.BAR_W + 5), 4)
    child = CreateFrame("Frame", nil, sf)
    child:SetSize(WIN_W - 2 * KHF.Theme.PAD - KHF.Theme.BAR_W - 5, 1)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    KHF.Theme.AttachScrollBar(sf)
    win:HookScript("OnHide", StopTicker)
end

--------------------------------------------------------------------------------
-- SHOWN WITH THE QUIZ WINDOW
--------------------------------------------------------------------------------
function HostWindow.Refresh(reopen)
    if reopen then userHidden = false end
    local hs = HS()
    local qw = KHF.QuizUI.Frame()
    if not (hs and qw and qw:IsShown() and not userHidden) then
        if win then win:Hide() end
        StopTicker()
        return
    end
    if not win then Build() end
    if not win:IsShown() then
        Place()
        win:Show()
    end
    Draw(hs)
end

local function OnBus() HostWindow.Refresh() end
for _, m in ipairs({ "SessionState", "QuestionShown", "AnswerCount", "Revealed", "BoardUpdated", "QuizEnded",
                     "QuizPaused", "SendQueueEmpty", "PlayersChanged", "ChatLockdown" }) do
    KHF.RegisterMessage("HostWindow", m, OnBus)
end

KHF.RegisterMessage("HostWindow", "SettingChanged", function(_, key)
    if win and key == "quizScale" then
        win:SetScale(KHF.GetSetting("quizScale") or 1)
        if win:IsShown() then Place() end
    end
end)

KHF.RegisterMessage("HostWindow", "WindowsReset", function()
    if KHF.db and KHF.db.windows then KHF.db.windows.host = {} end
    if win and win:IsShown() then Place() end
end)
