-- Kahoof Data/PatchNotesData.lua: the help book's Patch notes tab (ALL-73)
--
-- EDITABLE: one entry per release, newest first. The top one is the release
-- in the making until it ships (_work/unreleased.md is the source; the
-- release routine copies it here).
--   version  must match the TOC's ## Version
--   date     "YYYY-MM-DD", or nil while unreleased
--   entries  one line each, starting "New:", "Change:" or "Fixed:" (the tab
--            colors the label); a line for one client only is a table:
--            { forever = true, "..." } or { retail = true, "..." }
-- Rules as in HelpData.lua: plain ASCII, {name} / {cmd}, US spelling.

local _, KHF = ...

KHF.PATCH_NOTES = {
    {
        version = "0.1.0",
        date    = nil,
        entries = {
            "New: The first version of {name}: live quizzes for your party and raid, a lobby with invites and a ready check, a leaderboard and results.",
            "New: My Quizzes: write your own quizzes in the game, kept safe by {name}_DB.",
            "New: Practice mode: play a quiz on your own.",
            "New: {cmd} version shows who in your group has {name} and which version ({cmd} version guild asks your guild).",
            "New: Settings: sounds for every moment of the quiz, from {name}, the game or any LibSharedMedia pack, and the channel they play on.",
            "New: The help book: help, features and patch notes, from the Help button or {cmd} guide.",
        },
    },
}
