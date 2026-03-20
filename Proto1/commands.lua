----------------------------------------------------------------------
-- commands.lua
-- Unified command handler with:
--   • Multi-verb registration + ≥2-letter abbreviations (fixed precedence)
--   • Movement (incl. IN/OUT), numeric/string exit handling + room broadcasts
--   • EXITS: one-per-line; numeric → show room title+id, string → show text
--   • WHERE lookup (object by noun, player, NPC) with wizard room-id reveal
--   • SCORE/ STATS (self or other in same room), incl. stamina + inventory value
--   • Combat (ATTACK/KILL [WITH <weapon>], FLEE <dir>, RETALIATE [WITH] <weapon>)
--   • Theft (STEAL) w/ level-based chance; SUMMON w/ same chance and room broadcasts
--   • Wizard utilities: INVISIBLE / VISIBLE, SGO <room-id>
--   • HELP via help_loader; QUIT applies FLEE penalty if fighting, persists, disconnects
----------------------------------------------------------------------

local world       = require("world")
local objects     = require("objects")
local levels      = require("levels")
local help_loader = require("help_loader")
local combat      = require("combat")
local npc         = require("npc")
local database    = require("database")

local commands = {}

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------

local function tokenize(line)
    local t = {}
    for w in line:gmatch("%S+") do table.insert(t, w) end
    return t
end

-- Broadcast to all players in a room except an optional excluded player
local function broadcast_room(room_id, msg, except)
    if not _G.active_players then return end
    for _, p in pairs(_G.active_players) do
        if p.connected and p.location == room_id and p ~= except then
            p:send(msg)
        end
    end
end

-- Global player lookups
local function find_player_by_name(name)
    if not _G.active_players then return nil end
    local lname = (name or ""):lower()
    for _, p in pairs(_G.active_players) do
        if p.connected and p.name:lower() == lname then return p end
    end
    return nil
end

local function find_player_in_room_by_name(room_id, name)
    if not _G.active_players then return nil end
    local lname = (name or ""):lower()
    for _, p in pairs(_G.active_players) do
        if p.connected and p.location == room_id and p.name:lower() == lname then
            return p
        end
    end
    return nil
end

local function is_wizard(player)
    local idx = levels.get_level_index(player.score or 0)
    return idx == 13 -- Wizard/Witch
end

----------------------------------------------------------------------
-- Movement (incl. IN/OUT aliases and numeric/string exit handling)
----------------------------------------------------------------------

local direction_map = {
    n="north", s="south", e="east", w="west",
    ne="northeast", nw="northwest", se="southeast", sw="southwest",
    u="up", d="down",
    ["in"]="into",
    ["out"]="out"
}

-- try_move with optional opts: {suppress_broadcast=true} to skip room messages
local function try_move(player, verb, opts)
    opts = opts or {}
    local suppress = opts.suppress_broadcast == true

    local exits = world.get_exits(player.location) or {}
    local canonical = direction_map[verb] or verb  -- e.g., "in" -> "into"
    local dest = exits[canonical]

    if dest == nil then
        player:send("You cannot go that way.\n")
        return
    end

    local t = type(dest)
    if t == "string" then
        player:send(dest .. "\n")
        return
    end
    if t ~= "number" then
        player:send("You cannot go that way.\n")
        return
    end

    local origin = player.location

    -- Room broadcasts for standard movement
    if not suppress then
        broadcast_room(origin, player.name .. " leaves " .. canonical .. ".\n", player)
    end

    player.location = dest

    if not suppress then
        broadcast_room(dest, player.name .. " has arrived.\n", player)
    end

    world.look(player)
end

----------------------------------------------------------------------
-- Carry weight enforcement
----------------------------------------------------------------------

local function enforce_carry_limit(player)
    local carried = player:get_carry_weight()
    local max     = player:get_max_carry()
    if carried > max then
        player:send("Your backpack becomes too heavy! You drop everything!\n")
        player:drop_all_inventory()
        return true
    end
    return false
end

----------------------------------------------------------------------
-- Room & social
----------------------------------------------------------------------

local function do_look(player) world.look(player) end

-- EXITS: one direction per line, numeric shows title+id; string shows text
local function do_exits(player)
    local room = world.get_room(player.location)
    if not room then
        player:send("There are no exits.\n")
        return
    end

    local exits = room.exits or {}
    local any = false

    for dir, dest in pairs(exits) do
        any = true
        if type(dest) == "number" then
            local to_room = world.get_room(dest)
            local title = (to_room and to_room.title) or "Unknown"
            player:send(dir .. " → " .. title .. " (Room " .. tostring(dest) .. ")\n")
        elseif type(dest) == "string" then
            player:send(dir .. " → " .. dest .. "\n")
        end
    end

    if not any then
        player:send("There are no exits.\n")
    end
end

local function do_say(player, arg)
    if not arg or arg == "" then player:send("Say what?\n"); return end
    player:send("You say: " .. arg .. "\n")
    if _G.active_players then
        for _, p in pairs(_G.active_players) do
            if p ~= player and p.connected and p.location == player.location then
                p:send(player.name .. " says: " .. arg .. "\n")
            end
        end
    end
end

local function do_tell(player, arg)
    if not arg or arg == "" then
        player:send("Usage: TELL <PlayerName> <message>\n")
        return
    end
    local name, message = arg:match("^(%S+)%s+(.+)$")
    if not name or not message then
        player:send("Usage: TELL <PlayerName> <message>\n")
        return
    end
    local target = find_player_by_name(name)
    if not target then
        player:send("You cannot find '" .. name .. "' anywhere.\n")
        return
    end
    if target == player then
        player:send("Talking to yourself? Try SAY if you want to speak aloud.\n")
        return
    end
    target:send(player.name .. " tells you: " .. message .. "\n")
    player:send("You tell " .. target.name .. ": " .. message .. "\n")
end

local function do_shout(player, arg)
    if not arg or arg == "" then player:send("Usage: SHOUT <message>\n"); return end
    if _G.active_players then
        for _, p in pairs(_G.active_players) do
            if p.connected then
                p:send(player.name .. " shouts: " .. arg .. "\n")
            end
        end
    end
end

local function do_who(player)
    player:send("Players online:\n")
    if not _G.active_players then player:send("None.\n"); return end
    for _, p in pairs(_G.active_players) do
        if p.connected then player:send(" - " .. p.name .. "\n") end
    end
end

----------------------------------------------------------------------
-- Inventory & objects (noun-only matching helpers for inventory)
----------------------------------------------------------------------

local function object_matches_by_noun(obj, arg)
    if not obj or not obj.noun then return false end
    local set = {}
    for _, w in ipairs(obj.noun) do set[w:lower()] = true end
    for tok in (arg or ""):gmatch("%S+") do
        if set[tok:lower()] then return true end
    end
    return false
end

local function find_inventory_by_noun(player, arg)
    if not player.inventory then return nil end
    for _, obj in ipairs(player.inventory) do
        if object_matches_by_noun(obj, arg) then return obj end
    end
    return nil
end

local function do_inventory(player) player:list_inventory() end

local function do_carry(player)
    player:send("Carried weight: " ..
        player:get_carry_weight() .. " / " .. player:get_max_carry() .. "\n")
end

-- GET with room broadcast
local function do_get(player, arg)
    if not arg or arg == "" then
        player:send("Get what?\n")
        return
    end

    local obj = objects.find_in_room_by_name(player.location, arg)
    if not obj then
        player:send("You can't see that here.\n")
        return
    end

    if objects.player_pickup(player, obj.id) then
        local name = obj.name or "item"
        player:send("You pick up the " .. name .. ".\n")
        broadcast_room(player.location, player.name .. " picks up the " .. name .. ".\n", player)
        enforce_carry_limit(player)
    end
end

-- DROP with room broadcast + treasure-room scoring/respawn
local function do_drop(player, arg)
    if not arg or arg == "" then
        player:send("Drop what?\n")
        return
    end

    -- Capture the object reference before dropping (noun-only)
    local obj = find_inventory_by_noun(player, arg)
    local obj_name = obj and obj.name or "something"

    if not objects.player_drop(player, arg) then
        return
    end

    -- Announce to the room (others)
    broadcast_room(player.location, player.name .. " drops the " .. obj_name .. ".\n", player)

    -- --- Treasure handling ---
    -- Check if we're in a treasure room and the object has a non-zero value
    local room = world.get_room(player.location)
    local is_troom = room and room.flags and room.flags.is_troom
    local value = (obj and obj.value) or 0

    if is_troom then
        player:send("THIS IS A TROOM: " .. obj.name .. " is worth " .. value .. " / " .. obj.value .. "\n")
    end

    if is_troom and value > 0 and obj then
        -- Award points
        player:add_score(value)
        player:send("Your " .. (obj.name or "item") ..
                    " immediately vanishes and you are awarded " .. tostring(value) .. " points.\n")

        -- Remove the object from this room (it vanishes)
        objects.remove_from_room(player.location, obj.id)

        -- Respawn behavior:
        if obj.respawn and type(obj.respawn) == "table" and #obj.respawn > 0 then
            local idx = math.random(1, #obj.respawn)
            local rid = obj.respawn[idx]
            obj.location = rid
            world.place_object(rid, obj)
        else
            -- No respawn list → send to location 0 (effectively removed)
            obj.location = 0
        end
    end
    -- --- End treasure handling ---

    -- Update dropping player's weight line
    player:send("Carried weight: " ..
        player:get_carry_weight() .. " / " .. player:get_max_carry() .. "\n")
end

----------------------------------------------------------------------
-- Score / Stats (self or other in same room)
-- Includes stamina and total inventory value
----------------------------------------------------------------------

local function render_score(viewer, target)
    local score = target.score or 0
    local lvl_idx, _ = levels.get_level_index(score)
    local title = levels.get_title_for_player(target)
    local next_thresh, to_go = levels.get_next_threshold(score)

    local carry     = (target.get_carry_weight and target:get_carry_weight()) or 0
    local max_carry = (target.get_max_carry   and target:get_max_carry())   or 0
    local stamina   = target.stamina or 0

    local total_value = 0
    if target.inventory then
        for _, obj in ipairs(target.inventory) do
            total_value = total_value + (obj.value or 0)
        end
    end

    viewer:send("\nScore for " .. target.name .. ":\n")
    viewer:send(" Level:       " .. tostring(lvl_idx) .. " (" .. title .. ")\n")
    viewer:send(" Score:       " .. tostring(score) .. "\n")
    viewer:send(" Stamina:     " .. tostring(stamina) .. "\n")

    if next_thresh then
        viewer:send(" Next:        " .. tostring(next_thresh) ..
                    "  (+" .. tostring(to_go) .. ")\n")
    else
        viewer:send(" Next:        (maximum level)\n")
    end

    viewer:send(" Carry:       " .. tostring(carry) ..
                " / " .. tostring(max_carry) .. "\n")
    viewer:send(" Inv Value:   " .. tostring(total_value) .. "\n\n")
end

local function do_score(player, arg)
    if arg and arg ~= "" then
        local other = find_player_in_room_by_name(player.location, arg)
        if not other then
            player:send("You don't see " .. arg .. " here.\n")
            return
        end
        render_score(player, other)
        return
    end
    render_score(player, player)
end

----------------------------------------------------------------------
-- HELP (via help_loader)
----------------------------------------------------------------------

local function do_help(player, arg)
    if not arg or arg == "" then
        local topics = help_loader.topics() or {}
        if #topics == 0 then player:send("No help topics available.\n"); return end
        player:send("Help topics:\n")
        local line = {}
        local function flush()
            if #line > 0 then
                player:send("  " .. table.concat(line, ", ") .. "\n")
                line = {}
            end
        end
        for _, topic in ipairs(topics) do
            table.insert(line, topic)
            if #line >= 8 then flush() end
        end
        flush()
        player:send("Type: HELP <topic>\n")
        return
    end
    local txt = help_loader.lookup(arg)
    if not txt then
        player:send("No help available for '" .. arg .. "'.\n")
        return
    end
    player:send("\n" .. arg:upper() .. ":\n" .. txt .. "\n\n")
end

----------------------------------------------------------------------
-- WHERE <thing>  (object by noun, player, or NPC)
----------------------------------------------------------------------

local function find_npc_by_name_anywhere(name)
    local n = (name or ""):lower()
    if not npc.live then return nil end
    for _, inst in pairs(npc.live) do
        if inst.name and inst.name:lower() == n then
            return inst
        end
    end
    return nil
end

local function find_object_anywhere_by_noun(arg)
    -- Rooms
    for room_id, room in pairs(world.rooms or {}) do
        for _, obj in ipairs(room.objects or {}) do
            if object_matches_by_noun(obj, arg) then
                return obj, room_id
            end
        end
    end
    -- Player inventories
    if _G.active_players then
        for _, p in pairs(_G.active_players) do
            if p.connected and p.inventory then
                for _, obj in ipairs(p.inventory) do
                    if object_matches_by_noun(obj, arg) then
                        return obj, p.location
                    end
                end
            end
        end
    end
    return nil, nil
end

local function send_where_result(issuer, room_id)
    local room = world.rooms[room_id]
    if not room then
        issuer:send("Location unknown.\n")
        return
    end
    if is_wizard(issuer) then
        issuer:send("Location: " .. (room.title or "Unknown") .. " (Room " .. tostring(room_id) .. ")\n")
    else
        issuer:send("Location: " .. (room.title or "Unknown") .. "\n")
    end
end

local function do_where(player, arg)
    if not arg or arg == "" then
        player:send("Usage: WHERE <object|player|npc>\n")
        return
    end

    local obj, obj_room = find_object_anywhere_by_noun(arg)
    if obj and obj_room then send_where_result(player, obj_room); return end

    local other = find_player_by_name(arg)
    if other and other.location then send_where_result(player, other.location); return end

    local inst = find_npc_by_name_anywhere(arg)
    if inst and inst.location then send_where_result(player, inst.location); return end

    player:send("No match found.\n")
end

----------------------------------------------------------------------
-- Combat: ATTACK / KILL [WITH <weapon>], FLEE <dir>, RETALIATE [WITH] <weapon>
----------------------------------------------------------------------

local function do_attack(player, arg)
    if not arg or arg == "" then
        player:send("Attack whom?\n")
        return
    end

    -- Optional "WITH <weapon>"
    local target_part, weapon_part = arg:match("^%s*(.-)%s+[Ww][Ii][Tt][Hh]%s+(.-)%s*$")
    local target_name, weapon_name
    if target_part and weapon_part then
        target_name = target_part
        weapon_name = weapon_part
    else
        target_name = arg
        weapon_name = nil
    end

    if weapon_name and weapon_name ~= "" then
        local ok, res = player:wield_weapon_by_name(weapon_name)
        if not ok then
            player:send(res .. "\n")
            return
        end
        player:send("You ready the " .. ((res and res.name) or "weapon") .. " and prepare to strike.\n")
    end

    local target_player = find_player_in_room_by_name(player.location, target_name)
    if target_player and target_player ~= player then
        combat.attack_player(player, target_player)
        return
    end

    local inst = npc.find_in_room_by_name(player.location, target_name)
    if inst then
        combat.attack_npc(player, inst)
        return
    end

    player:send("You see no such foe here.\n")
end

-- FLEE with room broadcasts
local function do_flee(player, arg)
    if not arg or arg == "" then
        player:send("Usage: FLEE <direction>\n")
        return
    end

    local dir = arg:lower()

    if not player.in_combat then
        -- Not fighting: rely on normal movement broadcasts
        try_move(player, dir)
        return
    end

    -- Fighting: special flee messaging
    local origin = player.location

    combat.force_breakoff(player)
    broadcast_room(origin, player.name .. " flees " .. dir .. "!\n", player)

    player:drop_all_inventory()
    local score = player.score or 0
    local loss  = math.floor(score / 32)
    if loss > 0 then player:set_score(score - loss) end

    local before = player.location
    try_move(player, dir, { suppress_broadcast = true }) -- avoid default leave/arrive text

    local dest = player.location
    if dest ~= before then
        broadcast_room(dest, player.name .. " arrives, fleeing from danger!\n", player)
    end
end

local function do_retaliate(player, arg)
    if not player.in_combat then
        player:send("You are not fighting!\n")
        return
    end
    if not arg or arg == "" then
        player:send("Usage: RETALIATE [WITH] <weapon>\n")
        return
    end
    local trimmed = arg:gsub("^%s+", "")
    local lower   = trimmed:lower()
    local weapon_name = (lower:sub(1,5) == "with ") and trimmed:sub(6) or trimmed
    weapon_name = weapon_name:gsub("^%s+", ""):gsub("%s+$", "")
    if weapon_name == "" then
        player:send("Usage: RETALIATE [WITH] <weapon>\n")
        return
    end
    local ok, res = player:wield_weapon_by_name(weapon_name)
    if not ok then
        player:send(res .. "\n")
        return
    end
    player:send("You retaliate with the " .. ((res and res.name) or "weapon") .. ".\n")
end

----------------------------------------------------------------------
-- Theft & Magic (with room broadcasts for SUMMON)
----------------------------------------------------------------------

local function steal_succeeds(thief, victim)
    local t_idx = levels.get_level_index(thief.score or 0)
    local v_idx = levels.get_level_index(victim.score or 0)
    local p = 0.25 + 0.05 * (t_idx - v_idx)
    if p < 0.05 then p = 0.05 end
    if p > 0.90 then p = 0.90 end
    return math.random() < p
end

local function do_steal(player, arg)
    if not arg or arg == "" then
        player:send("Usage: STEAL <object> <player>  or  STEAL <object> FROM <player>\n")
        return
    end

    local obj, who = arg:match("^%s*(.-)%s+[Ff][Rr][Oo][Mm]%s+(%S+)%s*$")
    if not obj then obj, who = arg:match("^%s*(%S+)%s+(%S+)%s*$") end
    if not obj or not who then
        player:send("Usage: STEAL <object> <player>  or  STEAL <object> FROM <player>\n")
        return
    end

    local victim
    if is_wizard(player) then
        victim = find_player_by_name(who)
        if not victim then
            player:send("You cannot find '" .. who .. "'.\n")
            return
        end
    else
        victim = find_player_in_room_by_name(player.location, who)
        if not victim then
            player:send("You don't see " .. who .. " here.\n")
            return
        end
        if victim == player then
            player:send("You cannot steal from yourself.\n")
            return
        end
        if not steal_succeeds(player, victim) then
            player:send("You fail to steal the " .. obj .. " from " .. victim.name .. "!\n")
            victim:send(player.name .. " tried to steal your " .. obj .. "!\n")
            return
        end
    end

    local ok, res = objects.steal_from_player(player, victim, obj)
    if not ok then
        player:send(res .. "\n")
        return
    end

    local stolen = res
    player:send("You steal the " .. ((stolen and stolen.name) or "object") .. " from " .. victim.name .. ".\n")
    victim:send(player.name .. " steals your " .. ((stolen and stolen.name) or "object") .. "!\n")
    enforce_carry_limit(player)
end

-- SUMMON with room broadcasts
local function do_summon(player, arg)
    if not arg or arg == "" then
        player:send("Usage: SUMMON <player>\n")
        return
    end

    local target = find_player_by_name(arg)
    if not target then
        player:send("You cannot find '" .. arg .. "'.\n")
        return
    end

    if target.location == player.location then
        player:send(target.name .. " is already here.\n")
        return
    end

    local success = is_wizard(player) or steal_succeeds(player, target)
    if not success then
        target:send("You feel a strange tingling sensation but it soon subsides.\n")
        return
    end

    local origin_room = target.location
    local dest_room   = player.location

    if origin_room then
        broadcast_room(origin_room, target.name .. " has disappeared!\n", target)
    end

    target.location = dest_room
    broadcast_room(dest_room, target.name .. " arrives in a blinding flash!\n", target)

    target:send("You are suddenly surrounded by stars and faint! When you come round, you are somewhere else!\n")
    player:send("You summon " .. target.name .. " to your location.\n")

    world.look(target)
end

----------------------------------------------------------------------
-- Wizard utilities: INVISIBLE / VISIBLE, SGO <room-id>
----------------------------------------------------------------------

local function do_invisible(player)
    if not is_wizard(player) then
        player:send("Only a Wizard or Witch may use this command.\n")
        return
    end
    player.flags = player.flags or {}
    if player.flags.invisible then
        player:send("You are already invisible.\n")
        return
    end
    player.flags.invisible = true
    player:send("You fade from sight.\n")
end

local function do_visible(player)
    if not is_wizard(player) then
        player:send("Only a Wizard or Witch may use this command.\n")
        return
    end
    player.flags = player.flags or {}
    if not player.flags.invisible then
        player:send("You are already visible.\n")
        return
    end
    player.flags.invisible = false
    player:send("You return to visibility.\n")
end

local function do_sgo(player, arg)
    if not is_wizard(player) then
        player:send("Only a Wizard or Witch may use this command.\n")
        return
    end
    if not arg or arg == "" then
        player:send("Usage: SGO <room-id>\n")
        return
    end
    local rid = tonumber(arg)
    if not rid then
        player:send("Room id must be a number.\n")
        return
    end
    local room = world.rooms and world.rooms[rid]
    if not room then
        player:send("No such room: " .. tostring(rid) .. "\n")
        return
    end
    player.location = rid
    world.look(player)
end

----------------------------------------------------------------------
-- Quit: if fighting, apply FLEE penalty first, persist, then disconnect
----------------------------------------------------------------------

local function do_quit(player)
    if player.in_combat then
        combat.force_breakoff(player)
        local score = player.score or 0
        local loss  = math.floor(score / 32)
        if loss > 0 then
            player:set_score(score - loss)
            player:send("You abandon the fight and lose " .. tostring(loss) .. " points.\n")
        else
            player:send("You abandon the fight.\n")
        end
    end

    database.update_player(player)
    database.save("players.db")

    player:send("Goodbye!\n")
    player:disconnect()
end

----------------------------------------------------------------------
-- GIVE <object> [TO] <player>
-- Wizard/Witch: recipient can be anywhere.
-- Others: recipient must be in the same room.
-- Transfers an item (noun-only match) from giver's inventory to recipient.
----------------------------------------------------------------------

local function do_give(player, arg)
    if not arg or arg == "" then
        player:send("Usage: GIVE <object> <player>  or  GIVE <object> TO <player>\n")
        return
    end

    -- Parse "<obj> TO <who>" or "<obj> <who>"
    local obj_term, who = arg:match("^%s*(.-)%s+[Tt][Oo]%s+(%S+)%s*$")
    if not obj_term then
        obj_term, who = arg:match("^%s*(%S+)%s+(%S+)%s*$")
    end
    if not obj_term or not who then
        player:send("Usage: GIVE <object> <player>  or  GIVE <object> TO <player>\n")
        return
    end

    -- Resolve recipient per rules
    local recipient
    if is_wizard(player) then
        recipient = find_player_by_name(who)
        if not recipient then
            player:send("You cannot find '" .. who .. "'.\n")
            return
        end
    else
        recipient = find_player_in_room_by_name(player.location, who)
        if not recipient then
            player:send("You don't see " .. who .. " here.\n")
            return
        end
    end

    if recipient == player then
        player:send("You cannot give something to yourself.\n")
        return
    end

    -- Find the object in giver's inventory (noun-only)
    local obj = find_inventory_by_noun(player, obj_term)
    if not obj then
        player:send("You are not carrying that.\n")
        return
    end

    -- Remove from giver; auto-unwield if necessary
    local idx
    for i, o in ipairs(player.inventory) do
        if o == obj then idx = i; break end
    end
    if not idx then
        player:send("You are not carrying that.\n")
        return
    end
    table.remove(player.inventory, idx)
    if player.wielded == obj then
        player.wielded = nil
    end

    -- Give to recipient
    recipient.inventory = recipient.inventory or {}
    table.insert(recipient.inventory, obj)
    obj.location = nil -- carried

    -- Notify participants
    local oname = obj.name or "item"
    player:send("You give the " .. oname .. " to " .. recipient.name .. ".\n")
    recipient:send(player.name .. " gives you a " .. oname .. ".\n")

    -- Room broadcast if same room
    if recipient.location == player.location then
        broadcast_room(player.location,
            player.name .. " gives the " .. oname .. " to " .. recipient.name .. ".\n",
            nil -- let everyone else see it (including neither the giver nor recipient excluded)
        )
    end

    -- Enforce carry limit on recipient (may drop-all if overweight)
    enforce_carry_limit(recipient)
end

----------------------------------------------------------------------
-- Command Registry and Abbreviation Precedence
----------------------------------------------------------------------

local COMMANDS = {
    { name="look",      verbs={"LOOK","L"},                handler=do_look },
    { name="exits",     verbs={"EXITS"},                   handler=do_exits },
    { name="examine",   verbs={"EXAMINE"},                 handler=do_examine }, -- (added below)
    { name="get",       verbs={"GET","TAKE"},              handler=do_get },
    { name="drop",      verbs={"DROP"},                    handler=do_drop },
    { name="inventory", verbs={"INVENTORY","INV"},         handler=do_inventory },
    { name="carry",     verbs={"CARRY"},                   handler=do_carry },
    { name="say",       verbs={"SAY"},                     handler=do_say },
    { name="tell",      verbs={"TELL"},                    handler=do_tell },
    { name="shout",     verbs={"SHOUT"},                   handler=do_shout },
    { name="who",       verbs={"WHO"},                     handler=do_who },
    { name="where",     verbs={"WHERE"},                   handler=do_where },
    { name="score",     verbs={"SCORE","STATS"},           handler=do_score },
    { name="attack",    verbs={"ATTACK","KILL"},           handler=do_attack },
    { name="flee",      verbs={"FLEE"},                    handler=do_flee },
    { name="retaliate", verbs={"RETALIATE","RET"},         handler=do_retaliate },
    { name="steal",     verbs={"STEAL"},                   handler=do_steal },
    { name="summon",    verbs={"SUMMON"},                  handler=do_summon },
    { name="invisible", verbs={"INVISIBLE"},               handler=do_invisible },
    { name="visible",   verbs={"VISIBLE"},                 handler=do_visible },
    { name="sgo",       verbs={"SGO"},                     handler=do_sgo },
    { name="help",      verbs={"HELP"},                    handler=do_help },
    { name="quit",      verbs={"QUIT","EXIT"},             handler=do_quit },
    { name="give",      verbs={"GIVE"},                    handler=do_give },
}

-- Abbreviation precedence (used if input verb length ≥ 2 and no exact match)
local ABBREV_ORDER = {
    "LOOK","EXITS","EXAMINE","GET","TAKE","GIVE","DROP","INVENTORY","INV","CARRY",
    "SAY","TELL","SHOUT","STEAL","SUMMON","WHO","WHERE","SCORE","STATS",
    "ATTACK","KILL","FLEE","RETALIATE","HELP","INVISIBLE","VISIBLE","SGO",
    "QUIT","EXIT","TALK"
}

-- Build verb index
local VERB_INDEX = {}
for _, entry in ipairs(COMMANDS) do
    for _, v in ipairs(entry.verbs) do
        VERB_INDEX[v:upper()] = entry
    end
end

-- Resolve command: exact match first, else abbreviation via ABBREV_ORDER
local function resolve_command(word)
    if not word or word == "" then return nil end
    local u = word:upper()
    local exact = VERB_INDEX[u]
    if exact then return exact end
    if #u < 2 then return nil end
    for _, verb in ipairs(ABBREV_ORDER) do
        if verb:sub(1, #u) == u then
            local entry = VERB_INDEX[verb]
            if entry then return entry end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- EXAMINE <object> (placed after resolve_command so handler is in scope)
-- Inspect an object or NPC in the same room.
----------------------------------------------------------------------

local function do_examine(player, arg)
    if not arg or arg == "" then
        player:send("Examine what?\n")
        return
    end

    -- Try object in room (noun-only)
    local obj = objects.find_in_room_by_name(player.location, arg)
    if obj then
        local name   = obj.name   or "Unnamed object"
        local weight = obj.weight or 0
        local value  = obj.value  or 0
        local power  = obj.power  or 0

        player:send("You examine the " .. name .. ":\n")
        player:send(" Weight: " .. tostring(weight) .. "\n")
        player:send(" Value:  " .. tostring(value)  .. "\n")
        player:send(" Power:  " .. tostring(power)  .. "\n")
        return
    end

    -- Try NPC in room (exact-name)
    local inst = npc.find_in_room_by_name(player.location, arg)
    if inst then
        local name  = inst.name  or "Someone"
        local value = inst.value or 0
        local power = inst.power or 0

        player:send("You examine " .. name .. ":\n")
        player:send(" Value: " .. tostring(value) .. "\n")
        player:send(" Power: " .. tostring(power) .. "\n")
        return
    end

    player:send("You see nothing like that here.\n")
end

----------------------------------------------------------------------
-- Dispatcher
----------------------------------------------------------------------

function commands.handle(player, line)
    if not line or line == "" then return end
    local t = tokenize(line)
    local verb = (t[1] or "")
    local arg  = table.concat(t, " ", 2)

    -- Registered commands (with synonyms + abbreviation)
    local entry = resolve_command(verb)
    if entry then
        entry.handler(player, arg)
        return
    end

    -- Movement fallback (supports compass aliases and canonical exit names)
    local vlow  = verb:lower()
    local exits = world.get_exits(player.location) or {}
    if direction_map[vlow] or exits[vlow] then
        try_move(player, vlow)
        return
    end

    player:send("Unknown command.\n")
end

return commands