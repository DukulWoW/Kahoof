-- Kahoof Data/HelpData.lua: the help book's topics (ALL-73)
--
-- EDITABLE: the Help tab of the help book (UI/HelpBook.lua) reads this list,
-- in this order. A topic: { key, title, body }. key never changes (later "?"
-- buttons open a topic by it).
--
-- RULES:
--   - Plain ASCII only (no Unicode quotes, dashes or ellipses: boxes in WoW).
--   - Never spell the addon's name or its slash command: {name} and {cmd}.
--   - Headings inside a body: a line "# Heading". A bullet: a line "- text".
--     A blank line starts a new paragraph. WoW color codes are fine.
--   - US spelling. No em dashes: commas and colons.
-- Translations come after 1.0 (BNB's route): KHF.HELP_LOCALES[locale][key] =
-- { title, body }; a topic without one stays English.

local _, KHF = ...

KHF.HELP_TOPICS = {
    {
        key = "getting-started",
        title = "Getting started",
        body = [[
{name} is a live quiz for your party, raid or guild. A host runs a quiz, everyone with {name} answers timed questions, and the fastest right answers climb the leaderboard.

# Opening {name}
- Type {cmd} (or /khf) to open or close the main window.
- Left-click the minimap button to open it, right-click for Settings.
- It is also in the Addon Compartment, and in Titan Panel or any other broker display.

# The tabs
- Play: the quizzes open in your group, and Join.
- Host: pick a quiz, set it up, open a lobby or practice alone.
- My Quizzes: make, edit, copy and delete your quizzes.
- Settings: switches, the quiz window's size and the sounds.

Nobody needs a website or a server: {name} talks to the other players through the game itself. Everyone who plays needs {name}.
]],
    },
    {
        key = "playing",
        title = "Playing a quiz",
        body = [[
# Joining
When someone in your group opens a quiz, a small invite shows: click Join. You can also join from the Play tab. The host may run a ready check before the start: click Ready.

# Answering
Each question has two to four answers, marked with the raid markers Star, Circle, Diamond and Triangle. Click one, or press 1 to 4.

Some questions have more than one right answer. The host picks how they work: with Any one counts, one click on any right answer is full points; with Pick all of them, you tick your answers and press Send (or Space), and each wrong tick takes points off.

# The keys
- 1 to 4: pick or tick an answer.
- Space: send your ticks.
- The keys work only while a question shows and you are out of combat, so your action bars are never taken in a fight. Turn them off in Settings if you need 1 to 4 between pulls.
- Key Bindings has four {name} entries of its own; those work in combat too.

# The quiz window
Press Escape to hide it: the quiz goes on, and the Quiz running button brings it back. Leave quiz is its own button.
]],
    },
    {
        key = "scoring",
        title = "Points and the leaderboard",
        body = [[
# Points
- A right answer is worth 400 points, plus up to 600 for speed.
- The first second is free: an answer in it gets every speed point. After that the speed points fall evenly to nothing at time up.
- A wrong answer, or none, scores nothing.

# Several right answers
When all right answers are needed, your share is your right ticks minus your wrong ones, out of the right answers. Ticking everything never pays.

# The leaderboard
After the reveal the leaderboard shows the top ten and your own line, and names the biggest climber. Settings can show everyone instead. Equal points: the faster player (counting right answers only) ranks higher. Still equal: the same place.

At the end, the results show everyone with their points, right answers, accuracy and average time.
]],
    },
    {
        key = "hosting",
        title = "Hosting a quiz",
        body = [[
# Setting up
On the Host tab pick a quiz, then:
- Read time: how long the question shows before the answers open.
- Leaderboard: after every question, after every 5 questions, or only at the end.
- Several right answers: Any one counts, or Pick all of them.
- Randomize answers: the answers in a new order for every question.
- Next by itself: the quiz moves on without you pressing Next.
- I play too: you answer as well, in your own slot.

# The lobby
Open lobby tells your group that a quiz is open. Players join, you see who is in, and Ready check asks everyone to confirm. Start begins the quiz.

# During the quiz
The host window sits next to the quiz window: Next, Pause, Redo (play the question again) and Stop. Drag it away to place it on its own; the lock icon docks it again.

You own the clock, the questions and every score: the players only send their answers.
]],
    },
    {
        key = "practice",
        title = "Practice mode",
        body = [[
Practice plays a quiz on your own: the whole game with a group of one. Pick a quiz on the Host tab and click Practice.

Use it to try a quiz you just wrote before you run it for real.
]],
    },
    {
        key = "making-quizzes",
        title = "Making quizzes",
        body = [[
# My Quizzes
New starts an empty quiz; Edit, Duplicate and Delete work on the one you pick. The starter quiz that comes with {name} cannot be changed, but you can duplicate it.

# The editor
- A quiz has a title and up to 50 questions.
- A question has two to four answers and at least one right answer: tick each one that is right.
- Time limit: 10, 20, 30, 45 or 60 seconds.
- An explanation is optional: everyone sees it at the reveal.

Save keeps your changes, Cancel (or Escape) leaves without them.

# Where they are kept
Your quizzes live in the companion addon {name}_DB, so an update of {name} can never take them. Keep it enabled.
]],
    },
    {
        key = "settings-sounds",
        title = "Settings and sounds",
        body = [[
# Sounds
Each moment of the quiz can play a sound of your choice: pick it on the Settings tab, and Play lets you hear it. None means silence. Sounds from any LibSharedMedia sound pack show up in the lists too.

# Volume
The game gives addons no volume of their own: {name}'s sounds play on one of the game's sound channels. Pick a channel in Settings, then set that channel's volume in the game's own Sound settings. Ambience or Dialog are good picks if you want {name} quieter than the rest of the game.

# Reduce motion
Stops the shaking clock, the popping numbers and the counting leaderboard.
]],
    },
    {
        key = "commands",
        title = "Commands",
        body = [[
- {cmd}: open or close the main window.
- {cmd} guide: open this book.
- {cmd} version: your version, and who in your group has {name}. {cmd} version guild asks your guild.
- {cmd} minimap: show or hide the minimap button.
- {cmd} lock and {cmd} unlock: lock or unlock resizing the main window.
- {cmd} reset: put every window back in the middle of the screen.
- {cmd} help: the commands in chat.
]],
    },
}
