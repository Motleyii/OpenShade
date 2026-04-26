--============================================================--
-- commands.lua
--
-- PURPOSE:
--   Implements all standard player commands for the game.
--   This module defines the command handlers that execute
--   game logic in response to player input once parsing,
--   argument resolution, and validation have completed.
--
--   commands.lua does not parse text input, resolve nouns,
--   or enforce wizard privileges; those concerns are handled
--   by parser.lua, dispatcher.lua, and higher-level systems.
--
-- ARCHITECTURAL ROLE:
--   - Receives fully-parsed command invocations
--   - Operates only on resolved, tagged arguments
--   - Calls into world, movement, combat, and messaging systems
--   - Registers verbs and their argument grammar via Dispatcher
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- do_look(player)
--   Displays the current room description by delegating to
--   movement.describe_room(), respecting player verbosity.
--
-- do_exits(player)
--   Lists all available exits from the player’s current room.
--
-- do_inventory(player)
--   Displays a list of all objects currently carried
--   by the player.
--
-- do_get(player, parsed)
--   Picks up an object from the current room and places
--   it into the player’s inventory.
--
-- do_drop(player, parsed)
--   Removes an object from the player’s inventory and
--   places it in the current room.
--
-- do_give(player, parsed)
--   Transfers an object from the player’s inventory to
--   another player in the same room.
--
-- do_say(player, parsed)
--   Sends a message to all players in the same room,
--   spoken by the player.
--
-- do_tell(player, parsed)
--   Sends a private message from the player to another
--   specific player.
--
-- do_shout(player, parsed)
--   Sends a message globally to all players in the world.
--
-- do_emote(player, parsed)
--   Broadcasts an action-style message to the current room
--   without quotation or dialogue formatting.
--
-- do_who(player)
--   Displays a list of all currently connected players.
--
-- do_score(player, parsed)
--   Displays the player’s score, or the score of another
--   player in the same room if specified.
--
-- do_level(player)
--   Displays the player’s current level title, using
--   gender-aware level name resolution.
--
-- do_kill(player, parsed)
--   Initiates combat with a targeted NPC in the same room.
--
-- do_flee(player)
--   Attempts to disengage the player from combat and escape.
--
-- do_berserk(player)
--   Enables berserk mode, modifying the player’s combat
--   behavior and statistics.
--
-- do_wield(player, parsed)
--   Equips an object from inventory as the player’s weapon.
--
-- do_go(player, parsed)
--   Moves the player through a named exit to an adjacent room.
--
-- do_save(player)
--   Persists the player’s current state to disk.
--
-- do_quit(player)
--   Saves the player and cleanly disconnects them from
--   the game session.
--
--============================================================--
--
-- NOTE:
--   All command grammar (argspec strings) is declared at
--   registration time via dispatcher:register().
--   Commands assume arguments are already valid and
--   resolved when handlers are invoked.
--
--============================================================--

local db         = require("database")
local msg        = require("messaging")
local Dispatcher = require("dispatcher")
local movement   = require("movement")
local Combat     = require("combat")
local serpent    = require("serpent")

local Commands = {}
local dispatch = Dispatcher.new()

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function id(arg)    return tonumber(arg:sub(2)) end
local function room(player) return db.world.rooms[player.np.room] end

local function can_speak(player)
    local now = os.time()
    return not (player.np.dumb_until and player.np.dumb_until > now)
end

local function get_inventory_weight(player)
    local total = 0

    -- Defensive: inventory should exist, but don't assume
    for oid in pairs(player.np.inventory or {}) do
        local obj = db.world.objects[oid]
        if obj and obj.weight then
            total = total + obj.weight
        end
    end

    return total
end

local function get_max_carry_weight(player)
    local level_info = db.get_level(player)

    -- Defensive fallback, should never happen
    if not level_info or not level_info.level then
        return 0
    end

    return level_info.max_weight
end

local function force_drop_all(player)
    local room = db.world.rooms[player.np.room]
    local inventory = player.np.inventory or {}

    -- Nothing to drop
    if not next(inventory) then
        return
    end

    -------------------------------------------------
    -- Drop all carried objects into the room
    -------------------------------------------------
    for oid in pairs(inventory) do
        inventory[oid] = nil
        room.np.objects[oid] = true
    end

    -------------------------------------------------
    -- Notify player and room
    -------------------------------------------------
    msg.to_player(
        player,
        "You are carrying too much and drop everything!"
    )

    msg.to_room(
        player.np.room,
        player.name ..
        " collapses under the weight and drops everything.",
        player.id
    )
end

-------------------------------------------------
-- LOOK
-------------------------------------------------

local function do_look(player)
    local r = room(player)
    movement.describe_room(player, r, {force_desc = true})
end

-------------------------------------------------
-- EXITS
-------------------------------------------------

local function do_exits(player)
    local exits = room(player).exits or {}
    local list = {}
    for dir in pairs(exits) do table.insert(list, dir) end

    if #list == 0 then
        msg.to_player(player, "No obvious exits.")
    else
        msg.to_player(player, "Exits: " .. table.concat(list, ", "))
    end
end

-------------------------------------------------
-- INVENTORY
-------------------------------------------------

local function do_inventory(player)
    local list = {}
    for oid in pairs(player.np.inventory) do
        table.insert(list, db.world.objects[oid].name)
    end

    if #list == 0 then
        msg.to_player(player, "You are carrying nothing.")
    else
        msg.to_player(player, "You are carrying: " .. table.concat(list, ", "))
    end
end

-------------------------------------------------
-- GET / DROP
-------------------------------------------------

local function do_get(player, parsed)
    local arg  = parsed.args[1]
    local room = db.world.rooms[player.np.room]

    -------------------------------------------------
    -- GET ALL (wildcard: "#.")
    -------------------------------------------------

    if arg == "#." then
        if not room.np.objects or not next(room.np.objects) then
            msg.to_player(player, "There is nothing here to take.")
            return
        end

        for oid in pairs(room.np.objects) do
            room.np.objects[oid] = nil
            player.np.inventory[oid] = true
        end

    -------------------------------------------------
    -- GET single object
    -------------------------------------------------
    else
        local oid = tonumber(arg:sub(2))
        if not oid or not room.np.objects[oid] then
            msg.to_player(player, "That is not here.")
            return
        end

        room.np.objects[oid] = nil
        player.np.inventory[oid] = true
    end

    -------------------------------------------------
    -- Enforce carry weight (authoritative rule)
    -------------------------------------------------

    if get_inventory_weight(player) > get_max_carry_weight(player) then
        force_drop_all(player)
        return
    end

    msg.to_player(player, "Taken.")
end

local function do_drop(player, parsed)
    local oid = id(parsed.args[1])
    local r = room(player)

    if not player.np.inventory[oid] then
        msg.to_player(player, "You are not carrying that.")
        return
    end

    player.np.inventory[oid] = nil
    r.np.objects[oid] = true
    msg.to_player(player, "Dropped.")
end

-------------------------------------------------
-- GIVE
-------------------------------------------------

local function do_give(player, parsed)
    local oid = tonumber(parsed.args[1]:sub(2))
    local pid = tonumber(parsed.args[2]:sub(2))

    local target = db.world.players[pid]
    local room   = db.world.rooms[player.np.room]

    -------------------------------------------------
    -- Validation
    -------------------------------------------------
    if not target or not target.np then
        msg.to_player(player, "They are not here.")
        return
    end

    if target.id == player.id then
        msg.to_player(player, "You cannot give items to yourself.")
        return
    end

    if target.np.room ~= player.np.room then
        msg.to_player(player, "They are not here.")
        return
    end

    if not player.np.inventory[oid] then
        msg.to_player(player, "You are not carrying that.")
        return
    end

    -------------------------------------------------
    -- Transfer object
    -------------------------------------------------
    player.np.inventory[oid] = nil
    target.np.inventory[oid] = true

    msg.to_player(
        player,
        "You give " .. db.world.objects[oid].name ..
        " to " .. target.name .. "."
    )

    msg.to_player(
        target,
        player.name ..
        " gives you " .. db.world.objects[oid].name .. "."
    )

    msg.to_room(
        player.np.room,
        player.name .. " gives something to " .. target.name .. ".",
        nil
    )

    -------------------------------------------------
    -- Enforce carry weight on recipient
    -------------------------------------------------
    if get_inventory_weight(target) > get_max_carry_weight(target) then
        force_drop_all(target)
    end
end

-------------------------------------------------
-- SAY / TELL / SHOUT / EMOTE
-------------------------------------------------

local function do_say(player, parsed)
    if not can_speak(player) then
        msg.to_player(player, "You try to speak, but only drool comes out.")
        return
    end

    msg.to_player(player, "You say: " .. parsed.args[1])
    msg.to_room(
        player.np.room,
        player.name .. " says: " .. parsed.args[1],
        player.id
    )
end

local function do_tell(player, parsed)
    if not can_speak(player) then
        msg.to_player(player, "You try to speak, but your mind is too dull.")
        return
    end

    local pid = tonumber(parsed.args[1]:sub(2))
    local target = db.world.players[pid]

    if not target or not target.np then
        msg.to_player(player, "They are not available.")
        return
    end

    msg.to_player(
        player,
        "You tell " .. target.name .. ": " .. parsed.args[2]
    )

    msg.to_player(
        target,
        player.name .. " tells you: " .. parsed.args[2]
    )
end

local function do_shout(player, parsed)
    if not can_speak(player) then
        msg.to_player(player, "You open your mouth, but no intelligible sound emerges.")
        return
    end

    msg.to_world(player.name .. " shouts: " .. parsed.args[1])
end

local function do_emote(player, parsed)
    msg.to_room(player.np.room, player.name .. " " .. parsed.args[1], nil)
end

-------------------------------------------------
-- WHO / SCORE / LEVEL
-------------------------------------------------

local function do_who(player)
    msg.to_player(player, "Players online:")
    for _, p in pairs(db.world.players) do
        if p.np then
            msg.to_player(player, "  " .. p.name)
        end
    end
end

local function do_score(player, parsed)
    if not parsed.args[1] then
        msg.to_player(player, "Your score is " .. player.np.score .. ".")
        return
    end

    local pid = id(parsed.args[1])
    local t = db.world.players[pid]

    if not t or t.np.room ~= player.np.room then
        msg.to_player(player, "They are not here.")
        return
    end

    msg.to_player(player, db.get_level_name_adverb(t.name) .. "'s score is " .. t.np.score .. ".")
end

local function do_level(player)
    msg.to_player(player, "You are " .. db.get_level_name_adverb(player) .. ".")
end

-------------------------------------------------
-- WIELD
-------------------------------------------------

local function do_wield(player, parsed)
    local oid = id(parsed.args[1])

    if not player.np.inventory[oid] then
        msg.to_player(player, "You are not carrying that.")
        return
    end

    player.np.weapon = oid
    msg.to_player(player, "You wield it.")
end

-------------------------------------------------
-- GO <direction>
-------------------------------------------------

local function do_go(player, parsed)
    local now = os.time()

    -------------------------------------------------
    -- Frozen players cannot move
    -------------------------------------------------
    if player.np.frozen_until and player.np.frozen_until > now then
        msg.to_player(player, "You are frozen and cannot move!")
        return
    end

    -------------------------------------------------
    -- Fighting players can only flee
    -------------------------------------------------
    if Combat.is_in_combat(player) then
        msg.to_player(player, "You can't just leave during a fight, you have to FLEE!")
        return
    end

    -------------------------------------------------
    -- No direction supplied
    -------------------------------------------------
    if not parsed.args[1] then
        msg.to_player(player, "Go where?")
        return
    end

    -------------------------------------------------
    -- Extract canonical direction
    -------------------------------------------------
    local dir = parsed.args[1]:sub(2)

    local room = db.world.rooms[player.np.room]
    if not room or not room.exits then
        msg.to_player(player, "You can't go that way.")
        return
    end

    -------------------------------------------------
    -- Confusion may alter direction
    -------------------------------------------------
    if player.np.confused_until and player.np.confused_until > now then
        local dirs = {}
        for d, ex in pairs(room.exits) do
            if type(ex) == "number" then
                table.insert(dirs, d)
            end
        end

        if #dirs > 0 then
            local old = dir
            dir = dirs[math.random(#dirs)]
            msg.to_player(player,
                "In your confusion you stagger " .. dir ..
                (old ~= dir and " instead of " .. old or "") .. "."
            )
        end
    end

    -------------------------------------------------
    -- Resolve exit
    -------------------------------------------------
    local exit = room.exits[dir]
    if not exit then
        msg.to_player(player, "You can't go that way.")
        return
    end

    -------------------------------------------------
    -- String exit (blocked)
    -------------------------------------------------
    if type(exit) == "string" then
        msg.to_player(player, exit)
        return
    end

    local dest = db.world.rooms[exit]
    if not dest then
        msg.to_player(player, "You can't go that way.")
        return
    end

    -------------------------------------------------
    -- Leave messages
    -------------------------------------------------
    msg.to_room(
        player.np.room,
        player.name .. " leaves " .. dir .. ".",
        player.id
    )

    -------------------------------------------------
    -- Perform movement
    -------------------------------------------------
    room.np.players[player.id] = nil
    player.np.room = exit
    dest.np.players[player.id] = true

    -------------------------------------------------
    -- Enter messages
    -------------------------------------------------
    msg.to_room(
        exit,
        player.name .. " arrives.",
        player.id
    )

    -------------------------------------------------
    -- Describe destination
    -------------------------------------------------
    movement.describe_room(player, dest)
end

-------------------------------------------------
-- SAVE / QUIT
-------------------------------------------------

local function do_save(player)
    db.save_players("players.lua")
    msg.to_player(player, "Saved.")
end

local function do_quit(player)
    msg.to_player(player, "Goodbye.")
    do_save(player)
    player.np.conn:close()
end

-------------------------------------------------
-- VERBOSE / BRIEF
-------------------------------------------------

local function do_verbose(player)
    player.flags = player.flags or {}
    player.flags.verbose = true
    msg.to_player(player, "Verbose room descriptions enabled.")
end

local function do_brief(player)
    player.flags = player.flags or {}
    player.flags.verbose = false
    msg.to_player(player, "Brief room descriptions enabled.")
end

-------------------------------------------------
-- COMBAT
-------------------------------------------------

local function do_kill(player, parsed)
    local arg = parsed.args[1]
    local tag = arg:sub(1,1)
    local id  = tonumber(arg:sub(2))

    local target
    local room = db.world.rooms[player.np.room]

    -------------------------------------------------
    -- Resolve target (NPC or player)
    -------------------------------------------------

    if tag == "$" then
        target = db.world.npcs[id]
        if not target or not target.np or target.np.location ~= player.np.room then
            msg.to_player(player, "That creature is not here.")
            return
        end

    elseif tag == "&" then
        target = db.world.players[id]
        if not target or not target.np or target.np.room ~= player.np.room then
            msg.to_player(player, "That player is not here.")
            return
        end

        if target.id == player.id then
            msg.to_player(player, "You cannot attack yourself.")
            return
        end
    else
        msg.to_player(player, "You can't attack that.")
        return
    end

    -------------------------------------------------
    -- Prevent duplicate combat
    -------------------------------------------------

    if Combat.is_in_combat(player) then
        msg.to_player(player, "You are already fighting!")
        return
    end

    -------------------------------------------------
    -- Start combat
    -------------------------------------------------

    Combat.start(player, target)

    -------------------------------------------------
    -- Feedback
    -------------------------------------------------

    msg.to_player(player, "You attack " .. target.name .. "!")
    msg.to_room(
        player.np.room,
        player.name .. " attacks " .. target.name .. "!",
        player.id
    )
end

local function do_flee(player, parsed)
    -------------------------------------------------
    -- Must be in combat to flee
    -------------------------------------------------
    if not Combat.is_in_combat(player) then
        msg.to_player(player, "There's no point in fleeing if you aren't fighting.")
        return
    end

    -------------------------------------------------
    -- Extract canonical flee direction
    -------------------------------------------------
    local dir = parsed.args[1]:sub(2)

    local room = db.world.rooms[player.np.room]
    if not room or not room.exits then
        msg.to_player(player, "You panic, but cannot escape!")
        return
    end

    -------------------------------------------------
    -- Check exit validity (Shades allows fleeing in any direction)
    -- (string exits are NOT valid for fleeing)
    -------------------------------------------------
    local exit = room.exits[dir]
    if type(exit) ~= "number" then
        msg.to_player(player, "You try to flee but cannot escape!")
        return    -- combat continues
    end

    -------------------------------------------------
    -- Apply flee penalty (10% of score)
    -------------------------------------------------
    local penalty = math.floor(player.score * 0.10)
    player.score = player.score - penalty

    msg.to_player(
        player,
        "You flee in panic, losing " .. penalty .. " points!"
    )

    -------------------------------------------------
    -- Stop combat
    -------------------------------------------------
    Combat.stop(player)

    -------------------------------------------------
    -- Perform movement using existing logic
    -------------------------------------------------
    do_go(player, parsed)
end

local function do_berserk(player)
    player.np.berserk = true
    msg.to_player(player, "You fly into a berserk rage!")
end

-------------------------------------------------
-- Dispatcher registrations
-------------------------------------------------

dispatch:register("look",        { fn = do_look })
dispatch:register("exits",       { fn = do_exits })
dispatch:register("inventory",   { aliases={"inv"}, fn = do_inventory })

dispatch:register("get",         { aliases={"take","pickup"}, argspec="#.", fn = do_get })
dispatch:register("drop",        { argspec="#.", fn = do_drop })
dispatch:register("give",        { argspec="# &", fn = do_give })

dispatch:register("say",         { argspec="*", fn = do_say })
dispatch:register("tell",        { argspec="& *", fn = do_tell })
dispatch:register("shout",       { argspec="*", fn = do_shout })
dispatch:register("emote",       { argspec="*", fn = do_emote })

dispatch:register("who",         { fn = do_who })
dispatch:register("score",       { argspec="&?", fn = do_score })
dispatch:register("level",       { fn = do_level })

dispatch:register("kill",        { argspec = "$&", fn = do_kill })
dispatch:register("flee",        { argspec = ">", fn = do_flee })
dispatch:register("berserk",     { fn = do_berserk })

dispatch:register("wield",       { argspec = "#", fn = do_wield })

dispatch:register("go",          { argspec = ">", fn = do_go })

dispatch:register("save",        { fn = do_save })
dispatch:register("quit",        { fn = do_quit, aliases={"bye","exit"} })

dispatch:register("verbose",     { fn = do_verbose })
dispatch:register("brief",       { fn = do_brief })

-------------------------------------------------
-- Public API
-------------------------------------------------

function Commands.handle(player, parsed)
    return dispatch:handle(player, parsed)
end

function Commands.get_verbs()
    return dispatch:get_verbs()
end

function Commands.get_argspec(verb)
    return dispatch:get_argspec(verb)
end

return Commands