--============================================================--
-- repl.lua
--
-- PURPOSE:
--   Interactive editor REPL (Read–Eval–Print-Loop) for live
--   world construction and maintenance. This module provides
--   in-game editing facilities for objects, puzzles, and rooms
--   without requiring server restarts.
--
--   repl.lua implements editor command interpretation and
--   transactional editing. All changes are performed on
--   working copies and are only committed to the live world
--   when explicitly saved.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Provides interactive editing shells (OBJEDITOR,
--     PUZZEDITOR, ROOMEDITOR)
--   - Manages editor state per player
--   - Enforces SAVE / EXIT semantics to prevent partial writes
--   - Does not perform parsing of player commands outside
--     editor mode
--   - Does not execute gameplay logic
--
--   repl.lua sits above core systems such as parser.lua,
--   dispatcher.lua, and database.lua and must not be required
--   by them to avoid circular dependencies.
--
--============================================================--
--
-- GENERAL EDITOR MODEL:
--
--   * Editors are entered explicitly via wizard commands.
--   * All edits occur on a private working copy.
--   * SAVE commits the working copy to live world data.
--   * EXIT discards all uncommitted changes.
--   * Only one editor may be active per player at a time.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- start_object_editor(player, mode, id)
--   Enters OBJEDITOR in CREATE or EDIT mode. Creates or clones
--   an object record into a working copy for editing.
--
-- start_puzzle_editor(player, kind, id)
--   Enters PUZZEDITOR for a room, object, or NPC. Copies the
--   target’s puzzle table into a working working copy.
--
-- start_room_editor(player, mode, id)
--   Enters ROOMEDITOR in CREATE or EDIT mode. Creates or clones
--   a room definition into a working copy.
--
-- handle(player, input)
--   Handles all editor-mode input. Dispatches editor commands
--   based on the active editor type and current context.
--   Returns true if the input was consumed by the editor.
--
--============================================================--
--
-- OBJEDITOR COMMANDS:
--
--   OBJEDITOR edits object definitions (name, descriptions,
--   flags, stats, respawn data, etc.).
--
--   LIST
--     Displays all editable fields of the current object.
--
--   SET <field> <value>
--     Sets a named field on the working copy.
--
--   FIND <string>
--     Searches all objects by name substring and displays
--     matching object IDs.
--
--   SAVE
--     Commits the working copy to the live object database.
--
--   EXIT
--     Discards the working copy and exits OBJEDITOR.
--
--============================================================--
--
-- PUZZEDITOR COMMANDS:
--
--   PUZZEDITOR edits verb-based puzzle entries for rooms,
--   objects, and NPCs. Each puzzle entry represents a single
--   verb with its own argspec, test, effect, and messages.
--
--   NEWVERB <verb> [aliases...]
--     Creates a new puzzle verb entry and sets the edit context.
--
--   EDITVERB <index>
--     Switches the edit context to an existing verb entry.
--
--   DELVERB <index>
--     Deletes a verb entry from the working copy.
--
--   SHOWVERB
--     Displays the currently selected verb entry.
--
--   LIST
--     Lists all verb entries with indices and summaries.
--
--   ARGSPEC <spec>
--     Sets the argument grammar for the current verb entry.
--
--   TEST <expression>
--     Sets the test expression for the current verb entry.
--
--   EFFECT <expression>
--     Sets the effect expression for the current verb entry.
--
--   PSUCC / RSUCC / PFAIL / RFAIL / ASUCC / AFAIL / WSUCC / WFAIL <text>
--     Sets success or failure messages for the current verb.
--
--   FINDOBJ <string>
--     Searches all objects by name substring.
--
--   FINDNPC <string>
--     Searches all NPCs by name substring.
--
--   FINDROOM <string>
--     Searches all rooms by title substring.
--
--   SAVE
--     Commits all puzzle edits to the live world data.
--
--   EXIT
--     Discards all uncommitted puzzle edits and exits PUZZEDITOR.
--
--============================================================--
--
-- ROOMEDITOR COMMANDS:
--
--   ROOMEDITOR edits room definitions and connectivity.
--
--   LIST
--     Displays core room fields (title, description, flags).
--
--   LISTEXITS
--     Displays all exits from the room and their destinations.
--
--   SET <field> <value>
--     Sets a named room field on the working copy.
--
--   EXITADD <direction> <room_id>
--     Adds or updates an exit in the given direction.
--
--   EXITDEL <direction>
--     Removes an exit from the room.
--
--   SETFLAG <flag>
--     Adds a room flag.
--
--   CLRFLAG <flag>
--     Removes a room flag.
--
--   FINDROOM <string>
--     Searches all rooms by title substring.
--
--   SAVE
--     Commits the working copy to the live room database.
--
--   EXIT
--     Discards the working copy and exits ROOMEDITOR.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * repl.lua is user-facing but not gameplay-facing.
--   * All validation and syntax checking happens before
--     committing changes.
--   * Editors must never mutate live world data directly.
--   * Dependency injection is used to avoid circular requires
--     between REPL and wizard command modules.
--
--============================================================--

local db  = require("database")
local msg = require("messaging")
--local puzzle = require("puzzle")

local R = {}

-------------------------------------------------
-- Generic helpers
-------------------------------------------------

local function is_wizard(player)
    return db.get_level(player).level >= 13
end

local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = deep_copy(v) end
    return r
end

local function abort(player, message)
    msg.system(player, message)
    player.np.editor = nil
end

-------------------------------------------------
-- FIND helpers (shared)
-------------------------------------------------

local function find_objects(player, needle)
    needle = needle:lower()
    local found = false
    for id, o in pairs(db.world.objects) do
        if o.name and o.name:lower():find(needle, 1, true) then
            msg.to_player(player, "#" .. id .. " " .. o.name)
            found = true
        end
    end
    if not found then msg.to_player(player, "No objects matched.") end
end

local function find_npcs(player, needle)
    needle = needle:lower()
    local found = false
    for id, n in pairs(db.world.npcs) do
        if n.name and n.name:lower():find(needle, 1, true) then
            msg.to_player(player, "$" .. id .. " " .. n.name)
            found = true
        end
    end
    if not found then msg.to_player(player, "No NPCs matched.") end
end

local function find_rooms(player, needle)
    needle = needle:lower()
    local found = false
    for id, r in pairs(db.world.rooms) do
        if r.title and r.title:lower():find(needle, 1, true) then
            msg.to_player(player, "@" .. id .. " " .. r.title)
            found = true
        end
    end
    if not found then msg.to_player(player, "No rooms matched.") end
end

-------------------------------------------------
-- OBJEDITOR
-------------------------------------------------

local function obj_list(player)
    local o = player.np.editor.working_copy
    msg.to_player(player, "Object " .. o.id .. ":")
    for k, v in pairs(o) do
        if k ~= "np" then
            msg.to_player(player, "  " .. k .. " = " .. tostring(v))
        end
    end
end

local function obj_set(player, field, value)
    local o = player.np.editor.working_copy
    if o[field] == nil then
        msg.system(player, "Unknown field.")
        return
    end
    o[field] = value
    msg.system(player, field .. " updated.")
end

local function obj_find(player, term)
    find_objects(player, term)
end

local function obj_save(player)
    local o = player.np.editor.working_copy
    db.world.objects[o.id] = deep_copy(o)
    msg.system(player, "Object " .. o.id .. " saved.")
    player.np.editor = nil
end

function R.start_object_editor(player, mode, id)
    if not is_wizard(player) then
        msg.system(player, "Only Wizards may use OBJEDITOR.")
        return
    end

    if mode == "create" then
        local newid = 0
        for k in pairs(db.world.objects) do newid = math.max(newid, k + 1) end
        local o = {
            id=newid,
            name="new object",
            desc="unfinished object",
            noun={},
            home=0,
            respawn=nil,
            value=0,
            weight=0,
            power=0,
            flags={},
            puzzles={},
            np={state=0,location=0}
        }
        player.np.editor = { type="object", working_copy=o }
        msg.system(player,"OBJEDITOR: creating object "..newid)
        return
    end

    if mode == "edit" then
        local o = db.world.objects[id]
        if not o then msg.system(player,"No such object.") return end
        player.np.editor = { type="object", working_copy=deep_copy(o) }
        msg.system(player,"OBJEDITOR: editing object "..id)
    end
end

-------------------------------------------------
-- ROOMEDITOR
-------------------------------------------------

local function room_list(player)
    local r = player.np.editor.working_copy
    msg.to_player(player, "Room " .. r.id .. ":")
    msg.to_player(player, "  Title: " .. r.title)
    msg.to_player(player, "  Desc: " .. (r.desc or ""))
end

local function room_list_exits(player)
    local r = player.np.editor.working_copy
    msg.to_player(player, "Exits:")
    for dir, dest in pairs(r.exits or {}) do
        msg.to_player(player, "  " .. dir .. " -> " .. tostring(dest))
    end
end

local function room_set(player, field, value)
    local r = player.np.editor.working_copy
    if r[field] == nil then
        msg.system(player, "Unknown field.")
        return
    end
    r[field] = value
    msg.system(player, field .. " updated.")
end

local function room_exit_add(player, dir, dest)
    local r = player.np.editor.working_copy
    r.exits = r.exits or {}
    r.exits[dir] = dest
    msg.system(player, "Exit " .. dir .. " set to " .. dest .. ".")
end

local function room_exit_del(player, dir)
    local r = player.np.editor.working_copy
    if r.exits and r.exits[dir] then
        r.exits[dir] = nil
        msg.system(player, "Exit " .. dir .. " removed.")
    else
        msg.system(player, "No such exit.")
    end
end

local function room_save(player)
    local r = player.np.editor.working_copy
    db.world.rooms[r.id] = deep_copy(r)
    msg.system(player, "Room " .. r.id .. " saved.")
    player.np.editor = nil
end

function R.start_room_editor(player, mode, id)
    if not is_wizard(player) then
        msg.system(player, "Only Wizards may use ROOMEDITOR.")
        return
    end

    if mode == "create" then
        local newid = 0
        for k in pairs(db.world.rooms) do newid = math.max(newid, k + 1) end
        local r = {
            id=newid,
            title="New Room",
            desc="An unfinished place.",
            flags={},
            exits={},
            puzzles={},
            np={state=0}
        }
        player.np.editor = { type="room", working_copy=r }
        msg.system(player,"ROOMEDITOR: creating room "..newid)
        return
    end

    if mode == "edit" then
        local r = db.world.rooms[id]
        if not r then msg.system(player,"No such room.") return end
        player.np.editor = { type="room", working_copy=deep_copy(r) }
        msg.system(player,"ROOMEDITOR: editing room "..id)
    end
end

-------------------------------------------------
-- PUZZEDITOR helpers
-------------------------------------------------

local function current_puzzle(ed)
    if not ed.index then return nil end
    return ed.working_copy[ed.index]
end

local function show_verb_entry(player, index, pz)
    msg.to_player(player, "["..index.."] verb="..pz.verb)
    if pz.aliases and #pz.aliases > 0 then
        msg.to_player(player, "    Aliases: " .. table.concat(pz.aliases, " "))
    end
    if pz.argspec then
        msg.to_player(player, "    Argspec: " .. pz.argspec)
    end
    if pz.test then msg.to_player(player, "    Test: " .. pz.test) end
    if pz.effect then msg.to_player(player, "    Effect: " .. pz.effect) end
end

-------------------------------------------------
-- PUZZEDITOR
-------------------------------------------------

function R.start_puzzle_editor(player, kind, id)
    if not is_wizard(player) then
        msg.system(player, "Only Wizards may use PUZZEDITOR.")
        return
    end

    local src =
        kind=="room"   and db.world.rooms[id] or
        kind=="object" and db.world.objects[id] or
        kind=="npc"    and db.world.npcs[id]

    if not src then msg.system(player,"Invalid puzzle target.") return end

    player.np.editor = {
        type="puzzle",
        source=src,
        working_copy=deep_copy(src.puzzles or {}),
        index=nil
    }
    msg.system(player,"PUZZEDITOR started.")
end

-------------------------------------------------
-- REPL handler
-------------------------------------------------

function R.handle(player, input)
    local ed = player.np.editor
    if not ed then return false end

    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower()

    -------------------------------------------------
    -- OBJEDITOR
    -------------------------------------------------
    if ed.type=="object" then
        if cmd=="list" then obj_list(player)
        elseif cmd=="set" then
            local f,v = rest:match("^(%S+)%s+(.+)$")
            if f then obj_set(player,f,v) end
        elseif cmd=="find" then obj_find(player, rest)
        elseif cmd=="save" then obj_save(player)
        elseif cmd=="exit" then abort(player,"OBJEDITOR closed.")
        else msg.system(player,"Unknown OBJEDITOR command.")
        end
        return true
    end

    -------------------------------------------------
    -- ROOMEDITOR
    -------------------------------------------------
    if ed.type=="room" then
        if cmd=="list" then room_list(player)
        elseif cmd=="listexits" then room_list_exits(player)
        elseif cmd=="set" then
            local f,v = rest:match("^(%S+)%s+(.+)$")
            if f then room_set(player,f,v) end
        elseif cmd=="exitadd" then
            local d,r = rest:match("^(%S+)%s+(%d+)$")
            if d and r then room_exit_add(player,d,tonumber(r)) end
        elseif cmd=="exitdel" then room_exit_del(player, rest)
        elseif cmd=="findroom" then find_rooms(player, rest)
        elseif cmd=="save" then room_save(player)
        elseif cmd=="exit" then abort(player,"ROOMEDITOR closed.")
        else msg.system(player,"Unknown ROOMEDITOR command.")
        end
        return true
    end

    -------------------------------------------------
    -- PUZZEDITOR
    -------------------------------------------------
    if ed.type=="puzzle" then
        if cmd=="findobj" then find_objects(player, rest)
        elseif cmd=="findnpc" then find_npcs(player, rest)
        elseif cmd=="findroom" then find_rooms(player, rest)
        elseif cmd=="newverb" then
            local parts={}
            for w in rest:gmatch("%S+") do parts[#parts+1]=w end
            local pz={ verb=parts[1], aliases={} }
            for i=2,#parts do table.insert(pz.aliases, parts[i]) end
            table.insert(ed.working_copy,pz)
            ed.index=#ed.working_copy
            msg.to_player(player,"New verb created.")
        elseif cmd=="editverb" then
            local i=tonumber(rest)
            if not i or not ed.working_copy[i] then
                msg.to_player(player,"Invalid verb index.")
                return true
            end
            ed.index=i
            msg.to_player(player,"Editing verb "..ed.working_copy[i].verb)
        elseif cmd=="showverb" then
            local pz=current_puzzle(ed)
            if pz then show_verb_entry(player, ed.index, pz)
            else msg.to_player(player,"No verb selected.") end
        elseif cmd=="list" then
            for i,pz in ipairs(ed.working_copy) do
                show_verb_entry(player,i,pz)
            end
        elseif cmd=="save" then
            ed.source.puzzles = deep_copy(ed.working_copy)
            msg.system(player,"Puzzles saved.")
            player.np.editor=nil
        elseif cmd=="exit" then abort(player,"PUZZEDITOR closed.")
        else msg.system(player,"Unknown PUZZEDITOR command.")
        end
        return true
    end

    return false
end

return R