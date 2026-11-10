-- Kahoof Data/FeatureListData.lua: the help book's Features tab (ALL-73)
--
-- EDITABLE: one section per entry, shown in this order.
--   header  section title
--   blurb   one paragraph (2-4 sentences)
--   items   bullet list, one feature per line
--   help    optional: help topic keys (Data/HelpData.lua), shown as links
-- Rules as in HelpData.lua: plain ASCII, {name} / {cmd}, US spelling, no em
-- dashes. Keep it in step with the README and the help topics.

local _, KHF = ...

KHF.FEATURE_LIST = {
    {
        header = "Live quizzes",
        help   = { "playing", "scoring" },
        blurb  = "Timed multiple choice for your party or raid, with points for speed and a leaderboard between questions. No website, no server: everything goes through the game.",
        items  = {
            "Two to four answers per question, marked with the raid markers",
            "Questions with more than one right answer",
            "400 points for a right answer, up to 600 more for speed",
            "A leaderboard with the top ten, your own line and the biggest climber",
            "Results with points, right answers, accuracy and average time",
            "Answer with the keys 1 to 4 and Space, out of combat; Key Bindings for in combat",
        },
    },
    {
        header = "Hosting",
        help   = { "hosting", "practice" },
        blurb  = "The host runs the quiz: the clock, the questions and every score. Set it up, open a lobby, check who is ready and start.",
        items  = {
            "A lobby with an invite for everyone in your group",
            "Ready check before the start",
            "Read time, leaderboard rhythm, randomized answers, next by itself",
            "Pause, redo a question, stop",
            "Play your own quiz too, in your own slot",
            "Practice mode: the whole game on your own",
        },
    },
    {
        header = "Your quizzes",
        help   = { "making-quizzes" },
        blurb  = "Write your own quizzes in the game. They are kept by the companion addon {name}_DB, so an update can never take them.",
        items  = {
            "Up to 50 questions per quiz",
            "Time limits of 10, 20, 30, 45 or 60 seconds",
            "An explanation for the reveal",
            "A starter quiz to try and to copy",
        },
    },
    {
        header = "Settings and sounds",
        help   = { "settings-sounds" },
        blurb  = "A sound for every moment of the quiz, from {name}'s own, the game's, or any LibSharedMedia pack.",
        items  = {
            "Sounds on or off, and the game channel they play on",
            "A countdown tick for the last five seconds",
            "Quiz window scale, reduce motion, answer keys on or off",
            "Minimap button, Addon Compartment and broker launcher (Titan Panel and others)",
        },
    },
}
