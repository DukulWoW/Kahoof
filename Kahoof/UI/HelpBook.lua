-- Kahoof UI/HelpBook.lua: the help book: Help, Features, Patch notes (ALL-73)
-- BNB's help book (BigNoteBox UI/HelpBook.lua) made Kahoof's own (Dukul,
-- 2026-11-04: "steal the help, features and patch notes window from BNB"):
-- the same three tabs, Contents on the left, the page on the right, Previous
-- / Next along the bottom. Not ported: BNB's rich-note renderer, skin mode
-- and the parchment kit; Kahoof's pages are plain text blocks (# heading,
-- - bullet, paragraphs) in our own window (KHF.CreateWindow), fixed size.
-- The content is in Data/HelpData.lua, FeatureListData.lua, PatchNotesData.lua.
-- Opened by the Help button right of the Settings tab and {cmd} guide.
--
--   KHF.HelpBook.Open(key, which)   which = "help" (default) / "features" /
--                                   "patches"; key = a topic key, a feature
--                                   header or a version (nil = the first page)
--   KHF.HelpBook.Toggle() / Close()

local _, KHF = ...
local L = KHF.L

local HB = {}
KHF.HelpBook = HB

local W, H = 780, 540
local TOC_W = 200
local TABS_TOP = 28   -- the tab row's top, under the title band (as the main window's)
local FOOT_H = 34
local ROW_H = 22
local BAR = 22
local INDENT = 16

local TABS = { { key = "help", label = "HB_TAB_HELP" }, { key = "features", label = "HB_TAB_FEATURES" },
               { key = "patches", label = "HB_TAB_PATCHES" } }
local LABEL_COLOR = { New = "66bb6a", Change = "f0b232", Fixed = "6aa8f0" }

local win, tabs, tocScroll, tocChild, pageScroll, page, prevBtn, nextBtn, pageNo
local tocRows, blocks, links = {}, {}, {}
local which, index = "help", 1

local function Fill(text)
    return (tostring(text or ""):gsub("{name}", KHF.NAME):gsub("{cmd}", "/" .. KHF.SLASH))
end

local function ClientOK(e)
    if type(e) ~= "table" then return true end
    if e.forever then return KHF.IsForever end
    if e.retail then return not KHF.IsForever end
    return true
end

--------------------------------------------------------------------------------
-- THE PAGES of the open tab: { { toc = text, key = key, draw = fn }, ... }
--------------------------------------------------------------------------------
local Draw   -- the page writer, below

local function Pages()
    local out = {}
    if which == "help" then
        for _, t in ipairs(KHF.HELP_TOPICS or {}) do
            out[#out + 1] = { toc = Fill(t.title), key = t.key, topic = t }
        end
    elseif which == "features" then
        for _, f in ipairs(KHF.FEATURE_LIST or {}) do
            out[#out + 1] = { toc = Fill(f.header), key = f.header, feature = f }
        end
    else
        for _, r in ipairs(KHF.PATCH_NOTES or {}) do
            out[#out + 1] = { toc = r.version, key = r.version, release = r }
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- THE PAGE: pooled blocks stacked top down
--------------------------------------------------------------------------------
local y, nBlocks, nLinks

local function Block(font, text, indent, gapAbove, color)
    nBlocks = nBlocks + 1
    local fs = blocks[nBlocks]
    if not fs then
        fs = page:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        blocks[nBlocks] = fs
    end
    fs:SetFontObject(_G[font] or GameFontHighlight)
    y = y - (gapAbove or 0)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", indent or 0, y)
    fs:SetWidth(page:GetWidth() - (indent or 0) - 4)
    fs:SetText(text)
    if color then fs:SetTextColor(color[1], color[2], color[3]) else fs:SetTextColor(1, 1, 1) end
    fs:Show()
    y = y - fs:GetStringHeight()
    return fs
end

local GOLD = { 1, 0.82, 0 }

-- A topic body: "# Heading", "- bullet", blank line = new paragraph
local function Body(text)
    local para = nil
    local function Flush()
        if para then Block("GameFontHighlight", para, 0, 8); para = nil end
    end
    for line in (Fill(text) .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line == "" then Flush()
        elseif line:sub(1, 2) == "# " then Flush(); Block("GameFontNormalLarge", line:sub(3), 0, 14, GOLD)
        elseif line:sub(1, 2) == "- " then
            Flush()
            Block("GameFontHighlight", "|cffffd100-|r  " .. line:sub(3), INDENT, 4)
        else para = para and (para .. " " .. line) or line end
    end
    Flush()
end

local function Link(text, onClick)
    nLinks = nLinks + 1
    local b = links[nLinks]
    if not b then
        b = CreateFrame("Button", nil, page)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("LEFT")
        b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(self) self.text:SetTextColor(0.4, 0.75, 1) end)
        links[nLinks] = b
    end
    b.text:SetText(text)
    b.text:SetTextColor(0.4, 0.75, 1)
    b:SetSize(b.text:GetStringWidth() + 4, 18)
    y = y - 4
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", page, "TOPLEFT", INDENT, y)
    b:SetScript("OnClick", onClick)
    b:Show()
    y = y - 18
end

local function TopicTitle(key)
    for _, t in ipairs(KHF.HELP_TOPICS or {}) do
        if t.key == key then return Fill(t.title) end
    end
end

Draw = function(p)
    y, nBlocks, nLinks = 0, 0, 0
    if p.topic then
        Block("GameFontNormalHuge", p.toc, 0, 0, GOLD)
        Body(p.topic.body)
    elseif p.feature then
        local f = p.feature
        Block("GameFontNormalHuge", p.toc, 0, 0, GOLD)
        Block("GameFontHighlight", Fill(f.blurb), 0, 10)
        for _, item in ipairs(f.items or {}) do
            Block("GameFontHighlight", "|cffffd100-|r  " .. Fill(item), INDENT, 4)
        end
        if f.help and #f.help > 0 then
            Block("GameFontNormal", L["HB_MORE"], 0, 16, GOLD)
            for _, key in ipairs(f.help) do
                local title = TopicTitle(key)
                if title then Link(title, function() HB.Open(key, "help") end) end
            end
        end
    elseif p.release then
        local r = p.release
        Block("GameFontNormalHuge", string.format(L["HB_VERSION"], r.version), 0, 0, GOLD)
        Block("GameFontDisable", r.date or L["HB_UNRELEASED"], 0, 4)
        for _, e in ipairs(r.entries or {}) do
            if ClientOK(e) then
                local text = Fill(type(e) == "table" and e[1] or e)
                local label, rest = text:match("^(%a+):%s*(.*)$")
                if label and LABEL_COLOR[label] then
                    text = "|cff" .. LABEL_COLOR[label] .. label .. ":|r " .. rest
                end
                Block("GameFontHighlight", "|cffffd100-|r  " .. text, INDENT, 8)
                end
        end
    end
    for i = nBlocks + 1, #blocks do blocks[i]:Hide() end
    for i = nLinks + 1, #links do links[i]:Hide() end
    page:SetHeight(math.max(1, -y + 10))
    pageScroll:SetVerticalScroll(0)
end

--------------------------------------------------------------------------------
-- CONTENTS AND PAGING
--------------------------------------------------------------------------------
local function TocRow(i)
    local r = tocRows[i]
    if not r then
        r = CreateFrame("Button", nil, tocChild)
        r:SetHeight(ROW_H)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 0.82, 0, 0.15)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", 6, 0)
        r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(self) HB.Show(self._i) end)
        tocRows[i] = r
    end
    return r
end

function HB.Show(i)
    local list = Pages()
    if #list == 0 then return end
    index = math.max(1, math.min(i or 1, #list))
    for n, p in ipairs(list) do
        local r = TocRow(n)
        r._i = n
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", tocChild, "TOPLEFT", 0, -(n - 1) * ROW_H)
        r:SetPoint("RIGHT", tocChild, "RIGHT")
        r.text:SetText(p.toc)
        local cur = n == index
        r.hl:SetShown(cur)
        if cur then r.text:SetTextColor(1, 0.82, 0) else r.text:SetTextColor(1, 1, 1) end
        r:Show()
    end
    for n = #list + 1, #tocRows do tocRows[n]:Hide() end
    tocChild:SetHeight(math.max(1, #list * ROW_H))
    Draw(list[index])
    prevBtn:SetEnabled(index > 1)
    nextBtn:SetEnabled(index < #list)
    pageNo:SetText(string.format(L["HB_PAGE"], index, #list))
end

local function SelectTab(key)
    which = key
    for i, t in ipairs(TABS) do
        if t.key == key then PanelTemplates_SelectTab(tabs[i]) else PanelTemplates_DeselectTab(tabs[i]) end
    end
end

--------------------------------------------------------------------------------
-- THE WINDOW
--------------------------------------------------------------------------------
local function Build()
    win = KHF.CreateWindow({ name = "KahoofHelpWindow", w = W, h = H, posKey = "help",
                             title = L["HB_TITLE"] })
    local c = win.content
    KHF.AddTitleLogo(win, "TOPLEFT", 16)

    tabs = {}
    for i, t in ipairs(TABS) do
        local tab = CreateFrame("Button", "KahoofHelpWindowTab" .. i, win, "PanelTopTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(L[t.label])
        pcall(PanelTemplates_TabResize, tab, 15, nil, 70)
        if i == 1 then tab:SetPoint("TOPLEFT", win, "TOPLEFT", KHF.Theme.PAD, -TABS_TOP)
        else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 4, 0) end
        tab:SetScript("OnClick", function() SelectTab(t.key); HB.Show(1) end)
        tabs[i] = tab
    end

    -- the area under the tabs: a dark shade, as the main window's pages
    local area = CreateFrame("Frame", nil, c)
    area:SetPoint("TOPLEFT", win, "TOPLEFT", KHF.Theme.PAD, -(TABS_TOP + tabs[1]:GetHeight() - 2))
    area:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, FOOT_H)
    local shade = area:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.3)
    KHF.Theme.AddGlow(area)

    local head = area:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("TOPLEFT", area, "TOPLEFT", 10, -10)
    head:SetText(L["HB_CONTENTS"])

    tocScroll = CreateFrame("ScrollFrame", nil, area)
    tocScroll:SetPoint("TOPLEFT", area, "TOPLEFT", 6, -30)
    tocScroll:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", 6, 8)
    tocScroll:SetWidth(TOC_W - BAR)
    tocChild = CreateFrame("Frame", nil, tocScroll)
    tocChild:SetSize(TOC_W - BAR, 1)
    tocScroll:SetScrollChild(tocChild)
    KHF.Theme.AttachScrollBar(tocScroll)

    local line = area:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.25)
    line:SetWidth(1)
    line:SetPoint("TOPLEFT", area, "TOPLEFT", TOC_W + 6, -8)
    line:SetPoint("BOTTOMLEFT", area, "BOTTOMLEFT", TOC_W + 6, 8)

    pageScroll = CreateFrame("ScrollFrame", nil, area)
    pageScroll:SetPoint("TOPLEFT", area, "TOPLEFT", TOC_W + 22, -12)
    pageScroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -(BAR + 8), 8)
    page = CreateFrame("Frame", nil, pageScroll)
    page:SetSize(W - 2 * KHF.Theme.PAD - TOC_W - 22 - BAR - 8, 1)
    pageScroll:SetScrollChild(page)
    KHF.Theme.AttachScrollBar(pageScroll)

    prevBtn = KHF.CreateButton(c, L["HB_PREV"], 110, 24)
    prevBtn:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", TOC_W + 22, 4)
    prevBtn:SetScript("OnClick", function() HB.Show(index - 1) end)
    nextBtn = KHF.CreateButton(c, L["HB_NEXT"], 110, 24)
    nextBtn:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -8, 4)
    nextBtn:SetScript("OnClick", function() HB.Show(index + 1) end)
    pageNo = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    pageNo:SetPoint("BOTTOM", c, "BOTTOMRIGHT", -((W - 2 * KHF.Theme.PAD - TOC_W - 22) / 2) - 4, 10)

    SelectTab("help")
end

function HB.Open(key, tab)
    if not win then Build() end
    SelectTab(tab or "help")
    local at = 1
    if key then
        for i, p in ipairs(Pages()) do
            if p.key == key then at = i end
        end
    end
    win:Show()
    win:Raise()
    HB.Show(at)
end

function HB.Close()
    if win then win:Hide() end
end

function HB.Toggle()
    if win and win:IsShown() then HB.Close() else HB.Open(nil, which) end
end

KHF.RegisterMessage("HelpBook", "WindowsReset", function()
    if win and win:IsShown() then KHF.RestoreWindowPos(win) end
end)
