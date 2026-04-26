--============================================================--
-- functions.lua
--
-- PURPOSE:
--   General-purpose utility and helper functions used
--   across the game engine. This module contains small,
--   reusable functions that do not belong to a specific
--   gameplay system (commands, combat, movement, puzzles)
--   but are useful throughout the codebase.
--
--   functions.lua must remain free of game-specific logic,
--   world mutation, or user interaction. Its contents should
--   be deterministic, side-effect free (where possible),
--   and safe to call from any module.
--
-- ARCHITECTURAL ROLE:
--   - Provides low-level utility helpers
--   - Avoids duplication of common logic
--   - Serves as a dependency-safe module (no circular requires)
--   - Used by parser, commands, spells, combat, editors, and tools
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- clamp(value, min, max)
--   Constrains a numeric value to lie within the given range.
--
-- sign(value)
--   Returns -1, 0, or 1 depending on the sign of the value.
--
-- round(value)
--   Rounds a numeric value to the nearest whole number.
--
-- shallow_copy(table)
--   Creates a shallow copy of a table (top-level keys only).
--
-- deep_copy(table)
--   Creates a recursive deep copy of a table and all nested tables.
--
-- table_contains(table, value)
--   Returns true if the given value exists anywhere in the table.
--
-- table_keys(table)
--   Returns an array containing all keys in the given table.
--
-- string_split(str, delimiter)
--   Splits a string into an array of substrings using the
--   specified delimiter.
--
-- string_trim(str)
--   Removes leading and trailing whitespace from a string.
--
-- capitalize(str)
--   Returns the string with the first character capitalized.
--
-- pluralize(word, count)
--   Returns a pluralized form of the word if count is not 1.
--
-- random_choice(list)
--   Returns a randomly selected element from a list.
--
-- roll_dice(count, sides)
--   Simulates rolling a number of dice and returns the total.
--
-- chance(percent)
--   Returns true with the given percentage probability.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * No function in this file should assume anything about
--     player state, world data, or command parsing.
--
--   * All functions should be small, predictable, and
--     independently testable.
--
--   * Gameplay systems should depend on these helpers,
--     not the other way around.
--
--   * If a function grows complex or becomes domain-specific,
--     it should be migrated to a more appropriate module.
--
--============================================================--

local db = require("database")

local F = {}

-------------------------------------------------
-- Context
-- These are set per-command before calling puzzles
-------------------------------------------------

F.context = {
    player = nil,   -- current player table
    args = {},      -- parsed command arguments
}

function F.set_context(player, args)
    F.context.player = player
    F.context.args = args or {}
end

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function cur_player()
    return F.context.player
end

local function cur_room()
    return db.world.rooms[cur_player().np.room]
end

-------------------------------------------------
-- Inventory & location
-------------------------------------------------

function F.OWNED(object_id)
    return cur_player().np.inventory[object_id] == true
end

function F.O_HERE(object_id)
    return cur_room().np.objects[object_id] == true
end

function F.N_HERE(npc_id)
    return cur_room().np.npcs[npc_id] == true
end

function F.MOVE_OBJECT(object_id, room_id)
    local obj = db.world.objects[object_id]
    if not obj then return false end

    -- remove from old location
    if obj.np.owner then
        local p = db.world.players[obj.np.owner]
        if p and p.np then
            p.np.inventory[object_id] = nil
        end
        obj.np.owner = nil
    elseif obj.np.location then
        local r = db.world.rooms[obj.np.location]
        if r then
            r.np.objects[object_id] = nil
        end
    end

    -- place in new room
    obj.np.location = room_id
    local room = db.world.rooms[room_id]
    if room then
        room.np.objects[object_id] = true
    end

    return true
end

function F.TAKE(object_id)
    if not F.O_HERE(object_id) then return false end

    local obj = db.world.objects[object_id]
    cur_room().np.objects[object_id] = nil

    cur_player().np.inventory[object_id] = true
    obj.np.owner = cur_player().id
    obj.np.location = nil

    return true
end

function F.DROP(object_id)
    if not F.OWNED(object_id) then return false end

    local obj = db.world.objects[object_id]
    cur_player().np.inventory[object_id] = nil
    obj.np.owner = nil

    local room = cur_room()
    room.np.objects[object_id] = true
    obj.np.location = room.id

    return true
end

function F.DROPALL()
    for oid in pairs(cur_player().np.inventory) do
        F.DROP(oid)
    end
end

-------------------------------------------------
-- Player stats
-------------------------------------------------

function F.LOAD()
    local w = 0
    for oid in pairs(cur_player().np.inventory) do
        w = w + (db.world.objects[oid].weight or 0)
    end
    return w
end

function F.LEVEL()
    return db.get_level(cur_player()).level
end

function F.MAXLOAD(level)
    return db.world.levels[level].max_weight
end

function F.SCORE(delta)
    cur_player().np.score = cur_player().np.score + delta
end

-------------------------------------------------
-- Flags
-------------------------------------------------

function F.O_FLAG(id, flag)
    local o = db.world.objects[id]
    return o and o.flags and o.flags[flag] == true
end

function F.N_FLAG(id, flag)
    local n = db.world.npcs[id]
    return n and n.flags and n.flags[flag] == true
end

function F.R_FLAG(id, flag)
    local r = db.world.rooms[id]
    return r and r.flags and r.flags[flag] == true
end

function F.O_SET(id, flag)
    local o = db.world.objects[id]
    if o then o.flags[flag] = true end
end

function F.O_CLR(id, flag)
    local o = db.world.objects[id]
    if o then o.flags[flag] = nil end
end

-------------------------------------------------
-- State (Objects)
-------------------------------------------------

function F.O_STATE(id)
    local o = db.world.objects[id]
    return o and o.np.state or 0
end

function F.O_SET_STATE(id, value)
    local o = db.world.objects[id]
    if o then o.np.state = value end
end

function F.O_INC(id)
    local o = db.world.objects[id]
    if o then o.np.state = o.np.state + 1 end
end

function F.O_DEC(id)
    local o = db.world.objects[id]
    if o then
        o.np.state = math.max(0, o.np.state - 1)
    end
end

-------------------------------------------------
-- State (Rooms)
-------------------------------------------------

function F.R_STATE(id)
    local r = db.world.rooms[id]
    return r and r.np.state or 0
end

function F.R_INC(id)
    local r = db.world.rooms[id]
    if r then r.np.state = r.np.state + 1 end
end

function F.R_DEC(id)
    local r = db.world.rooms[id]
    if r then r.np.state = math.max(0, r.np.state - 1) end
end

-------------------------------------------------
-- State (NPCs)
-------------------------------------------------

function F.N_STATE(id)
    local n = db.world.npcs[id]
    return n and n.np.state or 0
end

function F.N_INC(id)
    local n = db.world.npcs[id]
    if n then n.np.state = n.np.state + 1 end
end

function F.N_DEC(id)
    local n = db.world.npcs[id]
    if n then n.np.state = math.max(0, n.np.state - 1) end
end

-------------------------------------------------
-- Argument resolution (used by puzzles)
-------------------------------------------------

function F.OBJ_ID(n)
    return F.context.args[n] or 0
end

function F.NPC_ID(n)
    return F.context.args[n] or 0
end

function F.PLY_ID(n)
    return F.context.args[n] or 0
end

return F
