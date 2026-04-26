--============================================================--
-- spells.lua
--
-- PURPOSE:
--   Implements all spell-based player actions for the game.
--   This module defines spell handlers that perform magical
--   effects such as sensing, summoning, teleportation, combat
--   manipulation, and state alteration.
--
--   spells.lua operates on fully parsed and resolved input
--   using the shared argspec grammar and dispatcher system.
--   It contains no parsing logic and no editor functionality.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Registers spell verbs and their argument grammar (argspec)
--   - Implements spell-side game logic and world mutation
--   - Invoked after wizard commands and before normal commands
--   - Operates only on resolved, tagged arguments
--   - Does not enforce permissions or mana costs directly
--
--   spells.lua does not parse input, resolve names, or handle
--   messaging delivery mechanics.
--
--============================================================--
--
-- FUNCTION OVERVIEW (SPELL HANDLERS):
--
-- spell_where(player, parsed)
--   Locates an object, NPC, or player anywhere in the world
--   and reports the room in which they are present.
--   Used by both WHERE and LOCATE spell aliases.
--
-- spell_summon(player, parsed)
--   Summons an NPC or player to the caster’s current room.
--
-- spell_cure(player, parsed)
--   Restores a target player or NPC to full health.
--
-- spell_jaunt(player)
--   Teleports the caster to a random or predefined room.
--
-- spell_teleport(player, parsed)
--   Teleports a target player or NPC to a specified room.
--
-- spell_steal(player, parsed)
--   Steals an object from another player or NPC and places
--   it into the caster’s inventory.
--
-- spell_strip(player, parsed)
--   Removes all objects from a target’s inventory and transfers
--   them to the caster.
--
-- spell_force(player, parsed)
--   Forces another player to execute a given command string.
--
-- spell_freeze(player, parsed)
--   Applies a frozen state to a target, preventing movement
--   or actions.
--
-- spell_confuse(player, parsed)
--   Applies a confused state to a target, altering behavior
--   or action reliability.
--
-- spell_dumb(player, parsed)
--   Reduces a target’s intelligence or mental capability.
--
-- spell_dispel(player, parsed)
--   Removes magical status effects such as freeze or confuse
--   from a target.
--
--============================================================--
--
-- DISPATCHER REGISTRATION:
--
--   All spells are registered via dispatcher:register() with:
--     - a verb name (and optional aliases)
--     - an argspec string defining grammar and scope
--     - a handler function listed above
--
--   Argument resolution and validation occur before handlers
--   are invoked.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * spells.lua must not require parser.lua or repl.lua.
--
--   * All spells assume arguments are valid and resolved.
--
--   * Spell privilege checks, costs, or cooldowns should be
--     enforced by higher-level systems, not hardcoded here.
--
--   * All player-visible messaging should be routed through
--     messaging.lua.
--
--   * Spells may modify world state but must do so explicitly
--     and predictably.
--
--============================================================--

local db         = require("database")
local msg        = require("messaging")
local Dispatcher = require("dispatcher")

local Spells = {}
local dispatch = Dispatcher.new()

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function id(arg)
    return tonumber(arg:sub(2))
end

local function here(player) return player.np.room end

-------------------------------------------------
-- SPELL IMPLEMENTATIONS
-------------------------------------------------

-- WHERE / LOCATE (global object, npc, player)
local function spell_where(player, parsed)
    local arg = parsed.args[1]
    local t = arg:sub(1,1)
    local i = id(arg)

    if t == "#" then
        local o = db.world.objects[i]
        if o and o.np then
            msg.to_player(player, o.name .. " is in room " .. o.np.location .. ".")
        end
    elseif t == "$" then
        local n = db.world.npcs[i]
        if n and n.np then
            msg.to_player(player, n.name .. " is in room " .. n.np.location .. ".")
        end
    elseif t == "&" then
        local p = db.world.players[i]
        if p and p.np then
            msg.to_player(player, p.name .. " is in room " .. p.np.room .. ".")
        end
    end
end

-- SUMMON <npc|player> (global)
local function spell_summon(player, parsed)
    local arg = parsed.args[1]
    local t = arg:sub(1,1)
    local i = id(arg)

-- Fail: Your spell failed miserably. Either get more points or try again.
-- Bad Fail: Your spell not only failed, it goes badly wrong... (player teleports to Room 1)
-- Same room: You can't summon them.

    if t == "$" then
        local n = db.world.npcs[i]
        if n and n.np then
            n.np.location = here(player)
            msg.to_room(here(player), n.name .. " suddenly appears!", nil)
        end
    elseif t == "&" then
        local p = db.world.players[i]
        if p and p.np then
            p.np.room = here(player)
            msg.to_player(p, player.name " summons you magically!")
        end
    end
     msg.to_player(player, "Your spell worked!")
end

-- CURE <player|npc> (local)
local function spell_cure(player, parsed)
    local arg = parsed.args[1]
    local t = arg:sub(1,1)
    local i = id(arg)

    if t == "&" then
        local p = db.world.players[i]
        if p then
            p.np.hp = p.np.maxhp
            msg.to_player(p, "You feel completely restored.")
        end
    elseif t == "$" then
        local n = db.world.npcs[i]
        if n then
            n.np.hp = n.np.maxhp
        end
    end
end

-- JAUNT (self teleport to random room)
local function spell_jaunt(player)
    local dest
    for k in pairs(db.world.rooms) do dest = k break end
    player.np.room = dest
    msg.to_player(player, "You vanish and reappear elsewhere.")
end

-- TELEPORT <player|npc> <room>
local function spell_teleport(player, parsed)
    local target = parsed.args[1]
    local roomid = id(parsed.args[2])

    if target:sub(1,1) == "&" then
        db.world.players[id(target)].np.room = roomid
    elseif target:sub(1,1) == "$" then
        db.world.npcs[id(target)].np.location = roomid
    end
end

-- STEAL <object> <player|npc>
local function spell_steal(player, parsed)
    local oid = id(parsed.args[1])
    local tgt = parsed.args[2]

    if tgt:sub(1,1) == "&" then
        local p = db.world.players[id(tgt)]
        if p and p.np.inventory[oid] then
            p.np.inventory[oid] = nil
            player.np.inventory[oid] = true
            msg.to_player(player, "You steal it!")
        end
    end
end

-- STRIP <player|npc>
local function spell_strip(player, parsed)
    local tgt = parsed.args[1]
    local t = tgt:sub(1,1)
    local inv

    if t == "&" then inv = db.world.players[id(tgt)].np.inventory
    elseif t == "$" then inv = db.world.npcs[id(tgt)].np.inventory end

    if inv then
        for oid in pairs(inv) do
            inv[oid] = nil
            player.np.inventory[oid] = true
        end
    end
end

-- FORCE <player> <command>
local function spell_force(player, parsed)
    local p = db.world.players[id(parsed.args[1])]
    local cmd = parsed.args[2]

    if p then
        msg.to_player(p, "You feel compelled to act...")
        require("game").handle_player_input(p, cmd)
    end
end

-- FREEZE <player|npc>
local function spell_freeze(player, parsed)
    local t = parsed.args[1]
    local ref = id(t)

    if t:sub(1,1) == "&" then db.world.players[ref].np.frozen = true
    elseif t:sub(1,1) == "$" then db.world.npcs[ref].np.frozen = true end
end

-- CONFUSE <player|npc>
local function spell_confuse(player, parsed)
    local t = parsed.args[1]
    local e = (t:sub(1,1)=="&") and db.world.players[id(t)] or db.world.npcs[id(t)]
    if e then e.np.confused = true end
end

-- DUMB <player|npc>
local function spell_dumb(player, parsed)
    local t = parsed.args[1]
    local e = (t:sub(1,1)=="&") and db.world.players[id(t)] or db.world.npcs[id(t)]
    if e then e.np.intelligence = 0 end
end

-- DISPEL <player|npc>
local function spell_dispel(player, parsed)
    local t = parsed.args[1]
    local e = (t:sub(1,1)=="&") and db.world.players[id(t)] or db.world.npcs[id(t)]
    if e then
        e.np.frozen = nil
        e.np.confused = nil
    end
end

-------------------------------------------------
-- DISPATCH REGISTRATION
-------------------------------------------------

dispatch:register("where",    { argspec="g#$&", fn=spell_where })
dispatch:register("locate",   { argspec="g#$&", fn=spell_where })

dispatch:register("summon",   { argspec="g$&", fn=spell_summon })
dispatch:register("cure",     { argspec="$&", fn=spell_cure })
dispatch:register("jaunt",    { fn=spell_jaunt })

dispatch:register("teleport", { argspec="g$& @", fn=spell_teleport })
dispatch:register("steal",    { argspec="# &", fn=spell_steal })
dispatch:register("strip",    { argspec="$&", fn=spell_strip })
dispatch:register("force",    { argspec="g& *", fn=spell_force })

dispatch:register("freeze",   { argspec="$&", fn=spell_freeze })
dispatch:register("confuse",  { argspec="$&", fn=spell_confuse })
dispatch:register("dumb",     { argspec="$&", fn=spell_dumb })
dispatch:register("dispel",   { argspec="$&", fn=spell_dispel })

-------------------------------------------------
-- Public API
-------------------------------------------------

function Spells.handle(player, parsed)
    return dispatch:handle(player, parsed)
end

function Spells.get_verbs()
    return dispatch:get_verbs()
end

function Spells.get_argspec(verb)
    return dispatch:get_argspec(verb)
end

return Spells