--============================================================--
-- combat.lua
--
-- PURPOSE:
--   Centralized combat system for the game engine.
--   This module manages all aspects of combat, including
--   initiating fights, resolving attacks, applying damage,
--   handling combat states, and managing combat termination.
--
--   combat.lua contains NO parsing or command logic.
--   It operates purely on resolved entities (players, NPCs,
--   objects) and is invoked by higher-level systems such as
--   commands, spells, and world events.
--
-- DESIGN PRINCIPLES:
--   - Combat logic is deterministic and server-authoritative
--   - No direct player I/O (all messaging via messaging.lua)
--   - Stateless helpers where possible; state stored on entities
--   - Safe to call repeatedly from the game loop
--   - No editor or parser dependencies
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- start_combat(attacker, defender)
--   Begins combat between two entities.
--   Sets combat state on both attacker and defender and
--   registers them as opponents.
--
-- is_in_combat(entity)
--   Returns true if the entity is currently engaged in combat.
--
-- get_opponent(entity)
--   Returns the entity this combatant is currently fighting
--   or nil if not engaged.
--
-- resolve_combat_round(entity)
--   Resolves a single combat round for the given entity.
--   Called from the main game loop or combat scheduler.
--
-- perform_attack(attacker, defender)
--   Calculates hit/miss, determines damage, applies special
--   effects, and sends combat messages.
--
-- calculate_hit(attacker, defender)
--   Determines whether the attack hits based on skills,
--   stats, equipment, and combat modifiers.
--
-- calculate_damage(attacker, defender)
--   Computes raw damage for a successful hit before
--   mitigation and resistances.
--
-- apply_damage(defender, amount)
--   Applies damage to the defender, updating hit points
--   and triggering death if HP reaches zero.
--
-- handle_death(entity, killer)
--   Handles entity death: messaging, corpse creation,
--   combat cleanup, and state transitions.
--
-- stop_combat(entity)
--   Terminates combat for the given entity and clears
--   all combat-related state.
--
-- flee_combat(entity)
--   Attempts to disengage the entity from combat and
--   move them to a valid exit if successful.
--
-- set_berserk(entity, state)
--   Enables or disables berserk mode, modifying combat
--   stats and behavior accordingly.
--
--============================================================--

local db  = require("database")
local msg = require("messaging")

local Combat = {}

-------------------------------------------------
-- Combat messages sent to players on successful hit
-------------------------------------------------

local msg_attacker = {
    "%p almost knocks you out with a crushing blow!",
    "%plands a blow.....you reel dizzily!",
    "%p makes a vicious slash at your head!",
    "%p presses home the attack with savage fury!",
    "%p rushes in, hacking crazily!",
    "%p slips past your defence and lands a fearsome blow!",
    "%p snarls and swings wildly at your head."
    }

local msg_defender = {
    "%p staggers backwards as you thump it heavily!",
    "%p tries in vain to avoid your expert attack!",
    "Taking the offensive you batter %p with a series of heavy blows!",
    "There is nowhere for %p to hide as your attack forces it back!",
    "You duck a badly misjudged blow and strike %p with all your might!",
    "You leap into the fray and smash %p backwards a few feet!",
    "You warily circle %p then lash out with a stunning blow!",
    }

-------------------------------------------------
-- Combat state helpers
-------------------------------------------------

function Combat.is_in_combat(entity)
    return entity.np and entity.np.target ~= nil
end

function Combat.get_target(entity)
    return entity.np and entity.np.target
end

-------------------------------------------------
-- Start combat
-------------------------------------------------

function Combat.start(attacker, defender)
    attacker.np.target = defender.id
    defender.np.target = attacker.id

    msg.to_room(
        attacker.np.room,
        attacker.name .. " engages " .. defender.name .. " in combat!",
        nil
    )
end

-------------------------------------------------
-- Stop combat
-------------------------------------------------

function Combat.stop(entity)
    if entity.np then
        entity.np.target = nil
    end
end

-------------------------------------------------
-- Combat round resolution
-------------------------------------------------

function Combat.resolve_round(entity)
    if not Combat.is_in_combat(entity) then
        return
    end

    local tid = entity.np.target
    local target =
           db.world.players[tid]
        or db.world.npcs[tid]

    if not target or not target.np then
        Combat.stop(entity)
        return
    end

    -- Simple hit/damage logic placeholder
    local damage = math.random(1, 5)
    Combat.apply_damage(target, damage)

    msg.to_room(
        entity.np.room,
        entity.name .. " hits " .. target.name .. " for " .. damage .. "!",
        nil
    )

    if target.np.stamina <= 0 then
        Combat.handle_death(target, entity)
    end
end

-------------------------------------------------
-- Damage application
-------------------------------------------------

function Combat.apply_damage(target, amount)
    target.np.stamina = math.max(0, target.np.stamina - amount)
end

-------------------------------------------------
-- Death handling
-------------------------------------------------

function Combat.handle_death(target, killer)
    msg.to_room(
        target.np.room,
        target.name .. " collapses and dies.",
        nil
    )

    Combat.stop(target)
    Combat.stop(killer)

    -- Drop inventory
    local room = db.world.rooms[target.np.room]

    if target.np.inventory then
        for oid in pairs(target.np.inventory) do
            target.np.inventory[oid] = nil
            room.np.objects[oid] = true
        end
    end

    -- Remove NPCs from world, players handled elsewhere
    if db.world.npcs[target.id] then
        room.np.npcs[target.id] = nil
    end
end

-------------------------------------------------
-- Tick handling
-------------------------------------------------

function Combat.tick()
    -------------------------------------------------
    -- Process player combat
    -------------------------------------------------
    for _, player in pairs(db.world.players) do
        if player.np and Combat.is_in_combat(player) then
            Combat.resolve_round(player)
        end
    end

    -------------------------------------------------
    -- Process NPC combat
    -------------------------------------------------
    for _, npc in pairs(db.world.npcs) do
        if npc.np and Combat.is_in_combat(npc) then
            Combat.resolve_round(npc)
        end
    end
end

return Combat