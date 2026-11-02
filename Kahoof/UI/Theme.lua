-- Kahoof UI/Theme.lua: the window look (skin code, kept apart from logic)
-- The WoW Forever look on every client (Dukul, 2026-11-02): the metal frame,
-- the wood background with its soft glow, the small red X and the red text
-- button. Ported from BNB's Forever theme test window
-- (BigNoteBox_Dev/ForeverThemeTest.lua, BNB ALL-647); the art is BNB's
-- Themes/Forever/Assets TGA, copied into Assets/Theme. Frame art scale 0.40
-- (Dukul, 2026-11-01: the X then matches the Retail main window's).

local _, KHF = ...

local Theme = {}
KHF.Theme = Theme

local ART = KHF.ADDON_PATH .. "Assets\\Theme\\"
local function T(p) return ART .. p end

local S = 0.4   -- frame art scale (the art is drawn at 2x)

-- Metal frame, in art pixels. Corners 190 x 190 (bottom ones 190 x 200), side
-- edges 190 x 256 tiled down, top / bottom bands 256 wide tiled across. The
-- frame's outer line is column 23 on the left, 187 of 190 on the right, row 24
-- at the top and 190 of 200 at the bottom: those go on the window's edges. The
-- top band's dark title strip is rows 24-83, centered on 53.5.
local ML, MR, MT, MB, MBAND = 23, 3, 24, 10, 53.5
local CORNER, CORNER_BH, TILE = 190, 200, 256
local WOOD_TILE = 256

-- Layout numbers for window content, in UI units (measured on the art: the
-- side and bottom bars are opaque up to ~6 px inside the window, the title
-- band down to ~22 px)
Theme.TITLE_H = math.floor((83 - MT) * S + 0.5)   -- 24: bottom of the title band
Theme.EDGE    = 6                                  -- how far the bars reach in
Theme.PAD     = 14                                 -- content inset from the sides
Theme.GAP     = 6                                  -- content gap under the title band
local BAND_Y  = (MT - MBAND) * S                   -- title band center, from the top

--------------------------------------------------------------------------------
-- FRAME
--------------------------------------------------------------------------------
local function Layout(f)
    local p = f._theme
    if not p then return end
    local w, h = f:GetSize()
    local C = CORNER * S

    -- Background: 10 art px in from the outer line, where every corner's bevel
    -- is opaque, so it never shows outside the frame (BNB round 3)
    local i = 10 * S
    p.bg:SetTexCoord(0, (w - 2 * i) / WOOD_TILE, 0, (h - 2 * i) / WOOD_TILE)

    local span  = math.max(1, w + (ML + MR) * S - 2 * C)
    local vspan = math.max(1, h + (MT + MB) * S - CORNER * S - CORNER_BH * S)
    p.top:SetTexCoord(0, span / (TILE * S), 0, 1)
    p.bottom:SetTexCoord(0, span / (TILE * S), 0, 1)
    p.left:SetTexCoord(0, 1, 0, vspan / (TILE * S))
    p.right:SetTexCoord(0, 1, 0, vspan / (TILE * S))
end

-- Draws the frame on f and keeps it fitted through resizes. Call once, right
-- after the frame is made. Hooks OnSizeChanged: never SetScript it afterwards.
function Theme.ApplyFrame(f)
    local p = {}
    f._theme = p
    local C = CORNER * S

    local i = 10 * S
    p.bg = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    p.bg:SetTexture(T("Background\\wood"), "REPEAT", "REPEAT")
    p.glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    p.glow:SetTexture(T("Background\\glow"))
    for _, t in ipairs({ p.bg, p.glow }) do
        t:SetPoint("TOPLEFT", f, "TOPLEFT", i, -i)
        t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -i, i)
    end

    local function Tex(sub, file) local t = f:CreateTexture(nil, "BORDER", nil, sub); t:SetTexture(file); return t end
    p.tl = Tex(3, T("Frame\\metal-corner-topleft"))
    p.tr = Tex(3, T("Frame\\metal-corner-topright"))
    p.bl = Tex(3, T("Frame\\metal-corner-bottomleft"))
    p.br = Tex(3, T("Frame\\metal-corner-bottomright"))
    p.tl:SetSize(C, C); p.tr:SetSize(C, C)
    p.bl:SetSize(C, CORNER_BH * S); p.br:SetSize(C, CORNER_BH * S)
    p.tl:SetPoint("TOPLEFT", f, "TOPLEFT", -ML * S, MT * S)
    p.tr:SetPoint("TOPRIGHT", f, "TOPRIGHT", MR * S, MT * S)
    p.bl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -ML * S, -MB * S)
    p.br:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", MR * S, -MB * S)

    p.top = f:CreateTexture(nil, "BORDER", nil, 2)
    p.top:SetTexture(T("Frame\\metal-edge-top"), "REPEAT", "CLAMP")
    p.top:SetPoint("TOPLEFT", p.tl, "TOPRIGHT"); p.top:SetPoint("BOTTOMRIGHT", p.tr, "BOTTOMLEFT")
    p.bottom = f:CreateTexture(nil, "BORDER", nil, 2)
    p.bottom:SetTexture(T("Frame\\metal-edge-bottom"), "REPEAT", "CLAMP")
    p.bottom:SetPoint("TOPLEFT", p.bl, "TOPRIGHT"); p.bottom:SetPoint("BOTTOMRIGHT", p.br, "BOTTOMLEFT")
    p.left = f:CreateTexture(nil, "BORDER", nil, 1)
    p.left:SetTexture(T("Frame\\metal-edge-left"), "CLAMP", "REPEAT")
    p.left:SetPoint("TOPLEFT", p.tl, "BOTTOMLEFT"); p.left:SetPoint("BOTTOMRIGHT", p.bl, "TOPRIGHT")
    p.right = f:CreateTexture(nil, "BORDER", nil, 1)
    p.right:SetTexture(T("Frame\\metal-edge-right"), "CLAMP", "REPEAT")
    p.right:SetPoint("TOPLEFT", p.tr, "BOTTOMLEFT"); p.right:SetPoint("BOTTOMRIGHT", p.br, "TOPRIGHT")

    -- The art reaches outside the window: the clamp keeps all of it on screen
    -- (positive top / right and negative left / bottom insets reach outside)
    f:SetClampRectInsets(-ML * S, MR * S, MT * S, -MB * S)

    Layout(f)
    f:HookScript("OnSizeChanged", Layout)
end

-- The soft orange glow on a panel inside a window, so it stands out from the
-- wood (BNB's AddForeverGlow, there on its note list and editor panes; here on
-- every client). Top of BACKGROUND: above the panel's own shade, below its
-- content. Stretches with the host.
function Theme.AddGlow(host, alpha)
    local glow = host:CreateTexture(nil, "BACKGROUND", nil, 7)
    glow:SetAllPoints(host)
    glow:SetTexture(T("Background\\glow"))
    if alpha then glow:SetAlpha(alpha) end
    return glow
end

-- The title, centered in the top band's title strip
function Theme.CreateTitle(f)
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", f, "TOP", 0, BAND_Y)
    return fs
end

-- The small red X in the title strip; its right edge 4 art px past the window
-- edge, so it covers the right border (Dukul, 2026-11-01)
function Theme.CreateCloseButton(f, onClick)
    local size = math.max(16, math.floor(56 * S + 0.5))
    local b = CreateFrame("Button", nil, f)
    b:SetSize(size, size)
    b:SetPoint("RIGHT", f, "TOPRIGHT", 4 * S, BAND_Y)
    b:SetFrameLevel(f:GetFrameLevel() + 20)
    b:SetNormalTexture(T("Buttons\\small-exit"))
    b:SetPushedTexture(T("Buttons\\small-exit-pressed"))
    b:SetDisabledTexture(T("Buttons\\small-exit-disabled"))
    b:SetHighlightTexture(T("Buttons\\small-highlight"), "ADD")
    b:SetScript("OnClick", function() onClick() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(KHF.L["CLOSE"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

--------------------------------------------------------------------------------
-- RED TEXT BUTTON: left cap 114, center 64 (tiled), right 292, all 128 high,
-- scaled to the button's height. Normal / pressed / disabled art; the
-- highlight is the normal art added at 22 %. A real Button: SetText, Enable /
-- Disable and OnClick work as usual.
--------------------------------------------------------------------------------
local LEFT_W, MID_W, RIGHT_W, ART_H = 114, 64, 292, 128

function Theme.CreateTextButton(parent, text, width, height)
    height = height or 24
    local k = height / ART_H
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(math.max(width or 80, math.ceil((LEFT_W + RIGHT_W) * k)), height)

    local l = b:CreateTexture(nil, "BACKGROUND"); l:SetPoint("TOPLEFT"); l:SetSize(LEFT_W * k, height)
    local r = b:CreateTexture(nil, "BACKGROUND"); r:SetPoint("TOPRIGHT"); r:SetSize(RIGHT_W * k, height)
    local c = b:CreateTexture(nil, "BACKGROUND")
    c:SetPoint("TOPLEFT", l, "TOPRIGHT"); c:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
    local hls = {}
    for n, src in ipairs({ l, c, r }) do
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(src); hl:SetBlendMode("ADD"); hl:SetAlpha(0.22)
        hls[n] = hl
    end

    local state
    local function Paint(st)
        state = st
        local s = st and ("-" .. st) or ""
        local midCoord = math.max(b:GetWidth() - (LEFT_W + RIGHT_W) * k, 0.01) / (MID_W * k)
        l:SetTexture(T("Buttons\\redbutton-left" .. s))
        r:SetTexture(T("Buttons\\redbutton-right" .. s))
        c:SetTexture(T("Buttons\\redbutton-center" .. s), "REPEAT", "CLAMP")
        c:SetTexCoord(0, midCoord, 0, 1)
        hls[1]:SetTexture(T("Buttons\\redbutton-left"))
        hls[3]:SetTexture(T("Buttons\\redbutton-right"))
        hls[2]:SetTexture(T("Buttons\\redbutton-center"), "REPEAT", "CLAMP")
        hls[2]:SetTexCoord(0, midCoord, 0, 1)
    end

    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    b:SetPushedTextOffset(1, -1)
    b:SetText(text or "")

    b:SetScript("OnMouseDown", function(self, btn)
        if btn == "LeftButton" and self:IsEnabled() then Paint("pressed") end
    end)
    b:SetScript("OnMouseUp", function(self)
        if self:IsEnabled() then Paint(nil) end
    end)
    b:SetScript("OnEnable", function() Paint(nil) end)
    b:SetScript("OnDisable", function() Paint("disabled") end)
    b:SetScript("OnSizeChanged", function() Paint(state) end)
    Paint(nil)
    return b
end
