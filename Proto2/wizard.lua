--============================================================--
-- wizard.lua
--
-- PURPOSE:
--   Implements wizard-only commands and privileged tooling.
--   This module defines commands available exclusively to
--   wizard-level players, including world navigation, object
--   manipulation, inspection, backups, and entry points into
--   in-game editors.
--
--   wizard.lua operates using the shared dispatcher and
--   argspec grammar system and contains no parsing logic.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Registers wizard-only verbs and their argument grammar
--   - Implements privileged actions unavailable to players
--   - Provides inspection and maintenance tools
--   - Acts as the gateway to live in-game editors
--     (OBJEDITOR, PUZZEDITOR, ROOMEDITOR)
--   - Enforces wizard privilege checks centrally
--
--   This module must not require editor or UI code directly
--   and relies on dependency injection to avoid circular
--   dependencies.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- inject_repl(repl)
--   Injects editor entry-point functions from repl.lua
--   (start_object_editor, start_puzzle_editor,
--   start_room_editor). Called once during engine bootstrap.
--
-- handle(player, parsed)
--   Dispatches a parsed wizard command via the internal
--   dispatcher. Returns true if the command was handled.
--
-- get_verbs()
--   Returns a list or set of all registered wizard verbs.
--   Used for introspection or help systems.
--
-- get_argspec(verb)
--   Returns the argspec string associated with a wizard verb,
--   or nil if the verb is not registered here.
--
--============================================================--
--
-- COMMAND HANDLER FUNCTIONS:
--
-- do_wizgo(player, parsed)
--   Teleports the wizard directly to a specified room.
--
-- do_wizget(player, parsed)
--   Retrieves an object from anywhere in the world and places
--   it into the wizard’s inventory.
--
-- do_wizwhere(player, parsed)
--   Locates an object, NPC, or player globally and reports
--   their current room.
--
-- do_wizbackup(player, parsed)
--   Performs a full or selective persistent world backup.
--
-- do_xo(player, parsed)
--   Examines an object in detail, displaying all static
--   object metadata (name, noun list, stats, home, respawn
--   bases, flags, and description) while explicitly excluding
--   puzzle information.
--
-- do_objeditor(player, parsed)
--   Enters OBJEDITOR in create or edit mode.
--
-- do_puzzeditor(player, parsed)
--   Enters PUZZEDITOR for a room, object, or NPC.
--
-- do_roomeditor(player, parsed)
--   Enters ROOMEDITOR in create or edit mode.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * All command grammar is declared at registration time
--     using argspec strings.
--
--   * Wizard-only privilege checks are enforced centrally
--     before any command logic executes.
--
--   * Editor functionality is accessed via injected
--     function references, not direct requires.
--
--   * wizard.lua performs no parsing and must not depend on
--     parser.lua or repl.lua at load time.
--
--============================================================--

local db         = require("database")
local msg        = require("messaging")
local Dispatcher = require("dispatcher")
local movement   = require("movement")
local serpent    = require("serpent")

local Wizard = {}
local dispatch = Dispatcher.new()

-------------------------------------------------
-- Injected editor entry points (set at runtime)
-------------------------------------------------

local start_object_editor
local start_puzzle_editor
local start_room_editor

-------------------------------------------------
-- Dependency injection hook
-------------------------------------------------

function Wizard.inject_repl(repl)
    start_object_editor = repl.start_object_editor
    start_puzzle_editor = repl.start_puzzle_editor
    start_room_editor   = repl.start_room_editor
end

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function id(arg)
    return tonumber(arg:sub(2))
end

local function is_wizard(player)
    return db.get_level(player).level >= 13
end

local function require_wizard(player)
    if not is_wizard(player) then
        msg.to_player(player, "You are not powerful enough to do that.")
        return false
    end
    return true
end

-------------------------------------------------
-- WIZGO @room
-------------------------------------------------

local function do_wizgo(player, parsed)
    if not require_wizard(player) then return end

    local rid = id(parsed.args[1])
    local room = db.world.rooms[rid]
    if not room then
        msg.to_player(player, "No such room.")
        return
    end

    -- remove from old room
    db.world.rooms[player.np.room].np.players[player.id] = nil

    -- move
    player.np.room = rid
    room.np.players[player.id] = true

    movement.describe_room(player, room)
end

-------------------------------------------------
-- WIZGET / MAGICGET g#object
-------------------------------------------------

local function do_wizget(player, parsed)
    if not require_wizard(player) then return end

    local oid = id(parsed.args[1])
    local obj = db.world.objects[oid]
    if not obj or not obj.np then
        msg.to_player(player, "No such object.")
        return
    end

    -- remove from world
    if obj.np.location and obj.np.location > 0 then
        local r = db.world.rooms[obj.np.location]
        if r and r.np.objects then
            r.np.objects[oid] = nil
        end
    end

    obj.np.location = 0
    player.np.inventory[oid] = true

    msg.to_player(player, "Object acquired.")
end

-------------------------------------------------
-- WIZWHERE / WHERE g#$& 
-------------------------------------------------

local function do_wizwhere(player, parsed)
    if not require_wizard(player) then return end

    local arg = parsed.args[1]
    local tag = arg:sub(1,1)
    local ref = id(arg)

    if tag == "#" then
        local o = db.world.objects[ref]
        if o and o.np then
            msg.to_player(player, o.name .. " is in room " .. o.np.location .. ".")
        end
    elseif tag == "$" then
        local n = db.world.npcs[ref]
        if n and n.np then
            msg.to_player(player, n.name .. " is in room " .. n.np.location .. ".")
        end
    elseif tag == "&" then
        local p = db.world.players[ref]
        if p and p.np then
            msg.to_player(player, p.name .. " is in room " .. p.np.room .. ".")
        end
    end
end

-------------------------------------------------
-- WIZBACKUP [#$&@]?
-------------------------------------------------

local function do_wizbackup(player, parsed)
    if not require_wizard(player) then return end

    local arg = parsed.args[1]
    if not arg then
        db.save_all()
        msg.to_player(player, "Full world backup complete.")
        return
    end

    local tag = arg:sub(1,1)
    if tag == "#" then db.save_objects("objects.lua")
    elseif tag == "$" then db.save_npcs("npcs.lua")
    elseif tag == "&" then db.save_players("players.lua")
    elseif tag == "@" then db.save_rooms("rooms.lua")
    end

    msg.to_player(player, "Selective backup complete.")
end

-------------------------------------------------
-- OBJEDITOR
-------------------------------------------------

local function do_objeditor(player, parsed)
    if not require_wizard(player) then return end
    if not start_object_editor then
        msg.to_player(player, "Editor subsystem not available.")
        return
    end

    local text = parsed.args[1] or ""
    local mode, idstr = text:match("^(%S+)%s*(%d*)$")
    if mode == "create" then
        start_object_editor(player, "create")
    elseif mode == "edit" then
        start_object_editor(player, "edit", tonumber(idstr))
    else
        msg.to_player(player, "Usage: objeditor create | objeditor edit <id>")
    end
end

-------------------------------------------------
-- PUZZEDITOR
-------------------------------------------------

local function do_puzzeditor(player, parsed)
    if not require_wizard(player) then return end
    if not start_puzzle_editor then
        msg.to_player(player, "Editor system not available.")
        return
    end

    local ref = parsed.args[1]
    if not ref then
        msg.to_player(player, "Usage: puzzeditor <@room|#object|$npc>")
        return
    end

    local tag = ref:sub(1,1)
    local id  = tonumber(ref:sub(2))

    if tag == "@" then
        start_puzzle_editor(player, "room", id)
    elseif tag == "#" then
        start_puzzle_editor(player, "object", id)
    elseif tag == "$" then
        start_puzzle_editor(player, "npc", id)
    else
        msg.to_player(player, "Usage: puzzeditor <@room|#object|$npc>")
    end
end

-------------------------------------------------
-- ROOMEDITOR
-------------------------------------------------

local function do_roomeditor(player, parsed)
    if not require_wizard(player) then return end
    if not start_room_editor then
        msg.to_player(player, "Editor subsystem not available.")
        return
    end

    local text = parsed.args[1] or ""
    local mode, idstr = text:match("^(%S+)%s*(%d*)$")
    if mode == "create" then
        start_room_editor(player, "create")
    elseif mode == "edit" then
        start_room_editor(player, "edit", tonumber(idstr))
    else
        msg.to_player(player, "Usage: roomeditor create | roomeditor edit <id>")
    end
end

-------------------------------------------------
-- XO (examine object, wizard-only)
-------------------------------------------------

local function do_xo(player, parsed)
    if not require_wizard(player) then return end

    local arg = parsed.args[1]
    local oid = tonumber(arg:sub(2))
    local o = db.world.objects[oid]

    if not o then
        msg.to_player(player, "No such object.")
        return
    end

    -------------------------------------------------
    -- Master line
    -------------------------------------------------

    msg.to_player(
        player,
        'Master Name: "' .. o.name .. '" Object No. ' .. o.id
    )

    -------------------------------------------------
    -- Aux names
    -------------------------------------------------

    if o.noun and #o.noun > 0 then
        msg.to_player(
            player,
            "Aux. names: " .. table.concat(o.noun, ", ")
        )
    else
        msg.to_player(player, "Aux. names: (none)")
    end

    -------------------------------------------------
    -- Core stats
    -------------------------------------------------

    msg.to_player(
        player,
        "Value " .. (o.value or 0) ..
        ", Power " .. (o.power or 0) ..
        ", Weight " .. (o.weight or 0)
    )

    -------------------------------------------------
    -- Home room
    -------------------------------------------------

    if o.home and db.world.rooms[o.home] then
        local r = db.world.rooms[o.home]
        msg.to_player(
            player,
            "Home: " .. r.title .. " (" .. o.home .. ")"
        )
    end

    -------------------------------------------------
    -- Respawn bases
    -------------------------------------------------

    if o.respawn then
        for _, rid in ipairs(o.respawn) do
            local r = db.world.rooms[rid]
            if r then
                msg.to_player(
                    player,
                    "Base: " .. r.title .. " (" .. rid .. ")"
                )
            end
        end
    end

    -------------------------------------------------
    -- Flags (compressed presentation)
    -------------------------------------------------

    local f = o.flags or {}
    local gender = f.ismale and "M" or "F"
    local plural = f.isplural and "P" or "S"
    local vowel  = f.isvowel  and "V" or "C"

    msg.to_player(
        player,
        "Gender " .. gender ..
        ", Plrl/Sing " .. plural ..
        ", Vowel/Cons " .. vowel
    )

    -------------------------------------------------
    -- Description
    -------------------------------------------------

    if o.desc then
        msg.to_player(player, '"' .. o.desc .. '"')
    end

    if o.np then
        msg.to_player(player, ".np = " .. serpent.line(o.np))
    end

end

-------------------------------------------------
-- Dispatch registrations
-------------------------------------------------

dispatch:register("wizgo",      {argspec = "@",     fn = do_wizgo, aliases = { "sgo" }})
dispatch:register("wizget",     {argspec = "g#",    fn = do_wizget, aliases = { "mt" }})
dispatch:register("wizwhere",   {argspec = "g#$&",  fn = do_wizwhere, aliases = { "ww" }})
dispatch:register("wizbackup",  {argspec = "#$&@?", fn = do_wizbackup})
dispatch:register("objeditor",  {argspec = "*",     fn = do_objeditor})
dispatch:register("puzzeditor", {argspec = "g#$@",  fn = do_puzzeditor})
dispatch:register("roomeditor", {argspec = "*",     fn = do_roomeditor})
dispatch:register("xobj",       {argspec = "g#",    fn = do_xo, aliases = { "xo"} })

-------------------------------------------------
-- Public API
-------------------------------------------------

function Wizard.handle(player, parsed)
    return dispatch:handle(player, parsed)
end

function Wizard.get_verbs()
    return dispatch:get_verbs()
end

function Wizard.get_argspec(verb)
    return dispatch:get_argspec(verb)
end

return Wizard
