-- Kahoof UI/ThemeControls.lua: Forever-look controls (skin code, kept apart from logic)
-- Ported from BNB's Forever theme test window (BigNoteBox_Dev/ForeverThemeTest.lua)
-- and BNB's layered icon buttons (BigNoteBox/UI/IconButton.lua); the art is
-- BNB's, copied into Assets/Theme/Scrollbar and Assets/Theme/IconButton.
--
--   Theme.AttachScrollBar(sf)            the bronze minimal scroll bar right of a
--                                        plain ScrollFrame (Dukul, 2026-11-02: "should
--                                        be the bronze ones from forever"; ALL-38)
--   Theme.CreateSlider(parent, width, o) the bronze slider: the scroll bar art
--                                        turned a quarter left (Dukul: "Take over
--                                        the horizontal one too"); for Settings
--   Theme.CreateIconButton(parent, size, symbol, tip) a square plate + symbol
--                                        button (the main window's lock, ALL-39)

local _, KHF = ...
local L = KHF.L
local Theme = KHF.Theme

local ART = KHF.ADDON_PATH .. "Assets\\Theme\\"
local SB  = ART .. "Scrollbar\\"
local function T(p) return SB .. p end

--------------------------------------------------------------------------------
-- SCROLL BAR
-- Arrows top and bottom (+ "return to bottom"), a track (top, a stretched
-- middle, bottom) and a thumb whose middle art is shown 1:1 from its top,
-- never squeezed. Each arrow goes inactive and dimmed at its end (the art has
-- no disabled look); with nothing to scroll the whole bar hides. The bar sits right of sf, BAR_W (17) wide plus a 3 px
-- gap: callers leave 22 for it. Mouse wheel, arrows, a track click (a page
-- toward the cursor) and a thumb drag all scroll. Follows sf's own changes
-- (SetVerticalScroll from code, the content growing) through hooks.
--------------------------------------------------------------------------------
Theme.BAR_W = 17
local STEP = 30

function Theme.AttachScrollBar(sf)
    local bar = CreateFrame("Frame", nil, sf:GetParent())
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 3, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 3, 0)
    bar:SetWidth(Theme.BAR_W)

    local function Arrow(name, h)
        local b = CreateFrame("Button", nil, bar)
        b:SetSize(Theme.BAR_W, h)
        b:SetNormalTexture(T(name))
        b:SetPushedTexture(T(name .. "-down"))
        b:SetHighlightTexture(T(name .. "-over"), "BLEND")
        return b
    end
    local up   = Arrow("arrow-top", 11);            up:SetPoint("TOP")
    local ret  = Arrow("arrow-returntobottom", 15); ret:SetPoint("BOTTOM")
    local down = Arrow("arrow-bottom", 11);         down:SetPoint("BOTTOM", ret, "TOP", 0, 3)

    local track = CreateFrame("Frame", nil, bar)
    track:SetWidth(8)
    track:SetPoint("TOP", up, "BOTTOM", 0, -3)
    track:SetPoint("BOTTOM", down, "TOP", 0, 3)
    local tt = track:CreateTexture(nil, "BACKGROUND"); tt:SetSize(8, 8); tt:SetPoint("TOP")
    tt:SetTexture(T("track-top"))
    local tb = track:CreateTexture(nil, "BACKGROUND"); tb:SetSize(8, 8); tb:SetPoint("BOTTOM")
    tb:SetTexture(T("track-bottom"))
    local tm = track:CreateTexture(nil, "BACKGROUND")
    tm:SetPoint("TOPLEFT", tt, "BOTTOMLEFT"); tm:SetPoint("BOTTOMRIGHT", tb, "TOPRIGHT")
    tm:SetTexture(T("track-middle"))

    -- Thumb: top 8, bottom 36 over the middle; the middle is 515 px of art
    local BOT, MIDH = 36, 515
    local MINH = 8 + BOT
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(8)
    local th = thumb:CreateTexture(nil, "ARTWORK", nil, 1); th:SetSize(8, 8); th:SetPoint("TOP")
    local tbot = thumb:CreateTexture(nil, "ARTWORK", nil, 2); tbot:SetSize(8, BOT); tbot:SetPoint("BOTTOM")
    local tmid = thumb:CreateTexture(nil, "ARTWORK", nil, 0)
    tmid:SetPoint("TOPLEFT", th, "BOTTOMLEFT"); tmid:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 8)
    local function PaintThumb(state)
        local s = state and ("-" .. state) or ""
        th:SetTexture(T("thumb-top" .. s))
        tbot:SetTexture(T("thumb-bottom" .. s))
        tmid:SetTexture(T("thumb-middle" .. s))
    end
    PaintThumb(nil)

    local function Range() return sf:GetVerticalScrollRange() or 0 end
    local function Update()
        local range, trackH, vis = Range(), track:GetHeight(), sf:GetHeight()
        local pos = sf:GetVerticalScroll()
        -- Nothing to scroll: no bar at all (Dukul, 2026-11-02: "No need
        -- showing scrollbar if there is nothing to scroll"); the hooks on sf
        -- bring it back when the content grows
        -- bar.off: the owner turned scrolling off (the leaderboard's top ten)
        if bar.off or range <= 0 then bar:Hide(); return end
        bar:Show()
        local atBottom = range <= 0 or pos >= range - 0.5
        for _, a in ipairs({ { up, range > 0 and pos > 0.5 }, { down, not atBottom }, { ret, not atBottom } }) do
            a[1]:SetEnabled(a[2])
            a[1]:SetAlpha(a[2] and 1 or 0.35)
        end
        if range <= 0 or trackH <= 0 then thumb:Hide(); return end
        thumb:Show()
        local tH = math.max(MINH, math.floor(trackH * vis / (vis + range)))
        thumb:SetHeight(tH)
        local off = (trackH - tH) * pos / range
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -off)
        tmid:SetTexCoord(0, 1, 0, math.min(1, math.max(1, tH - 16) / MIDH))
    end
    local function SetScroll(v)
        sf:SetVerticalScroll(math.max(0, math.min(Range(), v)))
        Update()
    end

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, d)
        if not bar.off then SetScroll(sf:GetVerticalScroll() - d * STEP) end
    end)
    sf:HookScript("OnScrollRangeChanged", Update)
    sf:HookScript("OnVerticalScroll", Update)
    sf:HookScript("OnSizeChanged", Update)
    up:SetScript("OnClick", function() SetScroll(sf:GetVerticalScroll() - STEP) end)
    down:SetScript("OnClick", function() SetScroll(sf:GetVerticalScroll() + STEP) end)
    ret:SetScript("OnClick", function() SetScroll(Range()) end)

    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local page = sf:GetHeight() - 20
        SetScroll(sf:GetVerticalScroll() + (cy > (thumb:GetTop() or 0) and -page or page))
    end)

    thumb:SetScript("OnEnter", function(self) if not self._drag then PaintThumb("over") end end)
    thumb:SetScript("OnLeave", function(self) if not self._drag then PaintThumb(nil) end end)
    thumb:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        PaintThumb("down")
        local s = self:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        self._drag = { y = cy / s, pos = sf:GetVerticalScroll() }
        -- an OnUpdate only while the thumb is held
        self:SetScript("OnUpdate", function(me)
            local _, y = GetCursorPosition()
            local span = track:GetHeight() - me:GetHeight()
            if span > 0 then SetScroll(me._drag.pos + (me._drag.y - y / s) * Range() / span) end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self._drag = nil
        PaintThumb(self:IsMouseOver() and "over" or nil)
    end)
    thumb:HookScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self._drag = nil
    end)

    bar.Update = Update
    C_Timer.After(0, Update)
    return bar
end

--------------------------------------------------------------------------------
-- SLIDER (bronze): the scroll bar art turned a quarter left, so up / down
-- arrows become < / >; the knob is Dukul's bronze diamond (32 px art shown at
-- 22). Row 1: label, value, "(Default: x)", Reset (off at the default).
-- Row 2: < track >, the arrows inactive at the ends. Drag, click the track,
-- or the mouse wheel.
--   o = { label, min, max, step, value, default, onChange(v), format = "%.2f" }
-- Returns the frame (48 high); f:SetValue(v) sets it without onChange.
--------------------------------------------------------------------------------
local function Rot(tex)
    tex:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
end

function Theme.CreateSlider(parent, width, o)
    local fmt = o.format or "%.2f"
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 48)

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", 0, -4)
    lbl:SetText(o.label)
    local val = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
    local def = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    def:SetPoint("LEFT", val, "RIGHT", 6, 0)
    def:SetText(string.format(L["SLIDER_DEFAULT"], string.format(fmt, o.default)))
    local reset = KHF.CreateButton(f, L["RESET"], 77, 22)
    reset:SetPoint("TOPRIGHT")

    local function Arrow(name)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(11, 17)
        b:SetNormalTexture(T(name));             Rot(b:GetNormalTexture())
        b:SetPushedTexture(T(name .. "-down"));  Rot(b:GetPushedTexture())
        b:SetHighlightTexture(T(name .. "-over"), "BLEND"); Rot(b:GetHighlightTexture())
        return b
    end
    local left  = Arrow("arrow-top");    left:SetPoint("BOTTOMLEFT", 0, 0)
    local right = Arrow("arrow-bottom"); right:SetPoint("BOTTOMRIGHT", 0, 0)

    local track = CreateFrame("Frame", nil, f)
    track:SetHeight(8)
    track:SetPoint("LEFT", left, "RIGHT", 4, 0)
    track:SetPoint("RIGHT", right, "LEFT", -4, 0)
    local tl = track:CreateTexture(nil, "BACKGROUND"); tl:SetSize(8, 8); tl:SetPoint("LEFT")
    tl:SetTexture(T("track-top")); Rot(tl)
    local tr = track:CreateTexture(nil, "BACKGROUND"); tr:SetSize(8, 8); tr:SetPoint("RIGHT")
    tr:SetTexture(T("track-bottom")); Rot(tr)
    local tm = track:CreateTexture(nil, "BACKGROUND")
    tm:SetPoint("TOPLEFT", tl, "TOPRIGHT"); tm:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    tm:SetTexture(T("track-middle")); Rot(tm)

    local TW = 22
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetSize(TW, TW)
    local knob = thumb:CreateTexture(nil, "ARTWORK")
    knob:SetAllPoints()
    knob:SetTexture(T("slider-diamond"))
    local knobGlow = thumb:CreateTexture(nil, "OVERLAY")
    knobGlow:SetAllPoints()
    knobGlow:SetTexture(T("slider-diamond"))
    knobGlow:SetBlendMode("ADD")
    knobGlow:SetAlpha(0.35)
    local function PaintThumb(state)
        if state == "over" then knobGlow:Show() else knobGlow:Hide() end
        local c = (state == "down") and 0.75 or 1
        knob:SetVertexColor(c, c, c)
    end
    PaintThumb(nil)

    local value = o.value
    local function Snap(v)
        v = math.floor((v - o.min) / o.step + 0.5) * o.step + o.min
        return math.max(o.min, math.min(o.max, v))
    end
    local function Place()
        local span = track:GetWidth() - TW
        local x = span > 0 and span * (value - o.min) / (o.max - o.min) or 0
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", x, 0)
        val:SetText(string.format(fmt, value))
        local lo, hi = value > o.min + 1e-6, value < o.max - 1e-6
        left:SetEnabled(lo);  left:SetAlpha(lo and 1 or 0.35)
        right:SetEnabled(hi); right:SetAlpha(hi and 1 or 0.35)
        reset:SetEnabled(math.abs(value - o.default) >= 1e-6)
    end
    local function Set(v)
        v = Snap(v)
        if math.abs(v - value) < 1e-6 then Place(); return end
        value = v
        Place()
        o.onChange(v)
    end
    local function ValueAt(cx, grab)
        local span = track:GetWidth() - TW
        if span <= 0 then return value end
        return o.min + (cx - (track:GetLeft() or 0) - grab) / span * (o.max - o.min)
    end
    function f:SetValue(v)
        value = Snap(v)
        Place()
    end

    left:SetScript("OnClick", function() Set(value - o.step) end)
    right:SetScript("OnClick", function() Set(value + o.step) end)
    reset:SetScript("OnClick", function() Set(o.default) end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, d) Set(value + d * o.step) end)
    track:EnableMouse(true)
    track:SetScript("OnMouseDown", function(self)
        Set(ValueAt(GetCursorPosition() / self:GetEffectiveScale(), TW / 2))
    end)
    thumb:SetScript("OnEnter", function(self) if not self._drag then PaintThumb("over") end end)
    thumb:SetScript("OnLeave", function(self) if not self._drag then PaintThumb(nil) end end)
    thumb:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        PaintThumb("down")
        local sc = self:GetEffectiveScale()
        self._drag = GetCursorPosition() / sc - (self:GetLeft() or 0)
        self:SetScript("OnUpdate", function(me)
            Set(ValueAt(GetCursorPosition() / sc, me._drag))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self._drag = nil
        PaintThumb(self:IsMouseOver() and "over" or nil)
    end)
    -- Placed once the track has a width
    f:SetScript("OnSizeChanged", Place)
    f:SetScript("OnShow", function() C_Timer.After(0, Place) end)
    C_Timer.After(0, Place)
    return f
end

--------------------------------------------------------------------------------
-- ICON BUTTON (BNB's layers, the Forever border): background, plate (pressed
-- plate on press), hover glow, symbol (its own pressed drawing), border.
--   tip = function(self) -> title, line, extra   (shown on hover)
-- btn:SetSymbol(name) swaps the symbol (bt-<name>-normal / -press).
--------------------------------------------------------------------------------
local IB = ART .. "IconButton\\"

function Theme.CreateIconButton(parent, size, symbol, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local function Layer(sub, file)
        local t = b:CreateTexture(nil, "ARTWORK", nil, sub)
        t:SetAllPoints()
        if file then t:SetTexture(file) end
        return t
    end
    Layer(0, IB .. "bt-background")
    local plate = Layer(1, IB .. "bt-button")
    local hover = Layer(2, IB .. "bt-hover")
    hover:Hide()
    local sym = Layer(3)
    Layer(4, IB .. "bt-border-forever")

    local pressed = false
    local function Paint()
        plate:SetTexture(IB .. (pressed and "bt-button-pressed" or "bt-button"))
        sym:SetTexture(IB .. "bt-" .. b._symbol .. (pressed and "-press" or "-normal"))
    end
    function b:SetSymbol(s)
        self._symbol = s
        Paint()
    end
    local function ShowTip(self)
        if not tip then return end
        local title, line, extra = tip(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title, 1, 1, 1)
        if line then GameTooltip:AddLine(line, nil, nil, nil, true) end
        if extra then GameTooltip:AddLine(extra, 0.6, 0.6, 0.6, true) end
        GameTooltip:Show()
    end
    b.RefreshTip = function(self) if self:IsMouseOver() then ShowTip(self) end end
    b:SetScript("OnEnter", function(self) hover:Show(); ShowTip(self) end)
    b:SetScript("OnLeave", function() hover:Hide(); GameTooltip_Hide() end)
    b:SetScript("OnMouseDown", function() pressed = true; Paint() end)
    b:SetScript("OnMouseUp", function() pressed = false; Paint() end)
    b._symbol = symbol
    Paint()
    return b
end
