-- Kahoof UI/QuizBoard.lua: the quiz window's leaderboard and results (S5b)
-- Leaderboard (BOARD): the top five (or everyone: the boardFull setting, the
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
local function Fill(r, rank, name, cols, ncols, mine, odd)
    local st = (rank and STYLE[rank]) or PLAIN
    r._rank = rank
    r:SetHeight(st.h)
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
    self.divider:Hide()
    for i = 1, n do
        local r = self.rows[i]
        if prev and prev <= 3 and (r._rank or 99) > 3 then
            self.divider:ClearAllPoints()
            self.divider:SetPoint("LEFT", self.child, "TOPLEFT", 20, y - DIV_H / 2)
            self.divider:SetPoint("RIGHT", self.child, "TOPRIGHT", -20, y - DIV_H / 2)
            self.divider:Show()
            y = y - DIV_H
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, y)
        r:SetPoint("RIGHT", self.child, "RIGHT")
        y = y - r:GetHeight() - ROW_GAP
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
-- THE LEADERBOARD
--------------------------------------------------------------------------------
function B:DrawBoard(s)
    local b = s.board
    self.head:SetText(L["QW_BOARD"])
    self.sub:SetText(string.format(L["QW_BOARD_AFTER"], s.qi, s.count))
    self.colHead:Hide()
    self:PlaceList(Y_LIST_BOARD)
    local full = KHF.GetSetting("boardFull") and true or false
    self.toggle:SetText(full and L["QW_TOP_FIVE"] or L["QW_SHOW_ALL"])
    self.toggle:Show()

    local rows = BySlot(b.rows)
    local n, mineShown = 0, false
    for i, slot in ipairs(b.order) do
        if not full and i > 5 then break end
        local r = rows[slot]
        n = n + 1
        local gain = (r.points and r.points > 0) and ("+" .. r.points) or ""
        Fill(self:RowAt(n), b.ranks[slot], QuizUI.ShortName(s.roster[slot]),
             { nil, nil, gain, tostring(r.total) }, 2, slot == s.slot, n % 2 == 1)
        if slot == s.slot then mineShown = true end
    end
    self:EndRows(n)

    -- your own line when the top five leaves you out
    if b.mine and not mineShown then
        local r = b.mine
        Fill(self.mineRow, b.ranks[s.slot], QuizUI.ShortName(s.roster[s.slot]),
             { nil, nil, (r.points and r.points > 0) and ("+" .. r.points) or "", tostring(r.total) }, 2, true)
    else
        self.mineRow:Hide()
    end

    if b.climber and b.climbUp then
        local key = (b.climbUp == 1) and "QW_CLIMBER_ONE" or "QW_CLIMBER"
        self.foot:SetText(string.format(L[key], QuizUI.ShortName(s.roster[b.climber]), b.climbUp))
    else
        self.foot:SetText("")
    end
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
    self.head:SetText(L["QW_RESULTS"])
    self.sub:SetText(KHF.EscapeText(s.title))
    self.toggle:Hide()
    self.mineRow:Hide()
    self:PlaceList(Y_LIST_FINAL)
    self.colHead:Show()

    local rows = BySlot(f.rows)
    for i, slot in ipairs(f.order) do
        local r = rows[slot]
        Fill(self:RowAt(i), f.ranks[slot], QuizUI.ShortName(s.roster[slot]), {
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

function B:PlaceList(y)
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
    self.scroll:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -BAR_W, FOOT_H)
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

    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.head:SetPoint("TOP", f, "TOP", 0, -2)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.sub:SetPoint("TOP", f.head, "BOTTOM", 0, -6)

    f.toggle = KHF.CreateButton(f, L["QW_SHOW_ALL"], 100, 22)
    f.toggle:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -2)
    f.toggle:SetScript("OnClick", function()
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
    KHF.Theme.AttachScrollBar(f.scroll)
    f.scroll:HookScript("OnSizeChanged", function(self, w) f.child:SetWidth(w or self:GetWidth()) end)
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
