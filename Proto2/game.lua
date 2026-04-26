--============================================================--
-- game.lua
--
-- PURPOSE:
--   Top-level game runtime controller and bootstrap module.
--   This file coordinates initialization, player input
--   handling, command dispatch, subsystem wiring, and
--   periodic world updates such as resets.
--
--   game.lua acts as the central orchestrator of the engine,
--   but contains no low-level gameplay logic itself. Instead,
--   it delegates responsibilities to parser, commands, spells,
--   wizard commands, combat, movement, database, and editors.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Bootstraps and wires together core subsystems
--   - Injects dependencies where required (e.g. REPL into wizard)
--   - Receives raw player input and initiates parsing
--   - Dispatches parsed input to wizard, spell, or command handlers
--   - Drives the main game loop
--   - Triggers and schedules world resets
--   - Emits global system messages
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- init()
--   Performs one-time initialization of the game engine.
--   Loads world data, initializes timers, wires subsystems,
--   and schedules the first world reset.
--
-- wire_subsystems()
--   Performs dependency injection between modules that must
--   communicate at runtime without direct require coupling
--   (e.g. injecting REPL entry points into wizard commands).
--
-- handle_player_input(player, input)
--   Entry point for all player-issued commands.
--   Parses raw input, resolves arguments using argspec,
--   and dispatches the command to wizard, spell, or
--   standard command handlers in priority order.
--
-- dispatch_parsed_command(player, parsed)
--   Routes a parsed command to the appropriate subsystem
--   (wizard, spells, or commands) and returns whether it
--   was handled.
--
-- game_tick()
--   Called periodically from the main loop.
--   Advances timers, resolves combat rounds, and checks
--   whether a world reset should occur.
--
-- schedule_next_reset()
--   Computes and stores the next scheduled world reset time
--   based on the configured reset interval.
--
-- check_world_reset()
--   Determines whether the current time has reached the
--   next reset threshold and triggers a reset if required.
--
-- reset_world()
--   Performs a full world reset by delegating to database
--   and reset helpers, then schedules the next reset.
--
-- player_login(player)
--   Handles player login initialization, including welcome
--   messages, reset countdown display, and initial room
--   description.
--
-- player_logout(player)
--   Cleans up player state and performs any required
--   persistence or shutdown logic.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * game.lua sits at the highest level of the engine.
--     It may require lower-level modules, but no core
--     subsystem should require game.lua.
--
--   * All command grammar and argument resolution occurs
--     in parser.lua before dispatch.
--
--   * All persistence and world mutation occurs via
--     database.lua and well-defined subsystems.
--
--   * This module intentionally contains coordination
--     logic only, not gameplay rules.
--
--============================================================--

local db        = require("database")
local parser    = require("parser")
local puzzle    = require("puzzle")
local commands  = require("commands")
local spells    = require("spells")
local wizard    = require("wizard")
local combat    = require("combat")
local msg       = require("messaging")
local repl      = require("repl")
local Movement  = require("movement")
local serpent   = require("serpent")

local G = {}

wizard.inject_repl(repl)

-------------------------------------------------
-- Configuration
-------------------------------------------------

G.TICK_INTERVAL = 1        -- seconds
G.NPC_TICK = 5             -- movement / aggression

G.RESET_INTERVAL = 3600    -- full reset every hour
G.RESET_WARNING_START = 600    -- 10 minutes
G.RESET_WARNING_STEP = 60      -- every minute

local reset_start_time = os.time()

local next_reset_time = reset_start_time + G.RESET_INTERVAL
local last_warning_time = nil
local reset_triggered = false

-------------------------------------------------
-- Time tracking
-------------------------------------------------

local last_tick = os.time()
local last_npc_tick = os.time()
local last_reset = os.time()

-------------------------------------------------
-- Movement handler
-------------------------------------------------

local DIRECTION_ALIASES = {
    north   = "n", northeast = "ne", northwest = "nw",
    south   = "s", southeast = "se", southwest = "sw",
    east    = "e", west      = "w",
    up      = "u", down      = "d",
    ["in"]  = "i", out       = "o",
}

-------------------------------------------------
-- Player command handling
-------------------------------------------------

function G.handle_player_input(player, input)
    if not input or input == "" then return end

    local parsed = parser.parse(player, input)
    if not parsed then
        msg.to_player(player, "Huh?")
        return
    end

print("handle_player_input: " .. serpent.line(parsed))

    -------------------------------------------------
    -- COMMAND PRECEDENCE
    -------------------------------------------------

    -- Wizard commands
    if wizard.handle(player, parsed) then return end

    -- Editors (placeholder routing)
    if player.np.editor then
        repl.handle(player, input)
        return
    end

    -- Local puzzles
    if puzzle.process(player, parsed) then return end

    -- Spells
    if spells.handle(player, parsed) then return end

    -- Standard commands
    if commands.handle(player, parsed) then return end

    msg.to_player(player, "Huh?")
end

-------------------------------------------------
-- NPC logic
-------------------------------------------------

function G.npc_tick()
    for _, npc in pairs(db.world.npcs) do
        if npc.speed and npc.speed > 0 then
            npc.np.move_counter = (npc.np.move_counter or 0) + G.NPC_TICK
            if npc.np.move_counter >= npc.speed then
                npc.np.move_counter = 0

                local old_room = npc.np.location
                if npc.path and #npc.path > 0 then
                    npc.np.path_index = (npc.np.path_index % #npc.path) + 1
                    local new_room = npc.path[npc.np.path_index]

                    if db.world.rooms[new_room] then
                        db.world.rooms[old_room].np.npcs[npc.id] = nil
                        npc.np.location = new_room
                        db.world.rooms[new_room].np.npcs[npc.id] = true

                        msg.to_room(old_room, npc.leaves)
                        msg.to_room(new_room, npc.enters)
                    end
                end
            end
        end

        -- aggression
        if npc.flags and npc.flags.isaggressive then
            local room = db.world.rooms[npc.np.location]
            for pid in pairs(room.np.players) do
                local p = db.world.players[pid]
                if p and not p.np.fighting then
                    combat.start_fight(
                        {type="npc", id=npc.id},
                        {type="player", id=p.id},
                        "npc"
                    )
                    break
                end
            end
        end
    end
end

-------------------------------------------------
-- Cleanup disconnected or dead players
-------------------------------------------------

function G.cleanup()
    for _, p in pairs(db.world.players) do
        if p.np and p.np.conn and p.np.conn.closed then
            local r = db.world.rooms[p.np.room]
            if r then r.np.players[p.id] = nil end
            p.score = p.np.score
            p.np = nil
        end
    end
end

-------------------------------------------------
-- Periodic world reset hook
-------------------------------------------------

function G.reset_if_needed()
    if os.time() - last_reset > G.RESET_INTERVAL then
        msg.to_world("** The world fades... then reforms. **")
        last_reset = os.time()
        -- actual reload handled by server.lua
    end
end

function G.trigger_reset()
    -- stop accepting further commands
    G.suspended = true

    -- server.lua owns the reset
    if G.on_reset then
        G.on_reset()
    end
end

function G.reset()
    reset_start_time = os.time()
    next_reset_time = reset_start_time + G.RESET_INTERVAL
    last_warning_time = nil
    reset_triggered = false
    G.suspended = false
end

local function check_reset_schedule()
    if reset_triggered then return end

    local now = os.time()
    local remaining = next_reset_time - now

    -- First warning at T-10
    if remaining <= G.RESET_WARNING_START and not last_warning_time then
        msg.to_world(
            "You hear a loud, ominous bell tolling in the distance - I would hurry up if I was you!"
        )
        last_warning_time = now
    end

    -- Repeat every minute
    if last_warning_time and remaining > 0 and now - last_warning_time >= G.RESET_WARNING_STEP then
        msg.to_world("The sound of the bell tolling is getting louder!")
        last_warning_time = now
    end

    -- Trigger reset
    if remaining <= 0 then
        reset_triggered = true
        msg.to_world("The world becomes shrouded in mist and everything goes dark...")
        G.trigger_reset()
    end
end

-- Returns seconds until next reset (>= 0)
function G.get_minutes_to_next_reset()
    local now = os.time()
    local seconds = math.max(0, next_reset_time - now)
    return math.ceil(seconds / 60)
end

-------------------------------------------------
-- Main game tick
-------------------------------------------------

function G.tick()
    local now = os.time()

    if now - last_tick >= G.TICK_INTERVAL then
        last_tick = now

        -- combat progresses every tick
        combat.tick()

        G.cleanup()
    end

    if now - last_npc_tick >= G.NPC_TICK then
        last_npc_tick = now
        G.npc_tick()
    end

    check_reset_schedule()
    G.reset_if_needed()
end

return G