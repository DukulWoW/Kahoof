-- Kahoof_Dev.lua: developer tools for Kahoof (ALL-30)
-- Like BigNoteBox_Dev: tracked in the repo, never packaged (.pkgmeta ignore),
-- a junction in each client. Enabling it (AddOn list + reload) is dev mode.
-- Plain English strings: nothing here is ever shown to players.
--
-- Kahoof reads one table, Kahoof.Dev (nil without this addon):
--   Dev.PracticePlayers(me) -> extra player keys for Practice (Core/Practice.lua)
--   Dev.PlayTabRow(page, anchor)  extra controls under Practice (the Host tab since S9: UI/HostTab.lua)
--   Dev.CommsTap(info)            every game message in / out (Core/Comms.lua):
--                                 the message log (Log.lua), the net test (NetTest.lua)
--
-- KahoofDevDB: bots (0-39, how many join a practice run), skip (0-1, the
-- share of bot answers left out).
--
-- /khfdev bots N | skip N (percent) | (nothing: the current values)
-- /khfdev ping | burst | lock: addon message probes (Probe.lua, RET-01 / FOR-01)
-- /khfdev log [clear]: the message log (Log.lua, ALL-69)
-- /khfdev net parts | flood: S8's network test (NetTest.lua)

local addonName, D = ...
local KHF = Kahoof

local DEFAULTS = { bots = 0, skip = 0.1 }

local function Say(msg) KHF:Print("|cffff9900Dev:|r " .. msg) end

local function Status()
    Say(string.format("bots %d, skip %d%%. /khfdev bots 0-%d, /khfdev skip 0-100",
        D.db.bots, math.floor(D.db.skip * 100 + 0.5), D.Bots.MAX))
end

--------------------------------------------------------------------------------
-- HOOKS KAHOOF READS
--------------------------------------------------------------------------------
KHF.Dev = {}

function KHF.Dev.PracticePlayers(me)
    return D.Bots.Players(me)
end

function KHF.Dev.CommsTap(info)
    D.Log.Add(info)
    D.NetTest.OnTap(info)
end

local slider
function KHF.Dev.PlayTabRow(page, anchor)
    -- wide enough that "(Default: 0)" clears the Reset button
    slider = KHF.Theme.CreateSlider(page, 360, {
        label = "Dev: practice bots", min = 0, max = D.Bots.MAX, step = 1,
        value = D.db.bots, default = 0, format = "%d",
        onChange = function(v) D.db.bots = math.floor(v + 0.5) end,
    })
    slider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    page:HookScript("OnShow", function() slider:SetValue(D.db.bots) end)
end

KHF.RegisterMessage("KahoofDev", "SessionState", function(_, s, state)
    D.Bots.OnHostState(s, state)
end)

--------------------------------------------------------------------------------
-- SAVED SETTINGS, SLASH COMMAND
--------------------------------------------------------------------------------
local function OnLoaded(_, name)
    if name ~= addonName then return end
    KHF.UnregisterEvent("ADDON_LOADED", OnLoaded)
    KahoofDevDB = KahoofDevDB or {}
    for k, v in pairs(DEFAULTS) do
        if KahoofDevDB[k] == nil then KahoofDevDB[k] = v end
    end
    D.db = KahoofDevDB
    D.Probe.Init()
    D.NetTest.Init()
end
KHF.RegisterEvent("ADDON_LOADED", OnLoaded)

SLASH_KAHOOFDEV1 = "/khfdev"
SlashCmdList.KAHOOFDEV = function(msg)
    -- the probes get the rest of the line as typed (whisper names keep case and spaces)
    local word, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = word:lower()
    if word == "ping" then return D.Probe.Ping(rest) end
    if word == "burst" then return D.Probe.Burst(rest) end
    if word == "lock" then return D.Probe.Lock(rest) end
    if word == "log" then return D.Log.Command(rest) end
    if word == "net" then return D.NetTest.Command(rest) end
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    local n = tonumber(arg)
    if cmd == "bots" and n then
        D.db.bots = math.max(0, math.min(math.floor(n), D.Bots.MAX))
        if slider then slider:SetValue(D.db.bots) end
    elseif cmd == "skip" and n then
        D.db.skip = math.max(0, math.min(n, 100)) / 100
    end
    Status()
    Say("probes: /khfdev ping <chan> [name] | burst <chan> [name] [n] [s] | lock [on|off]")
    Say("network: /khfdev log [clear] | net parts <group|guild|whisper name> | net flood <...> [n]")
end
