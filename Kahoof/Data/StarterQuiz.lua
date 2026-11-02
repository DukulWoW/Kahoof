-- Kahoof Data/StarterQuiz.lua: the starter quiz, shipped read-only (ALL-25)
-- Quiz text (_docs/features/quiz-text-format.md), parsed at the first look by
-- QuizStore (architecture.md A4): every login that opens the list runs the
-- parser on it. Never stored, so an update replaces it. Duplicate it to edit.
-- The same quiz on every client (A12). Plain ASCII only (CLAUDE.md, Code Style).
-- Questions 1-9 by Dukul (2026-11-02), 10 by Claude (Dukul: "You make the last
-- question."). Its master copy is this file; _work/starter-quiz.txt was the draft.

local _, KHF = ...

KHF.STARTER_QUIZ_TEXT = [=[
Quiz: WoW Forever
About: A simple 10 question quiz about WoW Forever.
Tag: Lore
Time: 20

Q: Ragnaros is the lord of which element?
* Fire
- Water
- Earth
- Air
Why: Ragnaros the Firelord rules the Elemental Plane of Fire.

Q: What was the project name for WoW Forever?
- Thebes
* Camelot
- Olympus
- Asgard
Why: Before being announced as WoW Forever, the project was internally known as Project Camelot.

Q: What is the new playable race introduced in WoW Forever?
- Highborne
- Vrykul
* Skyborne
- Ethereals
Why: The Skyborne are a new playable race. They can join either the Horde or Alliance.

Q: What is the starting zone for the Skyborne?
- Mount Hyjal
- Shen'dralas
- Riverglades
* Zephras Isle
Why: Zephras Isle is the Skyborne's new level 1-12 starting zone.

Q: What is the maximum character level in WoW Forever?
- 70
- 80
* 60
- 100
Why: WoW Forever retains the original level 1-60 progression, with no planned level cap increases.

Q: Which new battleground is introduced in WoW Forever?
- Warsong Highlands
- The Broken Shore
* Darkspear Islands
- Zul'Gurub Arena
Why: Darkspear Islands is a new 15-versus-15 battleground located off the coast of Dustwallow Marsh.

Q: Which of these new race and class combinations is available to the Horde?
- Human Hunter
- Dwarf Shaman
* Undead Paladin
- Gnome Priest
Why: WoW Forever introduces the Undead Paladin combination for the Horde.

Q: What is the name of WoW Forever's account-wide progression system?
- Champion's Path
- Azerothian Renown
- Warband Legacy
* Legacy System
Why: The Legacy System provides account-wide horizontal progression through exploration, challenges, perks and rewards.

Q: Which new WoW Forever system lets players build campfires in the open world, where others gather and share buffs?
- Fires of Azeroth
- Resting Grounds
* Camping
- Hearthkeeper
Why: The Camping system lets players craft campfires in the outdoor world where other adventurers can gather, contribute through professions and share campsite buffs.

Q: What is the capital city of the Forsaken?
- Orgrimmar
- Thunder Bluff
- Stormwind
* Undercity
Why: The Forsaken rule from the Undercity, built in the crypts beneath the ruined capital of Lordaeron.
]=]
