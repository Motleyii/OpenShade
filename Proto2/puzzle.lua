--============================================================--
-- puzzle.lua
--
-- PURPOSE:
--   Rule-based environmental interaction and world logic system.
--   This module implements puzzles: conditional verb handlers
--   that allow rooms, objects, and NPCs to respond dynamically
--   to player actions based on argument grammar, world state,
--   and declarative test/effect expressions.
--
--   Puzzles are evaluated before normal commands and spells
--   and may intercept player input when their conditions match.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Defines how puzzle entries are matched and evaluated
--   - Parses input using explicit argspec grammar
--   - Executes puzzle tests and effects in a safe environment
--   - Emits success or failure messages
--   - Integrates with rooms, objects, and NPC definitions
--
--   puzzle.lua contains no input parsing logic of its own
--   beyond calling parser.parse_with_argspec().
--
--============================================================--
--
-- PUZZLE ENTRY STRUCTURE:
--
--   Each puzzle entry is a table with the following fields:
--
--     verb
--       The verb string this puzzle responds to (e.g. "turn",
--       "pull", "push"). Must match the parsed input verb.
--
--     argspec
--       A string defining the argument grammar for this puzzle.
--       Uses the same argspec language as commands and spells:
--       # $ & @  = object, npc, player, room
--       g        = global resolution
--       ?        = optional argument
--       *        = rest-of-input
--
--     test (optional)
--       A Lua expression string evaluated in the puzzle test
--       environment. If omitted, the puzzle always matches.
--       Must return true for the puzzle to succeed.
--
--     effect (optional)
--       A Lua expression string evaluated in the puzzle effect
--       environment when the puzzle succeeds.
--
--     psucc / pfail
--       Message sent to the acting player on success/failure.
--
--     rsucc / rfail
--       Message sent to other players in the room on
--       success/failure.
--
--     asucc / afail
--       Message broadcast globally on success/failure.
--
--     wsucc / wfail
--       Optional world-level ambient messages.
--
--============================================================--
--
-- TEST ENVIRONMENT:
--
--   The `test` expression is evaluated with access to the
--   following helper functions and bindings:
--
--     ARG
--       Array of resolved argument references.
--
--     ID(n)
--       Returns the numeric ID of argument n.
--
--     IS_OBJ(n), IS_NPC(n), IS_PLAYER(n), IS_ROOM(n)
--       Type checks for the nth argument.
--
--     HERE(n)
--       Returns true if the nth argument is present in the
--       player’s current room.
--
--     OWNED(n)
--       Returns true if the nth argument (object) is in the
--       player’s inventory.
--
--     O_STATE(n), N_STATE(n), R_STATE(n)
--       Returns the numeric state of an object, NPC, or room.
--
--     STAT(n, key)
--       Returns a static attribute of the nth argument
--       (e.g. value, weight, power).
--
--     TRUE()
--       Convenience function that always returns true.
--
--============================================================--
--
-- EFFECT ENVIRONMENT:
--
--   The `effect` expression is evaluated with access to all
--   test helpers plus the following world-mutating functions:
--
--     O_INC(n), O_DEC(n), O_RESET(n), O_SET(n, value)
--       Modify object state.
--
--     N_INC(n), N_DEC(n), N_RESET(n), N_SET(n, value)
--       Modify NPC state.
--
--     R_INC(n), R_DEC(n), R_RESET(n), R_SET(n, value)
--       Modify room state.
--
--     MOVE(n, room_id)
--       Moves an object, NPC, or player to another room.
--
--     RESPAWN(n)
--       Sends an object back to one of its respawn locations.
--
--     SCORE(value)
--       Modifies the acting player’s score.
--
--     SEND(n, text)
--       Sends a private message to a target player.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- emit_messages(player, puzzle, success)
--   Sends the appropriate success or failure messages defined
--   by the puzzle entry.
--
-- build_env(player, parsed)
--   Constructs the execution environment used by puzzle
--   test and effect expressions.
--
-- eval_expr(expr, env)
--   Safely evaluates a Lua expression in the given environment
--   and returns the result.
--
-- try_puzzle(player, raw_input, puzzle)
--   Attempts to parse and evaluate a single puzzle entry.
--   Returns true if the puzzle matched and consumed the input.
--
-- process(player, raw_input)
--   Entry point for the puzzle system. Tests all applicable
--   room, object, and NPC puzzles in order and returns true
--   if any puzzle handled the input.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * Puzzle matching is strict: if argspec parsing fails,
--     the puzzle does not apply.
--
--   * Puzzles are evaluated before standard commands, which allows
--     overloading of command verbs.
--
--   * The parser and dispatcher are not aware of puzzles.
--
--   * All puzzle expressions are sandboxed via build_env().
--
--   * Puzzle behavior is purely declarative; no procedural
--     puzzle logic should live outside of this module.
--
--============================================================--

local db     = require("database")
local msg    = require("messaging")
local parser = require("parser")

local Puzzle = {}

-------------------------------------------------
-- Puzzle function registries (authoritative)
-------------------------------------------------

local PUZZLE_TEST_REGISTRY = {
    {
        name = "TRUE",
        sig  = "TRUE()",
        fn   = function() return true end,
    },
    {
        name = "IS_OBJ",
        sig  = "IS_OBJ($n)",
        fn   = function(env, n) return env._tag(n) == "#" end,
    },
    {
        name = "IS_NPC",
        sig  = "IS_NPC($n)",
        fn   = function(env, n) return env._tag(n) == "$" end,
    },
    {
        name = "IS_PLAYER",
        sig  = "IS_PLAYER($n)",
        fn   = function(env, n) return env._tag(n) == "&" end,
    },
    {
        name = "IS_ROOM",
        sig  = "IS_ROOM($n)",
        fn   = function(env, n) return env._tag(n) == "@" end,
    },
    {
        name = "HERE",
        sig  = "HERE($n)",
        fn   = function(env, n)
            local t = env._tag(n)
            if t == "#" then return env._obj(n).np.location == env._room end
            if t == "$" then return env._npc(n).np.location == env._room end
            if t == "&" then return env._player(n).np.room == env._room end
            return false
        end,
    },
    {
        name = "OWNED",
        sig  = "OWNED($n)",
        fn   = function(env, n)
            return env._tag(n) == "#" and env._inv[env._id(n)] == true
        end,
    },
    {
        name = "O_STATE",
        sig  = "O_STATE($n)",
        fn   = function(env, n) return env._obj(n).np.state or 0 end,
    },
    {
        name = "N_STATE",
        sig  = "N_STATE($n)",
        fn   = function(env, n) return env._npc(n).np.state or 0 end,
    },
    {
        name = "R_STATE",
        sig  = "R_STATE(@room)",
        fn   = function(env, n) return env._roomobj(n).np.state or 0 end,
    },
    {
        name = "STAT",
        sig  = "STAT($n, key)",
        fn   = function(env, n, key)
            local t = env._tag(n)
            if t == "#" then return env._obj(n)[key] end
            if t == "$" then return env._npc(n)[key] end
            if t == "&" then return env._player(n)[key] end
            return nil
        end,
    },
}

local PUZZLE_EFFECT_REGISTRY = {
    {
        name = "O_INC",
        sig  = "O_INC($n)",
        fn   = function(env, n)
            local o = env._obj(n)
            o.np.state = (o.np.state or 0) + 1
        end,
    },
    {
        name = "O_DEC",
        sig  = "O_DEC($n)",
        fn   = function(env, n)
            local o = env._obj(n)
            o.np.state = (o.np.state or 0) - 1
        end,
    },
    {
        name = "O_RESET",
        sig  = "O_RESET($n)",
        fn   = function(env, n)
            env._obj(n).np.state = 0
        end,
    },
    {
        name = "N_INC",
        sig  = "N_INC($n)",
        fn   = function(env, n)
            local e = env._npc(n)
            e.np.state = (e.np.state or 0) + 1
        end,
    },
    {
        name = "R_SET",
        sig  = "R_SET(@room, value)",
        fn   = function(env, room_id, v)
            env._roomobj_raw(room_id).np.state = v
        end,
    },
    {
        name = "MOVE",
        sig  = "MOVE($n, room_id)",
        fn   = function(env, n, rid)
            local t = env._tag(n)
            if t == "#" then env._obj(n).np.location = rid
            elseif t == "$" then env._npc(n).np.location = rid end
        end,
    },
    {
        name = "RESPAWN",
        sig  = "RESPAWN($n)",
        fn   = function(env, n)
            local o = env._obj(n)
            if not o or not o.np then return end

            local id = env._id(n)
            if env._inv[id] then
                env._inv[id] = nil
            end

            if o.respawn and #o.respawn > 0 then
                o.np.location = o.respawn[1]
            else
                o.np.location = 0
            end
        end,
    },
    {
        name = "SEND",
        sig  = "SEND($n, text)",
        fn   = function(env, n, text)
            env._msg(env._player(n), text)
        end,
    },
    {
        name = "SCORE",
        sig  = "SCORE(value)",
        fn   = function(env, v)
            env._score(v)
        end,
    },
}

-------------------------------------------------
-- Message emission (success / failure)
-------------------------------------------------

local function emit_messages(player, entry, success)
    if success then
        if entry.psucc then msg.to_player(player, entry.psucc) end
        if entry.rsucc then msg.to_room(player.np.room, entry.rsucc, player.id) end
        if entry.asucc then msg.to_world(entry.asucc) end
        if entry.wsucc then msg.to_world(entry.wsucc) end
    else
        if entry.pfail then msg.to_player(player, entry.pfail) end
        if entry.rfail then msg.to_room(player.np.room, entry.rfail, player.id) end
        if entry.afail then msg.to_world(entry.afail) end
        if entry.wfail then msg.to_world(entry.wfail) end
    end
end

-------------------------------------------------
-- Puzzle execution environment
-------------------------------------------------

-------------------------------------------------
-- Puzzle execution environment (authoritative)
-------------------------------------------------

local function build_env(player, parsed)
    local ARG = parsed.args or {}

    -------------------------------------------------
    -- Low-level helpers (internal)
    -------------------------------------------------

    local function tag(n)
        local a = ARG[n]
        return a and a:sub(1, 1)
    end

    local function id(n)
        local a = ARG[n]
        return a and tonumber(a:sub(2))
    end

    local function obj(n)
        return db.world.objects[id(n)]
    end

    local function npc(n)
        return db.world.npcs[id(n)]
    end

    local function plyr(n)
        return db.world.players[id(n)]
    end

    local function room(n)
        return db.world.rooms[id(n)]
    end

    -------------------------------------------------
    -- Environment table exposed to puzzle code
    -------------------------------------------------

    local env = {
        -------------------------------------------------
        -- Core bindings (not exposed directly)
        -------------------------------------------------
        _ARG      = ARG,
        _tag      = tag,
        _id       = id,
        _obj      = obj,
        _npc      = npc,
        _player   = plyr,
        _roomobj  = room,              -- from @room argument
        _room     = player.np.room,    -- current room id
        _inv      = player.np.inventory,
        _msg      = msg.to_player,
        _score    = function(v) player.np.score = player.np.score + v end,
    }

    -------------------------------------------------
    -- Public helpers (usable in TEST and EFFECT)
    -------------------------------------------------

    env.ARG = ARG
    env.ID  = function(n) return id(n) end

    -------------------------------------------------
    -- Register TEST functions from registry
    -------------------------------------------------

    for _, entry in ipairs(PUZZLE_TEST_REGISTRY) do
        env[entry.name] = function(...)
            return entry.fn(env, ...)
        end
    end

    -------------------------------------------------
    -- Register EFFECT functions from registry
    -------------------------------------------------

    for _, entry in ipairs(PUZZLE_EFFECT_REGISTRY) do
        env[entry.name] = function(...)
            return entry.fn(env, ...)
        end
    end

    -------------------------------------------------
    -- Built-in predicates that are small enough to
    -- inline (still first-class language features)
    -------------------------------------------------

    env.TRUE = function()
        return true
    end

    env.IS_OBJ = function(n) return tag(n) == "#" end
    env.IS_NPC = function(n) return tag(n) == "$" end
    env.IS_PLAYER = function(n) return tag(n) == "&" end
    env.IS_ROOM = function(n) return tag(n) == "@" end

    env.HERE = function(n)
        local t = tag(n)
        if t == "#" then
            return obj(n) and obj(n).np.location == env._room
        elseif t == "$" then
            return npc(n) and npc(n).np.location == env._room
        elseif t == "&" then
            return plyr(n) and plyr(n).np.room == env._room
        end
        return false
    end

    env.OWNED = function(n)
        return tag(n) == "#" and env._inv[id(n)] == true
    end

    -------------------------------------------------
    -- STATE accessors (numeric state machine)
    -------------------------------------------------

    env.O_STATE = function(n)
        local o = obj(n)
        return o and o.np and o.np.state or 0
    end

    env.N_STATE = function(n)
        local e = npc(n)
        return e and e.np and e.np.state or 0
    end

    env.R_STATE = function(n)
        local r = room(n)
        return r and r.np and r.np.state or 0
    end

    -------------------------------------------------
    -- World effects not tied to registries
    -- (still part of the puzzle language)
    -------------------------------------------------

    env.MOVE = function(n, dest)
        local t = tag(n)
        if t == "#" then
            obj(n).np.location = dest
        elseif t == "$" then
            npc(n).np.location = dest
        elseif t == "&" then
            plyr(n).np.room = dest
        end
    end

    env.RESPAWN = function(n)
        local o = obj(n)
        if not o or not o.np then return end

        if env._inv[id(n)] then
            env._inv[id(n)] = nil
        end

        if o.respawn and #o.respawn > 0 then
            o.np.location = o.respawn[1]
        else
            o.np.location = 0
        end
    end

    env.SEND = function(n, text)
        local p = plyr(n)
        if p and p.np then
            msg.to_player(p, text)
        end
    end

    env.SCORE = function(v)
        env._score(v)
    end

    -------------------------------------------------
    -- Final environment
    -------------------------------------------------

    return env
end

-------------------------------------------------
-- Expression evaluation
-------------------------------------------------

local function eval_expr(expr, env)
    local fn, err = load("return " .. expr, "puzzle", "t", env)
    if not fn then return false end
    local ok, result = pcall(fn)
    if not ok then return false end
    return result
end

-------------------------------------------------
-- Try a single puzzle entry
-------------------------------------------------

local function try_puzzle(player, raw, entry)
    if not entry.verb or not entry.argspec then
        return false
    end

    local parsed = parser.parse_with_argspec(player, raw, entry.argspec)
    if not parsed or parsed.verb ~= entry.verb then
        return false
    end

    local env = build_env(player, parsed)

    local success = true
    if entry.test then
        success = eval_expr(entry.test, env)
    end

    emit_messages(player, entry, success)

    if success and entry.effect then
        eval_expr(entry.effect, env)
    end

    return success
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function Puzzle.process(player, raw)
    local room = db.world.rooms[player.np.room]

    for _, pz in ipairs(room.puzzles or {}) do
        if try_puzzle(player, raw, pz) then return true end
    end

    for oid in pairs(room.np.objects or {}) do
        local o = db.world.objects[oid]
        for _, pz in ipairs(o.puzzles or {}) do
            if try_puzzle(player, raw, pz) then return true end
        end
    end

    for nid in pairs(room.np.npcs or {}) do
        local n = db.world.npcs[nid]
        for _, pz in ipairs(n.puzzles or {}) do
            if try_puzzle(player, raw, pz) then return true end
        end
    end

    return false
end

return Puzzle