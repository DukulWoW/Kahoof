-- Kahoof UI/PlayTab.lua: the Play tab of the main window (S9)
-- Where you join a quiz (ALL-72, Dukul, 2026-11-04: "Play is for when you
-- want to play a game"). Two views:
--   the list   the lobbies open in your group (Core/Lobbies.lua), one row each
--              with Join, or "Needs an update" for another version's lobby;
--              an empty line pointing to the Host tab; Look again (WHO).
--   your lobby while you join or wait in one (the player session before
--              START: Core/Player.lua): the quiz, the host, every player with
--              their ready mark (Dukul, 2026-11-09: "Every name"), the ready
--              check's Ready / Not ready, Leave.
-- A lobby that ended for you (removed, closed, no answer) leaves one red line
-- above the list. Opening the tab asks the group for lobbies (at most every
-- 10 s). Rows are pooled; their scripts read row._host.

local _, KHF = ...
local L = KHF.L

local PAD, ROW_H, ROWS = 10, 46, 6

local page, head, intro, status, lookBtn, empty
local rows = {}
local mine, mTitle, mInfo, mState, mCount, mGrid, readyBtn, notReadyBtn, leaveBtn

local function ShortName(key)
    return KHF.EscapeText(KHF.QuizUI.ShortName(key))
end

-- The player session while it is a lobby (JOINING / JOINED), or an ended one
local function Joined()
    local s = KHF.Player.Get()
    if s and s.prestart then return s end
    return nil
end

local function EndLine(s)
    return KHF.HostLobby.EndLine(s.endReason) or L["QW_ENDED"]
end

--------------------------------------------------------------------------------
-- THE LIST
--------------------------------------------------------------------------------
local function OnJoin(self)
    local e = KHF.Lobbies.Get(self:GetParent()._host)
    if not e then return end
    local ok, msg = KHF.Player.Join(e)
    status:SetText(ok and "" or (msg or ""))
end

local function NewRow(i)
    local r = CreateFrame("Frame", nil, page)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", page, "TOPLEFT", PAD, -90 - (i - 1) * (ROW_H + 4))
    r:SetPoint("RIGHT", page, "RIGHT", -PAD, 0)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.25)
    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -6)
    r.title:SetPoint("RIGHT", r, "RIGHT", -140, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
    r.info:SetPoint("RIGHT", r, "RIGHT", -140, 0)
    r.info:SetJustifyH("LEFT")
    r.info:SetWordWrap(false)
    r.join = KHF.CreateButton(r, L["PL_JOIN"], 110, 26)
    r.join:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.join:SetScript("OnClick", OnJoin)
    KHF.SetTooltip(r.join, function(self)
        local e = KHF.Lobbies.Get(self:GetParent()._host)
        if e and e.proto ~= KHF.Protocol.VERSION then return L["PL_OLD"] end
        return L["PL_JOIN"]
    end, nil)
    r.old = r:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    r.old:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    r.old:SetText(L["PL_OLD"])
    return r
end

local function DrawList()
    local list = KHF.Lobbies.List()
    for i = 1, math.max(#list, #rows) do
        local e = list[i]
        if e and i <= ROWS then
            local r = rows[i] or NewRow(i)
            rows[i] = r
            r._host = e.host
            r.title:SetText(KHF.EscapeText(e.title))
            local joined
            if e.players == 1 then joined = L["PL_JOINED_ONE"] else joined = string.format(L["PL_JOINED_N"], e.players or 0) end
            r.info:SetText(string.format(L["PL_ROW"], ShortName(e.host), KHF.HostLobby.Info(e.count, e.read), joined))
            local same = e.proto == KHF.Protocol.VERSION
            r.join:SetShown(same)
            r.old:SetShown(not same)
            r:Show()
        elseif rows[i] then
            rows[i]._host = nil
            rows[i]:Hide()
        end
    end
    if #list > 0 then
        empty:Hide()
    else
        empty:SetText(KHF.Channels.ForAudience("group") and L["PL_NONE"] or L["PL_NOGROUP"])
        empty:Show()
    end
end

--------------------------------------------------------------------------------
-- YOUR LOBBY
--------------------------------------------------------------------------------
local function DrawMine(s)
    mTitle:SetText(KHF.EscapeText(s.title))
    mInfo:SetText(string.format(L["PL_MINE_INFO"], ShortName(s.host), KHF.HostLobby.Info(s.count, s.read)))
    local list = {}
    for slot = 1, KHF.Protocol.MAX_SLOTS do
        local p = s.list and s.list[slot]
        if p then list[#list + 1] = { key = p.name, ready = p.ready } end
    end
    mGrid:SetRows(list)
    mCount:SetText(string.format(L["HL_PLAYERS"], #list))
    mCount:SetShown(#list > 0)
    if s.state == "JOINING" then
        mState:SetText(string.format(L["PL_JOINING"], ShortName(s.host)))
    elseif s.check and s.check.answer == nil then
        mState:SetText(string.format(L["PL_READY_Q"], ShortName(s.host)))
    elseif s.check then
        mState:SetText(s.check.answer and L["PL_SAID_READY"] or L["PL_SAID_NOT_READY"])
    else
        mState:SetText(string.format(L["PL_WAITING"], ShortName(s.host)))
    end
    local asking = s.state == "JOINED" and s.check ~= nil
    readyBtn:SetShown(asking)
    notReadyBtn:SetShown(asking)
end

local function Refresh()
    if not page or not page:IsVisible() then return end
    local s = Joined()
    local live = s and (s.state == "JOINING" or s.state == "JOINED")
    mine:SetShown(live and true or false)
    for _, f in ipairs({ head, intro, lookBtn }) do f:SetShown(not live) end
    if live then
        for _, r in ipairs(rows) do r:Hide() end
        empty:Hide()
        status:SetText("")
        DrawMine(s)
        return
    end
    DrawList()
end

--------------------------------------------------------------------------------
-- THE PAGE (built by UI/MainWindow.lua on the window's first open)
--------------------------------------------------------------------------------
local function BuildMine(p)
    mine = CreateFrame("Frame", nil, p)
    mine:SetAllPoints()
    mine:Hide()
    mTitle = mine:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mTitle:SetPoint("TOPLEFT", mine, "TOPLEFT", PAD, -12)
    mTitle:SetPoint("RIGHT", mine, "RIGHT", -PAD, 0)
    mTitle:SetJustifyH("LEFT")
    mTitle:SetWordWrap(false)
    mInfo = mine:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mInfo:SetPoint("TOPLEFT", mTitle, "BOTTOMLEFT", 0, -6)
    mInfo:SetPoint("RIGHT", mine, "RIGHT", -PAD, 0)
    mInfo:SetJustifyH("LEFT")
    mState = mine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mState:SetPoint("TOPLEFT", mInfo, "BOTTOMLEFT", 0, -12)
    mState:SetPoint("RIGHT", mine, "RIGHT", -PAD, 0)
    mState:SetJustifyH("LEFT")
    mCount = mine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mCount:SetPoint("TOPLEFT", mState, "BOTTOMLEFT", 0, -14)
    mGrid = KHF.HostLobby.CreateGrid(mine)
    mGrid:SetPoint("TOPLEFT", mCount, "BOTTOMLEFT", 0, -6)

    readyBtn = KHF.CreateButton(mine, L["PL_READY"], 120, 26)
    readyBtn:SetPoint("BOTTOMLEFT", mine, "BOTTOMLEFT", PAD, PAD)
    readyBtn:SetScript("OnClick", function() KHF.Player.Ready(true) end)
    notReadyBtn = KHF.CreateButton(mine, L["PL_NOT_READY"], 120, 26)
    notReadyBtn:SetPoint("LEFT", readyBtn, "RIGHT", 10, 0)
    notReadyBtn:SetScript("OnClick", function() KHF.Player.Ready(false) end)
    leaveBtn = KHF.CreateButton(mine, L["PL_LEAVE"], 120, 26)
    leaveBtn:SetPoint("BOTTOMRIGHT", mine, "BOTTOMRIGHT", -PAD, PAD)
    leaveBtn:SetScript("OnClick", function()
        KHF.Player.Leave()
        Refresh()
    end)
    KHF.SetTooltip(leaveBtn, L["PL_LEAVE"], L["PL_LEAVE_TIP"])
end

local function Build(p)
    page = p
    head = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -12)
    head:SetText(L["PL_HEAD"])
    intro = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    intro:SetPoint("RIGHT", p, "RIGHT", -140, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText(L["PL_INTRO"])
    lookBtn = KHF.CreateButton(p, L["PL_LOOK"], 120, 26)
    lookBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -PAD, -12)
    lookBtn:SetScript("OnClick", function()
        status:SetText("")
        KHF.Lobbies.Ask()
    end)
    KHF.SetTooltip(lookBtn, L["PL_LOOK"], L["PL_LOOK_TIP"])
    status = p:CreateFontString(nil, "OVERLAY", "GameFontRed")
    status:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
    status:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
    status:SetJustifyH("LEFT")
    status:SetText("")
    empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("TOP", p, "TOP", 0, -140)
    empty:SetPoint("LEFT", p, "LEFT", PAD, 0)
    empty:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
    BuildMine(p)

    p:HookScript("OnShow", function()
        KHF.Lobbies.Ask()
        Refresh()
    end)
    Refresh()
end
KHF.PageBuilders.TAB_PLAY = Build

KHF.RegisterMessage("PlayTab", "LobbiesChanged", Refresh)
KHF.RegisterMessage("PlayTab", "RosterChanged", function(_, s)
    if s.role == "player" then Refresh() end
end)
KHF.RegisterMessage("PlayTab", "ReadyCheck", Refresh)
KHF.RegisterMessage("PlayTab", "SessionState", function(_, s, state)
    if s.role ~= "player" then return end
    -- a fresh join clears the last red line; an end writes its reason
    if state == "JOINING" and status then status:SetText("") end
    if state == "ENDED" and s.prestart and status then status:SetText(EndLine(s)) end
    Refresh()
end)
