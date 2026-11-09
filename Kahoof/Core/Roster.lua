-- Kahoof Core/Roster.lua: the lobby's player list, slots and ready marks (S9)
-- Pure: no game calls, so it is tested offline (test_lobby.lua).
--
-- The host's side: who joined, in which slot (1-40, the lowest free one),
-- who was removed (a removed player cannot rejoin this session: game-engine.md),
-- each player's ready mark, and what changed since the last ROSTER went out.
-- The changes go out at most every 2 s (networking.md: ROSTER is batched);
-- a batch with a new player in it is sent as the FULL list, so the newcomer
-- learns everyone already there. Leaves and ready marks go as changes only.
--
-- Lobby slots are the lobby's own: at Start the players are numbered 1..n in
-- slot order and START carries the slots the quiz uses.
--
-- Ready marks: nil = no check run, 0 = not ready, 1 = ready, 2 = asked, no
-- answer yet. A player who joins during a check is ready (joining is being
-- ready, ALL-64).
--
--   Roster.New(max)                 -> r
--   Roster.Add(r, key)              -> slot | nil, "removed" | "full"
--   Roster.Remove(r, key, ban)      -> the slot it had, or nil
--   Roster.Slot(r, key) / Roster.Count(r) / Roster.Keys(r) (slot order)
--   Roster.StartCheck(r)            every mark to 2 (asked)
--   Roster.EndCheck(r)              ends the check; the marks stay as they are
--   Roster.SetReady(r, key, on)     -> true when the mark changed
--   Roster.Dirty(r)                 -> true when a ROSTER is owed
--   Roster.Flush(r)                 -> full (1 / 0), rows: what the ROSTER carries
--   Roster.Rows(r)                  -> every row (the full list)
--   Roster.Apply(list, full, rows)  the player's side: -> the new list, or nil
--                                   when changes came before any full list.
--                                   list = { [slot] = { name, ready } }

local _, KHF = ...

local Roster = {}
KHF.Roster = Roster

function Roster.New(max)
    return { max = max or 40, bySlot = {}, byKey = {}, banned = {}, changed = {}, added = false, check = false }
end

function Roster.Slot(r, key) return r.byKey[key] end

function Roster.Count(r)
    local n = 0
    for _ in pairs(r.bySlot) do n = n + 1 end
    return n
end

function Roster.Keys(r)
    local out = {}
    for slot = 1, r.max do
        local p = r.bySlot[slot]
        if p then out[#out + 1] = p.key end
    end
    return out
end

function Roster.Add(r, key)
    if r.banned[key] then return nil, "removed" end
    local have = r.byKey[key]
    if have then
        r.changed[have] = true   -- a repeated JOIN (the accept was lost): say it again
        r.added = true
        return have
    end
    for slot = 1, r.max do
        if not r.bySlot[slot] then
            -- joining during a check counts as ready (joining is being ready)
            r.bySlot[slot] = { key = key, ready = r.check and 1 or nil }
            r.byKey[key] = slot
            r.changed[slot] = true
            r.added = true
            return slot
        end
    end
    return nil, "full"
end

function Roster.Remove(r, key, ban)
    if ban then r.banned[key] = true end
    local slot = r.byKey[key]
    if not slot then return nil end
    r.bySlot[slot], r.byKey[key] = nil, nil
    r.changed[slot] = true
    return slot
end

function Roster.StartCheck(r)
    r.check = true
    for slot, p in pairs(r.bySlot) do
        p.ready = 2
        r.changed[slot] = true
    end
end

function Roster.EndCheck(r)
    r.check = false
end

function Roster.SetReady(r, key, on)
    local slot = r.byKey[key]
    local p = slot and r.bySlot[slot]
    if not p or not r.check then return false end
    local v = on and 1 or 0
    if p.ready == v then return false end
    p.ready = v
    r.changed[slot] = true
    return true
end

function Roster.Dirty(r) return next(r.changed) ~= nil end

local function Row(r, slot)
    local p = r.bySlot[slot]
    if p then return { slot = slot, name = p.key, ready = p.ready } end
    return { slot = slot, name = "" }
end

function Roster.Rows(r)
    local rows = {}
    for slot = 1, r.max do
        if r.bySlot[slot] then rows[#rows + 1] = Row(r, slot) end
    end
    return rows
end

function Roster.Flush(r)
    local full, rows
    if r.added then
        full, rows = 1, Roster.Rows(r)
    else
        full, rows = 0, {}
        for slot = 1, r.max do
            if r.changed[slot] then rows[#rows + 1] = Row(r, slot) end
        end
    end
    r.changed, r.added = {}, false
    return full, rows
end

function Roster.Apply(list, full, rows)
    if full == 1 then
        list = {}
    elseif not list then
        return nil   -- changes to a list we never had: wait for a full one
    end
    for _, row in ipairs(rows or {}) do
        if row.slot >= 1 and row.slot <= 40 then
            if row.name == "" then
                list[row.slot] = nil
            else
                list[row.slot] = { name = row.name, ready = row.ready }
            end
        end
    end
    return list
end
