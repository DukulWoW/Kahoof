-- Kahoof_Dev NetTest.lua: S8's network test with real game messages through the real Comms
-- Everyone with Kahoof_Dev loaded checks what arrives by itself and whispers
-- the result back on the probe prefix (Probe.lua): the tester types one
-- command, the others only need the addon on.
--
--   /khfdev net parts <group | guild | whisper name>
--        a 40-row BOARD and a 40-name START with UTF-8 text (2- and 3-byte
--        characters), each several parts; every receiver checks them field by
--        field against what it can rebuild from the session id: "intact", or
--        the first field that differs
--   /khfdev net flood <group | guild | whisper name> [n]
--        n (30, max 60) one-part messages through the send queue: the first
--        10 go at once, then 1 a second, and none should be throttled; every
--        receiver says how many came and whether in order
--
-- Test messages carry a mark no real game message has, so Kahoof itself
-- drops them: question id 0 (BOARD, GO) and question count 0 (START).

local _, D = ...
local KHF = Kahoof

local NetTest = {}
D.NetTest = NetTest

local function Say(msg) KHF:Print("|cffff9900Net:|r " .. msg) end

-- "group" | "guild" | "whisper First Last" -> dest, label
local function Dest(rest)
    local word, name = (rest or ""):match("^(%S*)%s*(.-)$")
    word = (word or ""):lower()
    if word == "group" or word == "guild" then return { audience = word }, word end
    if word == "whisper" and name ~= "" then return { whisper = name }, "whisper " .. name end
    return nil
end

--------------------------------------------------------------------------------
-- THE TEST MESSAGES: rebuilt from the session id at both ends
--------------------------------------------------------------------------------
local function Seed(sid)
    local n = 0
    for i = 1, #sid do n = (n * 31 + sid:byte(i)) % 100000 end
    return n
end

local function BoardRows(sid)
    local seed, rows = Seed(sid), {}
    for slot = 1, 40 do
        local v = (seed + slot * 7919) % 100000
        rows[slot] = { slot = slot, points = v % 1001, total = v, ctime = (v * 3) % 99999,
                       time = (slot % 5 ~= 0) and (v % 300) or nil }   -- every fifth: no answer
    end
    return rows
end

local ZHE, ENYE, A_JP = "\208\150", "\195\177", "\227\129\130"   -- 2, 2 and 3 bytes

local function StartData(sid)
    local seed, roster = Seed(sid), {}
    for slot = 1, 40 do
        roster[slot] = { slot = slot,
                         name = "N" .. slot .. ENYE .. string.rep(ZHE, (seed + slot) % 5) .. string.rep(A_JP, slot % 4) }
    end
    return { title = string.rep(A_JP, 20) .. " test", count = 0, read = 0, board = 1, shuffle = 0, mode = 2,
             roster = roster }
end

local function Check(got, want, fields)
    if #got ~= #want then return "rows " .. #got .. " of " .. #want end
    for i, w in ipairs(want) do
        for _, k in ipairs(fields) do
            if got[i][k] ~= w[k] then return "row " .. i .. " " .. k end
        end
    end
    return "intact"
end

local function CheckBoard(m)
    return Check(m.rows, BoardRows(m.sid), { "slot", "points", "time", "total", "ctime" })
end

local function CheckStart(m)
    local want = StartData(m.sid)
    if m.title ~= want.title then return "title" end
    return Check(m.roster, want.roster, { "slot", "name" })
end

local function Bytes(msgType, sid, data)
    return #KHF.Protocol.Encode(msgType, sid, data)
end

--------------------------------------------------------------------------------
-- SENDING
--------------------------------------------------------------------------------
local tests = {}   -- sid -> { kind, label, at, expect (messages), done, parts, results }

local function Track(sid, kind, label, expect)
    tests[sid] = { kind = kind, label = label, at = GetTime(), expect = expect, done = 0, parts = 0, results = {} }
end

local function Parts(rest)
    local dest, label = Dest(rest)
    if not dest then return Say("/khfdev net parts group | guild | whisper <name>") end
    local sid = KHF.Protocol.NewSessionId()
    local board = { qid = 0, show = 0, rows = BoardRows(sid) }
    local start = StartData(sid)
    Track(sid, "parts", label, 2)
    Say(string.format("parts %s on %s: BOARD %d bytes + START %d bytes, queue %d",
        sid, label, Bytes("BOARD", sid, board), Bytes("START", sid, start), KHF.Comms.Backlog()))
    KHF.Comms.SendTo(dest, "BOARD", sid, board)
    KHF.Comms.SendTo(dest, "START", sid, start)
end

local function Flood(rest)
    local body, n = (rest or ""):match("^(.-)%s+(%d+)$")
    if not body then body = rest end
    local dest, label = Dest(body)
    if not dest then return Say("/khfdev net flood group | guild | whisper <name> [count 30]") end
    n = math.max(1, math.min(tonumber(n) or 30, 60))
    local sid = KHF.Protocol.NewSessionId()
    Track(sid, "flood", label, n)
    Say(string.format("flood %s on %s: %d messages, queue %d", sid, label, n, KHF.Comms.Backlog()))
    for i = 1, n do KHF.Comms.SendTo(dest, "GO", sid, { qid = 0, phase = i }) end
end

function NetTest.Command(rest)
    local word, more = (rest or ""):match("^(%S*)%s*(.-)$")
    word = (word or ""):lower()
    if word == "parts" then return Parts(more) end
    if word == "flood" then return Flood(more) end
    Say("/khfdev net parts <group|guild|whisper name> | flood <group|guild|whisper name> [n]")
end

--------------------------------------------------------------------------------
-- THE TAP: our sends, and test messages arriving
--------------------------------------------------------------------------------
local floods = {}   -- sender SEP sid -> { got, last, ordered, first, t }

local function Results(t)
    local out = {}
    for k, v in pairs(t.results) do out[#out + 1] = k .. " x" .. v end
    table.sort(out)
    return table.concat(out, ", ")
end

local function OnOut(info)
    local t = tests[info.sid]
    if not t then return end
    t.results[info.result or "?"] = (t.results[info.result or "?"] or 0) + 1
    if info.result ~= "Success" and info.result ~= "0" then return end
    t.parts = t.parts + 1
    if (info.part or 1) == (info.total or 1) then t.done = t.done + 1 end
    if t.done >= t.expect then
        tests[info.sid] = nil
        Say(string.format("%s %s: %d messages (%d sends) out in %.1f s (%s)", t.kind, info.sid, t.done, t.parts,
            GetTime() - t.at, Results(t)))
    end
end

local function Reply(to, ...)
    D.Probe.Whisper(to, table.concat({ ... }, "~"))
end

local function OnFlood(info)
    local key = info.who .. "~" .. info.sid
    local f = floods[key]
    local now = GetTime()
    if not f then
        f = { got = 0, last = 0, ordered = true, first = now }
        floods[key] = f
    end
    f.got = f.got + 1
    if info.msg.phase ~= f.last + 1 then f.ordered = false end
    f.last, f.t = info.msg.phase, now
    -- report once 3 s pass with nothing new
    C_Timer.After(3, function()
        if floods[key] ~= f or GetTime() - f.t < 2.9 then return end
        floods[key] = nil
        local spread = f.t - f.first
        Say(string.format("flood %s from %s via %s: got %d, %s, over %.1f s", info.sid, info.who,
            tostring(info.chan), f.got, f.ordered and "in order" or "OUT OF ORDER", spread))
        Reply(info.who, "NETF", info.sid, f.got, f.ordered and "yes" or "no", string.format("%.1f", spread))
    end)
end

function NetTest.OnTap(info)
    if info.way == "out" then return OnOut(info) end
    if info.way == "fail" and tests[info.sid] then
        local t = tests[info.sid]
        tests[info.sid] = nil
        return Say(string.format("%s %s FAILED: %s (%s)", t.kind, info.sid, tostring(info.why), Results(t)))
    end
    if info.way ~= "in" or not info.msg or info.chan == "loopback" then return end
    local m, result = info.msg
    if m.type == "BOARD" and m.qid == 0 then
        result = CheckBoard(m)
    elseif m.type == "START" and m.count == 0 then
        result = CheckStart(m)
    elseif m.type == "GO" and m.qid == 0 then
        return OnFlood(info)
    else
        return
    end
    Say(string.format("%s %s from %s via %s: %d parts, %d bytes, %s", m.type, m.sid, info.who,
        tostring(info.chan), info.total or 1, info.bytes or 0, result))
    Reply(info.who, "NETP", m.sid, m.type, result, info.total or 1)
end

-- Replies, on the probe prefix
function NetTest.Init()
    D.Probe.handlers.NETP = function(sender, sid, msgType, result, parts)
        Say(string.format("%s %s at %s: %s (%s parts)", tostring(msgType), tostring(sid), tostring(sender),
            tostring(result), tostring(parts)))
    end
    D.Probe.handlers.NETF = function(sender, sid, got, ordered, spread)
        Say(string.format("flood %s at %s: got %s, in order %s, over %s s", tostring(sid), tostring(sender),
            tostring(got), tostring(ordered), tostring(spread)))
    end
end
