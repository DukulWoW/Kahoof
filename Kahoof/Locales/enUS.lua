-- Kahoof Locales/enUS.lua: every player-facing string, English (the default)
-- The proxy KHF.L is made in Init.lua. A key exists here before any code uses
-- it. Translations come after 1.0 (BNB's route): a later locale file sets only
-- the keys it translates. Never spell the addon's name or its slash command:
-- write {name} and {cmd} (Init.lua fills them in from KHF.NAME / KHF.SLASH).

local _, KHF = ...
local L = KHF.L

-- Addon identity
L["ADDON_NAME"]         = "{name}"
L["LOADED_MSG"]         = "v%s loaded (%s). Type {cmd} to open it."   -- %s = version, client name
L["CLIENT_RETAIL"]      = "Retail"
L["CLIENT_FOREVER"]     = "WoW Forever"

-- Shared
L["CLOSE"]              = "Close"
L["CANCEL"]             = "Cancel"
L["RESET"]              = "Reset"
L["SLIDER_DEFAULT"]     = "(Default: %s)"                                   -- %s = the default value

-- Main window tabs
L["TAB_PLAY"]           = "Play"
L["TAB_QUIZZES"]        = "My Quizzes"
L["TAB_HISTORY"]        = "History"
L["TAB_SETTINGS"]       = "Settings"
L["PAGE_PLACEHOLDER"]   = "%s: nothing here yet."   -- %s = tab name

-- The main window's lock button (UI/MainWindow.lua)
L["MW_LOCKED"]          = "Window size is locked"
L["MW_LOCKED_SUB"]      = "Click to allow resizing."
L["MW_UNLOCKED"]        = "Window size is unlocked"
L["MW_UNLOCKED_SUB"]    = "Click to lock it and hide the resize grip."
L["MW_RESET_TIP"]       = "Right-click to put the window back in the middle at its default size."

-- Slash commands
L["SLASH_HELP_TITLE"]   = "Commands:"
L["SLASH_HELP_TOGGLE"]  = "  {cmd} - open or close the window"
L["SLASH_HELP_RESET"]   = "  {cmd} reset - put every window back in the middle of the screen"
L["SLASH_HELP_DEBUG"]   = "  {cmd} debug on | off - debug mode until you reload or log out"
L["SLASH_HELP_VERSION"] = "  {cmd} version [guild] - your version, and who in your group (or guild) has {name}"
L["SLASH_UNKNOWN"]      = "Unknown command: %s. Type {cmd} help."
L["RESET_DONE"]         = "Every window is back in the middle of the screen."
L["DEBUG_ON"]           = "Debug mode on until you reload or log out."
L["DEBUG_OFF"]          = "Debug mode off."
L["VERSION_MSG"]        = "Version %s on %s."   -- %s = version, client name

-- Who has the addon (/kahoof version, S8)
L["VER_ASK_GROUP"]      = "Asking your group who has {name}..."
L["VER_ASK_GUILD"]      = "Asking your guild who has {name}..."
L["VER_GROUP_RESULT"]   = "%d of %d in your group have {name}: %s"     -- %d = with it, group size; %s = names
L["VER_GUILD_RESULT"]   = "%d online in your guild have {name}: %s"   -- %d = with it; %s = names
L["VER_WITHOUT"]        = "Without it: %s"                             -- %s = names
L["VER_ENTRY_OLD"]      = "%s (needs an update)"                       -- %s = name and version
L["VER_NEWER"]          = "A newer version of {name} is out: %s (you have %s)."   -- %s = theirs, yours
L["VER_TOO_SOON"]       = "You asked a moment ago. Try again in a few seconds."
L["VER_HINT"]           = "Not in a group. {cmd} version guild asks your guild."
L["VER_NO_GUILD"]       = "You are not in a guild."

-- Addon messages (Core/Comms.lua, Core/Channels.lua)
L["COMMS_LOCKED"]       = "The game blocks addon messages right now (an encounter, Mythic+ or a PvP match)."
L["COMMS_TRIAL"]        = "Trial accounts cannot send addon messages."
L["COMMS_FAILED"]       = "Could not send (%s)."                       -- %s = the reason code

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
L["FIELD_SHUFFLE"]      = "Shuffle:"

-- Quiz checks (Core/QuizStore.lua)
L["QZ_ERR_EMPTY"]        = "%s is empty."                                     -- %s = field
L["QZ_ERR_TOO_LONG"]     = "%s is too long: %d characters, at most %d."       -- %s = field, %d = length, %d = limit
L["QZ_ERR_BAD_TEXT"]     = "%s holds a character that cannot be shown (a line break or a broken character)."   -- %s = field
L["QZ_ERR_FLAG"]         = "%s must be yes or no."                            -- %s = field
L["QZ_ERR_TIME"]         = "The time limit must be 10, 20, 30, 45 or 60 seconds."
L["QZ_ERR_ANSWER_COUNT"] = "A question needs 2 to 4 answers."
L["QZ_ERR_CORRECT"]      = "A question needs at least one correct answer."
L["QZ_ERR_NO_QUESTIONS"] = "The quiz has no questions."
L["QZ_ERR_TOO_MANY_Q"]   = "A quiz holds at most %d questions."               -- %d = limit
L["QZ_ERR_DAMAGED"]      = "The quiz data is damaged."
L["QZ_ERR_READ_ONLY"]    = "The starter quiz cannot be changed. Duplicate it to make your own."
L["QZ_ERR_NOT_FOUND"]    = "That quiz is gone."
L["QZ_ERR_DB_MISSING"]   = "Quizzes cannot be saved: the addon {name} DB is not loaded."
L["QZ_ERR_DB_NEWER"]     = "Quizzes cannot be saved: they were saved by a newer version of {name}."
L["QUIZ_COPY_TITLE"]     = "%s (copy)"                                         -- %s = title
L["STARTER_BROKEN"]      = "The starter quiz could not be read: %s"            -- %s = first error

-- Quiz text errors (Core/QuizText.lua). The keywords Quiz: Q: Time: etc. stay English
L["QT_ERR_LINE"]             = "Line %d: %s"                                   -- %d = line, %s = message
L["QT_ERR_ONE_STAR"]         = "A question needs at least one correct answer, marked with *."
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
L["QUIZ_DB_MISSING_LINE"] = "{name} DB is not loaded: your quizzes are not shown and nothing can be saved."
L["QUIZ_DB_NEWER_LINE"]  = "Your quizzes were saved by a newer {name}: shown, but nothing can be saved."
L["DB_MISSING_POPUP"]    = "{name}: the addon {name} DB is not loaded.\n\nIt keeps your quizzes. Without it, your quizzes are not shown and nothing you make can be saved. You can still join quizzes and play the starter quiz.\n\nTurn {name} DB on in the AddOns list, or install {name} again."
L["DB_NEWER_POPUP"]      = "{name}: your quizzes were saved by a newer version of {name}.\n\nThis version shows them but will not change them, so nothing is lost. Update {name} to edit them again."
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
L["ED_QUESTION_N"]       = "Question %d of %d"                                 -- %d = number, %d = count
L["ED_ADD_Q"]            = "Add"
L["ED_ADD_TIP"]          = "A new, empty question after this one."
L["ED_DUP_TIP"]          = "A copy of this question, right after it."
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
L["ED_CORRECT"]          = "Correct answer"
L["ED_CORRECT_TIP"]      = "Tick every answer that is correct. More than one may be."
L["ED_CORRECT_HEAD"]     = "Correct"
L["ED_ANSWERS_HEAD"]     = "Answers"
L["ED_SHUFFLE"]          = "Randomize answers"
L["ED_SHUFFLE_TIP"]      = "The answers come in a different order when the quiz runs. The host can still change it when starting."
L["ED_MARKER_TIP"]       = "Click to tick or untick this answer as correct."
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

-- Slash commands and launchers added in S5b
L["SLASH_HELP_LOCK"]     = "  {cmd} lock | unlock - lock or unlock resizing the main window"
L["LOCK_DONE"]           = "Main window size locked."
L["UNLOCK_DONE"]         = "Main window size unlocked."
L["SLASH_HELP_MINIMAP"]  = "  {cmd} minimap - show or hide the minimap button"
L["MINIMAP_LEFT"]        = "Left-click: open or close {name}"
L["MINIMAP_RIGHT"]       = "Right-click: Settings"
L["MINIMAP_HIDDEN"]      = "Minimap button hidden. Type {cmd} minimap to bring it back."
L["MINIMAP_SHOWN"]       = "Minimap button shown."

-- The game's Options > AddOns page (UI/OptionsPanel.lua)
L["OPT_VERSION"]         = "Version: %s"                                    -- %s = version
L["OPT_AUTHOR"]          = "by Dukul"
L["OPT_HINT"]            = "Or type |cffffd100{cmd}|r to open the window."
L["OPT_OPEN"]            = "Open Settings"

-- Key Bindings (Bindings.xml)
L["BIND_ANSWER_1"]       = "Answer Star (1)"
L["BIND_ANSWER_2"]       = "Answer Circle (2)"
L["BIND_ANSWER_3"]       = "Answer Diamond (3)"
L["BIND_ANSWER_4"]       = "Answer Triangle (4)"
L["BIND_SEND"]           = "Send ticked answers"

-- The Play tab (UI/PlayTab.lua)
L["PT_HEAD"]             = "Practice a quiz"
L["PT_INTRO"]            = "Play a quiz on your own: the whole game, with you as the only player."
L["PT_QUIZ"]             = "Quiz"
L["PT_READ"]             = "Read time"
L["PT_READ_NONE"]        = "None: answers at once"
L["PT_READ_MANUAL"]      = "I start the clock"
L["PT_SECONDS"]          = "%d s"                                           -- %d = seconds
L["PT_BOARD"]            = "Leaderboard"
L["PT_BOARD_EACH"]       = "After every question"
L["PT_BOARD_FIVE"]       = "After every 5 questions"
L["PT_BOARD_END"]        = "Only at the end"
L["PT_PICK"]             = "Several correct answers"
L["PT_PICK_ALL"]         = "Pick all of them"
L["PT_PICK_ONE"]         = "Any one counts"
L["PT_PICK_TIP"]         = "For questions with more than one correct answer. Pick all of them: players tick that many, and each wrong tick takes points off. Any one counts: one click, any correct answer is full points."
L["PT_SHUFFLE_TIP"]      = "Shuffle each question's answers when the quiz starts. Starts as the quiz's own setting."
L["PT_AUTO"]             = "Next by itself"
L["PT_AUTO_TIP"]         = "Go on to the next question a few seconds after the reveal or leaderboard, without a click."
L["PT_PRACTICE"]         = "Practice"
L["PT_PRACTICE_TIP"]     = "Play this quiz alone, with these options. Nothing is sent to anyone."
L["PT_HOST_LATER"]       = "Hosting a quiz for your group or guild comes in a later version."

-- The quiz window (UI/QuizWindow.lua, UI/QuizPlay.lua, UI/QuizBoard.lua)
L["QW_LEAVE"]            = "Leave quiz"
L["QW_STOP"]             = "Stop practice"
L["QW_NEXT"]             = "Next"
L["QW_NEXT_TIP"]         = "Show the next question."
L["QW_RESULTS"]          = "Results"
L["QW_END"]              = "End"
L["QW_END_TIP"]          = "End the quiz now and show the results. A question still running is not scored."
L["QW_SKIP"]             = "Skip"
L["QW_SKIP_TIP"]         = "End this question now. Nobody gets points for it."
L["QW_START_CLOCK"]      = "Start the clock"
L["QW_START_CLOCK_TIP"]  = "Show the answers and start the timer."
L["QW_AGAIN"]            = "Play again"
L["QW_MAIN_MENU"]        = "Main Menu"
L["QW_IN_COUNT"]         = "Answered: %d / %d"                              -- %d = answers in, players
L["QW_RUNNING"]          = "Quiz running"
L["QW_RUNNING_TIP"]      = "Click to show the quiz window. Drag to move this button."
L["QW_GET_READY"]        = "Get ready!"
L["QW_ONE_QUESTION"]     = "1 question"
L["QW_N_QUESTIONS"]      = "%d questions"                                   -- %d = count
L["QW_STARTS_IN"]        = "Starting in"                                    -- over the raid countdown number
L["QW_QUESTION_N"]       = "Question %d of %d"                              -- %d = number, count
L["QW_ANSWERS_IN"]       = "Answers in"                                     -- over the raid countdown number
L["QW_WAIT_CLOCK"]       = "Waiting for the host to start the clock."
L["QW_PICK_N"]           = "Pick %d answers"                                -- %d = how many
L["QW_KEYS_ONE"]         = "Keys 1-4 answer."
L["QW_KEYS_MANY"]        = "Keys 1-4 tick, Space sends."
L["QW_ANSWER"]           = "Answer"
L["QW_SENT"]             = "Answer sent. Waiting for the others..."
L["QW_TIMES_UP"]         = "Time's up!"
L["QW_RES_RIGHT"]        = "Correct!"
L["QW_RES_PARTIAL"]      = "Partly right."
L["QW_RES_WRONG"]        = "Wrong."
L["QW_RES_NONE"]         = "No answer."
L["QW_RES_VOID"]         = "Skipped: no points for this question."
L["QW_RES_POINTS"]       = "  +%d points"                                   -- %d = points
L["QW_RES_TIME"]         = "  Your time: %.1f s"                            -- %.1f = seconds
L["QW_PICKED"]           = "%d picked"                                      -- %d = players
L["QW_YOUR_PICK"]        = "Your pick, "
L["QW_WHY"]              = "Why: %s"                                        -- %s = the explanation
L["QW_ENDED"]            = "The quiz has ended."
L["QW_ENDED_HOST"]       = "The host stopped the quiz."
L["QW_BOARD"]            = "Leaderboard"
L["QW_BOARD_AFTER"]      = "After question %d of %d"                        -- %d = number, count
L["QW_SHOW_ALL"]         = "Show all"
L["QW_TOP_TEN"]          = "Top ten"
L["QW_CLIMBER"]          = "Biggest climber: %s, up %d places"              -- %s = name, %d = places
L["QW_CLIMBER_ONE"]      = "Biggest climber: %s, up %d place"               -- %s = name, %d = 1
L["QW_COL_RANK"]         = "#"
L["QW_COL_PLAYER"]       = "Player"
L["QW_COL_POINTS"]       = "Points"
L["QW_COL_CORRECT"]      = "Correct"
L["QW_COL_ACCURACY"]     = "Accuracy"
L["QW_COL_TIME"]         = "Avg. time"
L["QW_OF"]               = "%d / %d"                                        -- %d = correct, played
L["QW_PERCENT"]          = "%d%%"                                           -- %d = percent
L["QW_SECONDS"]          = "%.1f s"                                         -- %.1f = seconds
L["QW_FINAL_YOU"]        = "You finished in place %d of %d with %d points." -- %d = place, players, points
