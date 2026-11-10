-- Kahoof UI/Widgets.lua: shared window and widget behavior
-- Ported from BNB (UI/Widgets.lua, UI/ToolWindow.lua, UI/MainWindow.lua,
-- UI/GlowOverlay.lua). Behavior only; the look is UI/Theme.lua.
--
--   KHF.CreateWindow(opts)            the one window builder (windows-widgets.md)
--   KHF.CreateButton(parent, text, w, h)
--   KHF.SetTooltip(frame, title, line)
--   KHF.AttachEscClose(f, closeFn, stepAside)
--   KHF.StartDragMoving / StopDragMoving, StartGripSizing / StopGripSizing
--   KHF.CreateResizeGrip(f, opts)
--   KHF.SaveWindowPos(f) / RestoreWindowPos(f)
--   KHF.FadeTo(frame, from, to, duration, onDone) / StopFade(frame)

local _, KHF = ...

--------------------------------------------------------------------------------
-- KEYBOARD AND ESC (combat-safe)
-- SetPropagateKeyboardInput is protected in combat, so:
--  * in combat our key handlers do nothing, so every key, ESC included, goes
--    to the game;
--  * every registered frame is set to propagate when combat starts
--    (PLAYER_REGEN_DISABLED fires before the lockdown), and AttachEscClose sets
--    it back to propagate one frame after taking an ESC, so a window never
--    keeps swallowing keys and the player can always move.
--------------------------------------------------------------------------------
function KHF.SetPropagate(f, on)
    if not InCombatLockdown() then f:SetPropagateKeyboardInput(on) end
end

local _kbFrames      = {}   -- [frame] = true
local _kbEnableLater = {}   -- frames built in combat: keyboard on when it ends

local function EnableKeyboardSafe(f)
    if InCombatLockdown() then _kbEnableLater[f] = true; return end
    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
end

-- closeFn(self): what ESC does. stepAside(self), optional: true = leave this
-- ESC to the game (e.g. a page inside the window wants it first).
-- onKey(self, key), optional: any other key; true = the window took it (the
-- quiz window's answer keys), anything else goes on to the game
function KHF.AttachEscClose(f, closeFn, stepAside, onKey)
    _kbFrames[f] = true
    f:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key ~= "ESCAPE" then
            if onKey and onKey(self, key) then
                self:SetPropagateKeyboardInput(false)
                C_Timer.After(0, function() KHF.SetPropagate(self, true) end)
            else
                self:SetPropagateKeyboardInput(true)
            end
            return
        end
        if stepAside and stepAside(self) then
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        C_Timer.After(0, function() KHF.SetPropagate(self, true) end)
        closeFn(self)
    end)
    EnableKeyboardSafe(f)
end

KHF.RegisterEvent("PLAYER_REGEN_DISABLED", function()
    if InCombatLockdown() then return end
    for f in pairs(_kbFrames) do f:SetPropagateKeyboardInput(true) end
end)

KHF.RegisterEvent("PLAYER_REGEN_ENABLED", function()
    for f in pairs(_kbEnableLater) do
        _kbEnableLater[f] = nil
        EnableKeyboardSafe(f)
    end
end)

--------------------------------------------------------------------------------
-- DRAG WITHOUT StartMoving (BNB ALL-97)
-- The client's StartMoving threw windows 100-190 px on drag at some UI scales.
-- Here TOPLEFT is pinned and follows the pointer's movement from the press,
-- kept on screen when the frame is clamped (honors SetClampRectInsets, which
-- the theme sets so the frame art stays on screen too). Start from OnDragStart,
-- Stop from OnDragStop.
--------------------------------------------------------------------------------
function KHF.StartDragMoving(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not (left and top) then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

    local s       = f:GetEffectiveScale()
    local cx, cy  = GetCursorPosition()
    local w, h    = f:GetSize()
    local us      = UIParent:GetEffectiveScale()
    local screenW = UIParent:GetWidth()  * us / s
    local screenH = UIParent:GetHeight() * us / s
    local clamp   = f:IsClampedToScreen()
    -- Positive top / right and negative left / bottom insets reach outside the frame
    local il, ir, it, ib = f:GetClampRectInsets()
    il, ir, it, ib = il or 0, ir or 0, it or 0, ib or 0

    local drv = f._dragDriver or CreateFrame("Frame")
    f._dragDriver = drv
    drv:SetScript("OnUpdate", function(self)
        if not f:IsShown() then self:SetScript("OnUpdate", nil); return end
        local x, y = GetCursorPosition()
        local l = left + (x - cx) / s
        local t = top  + (y - cy) / s
        if clamp then
            l = math.min(math.max(l, -il), math.max(-il, screenW - w - ir))
            t = math.max(math.min(t, screenH - it), math.min(h - ib, screenH - it))
        end
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end)
end

function KHF.StopDragMoving(f)
    if f._dragDriver then f._dragDriver:SetScript("OnUpdate", nil) end
end

--------------------------------------------------------------------------------
-- GRIP RESIZE WITHOUT StartSizing (BNB ALL-97)
-- StartSizing snapped the corner to the pointer. Here the top-left is pinned
-- and the size follows the pointer's movement, within the resize bounds and
-- never past the screen's right or bottom edge.
--------------------------------------------------------------------------------
function KHF.StartGripSizing(f)
    local left, top = f:GetLeft(), f:GetTop()
    if not (left and top) then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

    local s      = f:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local w0, h0 = f:GetSize()
    local minW, minH, maxW, maxH = f:GetResizeBounds()
    local screenW = UIParent:GetWidth() * UIParent:GetEffectiveScale() / s
    local roomW, roomH = screenW - left, top
    maxW = (maxW and maxW > 0) and math.min(maxW, roomW) or roomW
    maxH = (maxH and maxH > 0) and math.min(maxH, roomH) or roomH
    if not minW or minW <= 0 then minW = 150 end
    if not minH or minH <= 0 then minH = 100 end

    local drv = f._gripDriver or CreateFrame("Frame")
    f._gripDriver = drv
    drv:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local w = math.max(minW, math.min(maxW, w0 + (x - cx) / s))
        local h = math.max(minH, math.min(maxH, h0 + (cy - y) / s))
        f:SetSize(w, h)
    end)
end

function KHF.StopGripSizing(f)
    if f._gripDriver then f._gripDriver:SetScript("OnUpdate", nil) end
end

-- The resize grip: the damage meter's scale handle with its hover and pressed
-- atlases, the chat grabber where that atlas is missing. opts: { x, y =
-- BOTTOMRIGHT offset, onStop }. The grip owns its mouse scripts.
local GRIP_ATLAS, GRIP_ART, GRIP_HIT = "damagemeters-scalehandle", 32, 24
local GRABBER = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
function KHF.CreateResizeGrip(f, opts)
    opts = opts or {}
    local grip = CreateFrame("Button", nil, f)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", opts.x or 0, opts.y or 0)
    grip:SetFrameLevel(f:GetFrameLevel() + 20)
    local hasAtlas = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(GRIP_ATLAS) ~= nil
    local tex
    if hasAtlas then
        grip:SetSize(GRIP_HIT, GRIP_HIT)
        tex = grip:CreateTexture(nil, "OVERLAY")
        tex:SetSize(GRIP_ART, GRIP_ART)
        tex:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", 0, 0)
        tex:SetAtlas(GRIP_ATLAS)
    else
        grip:SetSize(16, 16)
        grip:SetNormalTexture(GRABBER .. "Up")
        grip:SetHighlightTexture(GRABBER .. "Highlight")
        grip:SetPushedTexture(GRABBER .. "Down")
    end

    local function SetState()
        if not tex then return end
        local hover = not grip._sizing and grip:IsMouseOver()
        tex:SetAtlas(GRIP_ATLAS .. (grip._sizing and "-pressed" or (hover and "-hover" or "")))
    end
    local function Stop()
        if not grip._sizing then return end
        grip._sizing = false
        KHF.StopGripSizing(f)
        SetState()
        if opts.onStop then opts.onStop() end
    end
    grip:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        grip._sizing = true
        SetState()
        KHF.StartGripSizing(f)
    end)
    grip:SetScript("OnMouseUp", Stop)
    grip:SetScript("OnEnter", SetState)
    grip:SetScript("OnLeave", SetState)
    grip:HookScript("OnHide", Stop)   -- hidden mid-drag (window closed)
    return grip
end

--------------------------------------------------------------------------------
-- WINDOW POSITION (BNB's main window): the center point in screen pixels and
-- the size, so a UI scale change keeps the place. Restored capped at the
-- screen. f._posKey names the entry in KahoofDB.windows; f._defW / _defH /
-- _minW / _minH come from CreateWindow.
--------------------------------------------------------------------------------
local function PosTable(f)
    local db = KHF.db
    if not (db and f._posKey) then return nil end
    db.windows = db.windows or {}
    db.windows[f._posKey] = db.windows[f._posKey] or {}
    return db.windows[f._posKey]
end

function KHF.SaveWindowPos(f)
    local pos = PosTable(f)
    if not pos then return end
    local s = f:GetEffectiveScale()
    local x, y = f:GetCenter()
    if x and y then pos.x, pos.y = x * s, y * s end
    if f._resizable then pos.w, pos.h = f:GetWidth(), f:GetHeight() end
end

function KHF.RestoreWindowPos(f)
    local pos = PosTable(f) or {}
    local w, h = f._defW, f._defH
    if f._resizable then
        w = math.max(math.min(pos.w or w, UIParent:GetWidth()),  f._minW or 0)
        h = math.max(math.min(pos.h or h, UIParent:GetHeight()), f._minH or 0)
    end
    f:SetSize(w, h)
    f:ClearAllPoints()
    if pos.x and pos.y then
        local s = f:GetEffectiveScale()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x / s, pos.y / s)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

--------------------------------------------------------------------------------
-- THE WINDOW BUILDER: every Kahoof window goes through this (windows-widgets.md).
-- opts:
--   name        global frame name (nil = none); a named window is also in
--               UISpecialFrames, so ESC closes it in combat too
--   w, h        default size
--   minW, minH  resizable windows: the smallest size
--   resizable   adds the grip; the size is saved
--   posKey      KahoofDB.windows key: the place (and size) is saved and restored
--   title       title text in the title band (nil = none)
--   strata      nil = "MEDIUM" (big windows); dialogs go higher
--   onClose     what the X and ESC do (nil = hide)
--   onEsc       asked first on ESC: return true when it took the key (a page
--               inside the window going back); the window then stays open
--   onKey       onKey(f, key) for every other key, out of combat: true = taken
--               (not passed on to the game)
-- Returns the frame, hidden. f.content is the area inside the frame art, below
-- the title band. f:SetWindowTitle(text), f.CloseButton.
--------------------------------------------------------------------------------
function KHF.CreateWindow(o)
    local Theme = KHF.Theme
    local f = CreateFrame("Frame", o.name, UIParent)
    f:Hide()
    f:SetFrameStrata(o.strata or "MEDIUM")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f._posKey, f._resizable = o.posKey, o.resizable and true or false
    f._defW, f._defH, f._minW, f._minH = o.w, o.h, o.minW, o.minH
    f:SetSize(o.w, o.h)

    Theme.ApplyFrame(f)

    local function Close()
        if o.onClose then o.onClose(f) else f:Hide() end
    end
    f._titleText = Theme.CreateTitle(f)
    function f:SetWindowTitle(text) self._titleText:SetText(text or "") end
    f:SetWindowTitle(o.title)
    f.CloseButton = Theme.CreateCloseButton(f, Close)

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", f, "TOPLEFT", Theme.PAD, -(Theme.TITLE_H + Theme.GAP))
    f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Theme.PAD, Theme.PAD)

    f:SetScript("OnDragStart", function(self) KHF.StartDragMoving(self) end)
    f:SetScript("OnDragStop", function(self)
        KHF.StopDragMoving(self)
        KHF.SaveWindowPos(self)
    end)

    KHF.AttachEscClose(f, function()
        if o.onEsc and o.onEsc(f) then return end
        Close()
    end, nil, o.onKey)
    if o.name then tinsert(UISpecialFrames, o.name) end

    if o.resizable then
        f:SetResizable(true)
        f:SetResizeBounds(o.minW or 200, o.minH or 150)
        f._grip = KHF.CreateResizeGrip(f, {
            x = -Theme.EDGE, y = Theme.EDGE,
            onStop = function() KHF.SaveWindowPos(f) end,
        })
    end
    if o.posKey then
        f:SetScript("OnShow", function(self) KHF.RestoreWindowPos(self) end)
    end
    return f
end

--------------------------------------------------------------------------------
-- BUTTONS: every text button goes through here (the theme's red button, on
-- every client: Dukul, 2026-11-02)
--------------------------------------------------------------------------------
function KHF.CreateButton(parent, text, w, h)
    return KHF.Theme.CreateTextButton(parent, text, w, h)
end

-- A plain tooltip: a title (text, or a function(frame) that returns it) and
-- an optional wrapped line under it. Hooks OnEnter / OnLeave, so a template's
-- own hover scripts (dropdowns, check boxes) keep working; call it once per frame.
function KHF.SetTooltip(frame, title, line)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title, 1, 1, 1)
        local l = type(line) == "function" and line(self) or line
        if l then GameTooltip:AddLine(l, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

--------------------------------------------------------------------------------
-- FADE (BNB.FadeTo): an AnimationGroup, never an OnUpdate fade. A new fade on a
-- frame replaces the running one and drops its onDone; a fade stopped by
-- anything else (frame hidden) lands on the final alpha and runs onDone.
--------------------------------------------------------------------------------
function KHF.FadeTo(target, fromAlpha, toAlpha, duration, onDone)
    local ag = target._khfFadeAG
    if not ag then
        ag = target:CreateAnimationGroup()
        ag:SetToFinalAlpha(true)
        ag._alpha = ag:CreateAnimation("Alpha")
        local function Complete(self)
            self:GetParent():SetAlpha(self._toAlpha)
            local cb = self._onDone
            self._onDone = nil
            if cb then cb() end
        end
        ag:SetScript("OnFinished", Complete)
        ag:SetScript("OnStop", function(self)
            if not self._restarting then Complete(self) end
        end)
        target._khfFadeAG = ag
    end
    ag._restarting = true
    ag:Stop()
    ag._restarting = false
    ag._toAlpha, ag._onDone = toAlpha, onDone
    ag._alpha:SetFromAlpha(fromAlpha)
    ag._alpha:SetToAlpha(toAlpha)
    ag._alpha:SetDuration(duration)
    target:SetAlpha(fromAlpha)
    ag:Play()
end

-- Cancels a running fade without its onDone; the caller sets the alpha it wants
function KHF.StopFade(target)
    local ag = target and target._khfFadeAG
    if not ag then return end
    ag._onDone = nil
    ag._restarting = true
    ag:Stop()
    ag._restarting = false
end
