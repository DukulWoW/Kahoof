-- Kahoof_Dev Log.lua: every game message in and out, in a window (ALL-69, built with S8)
-- Fed by Kahoof's KHF.Dev.CommsTap (Core/Comms.lua): one line per message
-- sent (each part, with the send result), arrived (whole, after its parts),
-- dropped (and why), failed, bounced (a whisper to someone offline) and our
-- own broadcast echo. Practice and the
-- bots show as "loopback". Lines are kept while the window is closed.
--
--   /khfdev log          open or close the window
--   /khfdev log clear    empty it

local _, D = ...
local KHF = Kahoof

local Log = {}
D.Log = Log

local MAX = 1000
local lines = {}
local win, smf

local COLOR = {
    out = "ffff9900", ["in"] = "ff40ff40", drop = "ffff4040", fail = "ffff4040", bounce = "ffff4040",
    echo = "ff888888",
}

local function Format(i)
    local parts = ""
    if i.total and i.total > 1 then
        parts = i.part and string.format(" %d/%d", i.part, i.total) or string.format(" %d parts", i.total)
    end
    local extra = i.result or i.why
    return string.format("|cff888888%s|r |c%s%s|r %s %s %s %s%s%s%s",
        date("%H:%M:%S"), COLOR[i.way] or "ffffffff", i.way, tostring(i.chan or "-"),
        tostring(i.type or "?"), tostring(i.sid or "-"), KHF.EscapeText(i.who or ""),
        i.bytes and (" " .. i.bytes .. " B") or "", parts, extra and (" | " .. tostring(extra)) or "")
end

local function Build()
    win = KHF.CreateWindow({
        name = "KahoofDevLog", w = 640, h = 300, minW = 360, minH = 160,
        resizable = true, posKey = "devLog", title = "Dev: game messages",
    })
    smf = CreateFrame("ScrollingMessageFrame", nil, win.content)
    smf:SetAllPoints()
    smf:SetFontObject(GameFontHighlightSmall)
    smf:SetJustifyH("LEFT")
    smf:SetFading(false)
    smf:SetMaxLines(MAX)
    smf:EnableMouseWheel(true)
    smf:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    for _, l in ipairs(lines) do smf:AddMessage(l) end
end

function Log.Add(info)
    local line = Format(info)
    lines[#lines + 1] = line
    if #lines > MAX then table.remove(lines, 1) end
    if smf then smf:AddMessage(line) end
end

function Log.Command(arg)
    if (arg or ""):lower() == "clear" then
        lines = {}
        if smf then smf:Clear() end
        return
    end
    if not win then Build() end
    win:SetShown(not win:IsShown())
end
