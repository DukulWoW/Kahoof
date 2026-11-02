-- Kahoof Core/QuizText.lua: the readable quiz text, parsed and written
-- Format: _docs/features/quiz-text-format.md. Line by line with plain string
-- functions, never loadstring (data.md). The keywords (Quiz: About: Tag: Time:
-- Shuffle: Q: Why:) are a file format: English on every client, never localized; the
-- error lines are localized like every other string.
--
--   QuizText.Parse(text) -> quiz | nil, { "Line 14: ...", ... }
--   QuizText.Write(quiz) -> text
--
-- Parse finds the layout errors (all of them, up to MAX_ERRORS), then hands the
-- quiz to QuizStore.Clean for types and limits; Clean's one error is turned back
-- into a line number. Nothing is returned until the whole text is clean.

local _, KHF = ...
local L = KHF.L

local QuizText = {}
KHF.QuizText = QuizText

local MAX_ERRORS = 10

-- Keywords, lower case (matched case-insensitively). HEADER = before the first
-- Q:, QUESTION = after one. Time: is both: the quiz default, or one question's.
local HEADER   = { quiz = "title", about = "about", tag = "tag", time = "time", shuffle = "shuffle" }
local QUESTION = { time = "time", why = "why" }
-- The keyword as it is written, for error lines
local SPELLING = { quiz = "Quiz:", about = "About:", tag = "Tag:", time = "Time:", why = "Why:", q = "Q:",
                   shuffle = "Shuffle:" }

-- "Time: 20" and "Time: 20s" both mean 20; anything else is left as text so
-- Clean refuses it with its own line
local function ReadTime(v)
    return tonumber(v:match("^(%d+)%s*[sS]?$") or "") or v
end

-- "Shuffle: yes" / "no" (also on / off, true / false); anything else is left
-- as text so Clean refuses it with its own line
local YES = { yes = true, on = true, ["true"] = true, no = false, off = false, ["false"] = false }
local function ReadFlag(v)
    local b = YES[v:lower()]
    if b == nil then return v end
    return b
end

function QuizText.Parse(text)
    local Trim = KHF.QuizStore.Trim
    if type(text) ~= "string" then return nil, { L["QZ_ERR_DAMAGED"] } end
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end   -- a BOM from a file

    local quiz = { questions = {} }
    local where = { questions = {} }   -- line numbers, for Clean's errors
    local errors = {}
    local q, qw                        -- the question being read, and its lines
    local stars                        -- * answers in it

    local function Err(n, msg)
        if #errors < MAX_ERRORS then
            errors[#errors + 1] = string.format(L["QT_ERR_LINE"], n, msg)
        end
    end
    -- at least one * per question (ALL-33), checked when the question ends
    local function EndQuestion()
        if q and stars < 1 then Err(qw.line, L["QT_ERR_ONE_STAR"]) end
    end

    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        line = Trim(line)
        local first = line:sub(1, 1)
        if line == "" or line:sub(1, 2) == "//" then
            -- blank or a comment
        elseif first == "*" or first == "-" then
            -- an answer: the marker, then one optional space, then the text as is
            -- ("- -5 degrees" is the wrong answer "-5 degrees")
            if not q then
                Err(n, L["QT_ERR_ANSWER_NO_Q"])
            elseif #q.answers >= KHF.QuizStore.MAX_ANSWERS then
                Err(n, string.format(L["QT_ERR_TOO_MANY_ANSWERS"], KHF.QuizStore.MAX_ANSWERS))
            else
                local a = line:sub(2):gsub("^ ", "")
                q.answers[#q.answers + 1] = a
                qw.answers[#q.answers] = n
                if first == "*" then
                    stars = stars + 1
                    q.correct = q.correct or {}
                    q.correct[#q.correct + 1] = #q.answers
                end
            end
        else
            -- keyword lines. Keywords are ASCII letters, so lower() is safe on them
            local word, value = line:match("^([A-Za-z]+)%s*:(.*)$")
            local key = word and word:lower()
            value = value and Trim(value)
            if key == "q" then
                EndQuestion()
                q = { text = value, answers = {} }
                qw = { line = n, answers = {} }
                stars = 0
                quiz.questions[#quiz.questions + 1] = q
                where.questions[#quiz.questions] = qw
            elseif q and QUESTION[key] then
                local field = QUESTION[key]
                if qw[field] then
                    Err(n, string.format(L["QT_ERR_TWICE"], SPELLING[key]))
                else
                    q[field] = (field == "time") and ReadTime(value) or value
                    qw[field] = n
                end
            elseif q and HEADER[key] then
                Err(n, string.format(L["QT_ERR_HEADER_AFTER_Q"], SPELLING[key]))
            elseif not q and HEADER[key] then
                local field = HEADER[key]
                if where[field] then
                    Err(n, string.format(L["QT_ERR_TWICE"], SPELLING[key]))
                else
                    if field == "time" then
                        quiz[field] = ReadTime(value)
                    elseif field == "shuffle" then
                        quiz[field] = ReadFlag(value)
                    else
                        quiz[field] = value
                    end
                    where[field] = n
                end
            elseif not q and key == "why" then
                Err(n, L["QT_ERR_WHY_NO_Q"])
            else
                Err(n, L["QT_ERR_UNKNOWN"])
            end
        end
    end
    EndQuestion()
    if #errors > 0 then return nil, errors end

    local clean, msg, path = KHF.QuizStore.Clean(quiz)
    if clean then return clean end
    -- Clean's path back to a line: an answer, a question's field, the question,
    -- a header field; no line at all for a missing title or no questions
    -- (where.questions and w.answers are lists, not lines: only numbers count)
    local function num(x) return type(x) == "number" and x or nil end
    local line
    if path.q then
        local w = where.questions[path.q]
        if w then line = (path.a and num(w.answers[path.a])) or (path.field and num(w[path.field])) or w.line end
    elseif path.field then
        line = num(where[path.field])
    end
    return nil, { line and string.format(L["QT_ERR_LINE"], line, msg) or msg }
end

-- The quiz back as text: what Parse reads gives the same quiz again (the
-- offline tests check it). Header lines only when set; a question's Time: only
-- when it differs from the quiz's.
function QuizText.Write(quiz)
    local out = {}
    local function add(s) out[#out + 1] = s end
    add("Quiz: " .. quiz.title)
    if quiz.about then add("About: " .. quiz.about) end
    if quiz.tag then add("Tag: " .. quiz.tag) end
    add("Time: " .. (quiz.time or KHF.QuizStore.DEFAULT_TIME))
    if quiz.shuffle then add("Shuffle: yes") end
    for _, q in ipairs(quiz.questions or {}) do
        add("")
        add("Q: " .. q.text)
        local right = {}
        for _, i in ipairs(type(q.correct) == "table" and q.correct or { q.correct }) do right[i] = true end
        for i, a in ipairs(q.answers) do
            add((right[i] and "* " or "- ") .. a)
        end
        if q.time and q.time ~= quiz.time then add("Time: " .. q.time) end
        if q.why then add("Why: " .. q.why) end
    end
    return table.concat(out, "\n") .. "\n"
end
