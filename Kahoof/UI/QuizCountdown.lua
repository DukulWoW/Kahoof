-- Kahoof UI/QuizCountdown.lua: the quiz window's skin pieces: countdown, bars, buttons, art (S5b polish)
-- Skin helpers for UI/QuizPlay.lua, kept apart from its logic:
--   QuizUI.CreateBigNumber(parent)   the game's raid countdown numbers (the
--                                    pull-timer digits, BigTimerNumbers), with
--                                    the pop each second (ALL-55)
--   QuizUI.Shake(fs, x, y, left)     the seconds shake: gently from 10, hard
--                                    from 5 (ALL-54); fs keeps its TOPRIGHT
--                                    anchor at (x, y) plus the shake
--   QuizUI.CreateClockBar(parent)    the time bar: gold border, black back,
--                                    a fill green -> yellow -> red as time runs
--                                    out, a spark at its moving end (ALL-56)
--   QuizUI.CreateReadyArt(box)       the Get ready bar with the text inside (ALL-57)
--   QuizUI.SkinAnswer(b, i)          Dukul's answer button art on button b, color i
--   QuizUI.PaintAnswer(b, look)      its look: open / ticked / dim / right / wrong / faded
--   QuizUI.ART                       our own copies of the game art
--
-- The art is OURS (Kahoof/Assets/Quiz, made by _work/tools/quiz-art.py from
-- Dukul's wow.export folder): it is Forever art that Retail lacks (Dukul,
-- 2026-11-02: "we need to place them in our assets as TGA files"), so both
-- clients draw the same files.

local _, KHF = ...
local QuizUI = KHF.QuizUI

--------------------------------------------------------------------------------
-- THE RAID COUNTDOWN NUMBERS: the same sheet and layout the game's pull timer
-- uses (TimerTracker's "BigGold" set: 256 x 170 cells, four to a row on a
-- 1024 x 512 sheet; the half width of each digit's ink, as a part of 128).
-- Drawn at half size.
--------------------------------------------------------------------------------
local NUM_TEX = "Interface\\Timer\\BigTimerNumbers"
local CELL_W, CELL_H, SHEET_W, SHEET_H = 256, 170, 1024, 512
local HALF = { [0] = 35 / 128, 14 / 128, 33 / 128, 32 / 128, 36 / 128,
               32 / 128, 33 / 128, 29 / 128, 31 / 128, 31 / 128 }
local DRAW_W, DRAW_H = CELL_W / 2, CELL_H / 2

local function SetDigit(tex, d, cx)
    local col, row = d % 4, math.floor(d / 4)
    local l, t = col * CELL_W / SHEET_W, row * CELL_H / SHEET_H
    tex:SetTexCoord(l, l + CELL_W / SHEET_W, t, t + CELL_H / SHEET_H)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", tex:GetParent(), "CENTER", cx, 0)
    tex:Show()
end

function QuizUI.CreateBigNumber(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(DRAW_W * 2, DRAW_H)
    f.digits = {}
    for i = 1, 2 do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetTexture(NUM_TEX)
        t:SetSize(DRAW_W, DRAW_H)
        f.digits[i] = t
    end
    -- each new number pops in, as the pull timer's do
    local ag = f:CreateAnimationGroup()
    local sc = ag:CreateAnimation("Scale")
    sc:SetScaleFrom(1.6, 1.6)
    sc:SetScaleTo(1, 1)
    sc:SetDuration(0.25)
    sc:SetOrigin("CENTER", 0, 0)
    local al = ag:CreateAnimation("Alpha")
    al:SetFromAlpha(0)
    al:SetToAlpha(1)
    al:SetDuration(0.15)
    f.anim = ag

    -- 0-99; the same number again changes nothing
    function f:SetNumber(n)
        n = math.max(0, math.min(99, math.floor(n)))
        if n == self.n then return end
        self.n = n
        local px = DRAW_W / 2   -- HALF is a part of half a cell
        if n < 10 then
            SetDigit(self.digits[1], n, 0)
            self.digits[2]:Hide()
        else
            -- two digits side by side, their ink touching, centered together
            local a, b = math.floor(n / 10), n % 10
            local ha, hb = HALF[a] * px, HALF[b] * px
            SetDigit(self.digits[1], a, -hb)
            SetDigit(self.digits[2], b, ha)
        end
        self.anim:Stop()
        if not KHF.GetSetting("reduceMotion") then self.anim:Play() end
    end

    return f
end

--------------------------------------------------------------------------------
-- THE SHAKE (ALL-54; Dukul: "Start gently shaking the countdown number when it
-- gets to 10, then violently shaking at 5"). Called every frame while the
-- clock runs; no shake above 10.
--------------------------------------------------------------------------------
function QuizUI.Shake(fs, x, y, left)
    if KHF.GetSetting("reduceMotion") then left = 99 end   -- in place (ALL-23)
    local dx, dy = 0, 0
    if left <= 5 then
        dx, dy = math.random(-40, 40) / 10, math.random(-30, 30) / 10
    elseif left <= 10 then
        local t = GetTime()
        dx, dy = math.sin(t * 31) * 1.2, math.cos(t * 23) * 0.8
    end
    fs:SetPoint("TOPRIGHT", fs:GetParent(), "TOPRIGHT", x + dx, y + dy)
end

--------------------------------------------------------------------------------
-- OUR ART (Kahoof/Assets/Quiz)
--------------------------------------------------------------------------------
local ART = KHF.ADDON_PATH .. "Assets\\Quiz\\"
QuizUI.ART = {
    line    = ART .. "question-line",   -- 708 x 56, a soft shadow band (ALL-58)
    ready   = ART .. "ready-bar",       -- 536 x 56, the damage meter header bar (N1)
    divider = ART .. "divider-gold",    -- 512 x 32, BNB's gold-plain divider
    gold    = ART .. "Rank\\gold",
    silver  = ART .. "Rank\\silver",
    bronze  = ART .. "Rank\\bronze",
}
local BAR = ART .. "Bar\\"

--------------------------------------------------------------------------------
-- THE TIME BAR (Dukul, 2026-11-02: "go from green, to yellow, red as it counts
-- down", the part that goes away marked; then "Maybe we can use this for the
-- countdown bar? interface/framegeneral/uiframebars.blp ... it contains all the
-- elements"). The frame's height h scales the 31 px art: the gold border
-- around it all, the black back in its 18 px opening, the white fill inside,
-- tinted, and the spark riding the fill's right end. The color follows the
-- time left in every phase (N3: also during Get ready and the read time).
--------------------------------------------------------------------------------
local GREEN  = { 0.20, 0.90, 0.20 }
local YELLOW = { 1.00, 0.85, 0.10 }
local RED    = { 1.00, 0.15, 0.10 }

local function Mix(a, b, k)
    return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
end

-- three slices (left cap, stretched middle, right cap) across f, at scale k
local function Slices(f, layer, name, capW, h, k, inset)
    local l = f:CreateTexture(nil, layer)
    l:SetTexture(BAR .. name .. "-left")
    l:SetSize(capW * k, h * k)
    l:SetPoint("LEFT", f, "LEFT", -inset, 0)
    local r = f:CreateTexture(nil, layer)
    r:SetTexture(BAR .. name .. "-right")
    r:SetSize(capW * k, h * k)
    r:SetPoint("RIGHT", f, "RIGHT", inset, 0)
    local c = f:CreateTexture(nil, layer)
    c:SetTexture(BAR .. name .. "-center")
    c:SetPoint("TOPLEFT", l, "TOPRIGHT")
    c:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    return { l, c, r }
end

-- h: the whole bar's height (the border's); the fill is ~55 % of it
function QuizUI.CreateClockBar(parent, h)
    local k = h / 31
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(h)

    -- the fill: inside the border's opening (7 px in at the ends, 6.5 top and bottom)
    local bar = CreateFrame("StatusBar", nil, holder)
    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 7 * k, -7 * k)
    bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -7 * k, 7 * k)
    bar:SetMinMaxValues(0, 1)
    bar:SetStatusBarTexture(BAR .. "fill")

    -- the black back under the fill, the gold border over everything
    Slices(bar, "BACKGROUND", "bg", 29, 18, k, 0.5 * k)
    local top = CreateFrame("Frame", nil, holder)
    top:SetAllPoints()
    top:SetFrameLevel(bar:GetFrameLevel() + 2)
    Slices(top, "ARTWORK", "border", 35, 31, k, 0)

    -- the cast bar's glow streaks over the fill (Dukul, 2026-11-02), tinted
    -- like it; cropped with it, never squeezed
    local glow = bar:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(BAR .. "lineglow")
    glow:SetBlendMode("ADD")
    glow:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, -2 * k)

    -- the spark at the moving end
    local spark = top:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(BAR .. "spark")
    spark:SetBlendMode("ADD")
    spark:SetSize(8 * k * 1.4, 31 * k)
    local fill = bar:GetStatusBarTexture()
    spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    glow:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 2 * k)

    -- frac: the part of the time left (1 -> 0)
    function holder:SetFraction(frac)
        frac = math.max(0, math.min(1, frac))
        bar:SetValue(frac)
        local r, g, b
        if frac > 0.5 then
            r, g, b = Mix(YELLOW, GREEN, (frac - 0.5) * 2)
        else
            r, g, b = Mix(RED, YELLOW, frac * 2)
        end
        bar:SetStatusBarColor(r, g, b)
        glow:SetVertexColor(r, g, b)
        glow:SetTexCoord(0, math.max(frac, 0.001), 0, 1)
        glow:SetShown(frac > 0)
        spark:SetShown(frac > 0 and frac < 1)
    end
    holder:SetFraction(1)
    return holder
end

--------------------------------------------------------------------------------
-- GET READY (N1, Dukul: "Too small ... We do have space on the first screen,
-- so we could move and scale things. And let's try changing over to ...
-- "ui-damagemeters-header-bar-2x" instead"). The bar at full width, the text
-- big and inside it.
--------------------------------------------------------------------------------
function QuizUI.CreateReadyArt(box)
    local art = { box = box }
    art.bar = box:CreateTexture(nil, "ARTWORK")
    art.bar:SetTexture(QuizUI.ART.ready)
    art.bar:SetAllPoints()
    art.text = box:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    art.text:SetPoint("CENTER", box, "CENTER", 0, 1)
    local huge = _G.GameFontNormalHuge3 or _G.GameFontNormalHuge2
    if huge then art.text:SetFontObject(huge) end
    art.text:SetTextColor(1, 1, 1)
    return art
end

--------------------------------------------------------------------------------
-- ANSWER BUTTONS: Dukul's own art (Kahoof/Assets/Buttons/answer-*, 2026-11-02:
-- "Shadow at bottom -> normal / press / disabled -> hover -> frame. Hover is a
-- white glow that needs to get the hue of the button color. Disabled is just
-- normal desaturated."). One fill color per marker: Star yellow, Circle
-- orange, Diamond purple, Triangle green. Each layer is 3-sliced: the ends keep
-- their shape at any width, the middle stretches (the slots are about 4:1, the
-- art 2:1). Cut by proportion, so the 512 x 256 versions drop in unchanged.
--------------------------------------------------------------------------------
local BTN = KHF.ADDON_PATH .. "Assets\\Buttons\\answer-"
local BTN_COLOR = { "yellow", "orange", "purple", "green" }
local HUE = {   -- the hover glow's tint, per button
    { 1.00, 0.85, 0.25 },
    { 1.00, 0.55, 0.15 },
    { 0.78, 0.40, 1.00 },
    { 0.40, 1.00, 0.35 },
}
local CAP   = 48 / 256   -- each end cap, as a part of the art's width
local CAP_K = 48 / 128   -- the cap's width as a part of the button's height
local FRAME_RIGHT = { 0.45, 1.00, 0.45 }   -- the frame tinted at the reveal
local FRAME_WRONG = { 1.00, 0.35, 0.35 }

-- three textures on one layer: left cap, stretched middle, right cap
local function Slice3(b, layer, sub)
    local s = {}
    for n = 1, 3 do s[n] = b:CreateTexture(nil, layer, nil, sub) end
    s[1]:SetPoint("TOPLEFT"); s[1]:SetPoint("BOTTOMLEFT")
    s[3]:SetPoint("TOPRIGHT"); s[3]:SetPoint("BOTTOMRIGHT")
    s[2]:SetPoint("TOPLEFT", s[1], "TOPRIGHT")
    s[2]:SetPoint("BOTTOMRIGHT", s[3], "BOTTOMLEFT")
    return s
end

local function SetFile(s, file)
    for n = 1, 3 do s[n]:SetTexture(file) end
    s[1]:SetTexCoord(0, CAP, 0, 1)
    s[2]:SetTexCoord(CAP, 1 - CAP, 0, 1)
    s[3]:SetTexCoord(1 - CAP, 1, 0, 1)
end

local function Each(s, method, ...)
    for n = 1, 3 do s[n][method](s[n], ...) end
end

local function ShowFill(b, press)
    SetFile(b._fill, BTN .. BTN_COLOR[b._i] .. (press and "-press" or "-normal"))
    Each(b._fill, "SetDesaturated", b._desat or false)
end

function QuizUI.SkinAnswer(b, i)
    b._i = i
    b._shadow = Slice3(b, "BACKGROUND", -1)
    b._fill   = Slice3(b, "BACKGROUND", 2)
    b._hover  = Slice3(b, "BORDER", 0)
    b._frame  = Slice3(b, "ARTWORK", -2)   -- under the marker and the text (ARTWORK 0 / OVERLAY)
    SetFile(b._shadow, BTN .. "shadow")
    SetFile(b._hover, BTN .. "hover")
    SetFile(b._frame, BTN .. "frame")
    Each(b._hover, "SetBlendMode", "ADD")
    Each(b._hover, "SetVertexColor", HUE[i][1], HUE[i][2], HUE[i][3])
    Each(b._hover, "Hide")
    ShowFill(b, false)

    -- the caps keep the art's shape: their width follows the button's height
    b:HookScript("OnSizeChanged", function(self, _, h)
        if not h or h <= 0 then return end
        for _, s in ipairs({ self._shadow, self._fill, self._hover, self._frame }) do
            s[1]:SetWidth(h * CAP_K)
            s[3]:SetWidth(h * CAP_K)
        end
    end)
    -- hover (enabled only) and the pressed fill while the mouse is down
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then Each(self._hover, "Show") end end)
    b:HookScript("OnLeave", function(self) Each(self._hover, "Hide") end)
    b:HookScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and self:IsEnabled() then ShowFill(self, true) end
    end)
    b:HookScript("OnMouseUp", function(self) QuizUI.PaintAnswer(self, self._look or "open") end)
    b:HookScript("OnDisable", function(self) Each(self._hover, "Hide") end)
end

-- open: ready to pick; ticked: picked (the pressed fill); dim: not yours /
-- time up (disabled = the normal fill desaturated); right / wrong: the reveal,
-- the frame tinted; faded: the reveal's other answers
function QuizUI.PaintAnswer(b, look)
    b._look = look
    b._desat = (look == "dim" or look == "faded")
    ShowFill(b, look == "ticked")
    local c
    if look == "right" then c = FRAME_RIGHT elseif look == "wrong" then c = FRAME_WRONG end
    if c then Each(b._frame, "SetVertexColor", c[1], c[2], c[3]) else Each(b._frame, "SetVertexColor", 1, 1, 1) end
    b:SetAlpha(look == "faded" and 0.55 or 1)
end

