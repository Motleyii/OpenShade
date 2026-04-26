--============================================================--
-- database.lua
--
-- PURPOSE:
--   Central persistence and world‑data access layer for the
--   game engine. This module owns all loaded world data
--   (rooms, objects, NPCs, players, levels) and provides
--   controlled helper functions for querying, saving, and
--   updating that data.
--
--   database.lua contains no command logic, parsing logic,
--   or presentation logic. It is a pure data and persistence
--   module used by commands, spells, combat, movement, and
--   editors.
--
-- ARCHITECTURAL ROLE:
--   - Single source of truth for world state tables
--   - Owns save/load operations
--   - Provides safe helper accessors for common queries
--   - Encapsulates reset scheduling and timing state
--   - Does not depend on parser, dispatcher, commands, spells,
--     or UI/editor code
--
--============================================================--
--
-- DATA STRUCTURES:
--
-- world.rooms[id]
--   Table of all room definitions and runtime state.
--
-- world.objects[id]
--   Table of all object prototypes and runtime state.
--
-- world.npcs[id]
--   Table of all NPC definitions and runtime state.
--
-- world.players[id]
--   Table of all currently loaded player records.
--
-- levels[level]
--   Table defining level metadata, including gender‑specific
--   level names.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- get_level(player)
--   Returns the level definition table for the given player,
--   based on their current level value.
--
-- get_level_name(player)
--   Returns the gender‑appropriate level name string for the
--   player (male or female), derived from the level table.
--
-- save_players(filename)
--   Persists all currently loaded player data to disk.
--
-- save_objects(filename)
--   Persists all object definitions and state to disk.
--
-- save_rooms(filename)
--   Persists all room definitions and state to disk.
--
-- save_npcs(filename)
--   Persists all NPC definitions and state to disk.
--
-- save_all()
--   Saves all world data (players, rooms, objects, NPCs)
--   in a single operation.
--
-- get_seconds_to_next_reset()
--   Returns the number of seconds remaining until the next
--   scheduled world reset.
--
-- get_minutes_to_next_reset()
--   Returns the number of whole minutes remaining until the
--   next scheduled world reset, rounded up.
--
-- schedule_next_reset()
--   Advances the world reset timer to the next scheduled
--   reset interval.
--
-- reset_world()
--   Performs a full world reset and schedules the next reset.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * All mutation of persistent world state should occur
--     through this module or through well‑defined systems
--     that operate on its tables.
--
--   * No gameplay rules (combat, movement, puzzles) should
--     be implemented here.
--
--   * No user messaging should be handled here.
--
--   * All callers must treat returned tables as authoritative.
--
--============================================================--

local serpent = require("serpent")

local database = {}

database.world = {
    rooms   = {},
    objects = {},
    npcs    = {},
    players = {},
    levels  = {},
    help    = {}
}

-------------------------------------------------
-- Utility helpers
-------------------------------------------------

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do
        r[k] = deepcopy(v)
    end
    return r
end

local function ensure(tbl, field, default)
    if tbl[field] == nil then
        tbl[field] = default
    end
end

-------------------------------------------------
-- Loaders
-------------------------------------------------

function database.load_help(path)
    database.help = dofile(path)
end

function database.load_rooms(path)
    local rooms = dofile(path)
    local count = 0
    for id, room in pairs(rooms) do
        local r = deepcopy(room)

        ensure(r, "flags", {})
        ensure(r, "np", {})

        r.np.state = 0
        r.np.players = {}
        r.np.objects = {}
        r.np.npcs = {}

        -- normalise exits
        ensure(r, "exits", {})
        local dirs = {"n","s","e","w","ne","nw","se","sw","i","o","u","d"}
        for _, d in ipairs(dirs) do
            if r.exits[d] == nil then
                r.exits[d] = nil
            end
        end

        database.world.rooms[id] = r
        count = count + 1
        if (r.flags and r.flags.is_troom) then
            print("Treasure room: " .. r.title .. " (" .. id .. ")")
        end
    end
    print("load_rooms()   count = " .. count)
end

function database.load_objects(path)
    local objects = dofile(path)
    local count = 0
    for id, obj in pairs(objects) do
        local o = deepcopy(obj)

        ensure(o, "flags", {})
        ensure(o, "puzzles", {})
        ensure(o, "np", {})

        o.np.state = 0
        o.np.location = o.home   -- room id or player id later
        o.np.owner = nil         -- player id if carried

        database.world.objects[id] = o

        -- place object in home room
        if database.world.rooms[o.home] then
            database.world.rooms[o.home].np.objects[id] = true
        end

        count = count + 1
    end
    print("load_objects() count = " .. count)
end

function database.load_npcs(path)
    local npcs = dofile(path)
    local count = 0
    for id, npc in pairs(npcs) do
        local n = deepcopy(npc)

        ensure(n, "flags", {})
        ensure(n, "puzzles", {})
        ensure(n, "np", {})

        n.np.state = 0
        n.np.stamina = n.max_stamina
        n.np.path_index = 1
        n.np.location = n.path and n.path[1] or 0

        database.world.npcs[id] = n

        -- place npc
        local room = database.world.rooms[n.np.location]
        if room then
            room.np.npcs[id] = true
        end

        count = count + 1
    end
    print("load_npcs()    count = " .. count)
end

function database.load_players(path)
    local players = dofile(path)
    local count = 0
    for id, ply in pairs(players) do
        database.world.players[id] = deepcopy(ply)
        count = count + 1
    end
    print("load_players() count = " .. count)
end

function database.load_levels(path)
    database.world.levels = dofile(path)
end

-------------------------------------------------
-- Online player initialisation
-------------------------------------------------

function database.init_online_player(player)
    player.np = {
        room = player.home or 1,
        stamina = database.get_level(player).max_stamina,
        score = player.score,
        inventory = {},
        wield = nil,
        fighting = nil,
        frozen_until = 0,
        confused_until = 0,
        dumb_until = 0,
        editor = nil,
        conn = nil,
    }

    local room = database.world.rooms[player.np.room]
    room.np.players[player.id] = true

    return player.np
end

-------------------------------------------------
-- Save players
-------------------------------------------------

function database.save_players(path)
    local out = {}
    for id, ply in pairs(database.world.players) do
        local p = deepcopy(ply)
        p.np = nil
        out[id] = p
    end

    local f = assert(io.open(path, "w"))
    f:write("return " .. require("serpent").block(out, {comment=false}))
    f:close()
end

-------------------------------------------------
-- Level lookup
-------------------------------------------------

function database.get_level(player)
    local score = player.np and player.np.score or player.score
    local lvl = 0
    for i, l in ipairs(database.world.levels) do
        if score >= l.threshold then
            lvl = i
        end
    end
    return database.world.levels[lvl]
end

-------------------------------------------------
-- Return gendered level name for a player
-------------------------------------------------

function database.get_level_name(player)
    if not player or not player.np or not player.flags then
        return "Mysterious"
    end

    local lvl = database.get_level(player)
    if not lvl then
        return "Confused"
    end

    -- default to male form if ismale is missing
    if player.flags.ismale == false then
        return lvl.female or "Unknowable"
    end

    return lvl.male or "Unmentionable"
end

function database.get_level_name_adverb(player)
    if not player or not player.np or not player.flags then
        return "slightly Mysterious"
    end

    local lvl = database.get_level(player)
    if not lvl then
        return "mostly Confused"
    end

    local adverb = ""
    if player.adverb and player.adverb ~= "" then
        adverb = player.adverb .. " "
    end

    -- default to male form if ismale is missing
    if player.flags.ismale == false then
        return (adverb .. lvl.female) or "seemingly Unknowable"
    end

    return (adverb .. lvl.male) or "absolutely Unmentionable"
end

-------------------------------------------------
-- Database writers
-------------------------------------------------

local function ensure_dir(path)
    -- Try POSIX-style mkdir first
    local ok = os.execute('mkdir "' .. path .. '" 2>nul')  -- Windows
    if ok == 0 then return true end

    ok = os.execute('mkdir -p "' .. path .. '" 2>/dev/null') -- Unix
    return ok == 0
end

function database.backup(name, data)
    local dir = "backup"
    if not ensure_dir(dir) then
        print("[WARN] Could not create backup directory: " .. dir)
        return
    end

    local ts = os.date("%Y%m%d-%H%M%S")
    local fname = string.format("%s/%s-%s.lua", dir, name, ts)

    -- Remove runtime state
    local copy = {}
    for k, v in pairs(data) do
        copy[k] = v
        if type(v) == "table" then
            copy[k].np = nil
        end
    end

    local f, err = io.open(fname, "w")
    if not f then
        print("[WARN] Backup failed (" .. fname .. "): " .. tostring(err))
        return
    end

    f:write("return ")
    f:write(serpent.block(copy, { comment = false }))
    f:write("\n")
    f:close()
end

return database
