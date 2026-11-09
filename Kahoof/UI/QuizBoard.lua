-- Kahoof UI/QuizBoard.lua: the quiz window's leaderboard and results (S5b)
-- Leaderboard (BOARD): the top ten (Dukul, 2026-11-04; or everyone: the boardFull setting, the
-- toggle top right), your own line under it when you are not in it, the
-- biggest climber (game-engine.md). Results (FINAL): everyone ranked, with
-- points, correct answers, accuracy and average answer time, and your place.
-- The top three (Dukul, 2026-11-02): "#1 bigger than #2 that is bigger than
-- #3 that is bigger than #4 and #4 and down are the same size", in gold,
-- silver and bronze with their ranked-PvP icons, and BNB's gold divider line
-- under them. The podium look is the look pass (ALL-19, ALL-51).
--
-- Everything comes from the player's session (s.board / s.final: the host's
-- numbers, ranked by Core/Scoring.lua in Core/Player.lua). Rows are pooled
-- and only drawn from the data handed to them.
--
--   KHF.QuizUI.BuildBoard(area) -> screen;  screen:Draw(s) / Hide()

local _, KHF = ...
local L = KHF.L
local QuizUI = KHF.QuizUI

local ROW_H, ROW_GAP = 24, 2
local COL_W = 84
local DIV_H = 18   -- the gold divider under the top three
local BAR_W = 22   -- room for the scroll bar
local Y_LIST_BOARD, Y_LIST_FINAL = -58, -82
local FOOT_H = 56  -- your line + the climber / summary under the list
-- By rank (shared ranks share the look): row height, font, icon, color
local STYLE = {
    { h = 40, font = "GameFontHighlightHuge",   icon = "gold",   color = { 1.00, 0.82, 0.00 } },
    { h = 34, font = "GameFontHighlightLarge",  icon = "silver", color = { 0.82, 0.85, 0.92 } },
    { h = 30, font = "GameFontHighlightMedium", icon = "bronze", color = { 0.88, 0.56, 0.26 } },
}
local PLAIN = { h = ROW_H, font = "GameFontHighlight" }
-- The leaderboard shows the top ten (Dukul, 2026-11-04: "I think we can show
-- top 10"). Ten rows fill the list exactly, never scroll and leave no gap
-- (Dukul: "it should use the space, and not have a huge empty gap"): the
-- rows from rank 4 down take their height from the list's real height
-- (plainH, worked out on every layout), with 1 px gaps and a 12 px divider.
-- The list reaches down to the climber line, or to your own line when the
-- final standing leaves you out of the ten. The results keep the full sizes.
local BOARD_TOP = 10
local TIGHT = { gap = 1, div = 12, min = 16, max = 26 }
local FOOT_LINE = 26  -- the climber line alone under the list
local plainH          -- the board's height for rank 4 down; nil = full sizes (the results)

local function Font(name)
    return _G[name] or GameFontHighlight
end

local B = {}

--------------------------------------------------------------------------------
-- ROWS: rank, name, up to four right-hand columns
--------------------------------------------------------------------------------
local function CreateRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.rank = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.rank:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.rank:SetWidth(30)
    r.rank:SetJustifyH("RIGHT")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetPoint("CENTER", r, "LEFT", 22, 0)
    r.icon:Hide()
    r.cols = {}
    for c = 1, 4 do
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("RIGHT", r, "RIGHT", -(6 + (4 - c) * COL_W), 0)
        fs:SetWidth(COL_W - 8)
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        r.cols[c] = fs
    end
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", r, "LEFT", 44, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    return r
end

-- cols: four texts (nil = empty); ncols: how many columns are in use (the
-- name gets the rest); mine: your own row, in Kahoof's color
-- A row's name; the host who plays its own quiz is marked (ALL-74)
local function RowName(s, slot)
    local key = s.roster[slot]
    local name = QuizUI.ShortName(key)
    if key and key == s.host then name = name .. " " .. L["QW_HOST_MARK"] end
    return name
end

local function Fill(r, rank, name, cols, ncols, mine, odd)
    local st = (rank and STYLE[rank]) or PLAIN
    r._rank = rank
    r:SetHeight((plainH and not st.icon) and plainH or st.h)
    -- the top three: their icon instead of the number, name and points in their color
    if st.icon then
        r.icon:SetTexture(QuizUI.ART[st.icon])
        r.icon:SetSize(st.h - 2, st.h - 2)
        r.icon:Show()
        r.rank:SetText("")
    else
        r.icon:Hide()
        r.rank:SetText(rank and tostring(rank) or "")
        r.rank:SetTextColor(1, 1, 1)
    end
    local cr, cg, cb = 1, 1, 1
    if st.color then cr, cg, cb = st.color[1], st.color[2], st.color[3] end
    r.name:SetFontObject(Font(st.font))
    r.name:SetText(name)
    r.name:SetTextColor(cr, cg, cb)
    r.name:SetPoint("RIGHT", r, "RIGHT", -(6 + ncols * COL_W), 0)
    for c = 1, 4 do
        r.cols[c]:SetFontObject(Font(st.font))
        r.cols[c]:SetTextColor(cr, cg, cb)
        r.cols[c]:SetText(cols[c] or "")
    end
    if mine then
        local c = QuizUI.BRAND
        r.bg:SetColorTexture(c[1], c[2], c[3], 0.35)
    else
        r.bg:SetColorTexture(0, 0, 0, odd and 0.3 or 0.15)
    end
    r:Show()
end

function B:RowAt(i)
    local r = self.rows[i]
    if not r then
        r = CreateRow(self.child)
        self.rows[i] = r
    end
    return r
end

-- Stacks the n filled rows (their heights differ by rank), the gold divider
-- between the top three and the rest
function B:EndRows(n)
    for i = n + 1, #self.rows do self.rows[i]:Hide() end
    local y, prev = 0, nil
    local gap, divH = plainH and TIGHT.gap or ROW_GAP, plainH and TIGHT.div or DIV_H
    self.divider:Hide()
    for i = 1, n do
        local r = self.rows[i]
        if prev and prev <= 3 and (r._rank or 99) > 3 then
            self.divider:ClearAllPoints()
            self.divider:SetHeight(divH)
            self.divider:SetPoint("LEFT", self.child, "TOPLEFT", 20, y - divH / 2)
            self.divider:SetPoint("RIGHT", self.child, "TOPRIGHT", -20, y - divH / 2)
            self.divider:Show()
            y = y - divH
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, y)
        r:SetPoint("RIGHT", self.child, "RIGHT")
        y = y - r:GetHeight() - gap
        prev = r._rank or 99
    end
    self.child:SetHeight(math.max(1, -y))
    self.scroll:SetVerticalScroll(0)
end

local function BySlot(rows)
    local t = {}
    for _, r in ipairs(rows) do t[r.slot] = r end
    return t
end

--------------------------------------------------------------------------------
-- THE LEADERBOARD, animated (ALL-65)
-- Dukul, 2026-11-04: "start everyone at 0 and count up to their points moving
-- them in the list. Then the second time and onward, do the same from the
-- numbers they have at the point up to the points they have after those
-- rounds." Each board starts from the totals the last board of this session
-- showed (the first: 0), counts every total up over ANIM_TIME and re-ranks as
-- it goes; each row chases its place, so players visibly pass each other and
-- climb in from below the top ten (the list clips them). One row per player
-- here (they move), apart from the results' pooled rows. An OnUpdate only
-- while it runs (CLAUDE.md: OnUpdate is not free). A redraw from the bus lets
-- it run on; the toggle and reopening the window jump to the end (Dukul:
-- "Jump to the end"). The climber line comes when it has settled.
--------------------------------------------------------------------------------
local ANIM_TIME = 2.5   -- Dukul: "2,5 second since 2 might be to little and 3 is to much"
local SLIDE_K = 10      -- how fast a row closes on its place (share per second)

local function Ease(t) return 1 - (1 - t) ^ 3 end   -- fast start, slow finish

function B:SlotRow(slot)
    local r = self.slotRows[slot]
    if not r then
        r = CreateRow(self.child)
        self.slotRows[slot] = r
    end
    return r
end

local function HideAll(list)
    for _, r in pairs(list) do r:Hide() end
end

local function Gain(r) return (r.points and r.points > 0) and ("+" .. r.points) or "" end

-- Draws the board for this moment of the animation. dt nil = snap every row
-- to its place (the first frame, the end, a jump); returns true when settled.
function B:LayoutBoard(s, dt)
    local b, a = s.board, self.anim
    local e = 1
    if a and not a.done then
        local t = (GetTime() - a.t0) / ANIM_TIME
        e = (t >= 1) and 1 or Ease(math.max(0, t))
    end
    local full = KHF.GetSetting("boardFull") and true or false

    -- the totals as shown now, and the standing they make (the host's own
    -- ranks once the count is done)
    local shown, list = {}, {}
    for _, r in ipairs(b.rows) do
        local from = (a and a.prev[r.slot]) or 0
        local v = (e >= 1) and r.total or math.floor(from + (r.total - from) * e + 0.5)
        shown[r.slot] = v
        list[#list + 1] = { slot = r.slot, total = v, ctime = r.ctime }
    end
    local ranks, order = b.ranks, b.order
    if e < 1 then ranks, order = KHF.Scoring.Rank(list) end

    -- rank 4 down shares what the list has left after the medal rows, the
    -- divider and the gaps (the list's height is real only once laid out)
    local listH = self.scroll:GetHeight() or 0
    local medals = STYLE[1].h + STYLE[2].h + STYLE[3].h
    local h4 = 20
    if listH > medals then
        h4 = math.floor((listH - medals - TIGHT.div - BOARD_TOP * TIGHT.gap) / (BOARD_TOP - 3))
    end
    plainH = math.max(TIGHT.min, math.min(h4, TIGHT.max))

    local rows = BySlot(b.rows)
    local y, cut, prevRank, settled, mineIn = 0, nil, nil, true, false
    self.divider:Hide()
    for i, slot in ipairs(order) do
        local r = self:SlotRow(slot)
        local rk = ranks[slot]
        if prevRank and prevRank <= 3 and rk > 3 then
            self.divider:SetHeight(TIGHT.div)
            self.divider:ClearAllPoints()
            self.divider:SetPoint("LEFT", self.child, "TOPLEFT", 20, y - TIGHT.div / 2)
            self.divider:SetPoint("RIGHT", self.child, "TOPRIGHT", -20, y - TIGHT.div / 2)
            self.divider:Show()
            y = y - TIGHT.div
        end
        -- refill only when something on the row changed
        local key = rk .. ":" .. shown[slot] .. ":" .. (i % 2) .. ":" .. plainH
        if r._key ~= key then
            r._key = key
            Fill(r, rk, RowName(s, slot), { nil, nil, Gain(rows[slot]), tostring(shown[slot]) },
                 2, slot == s.slot, i % 2 == 1)
        end
        r:Show()
        if not dt or not r._y then
            r._y = y
        else
            r._y = r._y + (y - r._y) * math.min(1, dt * SLIDE_K)
            if math.abs(y - r._y) < 0.5 then r._y = y else settled = false end
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, r._y)
        r:SetPoint("RIGHT", self.child, "RIGHT")
        y = y - r:GetHeight() - TIGHT.gap
        prevRank = rk
        if i == BOARD_TOP then cut = -y end
        if slot == s.slot and i <= BOARD_TOP then mineIn = true end
    end
    -- top ten: the list ends under the tenth row and clips the rest (they
    -- slide in from under its edge); everyone: the whole list scrolls
    -- (never taller than the list: a tie among the medal rows cannot make it scroll)
    local h = -y
    if not full then
        h = cut or h
        if listH > 0 then h = math.min(h, listH) end
    end
    self.child:SetHeight(math.max(1, h))
    -- top ten never scrolls: no bar, no wheel (Dukul, 2026-11-04: "Scrollbar still
    -- there when you only show top 10"); everyone scrolls
    self.bar.off = not full
    if not full then self.scroll:SetVerticalScroll(0) end
    self.bar.Update()

    -- your own line when the top ten leaves you out
    if self.mineSpace and not mineIn and b.mine then
        Fill(self.mineRow, ranks[s.slot], RowName(s, s.slot),
             { nil, nil, Gain(b.mine), tostring(shown[s.slot] or b.mine.total) }, 2, true)
    else
        self.mineRow:Hide()
    end

    local done = e >= 1 and settled
    if done and b.climber and b.climbUp then
        local k = (b.climbUp == 1) and "QW_CLIMBER_ONE" or "QW_CLIMBER"
        self.foot:SetText(string.format(L[k], QuizUI.ShortName(s.roster[b.climber]), b.climbUp))
    else
        self.foot:SetText("")
    end
    return done
end

local function OnAnimUpdate(self, elapsed)
    local s = self.animSession
    if not s or not s.board or not self.anim or self.anim.done then
        self:SetScript("OnUpdate", nil)
        return
    end
    if self:LayoutBoard(s, elapsed) then self:FinishAnim() end
end

-- Ends a running animation: everything at its place, the climber line shown
function B:FinishAnim()
    local a = self.anim
    if not a or a.done then return end
    a.done = true
    self:SetScript("OnUpdate", nil)
    local s = self.animSession
    if s and s.board and self:IsShown() and not self.final then self:LayoutBoard(s) end
end

function B:DrawBoard(s)
    local b = s.board
    self.final = false
    self.head:SetText(L["QW_BOARD"])
    self.sub:SetText(string.format(L["QW_BOARD_AFTER"], s.qi, s.count))
    self.colHead:Hide()
    -- room for your own line only when the final standing leaves you out of the ten
    local myIdx
    for i, slot in ipairs(b.order) do if slot == s.slot then myIdx = i end end
    self.mineSpace = not KHF.GetSetting("boardFull") and b.mine ~= nil and myIdx ~= nil and myIdx > BOARD_TOP
    self:PlaceList(Y_LIST_BOARD, self.mineSpace and FOOT_H or FOOT_LINE)
    local full = KHF.GetSetting("boardFull") and true or false
    self.toggle:SetText(full and L["QW_TOP_TEN"] or L["QW_SHOW_ALL"])
    self.toggle:Show()
    HideAll(self.rows)

    local key = s.id .. ":" .. b.qid
    if self.animKey ~= key then
        -- a new board: count up from what the last board of this session showed
        self.animKey = key
        local prev = (self.lastSid == s.id) and self.lastTotals or {}
        local now = {}
        for _, r in ipairs(b.rows) do now[r.slot] = r.total end
        self.lastSid, self.lastTotals = s.id, now
        self.anim = { t0 = GetTime(), prev = prev, done = false }
        self.animSession = s
        HideAll(self.slotRows)
        for _, r in pairs(self.slotRows) do r._y, r._key = nil, nil end
        self:LayoutBoard(s)   -- every row at its old place, the old totals
        self.scroll:SetVerticalScroll(0)
        self:SetScript("OnUpdate", OnAnimUpdate)
    elseif not self.anim or self.anim.done then
        self.animSession = s
        self:LayoutBoard(s)
    end
    -- else: it runs on (the bus redraws often)
end

--------------------------------------------------------------------------------
-- THE RESULTS
--------------------------------------------------------------------------------
local function Accuracy(r)
    if not r.played or r.played <= 0 then return "-" end
    return string.format(L["QW_PERCENT"], math.floor(r.correct / r.played * 100 + 0.5))
end

local function AvgTime(r)
    if not r.avg then return "-" end
    return string.format(L["QW_SECONDS"], r.avg / 10)
end

function B:DrawFinal(s)
    local f = s.final
    self:FinishAnim()
    self.final = true
    self.bar.off = false   -- the results scroll
    self.bar.Update()
    HideAll(self.slotRows)
    self.divider:SetHeight(DIV_H)
    self.head:SetText(L["QW_RESULTS"])
    self.sub:SetText(KHF.EscapeText(s.title))
    self.toggle:Hide()
    self.mineRow:Hide()
    self:PlaceList(Y_LIST_FINAL)
    self.colHead:Show()
    plainH = nil

    local rows = BySlot(f.rows)
    for i, slot in ipairs(f.order) do
        local r = rows[slot]
        Fill(self:RowAt(i), f.ranks[slot], RowName(s, slot), {
            tostring(r.total),
            string.format(L["QW_OF"], r.correct, r.played),
            Accuracy(r),
            AvgTime(r),
        }, 4, slot == s.slot, i % 2 == 1)
    end
    self:EndRows(#f.order)

    local mine = rows[s.slot]
    if mine then
        self.foot:SetText(string.format(L["QW_FINAL_YOU"], f.ranks[s.slot], #f.order, mine.total))
    else
        self.foot:SetText("")
    end
end

function B:Draw(s)
    self:Show()
    if s.state == "FINAL" and s.final then self:DrawFinal(s)
    elseif s.board then self:DrawBoard(s) end
end

function B:PlaceList(y, foot)
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
    self.scroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -BAR_W, foot or FOOT_H)
end

--------------------------------------------------------------------------------
-- BUILD
--------------------------------------------------------------------------------
function QuizUI.BuildBoard(area)
    local f = CreateFrame("Frame", nil, area)
    f:SetAllPoints()
    f:Hide()
    for k, fn in pairs(B) do f[k] = fn end
    f.rows = {}
    f.slotRows = {}   -- the leaderboard's rows, one per player (they move)

    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.head:SetPoint("TOP", f, "TOP", 0, -2)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.sub:SetPoint("TOP", f.head, "BOTTOM", 0, -6)

    f.toggle = KHF.CreateButton(f, L["QW_SHOW_ALL"], 100, 22)
    f.toggle:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
    f.toggle:SetScript("OnClick", function()
        f:FinishAnim()   -- Dukul: "Jump to the end"
        KHF.SetSetting("boardFull", not KHF.GetSetting("boardFull"))
    end)

    -- the results' column titles, lined up with the rows' columns
    f.colHead = CreateRow(f)
    f.colHead:SetPoint("TOPLEFT", f, "TOPLEFT", 0, Y_LIST_FINAL + ROW_H + ROW_GAP)
    f.colHead:SetPoint("RIGHT", f, "RIGHT", -BAR_W, 0)
    f.colHead.bg:SetColorTexture(0, 0, 0, 0)
    f.colHead.rank:SetText(L["QW_COL_RANK"])
    f.colHead.name:SetText(L["QW_COL_PLAYER"])
    f.colHead.name:SetPoint("RIGHT", f.colHead, "RIGHT", -(6 + 4 * COL_W), 0)
    for c, key in ipairs({ "QW_COL_POINTS", "QW_COL_CORRECT", "QW_COL_ACCURACY", "QW_COL_TIME" }) do
        f.colHead.cols[c]:SetFontObject(GameFontNormal)
        f.colHead.cols[c]:SetText(L[key])
    end
    f.colHead.name:SetFontObject(GameFontNormal)
    f.colHead:Hide()

    f.scroll = CreateFrame("ScrollFrame", nil, f)
    f.child = CreateFrame("Frame", nil, f.scroll)
    f.child:SetSize(1, 1)
    f.scroll:SetScrollChild(f.child)
    f.child:SetClipsChildren(true)   -- top ten: rows under the tenth stay hidden until they climb in
    f.bar = KHF.Theme.AttachScrollBar(f.scroll)
    f.scroll:HookScript("OnSizeChanged", function(self, w)
        f.child:SetWidth(w or self:GetWidth())
        -- the list's real height arrived: lay the settled board out again to fit it
        if f:IsShown() and not f.final and f.animSession and f.animSession.board
           and (not f.anim or f.anim.done) then f:LayoutBoard(f.animSession) end
    end)
    f:PlaceList(Y_LIST_BOARD)
    f.divider = f.child:CreateTexture(nil, "ARTWORK")
    f.divider:SetTexture(QuizUI.ART.divider)
    f.divider:SetHeight(DIV_H)
    f.divider:Hide()

    f.mineRow = CreateRow(f)
    f.mineRow:SetPoint("TOPLEFT", f.scroll, "BOTTOMLEFT", 0, -6)
    f.mineRow:SetPoint("TOPRIGHT", f.scroll, "BOTTOMRIGHT", 0, -6)
    f.mineRow:Hide()

    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 2, 4)
    f.foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 4)
    f.foot:SetJustifyH("CENTER")
    return f
end
