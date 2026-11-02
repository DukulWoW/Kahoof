-- Kahoof Core/Database.lua: SavedVariables, defaults, schema versions
--
--   KahoofDB         account    settings, window positions
--   KahoofQuizzesDB  account    quizzes (by id); owned by the companion addon
--                               Kahoof_DB, see InitQuizDB
--   KahoofCharDB     character  rejoin record, host resume state (ALL-16 / ALL-17)
--
-- SCHEMA VERSIONS (data.md): each DB has a dbVersion, written with math.max so
-- an older build never lowers it. A migration is a guarded block in that DB's
-- Migrate function, `if v < N then ... v = N end`, listed in CLAUDE.md
-- (DB Schema) with its date. A new SETTING is never a migration: it is one line
-- in KHF.DEFAULTS, read through KHF.GetSetting.

local _, KHF = ...

local SETTINGS_VERSION = 1
local QUIZZES_VERSION  = 1
local CHAR_VERSION     = 1

-- Every setting and its default. Nested tables are merged key by key.
KHF.DEFAULTS = {
    -- Window placement: center point in screen pixels (scale-safe) and size.
    -- Empty = centered at the default size. /kahoof reset empties them.
    windows = {
        main = {},
    },
    mainTab = 1,   -- the main window's last tab (1 Play, 2 My Quizzes, 3 History, 4 Settings)
}

local QUIZZES_DEFAULTS = {
    quizzes = {},
}

local CHAR_DEFAULTS = {}

-- Fills every nil key of db from def. A nested table is merged key by key, so
-- a saved table keeps its values and only gains the keys it lacks; a saved
-- value is never replaced, whatever its type.
local function ApplyDefaults(db, def)
    for k, v in pairs(def) do
        if db[k] == nil then
            db[k] = KHF.DeepCopy(v)
        elseif type(v) == "table" and type(db[k]) == "table" then
            ApplyDefaults(db[k], v)
        end
    end
end

-- Migrations. None yet; the first one goes in like this:
--   if v < 2 then
--       ...transform...
--       v = 2
--   end
local function MigrateSettings(db)
    local v = db.dbVersion or 1   -- luacheck: ignore (read by the first migration)
end

local function MigrateQuizzes(db)
    local v = db.dbVersion or 1   -- luacheck: ignore
end

local function MigrateChar(db)
    local v = db.dbVersion or 1   -- luacheck: ignore
end

-- One SavedVariable: a new table starts at the current version (nothing to
-- migrate). Migrations run before the defaults, so a migration that moves an
-- old key into a new one finds the new key still empty.
local function InitDB(name, defaults, version, migrate)
    local db = _G[name]
    if type(db) ~= "table" then
        db = { dbVersion = version }
        _G[name] = db   -- luacheck: ignore 122 (the SavedVariable, named in the TOC)
    end
    migrate(db)
    ApplyDefaults(db, defaults)
    db.dbVersion = math.max(db.dbVersion or 1, version)
    return db
end

-- KahoofQuizzesDB belongs to the companion addon Kahoof_DB (its own file, so
-- nothing that happens to Kahoof's settings can take the quizzes along). It
-- loads before Kahoof (OptionalDeps), so it is either loaded by now or absent.
-- KHF.quizDBState:
--   "ok"       loaded at a version this code knows: read and write
--   "missing"  Kahoof_DB not loaded: an empty table in memory, never saved;
--              every write is refused (QuizStore), a popup says why
--   "newer"    saved by a newer Kahoof (dbVersion above QUIZZES_VERSION): read,
--              never written, never migrated or defaulted, so an old build can
--              not damage data it does not understand (data.md)
local function InitQuizDB()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Kahoof_DB")
    if not loaded then
        KHF.quizDBState = "missing"
        KHF.quizDB = { dbVersion = QUIZZES_VERSION, quizzes = {} }
        return
    end
    local db = KahoofQuizzesDB
    if type(db) == "table" and type(db.dbVersion) == "number" and db.dbVersion > QUIZZES_VERSION then
        KHF.quizDBState = "newer"
        KHF.quizDB = db
        return
    end
    KHF.quizDB = InitDB("KahoofQuizzesDB", QUIZZES_DEFAULTS, QUIZZES_VERSION, MigrateQuizzes)
    KHF.quizDBState = "ok"
end

-- Called from Core/Events.lua at ADDON_LOADED
function KHF.InitializeDB()
    KHF.db     = InitDB("KahoofDB", KHF.DEFAULTS, SETTINGS_VERSION, MigrateSettings)
    KHF.charDB = InitDB("KahoofCharDB", CHAR_DEFAULTS, CHAR_VERSION, MigrateChar)
    InitQuizDB()
end

--------------------------------------------------------------------------------
-- SETTINGS
--------------------------------------------------------------------------------
-- The saved value, or the default when there is none (or the DB is not loaded)
function KHF.GetSetting(key)
    local db = KHF.db
    if db and db[key] ~= nil then return db[key] end
    return KHF.DEFAULTS[key]
end

function KHF.SetSetting(key, value)
    if not KHF.db then return end
    KHF.db[key] = value
    KHF.SendMessage("SettingChanged", key, value)
end

-- /kahoof reset: every window back to centered at its default size
function KHF.ResetWindows()
    if not KHF.db then return end
    KHF.db.windows = KHF.DeepCopy(KHF.DEFAULTS.windows)
    KHF.SendMessage("WindowsReset")
end
