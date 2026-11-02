-- Kahoof Core/QuizStore.lua: the quiz field list, the clean function and the store
--
-- ONE FIELD LIST (data.md): QUIZ_FIELDS and QUESTION_FIELDS below are the only
-- place a field is named. Clean builds a fresh quiz from them alone, so export,
-- import, the network and Duplicate (which all go through Clean) can never drop
-- or smuggle a field. A new field = one line here.
--
-- EVERYTHING FROM OUTSIDE IS CLEANED: quiz text, an import code, a quiz from the
-- network, even the store's own saved quizzes when they are read back. Invalid
-- = refused with a line that says why; nothing half-clean reaches the DB.
--
-- The store writes one quiz at a time (db.quizzes[id] = quiz) and never replaces
-- the whole table. Writes need KHF.quizDBState == "ok" (Core/Database.lua).
--
--   QuizStore.Clean(raw)        -> quiz | nil, msg, path
--   QuizStore.List()            -> { summary, ... }  starter first, then newest
--   QuizStore.Get(id)           -> a copy of the quiz, or nil
--   QuizStore.Create(raw)       -> id | nil, msg
--   QuizStore.Save(raw)         -> id | nil, msg     (raw.id = an existing quiz)
--   QuizStore.Delete(id)        -> true | nil, msg
--   QuizStore.Duplicate(id)     -> id | nil, msg
--   QuizStore.CanSave()         -> bool, msg
-- Every change sends QuizzesChanged (id, "created" | "saved" | "deleted").

local _, KHF = ...
local L = KHF.L

local QuizStore = {}
KHF.QuizStore = QuizStore

QuizStore.STARTER_ID   = "starter"
QuizStore.MAX_QUESTIONS = 50
QuizStore.MIN_ANSWERS  = 2
QuizStore.MAX_ANSWERS  = 4
QuizStore.DEFAULT_TIME = 20
local TITLE_MAX = 60
-- The time limits a question can have (data.md), in seconds
QuizStore.TIMES = { 10, 20, 30, 45, 60 }
local TIME_OK = {}
for _, t in ipairs(QuizStore.TIMES) do TIME_OK[t] = true end

--------------------------------------------------------------------------------
-- FIELD LIST
-- kind: "text" (one line of player text, max = visible characters),
-- "id", "stamp" (a time() value), "time" (a time limit), "questions",
-- "answers" (MIN..MAX_ANSWERS texts), "index" (the correct answer).
-- label = the locale key that names the field in an error line.
-- The about and tag limits are Claude's (2026-11-02), data.md names none.
--------------------------------------------------------------------------------
local QUIZ_FIELDS = {
    { key = "id",        kind = "id" },
    { key = "title",     kind = "text", max = TITLE_MAX,  required = true, label = "FIELD_TITLE" },
    { key = "about",     kind = "text", max = 200, label = "FIELD_ABOUT" },
    { key = "tag",       kind = "text", max = 24,  label = "FIELD_TAG" },
    { key = "author",    kind = "text", max = 60,  label = "FIELD_AUTHOR" },
    { key = "created",   kind = "stamp" },
    { key = "modified",  kind = "stamp" },
    { key = "time",      kind = "time", default = QuizStore.DEFAULT_TIME },
    { key = "questions", kind = "questions" },
}
local QUESTION_FIELDS = {
    { key = "text",    kind = "text", max = 200, required = true, label = "FIELD_QUESTION" },
    { key = "answers", kind = "answers", max = 60, label = "FIELD_ANSWER" },
    { key = "correct", kind = "index" },
    { key = "time",    kind = "time" },   -- nil = the quiz's time
    { key = "why",     kind = "text", max = 200, label = "FIELD_WHY" },
}
QuizStore.QUIZ_FIELDS = QUIZ_FIELDS
QuizStore.QUESTION_FIELDS = QUESTION_FIELDS

--------------------------------------------------------------------------------
-- TEXT
-- Player text is UTF-8. A string with one invalid byte shows as nothing at all
-- in a WoW edit box, so it is refused, not stored. Control characters (line
-- breaks included: every field is one line) are refused too; a tab becomes a
-- space. Lengths count characters, not bytes.
--------------------------------------------------------------------------------
-- Number of UTF-8 characters in s, or nil when s is not valid UTF-8 (overlong
-- forms and surrogates included) or holds a control character.
function QuizStore.TextLength(s)
    local n, i, len = 0, 1, #s
    while i <= len do
        local c = s:byte(i)
        local need
        local lo, hi = 0x80, 0xBF
        if c < 0x20 or c == 0x7F then
            return nil
        elseif c < 0x80 then
            need = 0
        elseif c >= 0xC2 and c <= 0xDF then
            need = 1
        elseif c >= 0xE0 and c <= 0xEF then
            need = 2
            if c == 0xE0 then lo = 0xA0 elseif c == 0xED then hi = 0x9F end
        elseif c >= 0xF0 and c <= 0xF4 then
            need = 3
            if c == 0xF0 then lo = 0x90 elseif c == 0xF4 then hi = 0x8F end
        else
            return nil
        end
        for k = 1, need do
            local b = s:byte(i + k)
            if not b then return nil end
            if k == 1 then
                if b < lo or b > hi then return nil end
            elseif b < 0x80 or b > 0xBF then
                return nil
            end
        end
        i = i + need + 1
        n = n + 1
    end
    return n
end

-- Spaces, tabs and non-breaking spaces (UTF-8 C2 A0, common in text pasted from
-- a web page) off both ends
function QuizStore.Trim(s)
    local prev
    repeat
        prev = s
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        if s:sub(1, 2) == "\194\160" then s = s:sub(3) end
        if s:sub(-2) == "\194\160" then s = s:sub(1, -3) end
    until s == prev
    return s
end

--------------------------------------------------------------------------------
-- CLEAN
-- Returns a new quiz built from the field lists, or nil, msg, path. path names
-- where the problem is ({ field = "title" } / { q = 3, field = "why" } /
-- { q = 3, a = 2 }), so QuizText can turn it into "Line 14: ...".
--------------------------------------------------------------------------------
local function Fail(msg, path) return nil, msg, path or {} end

-- One text value: nil / "" for an optional field come back as nil
local function CleanText(v, f, path)
    if v == nil then v = "" end
    if type(v) ~= "string" then return nil, L["QZ_ERR_DAMAGED"], path end
    v = QuizStore.Trim((v:gsub("\t", " ")))
    if v == "" then
        if f.required then return nil, string.format(L["QZ_ERR_EMPTY"], L[f.label]), path end
        return false   -- empty optional field: leave it out
    end
    local n = QuizStore.TextLength(v)
    if not n then return nil, string.format(L["QZ_ERR_BAD_TEXT"], L[f.label]), path end
    if n > f.max then
        return nil, string.format(L["QZ_ERR_TOO_LONG"], L[f.label], n, f.max), path
    end
    return v
end

local function CleanTime(v, path)
    if type(v) == "string" then v = tonumber(v) end
    if type(v) ~= "number" or not TIME_OK[v] then return nil, L["QZ_ERR_TIME"], path end
    return v
end

local function CleanQuestion(raw, qi, quizTime)
    if type(raw) ~= "table" then return Fail(L["QZ_ERR_DAMAGED"], { q = qi }) end
    local q = {}
    for _, f in ipairs(QUESTION_FIELDS) do
        local v, path = raw[f.key], { q = qi, field = f.key }
        if f.kind == "text" then
            local t, msg = CleanText(v, f, path)
            if t == nil then return Fail(msg, path) end
            q[f.key] = t or nil
        elseif f.kind == "answers" then
            if type(v) ~= "table" then return Fail(L["QZ_ERR_ANSWER_COUNT"], path) end
            local n = #v
            if n < QuizStore.MIN_ANSWERS or n > QuizStore.MAX_ANSWERS then
                return Fail(L["QZ_ERR_ANSWER_COUNT"], path)
            end
            local out = {}
            for ai = 1, n do
                local apath = { q = qi, a = ai }
                local t, msg = CleanText(v[ai], { max = f.max, required = true, label = f.label }, apath)
                if not t then return Fail(msg, apath) end
                out[ai] = t
            end
            q.answers = out
        elseif f.kind == "index" then
            if type(v) ~= "number" or v ~= math.floor(v) or v < 1 or v > #q.answers then
                return Fail(L["QZ_ERR_CORRECT"], path)
            end
            q[f.key] = v
        elseif f.kind == "time" then
            if v ~= nil then
                local t, msg = CleanTime(v, path)
                if not t then return Fail(msg, path) end
                -- the same as the quiz's time = no time of its own, so a quiz
                -- written out and read back comes back the same
                if t ~= quizTime then q[f.key] = t end
            end
        end
    end
    return q
end

function QuizStore.Clean(raw)
    if type(raw) ~= "table" then return Fail(L["QZ_ERR_DAMAGED"]) end
    local quiz = {}
    for _, f in ipairs(QUIZ_FIELDS) do
        local v, path = raw[f.key], { field = f.key }
        if f.kind == "text" then
            local t, msg = CleanText(v, f, path)
            if t == nil then return Fail(msg, path) end
            quiz[f.key] = t or nil
        elseif f.kind == "id" then
            if v ~= nil then
                if type(v) ~= "string" or not v:match("^[%w%-]+$") or #v > 40 then
                    return Fail(L["QZ_ERR_DAMAGED"], path)
                end
                quiz.id = v
            end
        elseif f.kind == "stamp" then
            if v ~= nil then
                if type(v) ~= "number" or v < 0 then return Fail(L["QZ_ERR_DAMAGED"], path) end
                quiz[f.key] = math.floor(v)
            end
        elseif f.kind == "time" then
            if v == nil then
                quiz[f.key] = f.default
            else
                local t, msg = CleanTime(v, path)
                if not t then return Fail(msg, path) end
                quiz[f.key] = t
            end
        elseif f.kind == "questions" then
            if type(v) ~= "table" or #v == 0 then return Fail(L["QZ_ERR_NO_QUESTIONS"], path) end
            if #v > QuizStore.MAX_QUESTIONS then
                return Fail(string.format(L["QZ_ERR_TOO_MANY_Q"], QuizStore.MAX_QUESTIONS),
                    { q = QuizStore.MAX_QUESTIONS + 1 })
            end
            local out = {}
            for qi = 1, #v do
                local q, msg, qpath = CleanQuestion(v[qi], qi, quiz.time)
                if not q then return Fail(msg, qpath) end
                out[qi] = q
            end
            quiz.questions = out
        end
    end
    return quiz
end

--------------------------------------------------------------------------------
-- THE STARTER QUIZ (architecture.md A4): quiz text in Data/StarterQuiz.lua,
-- parsed the first time it is asked for, never stored, read-only. A parse
-- failure here is a bug in the shipped text: said in chat, the quiz left out.
--------------------------------------------------------------------------------
local starter, starterTried

local function Starter()
    if starterTried then return starter end
    starterTried = true
    local text = KHF.STARTER_QUIZ_TEXT
    if type(text) ~= "string" then return nil end
    local quiz, errors = KHF.QuizText.Parse(text)
    if not quiz then
        KHF:Print(string.format(L["STARTER_BROKEN"], tostring(errors and errors[1])))
        return nil
    end
    quiz.id = QuizStore.STARTER_ID
    quiz.author = "Dukul"
    quiz.created, quiz.modified = 0, 0
    starter = quiz
    return starter
end

function QuizStore.IsReadOnly(id)
    return id == QuizStore.STARTER_ID
end

--------------------------------------------------------------------------------
-- READING
--------------------------------------------------------------------------------
local function Saved()
    local db = KHF.quizDB
    if type(db) ~= "table" or type(db.quizzes) ~= "table" then return {} end
    return db.quizzes
end

-- A stored quiz, cleaned on the way out: a saved quiz that no longer passes
-- (hand-edited file, a newer build's shape) is left alone on disk, not shown
local function ReadSaved(id)
    local raw = Saved()[id]
    if raw == nil then return nil end
    local quiz = QuizStore.Clean(raw)
    if quiz then quiz.id = id end
    return quiz
end

function QuizStore.Get(id)
    if id == QuizStore.STARTER_ID then
        local s = Starter()
        return s and KHF.DeepCopy(s)
    end
    if type(id) ~= "string" then return nil end
    return ReadSaved(id)
end

local function Summary(quiz)
    return {
        id = quiz.id, title = quiz.title, tag = quiz.tag, author = quiz.author,
        count = #quiz.questions, modified = quiz.modified or 0,
        readOnly = QuizStore.IsReadOnly(quiz.id),
    }
end

function QuizStore.List()
    local out = {}
    for id in pairs(Saved()) do
        if type(id) == "string" then
            local quiz = ReadSaved(id)
            if quiz then out[#out + 1] = Summary(quiz) end
        end
    end
    -- newest first; the id breaks a tie so the order never jumps
    table.sort(out, function(a, b)
        if a.modified ~= b.modified then return a.modified > b.modified end
        return a.id < b.id
    end)
    local s = Starter()
    if s then table.insert(out, 1, Summary(s)) end
    return out
end

--------------------------------------------------------------------------------
-- WRITING
--------------------------------------------------------------------------------
function QuizStore.CanSave()
    local state = KHF.quizDBState
    if state == "ok" then return true end
    if state == "newer" then return false, L["QZ_ERR_DB_NEWER"] end
    return false, L["QZ_ERR_DB_MISSING"]
end

-- Ids are made once and never reused: "<time>-<4 hex>"
local function NewId()
    local quizzes = Saved()
    local id
    repeat
        id = string.format("%d-%04x", time(), math.random(0, 0xFFFF))
    until quizzes[id] == nil and id ~= QuizStore.STARTER_ID
    return id
end

local function Changed(id, what)
    KHF.SendMessage("QuizzesChanged", id, what)
end

function QuizStore.Create(raw)
    local ok, why = QuizStore.CanSave()
    if not ok then return nil, why end
    local quiz, msg = QuizStore.Clean(raw)
    if not quiz then return nil, msg end
    quiz.id = NewId()
    quiz.author = quiz.author or KHF.UnitKey("player")
    quiz.created = time()
    quiz.modified = quiz.created
    KHF.quizDB.quizzes[quiz.id] = quiz
    Changed(quiz.id, "created")
    return quiz.id
end

-- An edit of a saved quiz: its id, author and created date stay as stored
function QuizStore.Save(raw)
    local ok, why = QuizStore.CanSave()
    if not ok then return nil, why end
    local id = type(raw) == "table" and raw.id
    if QuizStore.IsReadOnly(id) then return nil, L["QZ_ERR_READ_ONLY"] end
    local old = type(id) == "string" and Saved()[id]
    if type(old) ~= "table" then return nil, L["QZ_ERR_NOT_FOUND"] end
    local quiz, msg = QuizStore.Clean(raw)
    if not quiz then return nil, msg end
    quiz.id = id
    quiz.author = old.author
    quiz.created = old.created
    quiz.modified = time()
    KHF.quizDB.quizzes[id] = quiz
    Changed(id, "saved")
    return id
end

function QuizStore.Delete(id)
    local ok, why = QuizStore.CanSave()
    if not ok then return nil, why end
    if QuizStore.IsReadOnly(id) then return nil, L["QZ_ERR_READ_ONLY"] end
    if type(id) ~= "string" or Saved()[id] == nil then return nil, L["QZ_ERR_NOT_FOUND"] end
    KHF.quizDB.quizzes[id] = nil
    Changed(id, "deleted")
    return true
end

-- A copy under a new id, made by you now; the title gets " (copy)" when that
-- still fits the limit
function QuizStore.Duplicate(id)
    local src = QuizStore.Get(id)
    if not src then return nil, L["QZ_ERR_NOT_FOUND"] end
    local title = string.format(L["QUIZ_COPY_TITLE"], src.title)
    if (QuizStore.TextLength(title) or 999) <= TITLE_MAX then src.title = title end
    src.id, src.author, src.created, src.modified = nil, nil, nil, nil
    return QuizStore.Create(src)
end
