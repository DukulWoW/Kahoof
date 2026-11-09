-- Kahoof UI/HostLobby.lua: the host's lobby page, inside the Host tab (S9)
-- Shown by UI/HostTab.lua while your lobby is open or its quiz runs. The
-- quiz, who has Kahoof in your group ("6 of 9", the names without it on
-- hover: the version ping), the players who joined with their ready marks
-- and a Remove button each, and Start / Ready check / Close lobby. While the
-- quiz runs: one line and Show quiz.
--
-- Also the player grid the Play tab uses (KHF.HostLobby.CreateGrid): up to 40
-- names in three columns, pooled cells (windows-widgets.md), each with the
-- ready check mark and, on the host's page, a Remove button. Cell scripts read
-- cell._key, never a captured value. Names are drawn through KHF.EscapeText.
--
--   KHF.HostLobby.Build(page) / Refresh()
--   KHF.HostLobby.CreateGrid(parent, onRemove) -> grid; grid:SetRows(rows)
--       rows = { { key, ready }, ... } in slot order
--   KHF.HostLobby.ReadTime(t) / Info(count, read) -> the lobby's info line
--   KHF.HostLobby.EndLine(reason) -> the line for a lobby or quiz that ended
--       (a QuizEnded reason), or nil when it has none

local _, KHF = ...
local L = KHF.L

local HostLobby = {}
KHF.HostLobby = HostLobby

local COLS, CELL_W, CELL_H = 3, 176, 20
local PAD = 10

-- The game's own ready check marks (on every client)
local READY_TEX = {
    [0] = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    [1] = "Interface\\RaidFrame\\ReadyCheck-Ready",
    [2] = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local READY_TIP = { [0] = "LB_NOT_READY", [1] = "LB_READY", [2] = "LB_NO_ANSWER" }

function HostLobby.ReadTime(t)
    if t == 0 then return L["PT_READ_NONE"] end
    if t and t < 0 then return L["PT_READ_MANUAL"] end
    return string.format(L["PT_SECONDS"], t or 0)
end

function HostLobby.Info(count, read)
    local n
    if count == 1 then n = L["QUIZ_COUNT_ONE"] else n = string.format(L["QUIZ_COUNT"], count or 0) end
    return string.format(L["LB_INFO"], n, HostLobby.ReadTime(read))
end

-- QuizEnded reasons (Core/Events.lua) that have their own line
local END_LINES = {
    nohost = "LB_END_nohost", removed = "LB_END_removed", full = "LB_END_full",
    started = "LB_END_started", closed = "LB_END_closed", hostleft = "LB_END_hostleft",
    nogroup = "LB_END_nogroup", stopped = "LB_END_stopped", cancelled = "LB_END_cancelled",
}
function HostLobby.EndLine(reason)
    local key = END_LINES[reason]
    if key then return L[key] end
    return nil
end

local function ShortName(key)
    return KHF.EscapeText(KHF.QuizUI.ShortName(key))
end

--------------------------------------------------------------------------------
-- THE PLAYER GRID
--------------------------------------------------------------------------------
local function NewCell(grid, i)
    local c = CreateFrame("Frame", nil, grid)
    c:SetSize(CELL_W, CELL_H)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    c:SetPoint("TOPLEFT", grid, "TOPLEFT", col * CELL_W, -row * CELL_H)
    c.mark = c:CreateTexture(nil, "ARTWORK")
    c.mark:SetSize(14, 14)
    c.mark:SetPoint("LEFT", c, "LEFT", 0, 0)
    c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.name:SetPoint("LEFT", c, "LEFT", 18, 0)
    c.name:SetPoint("RIGHT", c, "RIGHT", -22, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    -- the mark's tooltip: what the ready answer was
    c:EnableMouse(true)
    c:SetScript("OnEnter", function(self)
        if self._ready == nil then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L[READY_TIP[self._ready]], 1, 1, 1)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip_Hide() end)
    if grid._onRemove then
        local x = CreateFrame("Button", nil, c)
        x:SetSize(16, 16)
        x:SetPoint("RIGHT", c, "RIGHT", -4, 0)
        x:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        x:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
        x:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        x:SetScript("OnClick", function(self)
            local key = self:GetParent()._key
            if key then grid._onRemove(key) end
        end)
        KHF.SetTooltip(x, function(self)
            return string.format(L["HL_REMOVE"], ShortName(self:GetParent()._key or ""))
        end, L["HL_REMOVE_TIP"])
        c.remove = x
    end
    return c
end

function HostLobby.CreateGrid(parent, onRemove)
    local grid = CreateFrame("Frame", nil, parent)
    grid:SetSize(COLS * CELL_W, math.ceil(KHF.Protocol.MAX_SLOTS / COLS) * CELL_H)
    grid._onRemove, grid._cells = onRemove, {}
    function grid:SetRows(rows)
        for i, r in ipairs(rows) do
            local c = self._cells[i] or NewCell(self, i)
            self._cells[i] = c
            c._key, c._ready = r.key, r.ready
            c.name:SetText(ShortName(r.key))
            if r.ready ~= nil and READY_TEX[r.ready] then
                c.mark:SetTexture(READY_TEX[r.ready])
                c.mark:Show()
            else
                c.mark:Hide()
            end
            c:Show()
        end
        for i = #rows + 1, #self._cells do
            self._cells[i]._key = nil
            self._cells[i]:Hide()
        end
    end
    return grid
end

--------------------------------------------------------------------------------
-- THE HOST'S PAGE
--------------------------------------------------------------------------------
local page, head, info, have, haveHit, count, grid, empty, running
local startBtn, checkBtn, closeBtn, showBtn, err

-- Who in the group has Kahoof: a version reply, a join, or you
local function Have(s)
    local without, n = {}, 0
    local keys = KHF.Channels.ForAudience("group") and KHF.Channels.GroupKeys() or {}
    local me = KHF.UnitKey("player")
    for _, k in ipairs(keys) do
        if k == me or s.lobby.have[k] or KHF.Roster.Slot(s.lobby.roster, k) then
            n = n + 1
        else
            without[#without + 1] = k
        end
    end
    return n, #keys, without
end

function HostLobby.Refresh()
    if not page or not page:IsVisible() then return end
    local s = KHF.Host.Get()
    if not s then return end
    head:SetText(string.format(L["HL_HEAD"], KHF.EscapeText(s.quiz.title)))
    info:SetText(HostLobby.Info(s.count, s.opts.read))
    local lobby = s.state == "LOBBY"
    for _, f in ipairs({ have, count, grid, startBtn, checkBtn, closeBtn }) do f:SetShown(lobby) end
    running:SetShown(not lobby)
    showBtn:SetShown(not lobby)
    if not lobby then
        empty:Hide()
        return
    end
    local n, total = Have(s)
    have:SetText(string.format(L["HL_HAVE"], n, total))

    local r = s.lobby.roster
    local rows = {}
    for _, key in ipairs(KHF.Roster.Keys(r)) do
        local p = r.bySlot[KHF.Roster.Slot(r, key)]
        rows[#rows + 1] = { key = key, ready = p.ready }
    end
    grid:SetRows(rows)
    count:SetText(string.format(L["HL_PLAYERS"], #rows))
    empty:SetShown(#rows == 0)
    startBtn:SetEnabled(#rows > 0)
    local checking = s.lobby.checkUntil ~= nil
    checkBtn:SetText(checking and L["HL_CHECKING"] or L["HL_CHECK"])
    checkBtn:SetEnabled(#rows > 0 and not checking)
end

local function Start()
    local ok, msg = KHF.Host.StartLobby()
    err:SetText(ok and "" or (msg or ""))
    if ok then KHF.HideMainWindow() end   -- the quiz window takes the stage
end

function HostLobby.Build(p)
    page = p
    head = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, -12)
    head:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
    head:SetJustifyH("LEFT")
    head:SetWordWrap(false)
    info = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
    info:SetJustifyH("LEFT")

    have = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    have:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -10)
    -- hover: the names without Kahoof (a frame over the text: a FontString takes no mouse)
    haveHit = CreateFrame("Frame", nil, p)
    haveHit:SetAllPoints(have)
    haveHit:EnableMouse(true)
    haveHit:SetScript("OnEnter", function(self)
        local s = KHF.Host.Get()
        if not s or not s.lobby then return end
        local _, _, without = Have(s)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        if #without == 0 then
            GameTooltip:SetText(L["HL_HAVE_ALL"], 1, 1, 1)
        else
            GameTooltip:SetText(L["HL_WITHOUT"], 1, 1, 1)
            for _, k in ipairs(without) do GameTooltip:AddLine(ShortName(k)) end
        end
        GameTooltip:Show()
    end)
    haveHit:SetScript("OnLeave", function() GameTooltip_Hide() end)

    count = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    count:SetPoint("TOPLEFT", have, "BOTTOMLEFT", 0, -14)
    grid = HostLobby.CreateGrid(p, function(key) KHF.Host.Remove(key) end)
    grid:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -6)
    empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -8)
    empty:SetText(L["HL_EMPTY"])

    startBtn = KHF.CreateButton(p, L["HL_START"], 120, 26)
    startBtn:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", PAD, PAD)
    startBtn:SetScript("OnClick", Start)
    KHF.SetTooltip(startBtn, L["HL_START"], L["HL_START_TIP"])
    checkBtn = KHF.CreateButton(p, L["HL_CHECK"], 120, 26)
    checkBtn:SetPoint("LEFT", startBtn, "RIGHT", 10, 0)
    checkBtn:SetScript("OnClick", function() KHF.Host.ReadyCheck() end)
    KHF.SetTooltip(checkBtn, L["HL_CHECK"], L["HL_CHECK_TIP"])
    closeBtn = KHF.CreateButton(p, L["HL_CLOSE"], 120, 26)
    closeBtn:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -PAD, PAD)
    closeBtn:SetScript("OnClick", function() KHF.Host.Cancel("closed") end)
    KHF.SetTooltip(closeBtn, L["HL_CLOSE"], L["HL_CLOSE_TIP"])

    running = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    running:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -16)
    running:SetText(L["HL_RUNNING"])
    showBtn = KHF.CreateButton(p, L["HL_SHOW"], 120, 26)
    showBtn:SetPoint("TOPLEFT", running, "BOTTOMLEFT", 0, -10)
    showBtn:SetScript("OnClick", function()
        KHF.QuizUI.Show()
        KHF.QuizUI.Refresh()
    end)

    err = p:CreateFontString(nil, "OVERLAY", "GameFontRed")
    err:SetPoint("BOTTOMLEFT", startBtn, "TOPLEFT", 0, 8)
    err:SetPoint("RIGHT", p, "RIGHT", -PAD, 0)
    err:SetJustifyH("LEFT")

    p:HookScript("OnShow", HostLobby.Refresh)
end

KHF.RegisterMessage("HostLobby", "RosterChanged", function(_, s)
    if s.role == "host" then HostLobby.Refresh() end
end)
KHF.RegisterEvent("GROUP_ROSTER_UPDATE", function() HostLobby.Refresh() end)
