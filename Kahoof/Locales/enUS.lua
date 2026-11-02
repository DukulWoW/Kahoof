-- Kahoof Locales/enUS.lua: every player-facing string, English (the default)
-- The proxy KHF.L is made in Init.lua. A key exists here before any code uses
-- it. Translations come after 1.0 (BNB's route): a later locale file sets only
-- the keys it translates.

local _, KHF = ...
local L = KHF.L

-- Addon identity
L["ADDON_NAME"]         = "Kahoof"
L["LOADED_MSG"]         = "v%s loaded (%s). Type /kahoof to open it."   -- %s = version, client name
L["CLIENT_RETAIL"]      = "Retail"
L["CLIENT_FOREVER"]     = "WoW Forever"

-- Shared
L["CLOSE"]              = "Close"
L["CANCEL"]             = "Cancel"

-- Main window tabs
L["TAB_PLAY"]           = "Play"
L["TAB_QUIZZES"]        = "My Quizzes"
L["TAB_HISTORY"]        = "History"
L["TAB_SETTINGS"]       = "Settings"
L["PAGE_PLACEHOLDER"]   = "%s: nothing here yet."   -- %s = tab name

-- Slash commands
L["SLASH_HELP_TITLE"]   = "Commands:"
L["SLASH_HELP_TOGGLE"]  = "  /kahoof - open or close the window"
L["SLASH_HELP_RESET"]   = "  /kahoof reset - put every window back in the middle of the screen"
L["SLASH_HELP_DEBUG"]   = "  /kahoof debug on | off - debug mode until you reload or log out"
L["SLASH_HELP_VERSION"] = "  /kahoof version - show the version"
L["SLASH_UNKNOWN"]      = "Unknown command: %s. Type /kahoof help."
L["RESET_DONE"]         = "Every window is back in the middle of the screen."
L["DEBUG_ON"]           = "Debug mode on until you reload or log out."
L["DEBUG_OFF"]          = "Debug mode off."
L["VERSION_MSG"]        = "Version %s on %s."   -- %s = version, client name

-- Launchers
L["COMPARTMENT_TIP"]    = "Click to open or close the window."

-- Quiz fields, as named in error lines ("the title is too long")
L["FIELD_TITLE"]        = "The title"
L["FIELD_ABOUT"]        = "The description"
L["FIELD_TAG"]          = "The tag"
L["FIELD_AUTHOR"]       = "The author"
L["FIELD_QUESTION"]     = "The question"
L["FIELD_ANSWER"]       = "An answer"
L["FIELD_WHY"]          = "The explanation"

-- Quiz checks (Core/QuizStore.lua)
L["QZ_ERR_EMPTY"]        = "%s is empty."                                     -- %s = field
L["QZ_ERR_TOO_LONG"]     = "%s is too long: %d characters, at most %d."       -- %s = field, %d = length, %d = limit
L["QZ_ERR_BAD_TEXT"]     = "%s holds a character that cannot be shown (a line break or a broken character)."   -- %s = field
L["QZ_ERR_TIME"]         = "The time limit must be 10, 20, 30, 45 or 60 seconds."
L["QZ_ERR_ANSWER_COUNT"] = "A question needs 2 to 4 answers."
L["QZ_ERR_CORRECT"]      = "A question needs one correct answer."
L["QZ_ERR_NO_QUESTIONS"] = "The quiz has no questions."
L["QZ_ERR_TOO_MANY_Q"]   = "A quiz holds at most %d questions."               -- %d = limit
L["QZ_ERR_DAMAGED"]      = "The quiz data is damaged."
L["QZ_ERR_READ_ONLY"]    = "The starter quiz cannot be changed. Duplicate it to make your own."
L["QZ_ERR_NOT_FOUND"]    = "That quiz is gone."
L["QZ_ERR_DB_MISSING"]   = "Quizzes cannot be saved: the addon Kahoof_DB is not loaded."
L["QZ_ERR_DB_NEWER"]     = "Quizzes cannot be saved: they were saved by a newer version of Kahoof."
L["QUIZ_COPY_TITLE"]     = "%s (copy)"                                         -- %s = title
L["STARTER_BROKEN"]      = "The starter quiz could not be read: %s"            -- %s = first error

-- Quiz text errors (Core/QuizText.lua). The keywords Quiz: Q: Time: etc. stay English
L["QT_ERR_LINE"]             = "Line %d: %s"                                   -- %d = line, %s = message
L["QT_ERR_ONE_STAR"]         = "A question needs exactly one correct answer, marked with *."
L["QT_ERR_ANSWER_NO_Q"]      = "An answer needs a Q: line above it."
L["QT_ERR_WHY_NO_Q"]         = "Why: needs a Q: line above it."
L["QT_ERR_TOO_MANY_ANSWERS"] = "A question has at most %d answers."            -- %d = limit
L["QT_ERR_TWICE"]            = "%s is given twice."                            -- %s = keyword
L["QT_ERR_HEADER_AFTER_Q"]   = "%s belongs before the first Q: line."          -- %s = keyword
L["QT_ERR_UNKNOWN"]          = "Not a quiz line. Start it with Q:, * or - or a keyword (Quiz:, About:, Tag:, Time:, Why:)."

-- My Quizzes tab (UI/QuizzesTab.lua)
L["QUIZ_COUNT"]          = "%d questions"                                      -- %d = count
L["QUIZ_COUNT_ONE"]      = "1 question"
L["QUIZ_STARTER"]        = "Starter quiz"
L["QUIZ_BY"]             = "by %s"                                             -- %s = author
L["QUIZ_DUPLICATE"]      = "Duplicate"
L["QUIZ_DELETE"]         = "Delete"
L["QUIZ_NEW"]            = "New quiz"
L["QUIZ_EDIT"]           = "Edit"
L["QUIZ_DELETE_CONFIRM"] = "Delete the quiz \"%s\"? This cannot be undone."   -- %s = title
L["QUIZ_NONE_YET"]       = "Your own quizzes show up here. Press New quiz to write one, or duplicate the starter quiz."
L["QUIZ_DB_MISSING_LINE"] = "Kahoof_DB is not loaded: your quizzes are not shown and nothing can be saved."
L["QUIZ_DB_NEWER_LINE"]  = "Your quizzes were saved by a newer Kahoof: shown, but nothing can be saved."
L["DB_MISSING_POPUP"]    = "Kahoof: the addon Kahoof_DB is not loaded.\n\nIt keeps your quizzes. Without it, your quizzes are not shown and nothing you make can be saved. You can still join quizzes and play the starter quiz.\n\nTurn Kahoof_DB on in the AddOns list, or install Kahoof again."
L["DB_NEWER_POPUP"]      = "Kahoof: your quizzes were saved by a newer version of Kahoof.\n\nThis version shows them but will not change them, so nothing is lost. Update Kahoof to edit them again."
L["OK"]                  = "OK"

-- The quiz editor (UI/QuizEditor.lua, Core/QuizDraft.lua)
L["ED_BACK"]             = "Back"
L["ED_TITLE"]            = "Title"
L["ED_TAG"]              = "Tag"
L["ED_TIME"]             = "Time"
L["ED_ABOUT"]            = "About"
L["ED_WHY"]              = "Why"
L["ED_SAVE"]             = "Save"
L["ED_SAVED"]            = "Saved."
L["ED_NOT_SAVED"]        = "Not saved: %s"                                     -- %s = the reason
L["ED_ERR_Q"]            = "Question %d: %s"                                   -- %d = question number, %s = the problem
L["ED_ERR_CORRECT_EMPTY"] = "The answer marked correct is empty."
L["ED_QUESTION_N"]       = "Question %d of %d"                                 -- %d = number, %d = count
L["ED_ADD_Q"]            = "Add question"
L["ED_UP"]               = "Up"
L["ED_DOWN"]             = "Down"
L["ED_EMPTY_Q"]          = "(empty)"
L["ED_Q_HINT"]           = "Type the question here"
L["ED_ANSWER_HINT"]      = "Answer"
L["ED_ANSWER_OPT_HINT"]  = "Answer (optional)"
L["ED_WHY_HINT"]         = "Optional: shown to everyone after the answer"
L["ED_TIME_QUIZ"]        = "Quiz time (%d s)"                                  -- %d = seconds
L["ED_TIME_N"]           = "%d s"                                              -- %d = seconds
L["ED_COUNT"]            = "%d / %d characters"                                -- %d = typed, %d = limit
L["ED_MARKER_TIP"]       = "Click to make this the correct answer."
L["ED_LEAVE_CONFIRM"]    = "Leave the editor? Your changes are not saved."
L["ED_DISCARD"]          = "Discard"
L["ED_KEEP_EDITING"]     = "Keep editing"

-- The quiz engine (Core/Host.lua, Core/Practice.lua)
L["ENG_ERR_RUNNING"]     = "A quiz is already running. Leave it first."
L["ENG_ERR_PLAYERS"]     = "A quiz needs 1 to 40 players."

-- The answer markers (raid target icons), in answer order
L["MARKER_1"]            = "Star"
L["MARKER_2"]            = "Circle"
L["MARKER_3"]            = "Diamond"
L["MARKER_4"]            = "Triangle"
