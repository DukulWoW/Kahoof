-- Kahoof Core/Protocol.lua: the wire format, encode / decode of every game message (S5a)
-- Decided in ALL-01 part 2 (networking.md, Protocol). Plain text, no
-- compression: "<version> SEP <session id> SEP <type> SEP <field> SEP ...",
-- SEP = byte 31. Byte 31 is stripped from player text on the way out, so quiz
-- text can never split a message; "|" is kept as it is. A message over 255
-- bytes goes as numbered parts (SplitParts / ParsePart, S8); Comms sends them
-- and puts them back together. The loopback (practice) carries whole messages.
--
-- One table, TYPES, names every message's fields; Encode and Decode both read
-- it, so the two can never disagree. Decode checks shape only (field count,
-- whole numbers, text that can be shown, list lengths); Host and Player check
-- meaning (is the answer within the question's answers, is the sender the
-- host). Offline tested: _work/tools/tests/test_protocol.lua.
--
--   Protocol.Encode(type, sessionId, data)   -> string
--   Protocol.Decode(str)                     -> msg | nil, why, version
--   Protocol.SplitParts(str, sid, mid)       -> { part, ... } (one = the whole message)
--   Protocol.ParsePart(str)                  -> sid, mid, n, total, piece | nil
--   Protocol.NewSessionId()                  -> 4 letters / digits
--   Protocol.EncodeBits(set) / DecodeBits(s) -> the IN bitmap of slots
--   Protocol.Mask(list) / Unmask(mask, n)    -> answer positions <-> one number

local _, KHF = ...

local Protocol = {}
KHF.Protocol = Protocol

Protocol.VERSION   = 1
Protocol.MAX_SLOTS = 40
Protocol.MAX_BYTES = 255   -- one addon message, header included
Protocol.MAX_PARTS = 16    -- a longer message is refused (a CJK question is about 14)
local SEP       = "\031"
local MAX_TEXT  = 200   -- characters in one text field (the longest quiz field)
local NONE      = {}    -- Dec's "optional field left empty"

--------------------------------------------------------------------------------
-- THE MESSAGES (the ones the game round needs; LOBBY, JOIN, ROSTER etc. come
-- with the lobby, S9). Field kinds: n = whole number, o = whole number or
-- empty, t = text. rest = the fields repeated to the end of the message,
-- gathered under restKey (a list of values when rest has one field, a list of
-- tables otherwise), restMin..restMax times.
--
--   START   title, question count, read time (0 none, -1 the host starts it,
--           2-10 s), board (1 every question, 5 every fifth, 0 only at the
--           end), shuffle (0 / 1), mode (1 = with several correct answers any
--           one counts, 2 = pick all of them: ALL-33); roster: slot, name ...
--   Q       question id, time limit, read time, pick (how many answers to
--           pick: 1 = one click; more = tick that many and press Answer),
--           text; answers ... (shown order; never the correct ones)
--   GO      question id, phase (1 = show the question, 2 = the host started
--           the clock: read time "the host starts it" only)
--   A       question id, picks (a mask of shown positions, bit 1 = the
--           first answer: 1-15)                              player -> host
--   IN      question id, bitmap of the slots that answered
--   REVEAL  question id, correct (a mask like A's), void (1 = skipped, no points),
--           why (the explanation, empty = none: here and not in Q, so it never
--           goes out before the reveal); counts per answer ...
--   BOARD   question id, show (1 = a leaderboard screen follows the reveal);
--           rows: slot, points this question, answer time (tenths, empty =
--           no answer), total, ctime (tenths: summed time of correct answers,
--           the tie break) ...
--   FINAL   questions played; rows: slot, total, correct, answered, played,
--           tsum (tenths, all answers), ctime ...
--   CANCEL  reason code
--   HI      ver (my addon version): "who has Kahoof?"         anyone -> audience
--   VER     ver: the answer to a HI, same id                  whisper to the asker
-- HI and VER are read from EVERY protocol version (ANY_VERSION), so an old
-- client still answers a new one's version check and shows as "needs an
-- update". Their fields never change; a later version may only add fields at
-- the end, and an older client ignores them (open = true).
--------------------------------------------------------------------------------
local TYPES = {
    START  = { fields = { "title:t", "count:n", "read:n", "board:n", "shuffle:n", "mode:n" },
               rest = { "slot:n", "name:t" }, restKey = "roster", restMin = 1, restMax = 40 },
    Q      = { fields = { "qid:n", "limit:n", "read:n", "pick:n", "text:t" },
               rest = { "answer:t" }, restKey = "answers", restMin = 2, restMax = 4 },
    GO     = { fields = { "qid:n", "phase:n" } },
    A      = { fields = { "qid:n", "picks:n" } },
    IN     = { fields = { "qid:n", "bits:t" } },
    REVEAL = { fields = { "qid:n", "correct:n", "void:n", "why:t" },
               rest = { "count:n" }, restKey = "counts", restMin = 2, restMax = 4 },
    BOARD  = { fields = { "qid:n", "show:n" },
               rest = { "slot:n", "points:n", "time:o", "total:n", "ctime:n" },
               restKey = "rows", restMin = 0, restMax = 40 },
    FINAL  = { fields = { "played:n" },
               rest = { "slot:n", "total:n", "correct:n", "answered:n", "played:n", "tsum:n", "ctime:n" },
               restKey = "rows", restMin = 0, restMax = 40 },
    CANCEL = { fields = { "reason:t" } },
    HI     = { fields = { "ver:t" }, open = true },
    VER    = { fields = { "ver:t" }, open = true },
}
local ANY_VERSION = { HI = true, VER = true }
Protocol.TYPES = TYPES

-- "name:kind" -> name, kind (split once, at load)
for _, spec in pairs(TYPES) do
    for _, list in ipairs({ spec.fields, spec.rest or {} }) do
        for i, f in ipairs(list) do
            local name, kind = f:match("^(%w+):(%a)$")
            list[i] = { name = name, kind = kind }
        end
    end
end

--------------------------------------------------------------------------------
-- VALUES
--------------------------------------------------------------------------------
local function Enc(kind, v)
    if kind == "t" then
        return (tostring(v or ""):gsub(SEP, ""))
    elseif kind == "o" and v == nil then
        return ""
    end
    assert(type(v) == "number", "Protocol: a number field got " .. type(v))
    return string.format("%d", math.floor(v + 0.5))
end

local function Dec(kind, s)
    if s == nil then return nil end
    if kind == "t" then
        local n = KHF.QuizStore.TextLength(s)
        if not n or n > MAX_TEXT then return nil end
        return s
    end
    if kind == "o" and s == "" then return NONE end
    if #s > 9 or not s:match("^%-?%d+$") then return nil end
    return tonumber(s)
end

-- Every field, empty ones included
local function Split(str)
    local out, pos = {}, 1
    while true do
        local i = str:find(SEP, pos, true)
        if not i then
            out[#out + 1] = str:sub(pos)
            return out
        end
        out[#out + 1] = str:sub(pos, i - 1)
        pos = i + 1
    end
end

--------------------------------------------------------------------------------
-- ENCODE / DECODE
--------------------------------------------------------------------------------
function Protocol.Encode(msgType, sid, data)
    local spec = assert(TYPES[msgType], "Protocol: unknown type")
    data = data or {}
    local out = { tostring(Protocol.VERSION), sid, msgType }
    for _, f in ipairs(spec.fields) do out[#out + 1] = Enc(f.kind, data[f.name]) end
    if spec.rest then
        local single = #spec.rest == 1
        for _, item in ipairs(data[spec.restKey] or {}) do
            for _, f in ipairs(spec.rest) do
                out[#out + 1] = Enc(f.kind, single and item or item[f.name])
            end
        end
    end
    return table.concat(out, SEP)
end

-- msg.proto = the sender's protocol version. Another version than ours is
-- refused (nil, "version", its number: S9 shows "needs update"), except HI / VER.
function Protocol.Decode(str)
    if type(str) ~= "string" then return nil, "not text" end
    local f = Split(str)
    local ver = f[1]:match("^%d%d?%d?$") and tonumber(f[1])
    if not ver or ver < 1 then return nil, "version" end
    local sid = f[2]
    if not (sid and sid:match("^%w%w%w%w$")) then return nil, "session id" end
    local spec = TYPES[f[3]]
    if ver ~= Protocol.VERSION and not (spec and ANY_VERSION[f[3]]) then return nil, "version", ver end
    if not spec then return nil, "type" end
    local msg = { type = f[3], sid = sid, proto = ver }
    local i = 4
    for _, fd in ipairs(spec.fields) do
        local v = Dec(fd.kind, f[i])
        if v == nil then return nil, fd.name end
        if v ~= NONE then msg[fd.name] = v end
        i = i + 1
    end
    if spec.rest then
        local per, left = #spec.rest, #f - i + 1
        if left % per ~= 0 then return nil, "list" end
        local n = left / per
        if n < spec.restMin or n > spec.restMax then return nil, "list length" end
        local list = {}
        for k = 1, n do
            local item = {}
            for _, fd in ipairs(spec.rest) do
                local v = Dec(fd.kind, f[i])
                if v == nil then return nil, fd.name end
                if v ~= NONE then item[fd.name] = v end
                i = i + 1
            end
            if per == 1 then list[k] = item[spec.rest[1].name] else list[k] = item end
        end
        msg[spec.restKey] = list
    elseif i <= #f and not spec.open then
        return nil, "extra fields"
    end
    return msg
end

--------------------------------------------------------------------------------
-- PARTS (S8): a message over MAX_BYTES goes as numbered parts, each
--   "<version> SEP <sid> SEP + SEP <message id> SEP <n> SEP <total> SEP <piece>"
-- The pieces, joined in order, are the whole message. "+" is never a message
-- type, so a part can never be read as a whole message. The message id is the
-- sender's own counter (1-999): two messages from one sender in flight never
-- mix. A piece never ends inside a UTF-8 character (a quiz in Chinese or
-- Russian splits cleanly). This frame never changes between versions, so any
-- version's parts can be put together and the whole message read (or refused
-- with its version).
--------------------------------------------------------------------------------
local PART = "+"

-- A UTF-8 continuation byte (10xxxxxx): a character goes on past it
local function Cont(b) return b ~= nil and b >= 128 and b < 192 end

-- -> the parts in send order (a message that fits = itself alone), or nil when
-- it would take more than MAX_PARTS
function Protocol.SplitParts(str, sid, mid)
    if #str <= Protocol.MAX_BYTES then return { str } end
    -- room for a piece next to the longest header (n and total at two digits)
    local head = #table.concat({ Protocol.VERSION, sid, PART, mid, Protocol.MAX_PARTS, Protocol.MAX_PARTS, "" }, SEP)
    local room = Protocol.MAX_BYTES - head
    local pieces, pos = {}, 1
    while pos <= #str do
        local stop = math.min(pos + room - 1, #str)
        while stop < #str and stop > pos and Cont(str:byte(stop + 1)) do stop = stop - 1 end
        pieces[#pieces + 1] = str:sub(pos, stop)
        if #pieces > Protocol.MAX_PARTS then return nil end
        pos = stop + 1
    end
    for i, piece in ipairs(pieces) do
        pieces[i] = table.concat({ Protocol.VERSION, sid, PART, mid, i, #pieces, piece }, SEP)
    end
    return pieces
end

-- -> sid, message id, n, total, piece for a well-formed part; nil for anything
-- else (a whole message, or a part that breaks the limits)
function Protocol.ParsePart(str)
    if type(str) ~= "string" then return nil end
    local sid, mid, n, total, piece =
        str:match("^%d%d?%d?\031(%w%w%w%w)\031%+\031(%d%d?%d?)\031(%d%d?)\031(%d%d?)\031(.+)$")
    if not sid then return nil end
    mid, n, total = tonumber(mid), tonumber(n), tonumber(total)
    if mid < 1 or n < 1 or n > total or total < 2 or total > Protocol.MAX_PARTS then return nil end
    return sid, mid, n, total, piece
end

--------------------------------------------------------------------------------
-- SESSION IDS AND THE IN BITMAP
--------------------------------------------------------------------------------
local ID_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"

function Protocol.NewSessionId()
    local t = {}
    for k = 1, 4 do
        local r = math.random(1, #ID_CHARS)
        t[k] = ID_CHARS:sub(r, r)
    end
    return table.concat(t)
end

-- set: { [slot] = true }. 40 slots in 10 hex digits, 4 slots per digit
-- (slot 1 = the lowest bit of the first digit).
function Protocol.EncodeBits(set)
    local out = {}
    for d = 1, Protocol.MAX_SLOTS / 4 do
        local v = 0
        for b = 0, 3 do
            if set[(d - 1) * 4 + b + 1] then v = v + 2 ^ b end
        end
        out[d] = string.format("%x", v)
    end
    return table.concat(out)
end

-- -> { [slot] = true }, count; nil for a malformed bitmap
function Protocol.DecodeBits(s)
    if type(s) ~= "string" or #s ~= Protocol.MAX_SLOTS / 4 or not s:match("^%x+$") then return nil end
    local set, n = {}, 0
    for d = 1, #s do
        local v = tonumber(s:sub(d, d), 16)
        for b = 0, 3 do
            if v % 2 == 1 then
                set[(d - 1) * 4 + b + 1] = true
                n = n + 1
            end
            v = math.floor(v / 2)
        end
    end
    return set, n
end

-- Answer positions as one number: position p = 2^(p-1). { 1, 3 } = 5.
function Protocol.Mask(list)
    local m, seen = 0, {}
    for _, p in ipairs(list) do
        if not seen[p] then seen[p] = true; m = m + 2 ^ (p - 1) end
    end
    return m
end

-- -> the sorted positions, or nil when the mask is not a whole number in
-- 1 .. (2^n - 1) (empty, or a position past the n answers)
function Protocol.Unmask(mask, n)
    if type(mask) ~= "number" or mask ~= math.floor(mask) or mask < 1 or mask >= 2 ^ n then return nil end
    local list = {}
    for p = 1, n do
        if mask % 2 == 1 then list[#list + 1] = p end
        mask = math.floor(mask / 2)
    end
    return list
end
