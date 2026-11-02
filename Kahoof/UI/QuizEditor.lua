-- Kahoof UI/QuizEditor.lua: the quiz editor, a page inside the My Quizzes tab (S4)
-- Decided with Dukul, 2026-11-02 (ALL-08 part 2): the question list on the
-- left, the shown question on the right ("List + one question"); nothing is
-- stored until Save ("Save + Cancel"); Add / Delete / Up / Down for questions;
-- the starter quiz is never opened here (Duplicate only).
--
--   top      back arrow, Title, Tag, Time (the quiz's), About
--   left     the questions (red = not finished, gray = empty), Add question
--   right    Question N of M, Up / Down / Delete, the question, four answers by
--            raid marker (click a marker = the correct answer), Time, Why
--   bottom   status line (author, Saved., or the problem), count, Cancel, Save
--
-- The boxes edit a draft (Core/QuizDraft.lua), never the stored quiz. Save
-- checks the draft through QuizStore.Clean; a problem is a red line and a jump
-- to its question and box. After a save the draft is read back from the store,
-- so the screen shows what was stored (trimmed, gaps closed, empty questions
-- gone). Leaving with unsaved changes asks first. ESC: a box with focus lets
-- go of it; then ESC goes back (UI/MainWindow.lua, PageEscHandlers). The red X
-- only hides the window: the draft stays until a reload.
--
--   Editor.Attach(page, onLeave)   build (once), hidden; onLeave shows the list
--   Editor.Open(id)                id = a saved quiz, nil = a new one -> ok
--   Editor.Leave()                 back / Cancel / ESC (asks when unsaved)
--   Editor.IsOpen()

local _, KHF = ...
local L = KHF.L
local QuizStore, QuizDraft = KHF.QuizStore, KHF.QuizDraft

local Editor = {}
KHF.QuizEditor = Editor

local SLOTS = QuizStore.MAX_ANSWERS
local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local MARKER_KEYS = { "MARKER_1", "MARKER_2", "MARKER_3", "MARKER_4" }   -- Star, Circle, Diamond, Triangle
local CHECK_TEX  ="Interface\\RaidFrame\\ReadyCheck-Ready"
local BACK_TEX   = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-"
local BOX_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Layout (UI units). MainWindow's MIN_H (500) is set so the right pane fits.
local LIST_W, ITEM_H, BAR_W = 180, 22, 22
local MID_Y    = -70   -- top of the list and the question pane
local BOTTOM_H = 40    -- the bottom bar
local ROW_H, ROW_STEP = 26, 28
local INDENT   = 36    -- answer boxes start here (marker column); Time and Why line up
local ROW1_Y, ROW2_Y = -20, -50   -- header rows, by their middle
-- The question pane, top of each part from the pane's top. Top-to-top
-- anchors only, so no box gets a second, clashing vertical anchor.
local Y_Q, Q_H     = -28, 64
local Y_A          = -100
local Y_TIME       = -220
local Y_WHY, WHY_H = -254, 50   -- bottom -304: MainWindow MIN_H 500 leaves it room

-- The limits come from the one field list (data.md)
local LIMIT = {}
for _, f in ipairs(QuizStore.QUIZ_FIELDS) do LIMIT[f.key] = f.max end
for _, f in ipairs(QuizStore.QUESTION_FIELDS) do LIMIT["q_" .. f.key] = f.max end

local ed                -- the editor frame
local onLeave           -- set by Attach: the list comes back
local draft, saved      -- the working copy, and the copy as opened / last saved
local sel = 1           -- the question shown
local loading           -- boxes being filled from the draft: not a change
local W = {}            -- widgets
local boxes = {}        -- every edit box, in Tab order
local items = {}        -- the question list's pooled buttons

local function Q() return draft and draft.questions[sel] end

--------------------------------------------------------------------------------
-- STATUS LINE: the author, or a message until the next change
--------------------------------------------------------------------------------
local function SetStatus(text, r, g, b)
    if text then
        W.status:SetText(text)
        W.status:SetTextColor(r or 1, g or 0.82, b or 0)
    else
        local author = draft and draft.author
        W.status:SetText(author and string.format(L["QUIZ_BY"], KHF.EscapeText(author)) or "")
        W.status:SetTextColor(0.6, 0.6, 0.6)
    end
end

--------------------------------------------------------------------------------
-- THE QUESTION LIST
--------------------------------------------------------------------------------
local function RefreshList()
    if not draft then return end
    local qs = draft.questions
    for i, q in ipairs(qs) do
        local b = items[i]
        b._index = i
        b.num:SetText(tostring(i))
        if QuizDraft.Filled(q.text) then
            b.text:SetText(KHF.EscapeText(QuizStore.Trim(q.text)))
        else
            b.text:SetText(L["ED_EMPTY_Q"])
        end
        if QuizDraft.IsBlank(q) then
            b.text:SetTextColor(0.5, 0.5, 0.5)
        elseif QuizDraft.IsComplete(q) then
            b.text:SetTextColor(1, 1, 1)
        else
            b.text:SetTextColor(1, 0.35, 0.35)
        end
        if i == sel then b.sel:Show() else b.sel:Hide() end
        b:Show()
    end
    for i = #qs + 1, #items do
        items[i]._index = nil
        items[i]:Hide()
    end
    W.listChild:SetHeight(math.max(1, #qs * ITEM_H))
    W.add:SetEnabled(#qs < QuizStore.MAX_QUESTIONS)
end

-- The shown question inside the list's view (next frame: the scroll range
-- follows the list's new height)
local function ScrollToSel()
    C_Timer.After(0, function()
        local sf = W.listScroll
        local top, h, cur = (sel - 1) * ITEM_H, sf:GetHeight(), sf:GetVerticalScroll()
        local v = cur
        if top < cur then v = top elseif top + ITEM_H > cur + h then v = top + ITEM_H - h end
        sf:SetVerticalScroll(math.max(0, math.min(v, sf:GetVerticalScrollRange())))
    end)
end

-- Every change to the draft: the list follows, an old message goes
local function Changed()
    RefreshList()
    SetStatus(nil)
end

--------------------------------------------------------------------------------
-- THE SHOWN QUESTION
--------------------------------------------------------------------------------
local function ShowMarkers()
    local q = Q()
    for s, a in ipairs(W.answers) do
        local on = q and q.correct == s
        a.marker.tex:SetDesaturated(not on)
        a.marker.tex:SetAlpha(on and 1 or 0.45)
        if on then a.check:Show() else a.check:Hide() end
    end
end

local function ShowQuestion()
    local q = Q()
    if not q then return end
    loading = true
    W.qText:SetText(q.text)
    for s, a in ipairs(W.answers) do a.box:SetText(q.answers[s]) end
    W.why:SetText(q.why)
    loading = false
    W.qHead:SetText(string.format(L["ED_QUESTION_N"], sel, #draft.questions))
    W.qUp:SetEnabled(sel > 1)
    W.qDown:SetEnabled(sel < #draft.questions)
    ShowMarkers()
    W.qTime:GenerateMenu()
    RefreshList()
end

local function Select(i)
    if not (draft and draft.questions[i]) then return end
    sel = i
    ShowQuestion()
    ScrollToSel()
end

local function ShowDraft()
    loading = true
    W.title:SetText(draft.title)
    W.tag:SetText(draft.tag)
    W.about:SetText(draft.about)
    loading = false
    W.time:GenerateMenu()
    sel = math.min(math.max(sel, 1), #draft.questions)
    ShowQuestion()
    ScrollToSel()
    SetStatus(nil)
end

--------------------------------------------------------------------------------
-- EDIT BOXES
-- Each box writes its text into the draft through onChange (only a real
-- change counts, so filling the boxes never marks the quiz as changed). Tab /
-- Shift-Tab and Enter walk the boxes; ESC lets go of the box. The multi-line
-- boxes (question, why) wrap but hold one line: a line break, typed or pasted,
-- becomes a space.
--------------------------------------------------------------------------------
local function UpdateHint(eb)
    if not eb._hint then return end
    if eb:GetText() == "" then eb._hint:Show() else eb._hint:Hide() end
end

local function UpdateCount(eb)
    if eb._max and eb:HasFocus() then
        W.count:SetText(string.format(L["ED_COUNT"], eb:GetNumLetters(), eb._max))
        W.count:Show()
    else
        W.count:Hide()
    end
end

local function FocusStep(eb, dir)
    local n = #boxes
    boxes[((eb._tab - 1 + dir) % n) + 1]:SetFocus()
end

local function SetupBox(eb, max, hint, hintFont, onChange)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(max)
    eb._max = max
    boxes[#boxes + 1] = eb
    eb._tab = #boxes
    if hint then
        local fs = eb:CreateFontString(nil, "ARTWORK", hintFont or "GameFontDisable")
        if eb._multi then fs:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, 0) else fs:SetPoint("LEFT", eb, "LEFT", 6, 0) end
        fs:SetText(hint)
        eb._hint = fs
    end
    -- SetScript first: HookScript after the last SetScript (CLAUDE.md)
    eb:SetScript("OnTabPressed", function(self) FocusStep(self, IsShiftKeyDown() and -1 or 1) end)
    eb:SetScript("OnEnterPressed", function(self)
        if self._tab == #boxes then self:ClearFocus() else FocusStep(self, 1) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        if self._multi and t:find("[\r\n]") then
            local pos = self:GetCursorPosition()
            local one = t:gsub("%s*[\r\n]+%s*", " ")
            self:SetText(one)   -- comes back here without the break
            self:SetCursorPosition(math.min(pos, #one))
            return
        end
        UpdateHint(self)
        UpdateCount(self)
        if not loading then onChange(t) end
    end)
    eb:HookScript("OnEditFocusGained", UpdateCount)
    eb:HookScript("OnEditFocusLost", UpdateCount)
end

local function Dark(f)
    f:SetBackdrop(BOX_BACKDROP)
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
end

-- One line: a plain EditBox on its own dark backdrop, never InputBoxTemplate
-- (BNB: two borders, and its outer ring does not take clicks)
local function InputBox(parent)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetHeight(24)
    Dark(eb)
    eb:SetFontObject("GameFontHighlight")
    eb:SetTextInsets(6, 6, 0, 0)
    return eb
end

-- A wrapping box in a dark frame; a click anywhere in the frame focuses it
local function MultiBox(parent, height, font)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetHeight(height)
    Dark(holder)
    holder:SetClipsChildren(true)
    local eb = CreateFrame("EditBox", nil, holder)
    eb._multi = true
    eb:SetMultiLine(true)
    eb:SetFontObject(font)
    eb:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -7)
    eb:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -8, -7)
    eb:SetHeight(height - 14)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() eb:SetFocus() end)
    return holder, eb
end

-- onChange makers: quiz field, question field, answer slot
local function Field(key)
    return function(t)
        if draft and draft[key] ~= t then draft[key] = t; Changed() end
    end
end
local function QField(key)
    return function(t)
        local q = Q()
        if q and q[key] ~= t then q[key] = t; Changed() end
    end
end
local function AField(s)
    return function(t)
        local q = Q()
        if q and q.answers[s] ~= t then q.answers[s] = t; Changed() end
    end
end

--------------------------------------------------------------------------------
-- SAVE, LEAVE
--------------------------------------------------------------------------------
-- A problem from QuizDraft.Check: the red line, then its question and box
local function ShowProblem(msg, path)
    local box
    if path.q then
        Select(path.q)
        msg = string.format(L["ED_ERR_Q"], path.q, msg)
        if path.a then box = W.answers[path.a].box
        elseif path.field == "text" then box = W.qText
        elseif path.field == "why" then box = W.why end
    elseif path.field == "questions" then
        Select(1)
        box = W.qText
    elseif path.field == "title" or path.field == "tag" or path.field == "about" then
        box = W[path.field]
    end
    if box then box:SetFocus() end
    SetStatus(msg, 1, 0.3, 0.3)
end

local function Save()
    if not draft then return end
    local raw, msg, path = QuizDraft.Check(draft)
    if not raw then ShowProblem(msg, path or {}); return end
    local id, err
    if draft.id then id, err = QuizStore.Save(raw) else id, err = QuizStore.Create(raw) end
    if not id then
        SetStatus(string.format(L["ED_NOT_SAVED"], tostring(err)), 1, 0.3, 0.3)
        return
    end
    local quiz = QuizStore.Get(id)
    if not quiz then return end
    draft = QuizDraft.FromQuiz(quiz)
    saved = KHF.DeepCopy(draft)
    ShowDraft()
    SetStatus(L["ED_SAVED"], 0.3, 1, 0.3)
end

local function Close()
    draft, saved = nil, nil
    if ed then ed:Hide() end
    if onLeave then onLeave() end
end

StaticPopupDialogs["KAHOOF_LEAVE_EDITOR"] = {
    text = L["ED_LEAVE_CONFIRM"],
    button1 = L["ED_DISCARD"],
    button2 = L["ED_KEEP_EDITING"],
    OnAccept = function() Close() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Editor.Leave()
    if draft and saved and not QuizDraft.Same(draft, saved) then
        StaticPopup_Show("KAHOOF_LEAVE_EDITOR")
    else
        Close()
    end
end

function Editor.IsOpen()
    return ed ~= nil and ed:IsShown()
end

--------------------------------------------------------------------------------
-- BUILDERS
--------------------------------------------------------------------------------
local function Tooltip(frame, title, line)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 1, 1)
        if line then GameTooltip:AddLine(line, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Label(text)
    local fs = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function TimeLabel(t) return string.format(L["ED_TIME_N"], t) end

-- Top: back arrow, Title, Tag, Time; About under them
local function BuildHeader()
    local back = CreateFrame("Button", nil, ed)
    back:SetSize(26, 26)
    back:SetPoint("LEFT", ed, "TOPLEFT", 6, ROW1_Y)
    back:SetNormalTexture(BACK_TEX .. "Up")
    back:SetPushedTexture(BACK_TEX .. "Down")
    back:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    back:SetScript("OnClick", function() Editor.Leave() end)
    Tooltip(back, L["ED_BACK"])

    W.time = CreateFrame("DropdownButton", nil, ed, "WowStyle1DropdownTemplate")
    W.time:SetWidth(84)
    W.time:SetPoint("RIGHT", ed, "TOPRIGHT", -10, ROW1_Y)
    -- SetupMenu runs this at once: draft may be nil here
    W.time:SetupMenu(function(_, root)
        for _, t in ipairs(QuizStore.TIMES) do
            root:CreateRadio(TimeLabel(t),
                function() return draft ~= nil and draft.time == t end,
                function()
                    if not draft or draft.time == t then return end
                    draft.time = t
                    Changed()
                    W.qTime:GenerateMenu()   -- its "Quiz time (N s)" line
                end)
        end
    end)
    local timeLabel = Label(L["ED_TIME"])
    timeLabel:SetPoint("RIGHT", W.time, "LEFT", -8, 0)

    W.tag = InputBox(ed)
    W.tag:SetWidth(110)
    W.tag:SetPoint("RIGHT", timeLabel, "LEFT", -16, 0)
    local tagLabel = Label(L["ED_TAG"])
    tagLabel:SetPoint("RIGHT", W.tag, "LEFT", -10, 0)

    local titleLabel = Label(L["ED_TITLE"])
    titleLabel:SetPoint("LEFT", back, "RIGHT", 8, 0)
    W.title = InputBox(ed)
    W.title:SetPoint("LEFT", titleLabel, "RIGHT", 12, 0)
    W.title:SetPoint("RIGHT", tagLabel, "LEFT", -16, 0)

    W.about = InputBox(ed)
    W.about:SetPoint("LEFT", W.title, "LEFT", 0, ROW2_Y - ROW1_Y)
    W.about:SetPoint("RIGHT", ed, "TOPRIGHT", -10, ROW2_Y)
    local aboutLabel = Label(L["ED_ABOUT"])
    aboutLabel:SetPoint("RIGHT", W.about, "LEFT", -12, 0)

    -- Tab order: title, tag, about
    SetupBox(W.title, LIMIT.title, nil, nil, Field("title"))
    SetupBox(W.tag, LIMIT.tag, nil, nil, Field("tag"))
    SetupBox(W.about, LIMIT.about, nil, nil, Field("about"))
end

-- Left: the questions and Add question
local function BuildList()
    local pane = CreateFrame("Frame", nil, ed)
    pane:SetPoint("TOPLEFT", ed, "TOPLEFT", 10, MID_Y)
    pane:SetPoint("BOTTOMLEFT", ed, "BOTTOMLEFT", 10, BOTTOM_H)
    pane:SetWidth(LIST_W)
    W.listPane = pane

    W.add = KHF.CreateButton(pane, L["ED_ADD_Q"], LIST_W, 24)
    W.add:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 0)
    W.add:SetScript("OnClick", function()
        if not draft then return end
        local i = QuizDraft.AddQuestion(draft, sel)
        if not i then return end
        Changed()
        Select(i)
        W.qText:SetFocus()
    end)

    local sf = CreateFrame("ScrollFrame", nil, pane, "ScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", W.add, "TOPRIGHT", -BAR_W, 8)
    local bg = sf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.3)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    sf:HookScript("OnSizeChanged", function(self, w) child:SetWidth(w or self:GetWidth()) end)
    W.listScroll, W.listChild = sf, child

    -- Pooled (windows-widgets.md): built once for the most a quiz can hold,
    -- the click reads the button's current index
    for i = 1, QuizStore.MAX_QUESTIONS do
        local b = CreateFrame("Button", nil, child)
        b:SetHeight(ITEM_H)
        b:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ITEM_H)
        b:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(i - 1) * ITEM_H)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 0.82, 0, 0.25)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b.num = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.num:SetPoint("LEFT", b, "LEFT", 2, 0)
        b.num:SetWidth(20)
        b.num:SetJustifyH("RIGHT")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", b.num, "RIGHT", 6, 0)
        b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        b.text:SetJustifyH("LEFT")
        b.text:SetWordWrap(false)
        b:SetScript("OnClick", function(self) if self._index then Select(self._index) end end)
        b:Hide()
        items[i] = b
    end
end

-- Up / Down / Delete over the shown question
local function BuildQuestionTools(p)
    W.qDel = KHF.CreateButton(p, L["QUIZ_DELETE"], 72, 22)
    W.qDel:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    W.qDel:SetScript("OnClick", function()
        if not draft then return end
        sel = QuizDraft.DeleteQuestion(draft, sel)   -- Cancel brings it back
        Changed()
        Select(sel)
    end)
    W.qDown = KHF.CreateButton(p, L["ED_DOWN"], 66, 22)
    W.qDown:SetPoint("RIGHT", W.qDel, "LEFT", -4, 0)
    W.qUp = KHF.CreateButton(p, L["ED_UP"], 66, 22)
    W.qUp:SetPoint("RIGHT", W.qDown, "LEFT", -4, 0)
    local function Move(delta)
        if not draft then return end
        local j = QuizDraft.MoveQuestion(draft, sel, delta)
        if not j then return end
        Changed()
        Select(j)
    end
    W.qUp:SetScript("OnClick", function() Move(-1) end)
    W.qDown:SetScript("OnClick", function() Move(1) end)

    W.qHead = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    W.qHead:SetPoint("LEFT", p, "TOPLEFT", 0, -11)
    W.qHead:SetPoint("RIGHT", W.qUp, "LEFT", -8, 0)
    W.qHead:SetJustifyH("LEFT")
    W.qHead:SetWordWrap(false)
end

-- One answer row: the marker (click = correct), the box, the check
local function BuildAnswer(p, s)
    local row = CreateFrame("Frame", nil, p)
    row:SetHeight(ROW_H)
    local y = Y_A - (s - 1) * ROW_STEP
    row:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, y)

    local m = CreateFrame("Button", nil, row)
    m:SetSize(24, 24)
    m:SetPoint("LEFT", row, "LEFT", 2, 0)
    m.tex = m:CreateTexture(nil, "ARTWORK")
    m.tex:SetAllPoints()
    m.tex:SetTexture(MARKER_TEX .. s)
    m:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    m._slot = s
    m:SetScript("OnClick", function(self)
        local q = Q()
        if not q or q.correct == self._slot then return end
        q.correct = self._slot
        Changed()
        ShowMarkers()
    end)
    Tooltip(m, function(self) return L[MARKER_KEYS[self._slot]] end, L["ED_MARKER_TIP"])

    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(18, 18)
    check:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    check:SetTexture(CHECK_TEX)

    local eb = InputBox(row)
    eb:SetPoint("LEFT", row, "LEFT", INDENT, 0)
    eb:SetPoint("RIGHT", check, "LEFT", -8, 0)
    return { row = row, marker = m, box = eb, check = check }
end

-- Right: the shown question
local function BuildQuestionPane()
    local p = CreateFrame("Frame", nil, ed)
    p:SetPoint("TOPLEFT", W.listPane, "TOPRIGHT", 14, 0)
    p:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -10, BOTTOM_H)
    BuildQuestionTools(p)

    local qHolder
    qHolder, W.qText = MultiBox(p, Q_H, "GameFontHighlight")
    qHolder:SetPoint("TOPLEFT", p, "TOPLEFT", 0, Y_Q)
    qHolder:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, Y_Q)

    W.answers = {}
    for s = 1, SLOTS do W.answers[s] = BuildAnswer(p, s) end

    W.qTime = CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")
    W.qTime:SetWidth(170)
    W.qTime:SetPoint("TOPLEFT", p, "TOPLEFT", INDENT, Y_TIME)
    -- SetupMenu runs this at once: draft may be nil here
    W.qTime:SetupMenu(function(_, root)
        local function Pick(t)
            local q = Q()
            if not q or q.time == t then return end
            q.time = t
            Changed()
        end
        root:CreateRadio(string.format(L["ED_TIME_QUIZ"], draft and draft.time or QuizStore.DEFAULT_TIME),
            function() local q = Q(); return q ~= nil and q.time == nil end,
            function() Pick(nil) end)
        for _, t in ipairs(QuizStore.TIMES) do
            root:CreateRadio(TimeLabel(t),
                function() local q = Q(); return q ~= nil and q.time == t end,
                function() Pick(t) end)
        end
    end)
    local timeLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 0, Y_TIME - 7)
    timeLabel:SetText(L["ED_TIME"])

    local whyHolder
    whyHolder, W.why = MultiBox(p, WHY_H, "GameFontHighlightSmall")
    whyHolder:SetPoint("TOPLEFT", p, "TOPLEFT", INDENT, Y_WHY)
    whyHolder:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, Y_WHY)
    local whyLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    whyLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 0, Y_WHY - 8)
    whyLabel:SetText(L["ED_WHY"])

    -- Tab order after the header: question, answers 1-4, why
    SetupBox(W.qText, LIMIT.q_text, L["ED_Q_HINT"], nil, QField("text"))
    for s = 1, SLOTS do
        local hint = (s <= QuizStore.MIN_ANSWERS) and L["ED_ANSWER_HINT"] or L["ED_ANSWER_OPT_HINT"]
        SetupBox(W.answers[s].box, LIMIT.q_answers, hint, nil, AField(s))
    end
    SetupBox(W.why, LIMIT.q_why, L["ED_WHY_HINT"], "GameFontDisableSmall", QField("why"))
end

-- Bottom: status, count, Cancel, Save
local function BuildBottom()
    W.save = KHF.CreateButton(ed, L["ED_SAVE"], 90, 24)
    W.save:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -10, 8)
    W.save:SetScript("OnClick", Save)
    W.cancel = KHF.CreateButton(ed, L["CANCEL"], 90, 24)
    W.cancel:SetPoint("RIGHT", W.save, "LEFT", -6, 0)
    W.cancel:SetScript("OnClick", function() Editor.Leave() end)

    W.count = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.count:SetPoint("RIGHT", W.cancel, "LEFT", -12, 0)
    W.count:Hide()
    W.status = ed:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    W.status:SetPoint("LEFT", ed, "BOTTOMLEFT", 10, 20)
    W.status:SetPoint("RIGHT", W.count, "LEFT", -10, 0)
    W.status:SetJustifyH("LEFT")
    W.status:SetWordWrap(false)
end

function Editor.Attach(page, leaveFn)
    if ed then return ed end
    onLeave = leaveFn
    ed = CreateFrame("Frame", nil, page)
    ed:SetAllPoints()
    ed:Hide()
    BuildHeader()
    BuildList()
    BuildQuestionPane()
    BuildBottom()
    -- A hidden box must not keep the keyboard (window closed, tab changed)
    ed:SetScript("OnHide", function()
        for _, eb in ipairs(boxes) do eb:ClearFocus() end
    end)
    return ed
end

function Editor.Open(id)
    if not ed then return false end
    local ok, why = QuizStore.CanSave()
    if not ok then KHF:Print(why); return false end
    if id ~= nil then
        if QuizStore.IsReadOnly(id) then KHF:Print(L["QZ_ERR_READ_ONLY"]); return false end
        local quiz = QuizStore.Get(id)
        if not quiz then KHF:Print(L["QZ_ERR_NOT_FOUND"]); return false end
        draft = QuizDraft.FromQuiz(quiz)
    else
        draft = QuizDraft.New(KHF.GetSetting("newQuizTime"))
        draft.author = KHF.UnitKey("player")
    end
    saved = KHF.DeepCopy(draft)
    sel = 1
    W.listScroll:SetVerticalScroll(0)
    ed:Show()
    ShowDraft()
    if id == nil then W.title:SetFocus() end
    return true
end

-- ESC on the main window while the editor shows: the leave popup first, then back
KHF.PageEscHandlers.TAB_QUIZZES = function()
    if not (ed and ed:IsVisible()) then return false end
    if StaticPopup_Visible("KAHOOF_LEAVE_EDITOR") then
        StaticPopup_Hide("KAHOOF_LEAVE_EDITOR")
    else
        Editor.Leave()
    end
    return true
end
