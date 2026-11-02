-- Kahoof UI/QuizzesTab.lua: the My Quizzes tab of the main window (S3, S4)
-- The starter quiz and your own quizzes, one row each, with Edit, Duplicate
-- and Delete (Delete asks first; the starter quiz has Duplicate only), and New
-- quiz on top. New and Edit swap the list for the editor page
-- (UI/QuizEditor.lua) inside the same tab; leaving it brings the list back.
-- Also the login popup when the quizzes cannot be saved (Kahoof_DB missing, or
-- saved by a newer Kahoof: Core/Database.lua, InitQuizDB).
--
-- Rows are pooled (windows-widgets.md): their scripts read row._data, never a
-- captured value. Player text is drawn through KHF.EscapeText.

local _, KHF = ...
local L = KHF.L
local QuizStore = KHF.QuizStore

local ROW_H, ROW_GAP = 46, 4
local BAR_W = 22   -- room for the scroll bar right of the list

local page, list, newBtn, status, scroll, child, empty
local rows = {}

--------------------------------------------------------------------------------
-- POPUPS
--------------------------------------------------------------------------------
StaticPopupDialogs["KAHOOF_DELETE_QUIZ"] = {
    text = L["QUIZ_DELETE_CONFIRM"],
    button1 = L["QUIZ_DELETE"],
    button2 = L["CANCEL"],
    OnAccept = function(_, id)
        local ok, msg = QuizStore.Delete(id)
        if not ok then KHF:Print(msg) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["KAHOOF_DB_PROBLEM"] = {
    text = "%s",
    button1 = L["OK"],
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function OnLogin()
    KHF.UnregisterEvent("PLAYER_LOGIN", OnLogin)
    local state = KHF.quizDBState
    if state == "missing" then
        StaticPopup_Show("KAHOOF_DB_PROBLEM", L["DB_MISSING_POPUP"])
    elseif state == "newer" then
        StaticPopup_Show("KAHOOF_DB_PROBLEM", L["DB_NEWER_POPUP"])
    end
end
KHF.RegisterEvent("PLAYER_LOGIN", OnLogin)

--------------------------------------------------------------------------------
-- ROWS
--------------------------------------------------------------------------------
local function InfoLine(s)
    local count
    if s.count == 1 then count = L["QUIZ_COUNT_ONE"] else count = string.format(L["QUIZ_COUNT"], s.count) end
    local parts = { count }
    if s.tag then parts[#parts + 1] = KHF.EscapeText(s.tag) end
    if s.readOnly then
        parts[#parts + 1] = L["QUIZ_STARTER"]
    elseif s.author then
        parts[#parts + 1] = string.format(L["QUIZ_BY"], KHF.EscapeText(s.author))
    end
    return table.concat(parts, "   ")
end

local function OpenEditor(id)
    KHF.QuizEditor.Attach(page, function() list:Show() end)
    list:Hide()
    if not KHF.QuizEditor.Open(id) then list:Show() end
end

local function CreateRow()
    local r = CreateFrame("Frame", nil, child)
    r:SetHeight(ROW_H)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)

    r.del = KHF.CreateButton(r, L["QUIZ_DELETE"], 80, 24)
    r.del:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.del:SetScript("OnClick", function(self)
        local s = self:GetParent()._data
        if s then StaticPopup_Show("KAHOOF_DELETE_QUIZ", KHF.EscapeText(s.title), nil, s.id) end
    end)
    r.dup = KHF.CreateButton(r, L["QUIZ_DUPLICATE"], 96, 24)
    r.dup:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
    r.dup:SetScript("OnClick", function(self)
        local s = self:GetParent()._data
        if not s then return end
        local id, msg = QuizStore.Duplicate(s.id)
        if not id then KHF:Print(msg) end
    end)
    r.edit = KHF.CreateButton(r, L["QUIZ_EDIT"], 80, 24)
    r.edit:SetPoint("RIGHT", r.dup, "LEFT", -6, 0)
    r.edit:SetScript("OnClick", function(self)
        local s = self:GetParent()._data
        if s then OpenEditor(s.id) end
    end)

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("TOPLEFT", r, "TOPLEFT", 10, -8)
    r.title:SetPoint("RIGHT", r.edit, "LEFT", -10, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -5)
    r.info:SetPoint("RIGHT", r.edit, "LEFT", -10, 0)
    r.info:SetJustifyH("LEFT")
    r.info:SetWordWrap(false)
    return r
end

local function Refresh()
    if not page then return end
    local state = KHF.quizDBState
    local canSave = QuizStore.CanSave()
    newBtn:SetEnabled(canSave)

    scroll:ClearAllPoints()
    if state == "missing" or state == "newer" then
        status:SetText(state == "missing" and L["QUIZ_DB_MISSING_LINE"] or L["QUIZ_DB_NEWER_LINE"])
        status:Show()
        scroll:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -10)
    else
        status:Hide()
        scroll:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -10)
    end
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -(10 + BAR_W), 10)

    local list = QuizStore.List()
    for i, s in ipairs(list) do
        local r = rows[i]
        if not r then
            r = CreateRow()
            r:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * (ROW_H + ROW_GAP))
            r:SetPoint("RIGHT", child, "RIGHT")
            rows[i] = r
        end
        r._data = s
        r.title:SetText(KHF.EscapeText(s.title))
        r.info:SetText(InfoLine(s))
        r.dup:SetEnabled(canSave)
        r.edit:SetShown(not s.readOnly)
        r.edit:SetEnabled(canSave)
        r.del:SetShown(not s.readOnly)
        r.del:SetEnabled(canSave)
        r:Show()
    end
    for i = #list + 1, #rows do
        rows[i]._data = nil
        rows[i]:Hide()
    end

    -- the hint while you have no quiz of your own
    local h = #list * (ROW_H + ROW_GAP)
    local own = #list - ((list[1] and list[1].readOnly) and 1 or 0)
    if own == 0 and canSave then
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", child, "TOPLEFT", 10, -(h + 8))
        empty:SetPoint("RIGHT", child, "RIGHT", -10, 0)
        empty:Show()
        h = h + 40
    else
        empty:Hide()
    end
    child:SetHeight(math.max(1, h))
end

--------------------------------------------------------------------------------
-- THE PAGE (built by UI/MainWindow.lua on the window's first open)
--------------------------------------------------------------------------------
local function Build(p)
    page = p
    -- The list view; the editor (UI/QuizEditor.lua) takes its place when open
    list = CreateFrame("Frame", nil, p)
    list:SetAllPoints()

    newBtn = KHF.CreateButton(list, L["QUIZ_NEW"], 110, 24)
    newBtn:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -10)
    newBtn:SetScript("OnClick", function() OpenEditor(nil) end)

    status = list:CreateFontString(nil, "OVERLAY", "GameFontRed")
    status:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 0, -10)
    status:SetPoint("TOPRIGHT", list, "TOPRIGHT", -10, -44)
    status:SetJustifyH("LEFT")

    -- a plain ScrollFrame with the bronze Forever bar (UI/ThemeControls.lua, ALL-38)
    scroll = CreateFrame("ScrollFrame", nil, list)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    KHF.Theme.AttachScrollBar(scroll)
    scroll:HookScript("OnSizeChanged", function(self, w) child:SetWidth(w or self:GetWidth()) end)

    empty = child:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetJustifyH("LEFT")
    empty:SetText(L["QUIZ_NONE_YET"])

    -- OnShow: the tab shown with the list on it, or the list back from the editor
    list:HookScript("OnShow", Refresh)
    Refresh()
end
KHF.PageBuilders.TAB_QUIZZES = Build

KHF.RegisterMessage("QuizzesTab", "QuizzesChanged", function()
    if list and list:IsVisible() then Refresh() end
end)
