-- repl.lua
-- In-game editor REPL: OBJEDITOR, PUZZEDITOR, ROOMEDITOR
-- Transactional editing: work on copies; SAVE commits; EXIT discards.

local db  = require("database")
local msg = require("messaging")

local R = {}

-------------------------------------------------
-- Generic helpers
-------------------------------------------------

local function is_wizard(player)
    local lvl = db.get_level(player)
    return lvl and lvl.level and lvl.level >= 13
end

local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do
        r[k] = deep_copy(v)
    end
    return r
end

local function abort(player, message)
    msg.system(player, message)
    player.np.editor = nil
end

local function ensure_table(t)
    if type(t) ~= "table" then return {} end
    return t
end

-------------------------------------------------
-- Shared FIND helpers (tagged output)
-------------------------------------------------

local function find_objects(player, needle)
    if not needle or needle == "" then
        msg.to_player(player, "Usage: FINDOBJ <string>")
        return
    end
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
    if not needle or needle == "" then
        msg.to_player(player, "Usage: FINDNPC <string>")
        return
    end
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
    if not needle or needle == "" then
        msg.to_player(player, "Usage: FINDROOM <string>")
        return
    end
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
-- PUZZEDITOR docs (updated unified API)
-------------------------------------------------

local PUZZLE_TEST_FUNCTIONS = {
    "TRUE()",
    "IF(c,a,b)",
    "IS_OBJ(x)",
    "IS_NPC(x)",
    "IS_PLAYER(x)",
    "IS_ROOM(x)",
    "IS_DIR(x)",
    "HERE(x)",
    "OWNED(x)",
    "NAME(x)                -- returns the name string of an object / NPC / player",
    "IN_ROOM(x, @room)",
    "STATE(x)",
    "STAT(x, key)",
    "IS_LOCKED(>dir, @room)",
    "IS_UNLOCKED(>dir, @room)",
    "CHANCE(x)",
    "LUCKY()",
    "O(x)", "R(x)", "N(x)", "P(x)", "D(x)",
    "ARG1", "ARG2", "TEXT", "RAW",
    "LOCATE(x)              -- returns @room where x is located (#/$/& only)",
    "ME()                   -- returns &player for the acting player",
    "GETVAR(x, key)         -- returns entity.np.vars[key] or nil",
    "IS_CONFUSED(&player?)",
    "IS_DUMB(&player?)",
    "IS_FROZEN(&player?)",
}

local PUZZLE_EFFECT_FUNCTIONS = {
    "ARG1                   -- first parsed argument",
    "ARG2                   -- second parsed argument",
    "TEXT                   -- text after parsed argument",
    "RAW                    -- complete player input line",
    "STINC(x)               -- increment state of x",
    "STDEC(x)               -- decrement state of x",
    "STSET(x, value)        -- set state of x to value",
    "STRESET(x)             -- reset state of x to 0",
    "MOVE(x, @room)         -- move object to room",
    "RESPAWN(x)             -- respawn object x",
    "SCORE(value)           -- increment current players score",
    "SEND(&player, text)    -- send message to player",
    "LOCK(>dir, @room)      -- lock exit direction",
    "UNLOCK(>dir, @room)    -- unlock exit direction",
    "TOGLOCK(>dir, @room)   -- toggle locked exit direction status",
    "SET_DESC(x, text)      -- set alternative object description",
    "O(x)                   -- tagged object #x",
    "R(x)                   -- tagged room @x",
    "N(x)                   -- tagged NPC $x",
    "P(x)                   -- tagged player &x",
    "D(x)                   -- tagged direction >x (1=n,s,e,w,ne,nw,se,sw,u,d,i,o=12)",
    "LOCATE(x)              -- returns @room where x is located (#/$/& only)",
    "ME()                   -- returns &player for the acting player",
    "AFTER(seconds, fn)     -- schedule a function to run later (returns timer id)",
    "CANCEL(timer_id)       -- cancel a scheduled event by id",
    "GETVAR(x, key)         -- returns entity.np.vars[key] or nil",
    "SETVAR(x, key, value)  -- sets entity.np.vars[key] = value",
    "HEAL(num?)             -- add num stamina, or full heal if omitted",
    "HURT(x?)               -- damage $npc or &player (default ME); damage uses STAT(ARG1,'power')",
    "NAME(x)                -- returns the name string of an object / NPC / player",
    "CLEAR_CONFUSED()",
    "CLEAR_DUMB()",
    "CLEAR_FROZEN()",
    "SET_CONFUSED(seconds, &player?)",
    "SET_DUMB(seconds, &player?)",
    "SET_FROZEN(seconds, &player?)",
    "SET_LUCKY(seconds, &player?)",
    "CLEAR_LUCKY(&player?)",
}

-------------------------------------------------
-- PUZZEDITOR expression validation
-- Syntax-only by default, but we provide stubs so common
-- names resolve during pcall if desired in the future.
-------------------------------------------------

local puzzle_test_env_stub = {
    ARG1 = nil, ARG2 = nil, TEXT = "", RAW = "",
    TRUE = function() return true end,
    IF = function() end,
    IS_OBJ = function() end,
    IS_NPC = function() end,
    IS_PLAYER = function() end,
    IS_ROOM = function() end,
    IS_DIR = function() end,
    IS_LOCKED = function() end,
    IS_UNLOCKED = function() end,
    IS_CONFUSED = function() end,
    IS_DUMB = function() end,
    IS_FROZEN = function() end,
    HERE = function() end,
    OWNED = function() end,
    IN_ROOM = function() end,
    STATE = function() end,
    STAT = function() end,
    CHANCE = function() end,
    LUCKY = function() end,
    O = function() end,
    N = function() end,
    P = function() end,
    R = function() end,
    D = function() end,
    LOCATE = function() end,
    ME = function() end,
    GETVAR = function() end,
    NAME = function() end,
}

local puzzle_effect_env_stub = {
    ARG1 = nil, ARG2 = nil, TEXT = "", RAW = "",
    STINC = function() end,
    STDEC = function() end,
    STSET = function() end,
    STRESET = function() end,
    MOVE = function() end,
    RESPAWN = function() end,
    SCORE = function() end,
    SEND = function() end,
    LOCK = function() end,
    UNLOCK = function() end,
    TOGLOCK = function() end,
    SET_DESC = function() end,
    O = function() end,
    N = function() end,
    P = function() end,
    R = function() end,
    D = function() end,
    LOCATE = function() end,
    ME = function() end,
    AFTER = function() end,
    CANCEL = function() end,
    GETVAR = function() end,
    SETVAR = function() end,
    CLEAR_CONFUSED = function() end,
    CLEAR_DUMB = function() end,
    CLEAR_FROZEN = function() end,
    SET_CONFUSED = function() end,
    SET_DUMB = function() end,
    SET_FROZEN = function() end,
    SET_LUCKY = function() end,
    CLEAR_LUCKY = function() end,
    HEAL = function() end,
    HURT = function() end,
    NAME = function() end,
}

local function validate_expression(expr, env, is_test)
    if not expr or expr == "" then
        return false, "Expression cannot be empty."
    end

    local chunk = expr
    if is_test then
        chunk = "return (" .. expr .. ")"
    end

    local fn, err = load(chunk, "puzzle_validate", "t", env)
    if not fn then
        return false, err
    end

    -- Syntax/compile OK. We do not execute user code for side effects.
    return true
end

-------------------------------------------------
-- PUZZEDITOR argspec validation + pretty-print
-- Grammar tokens are space separated.
-- Token form:
--   [g] ( (">") | ( types [.] ) ) [?]
--   OR "*"
-- types is one or more of # $ & @
-- '.' indicates object wildcard (requires '#')
-- '>' indicates direction
-- '*' indicates rest-of-input and must be last token
-------------------------------------------------

local function validate_argspec(spec)
    if not spec or spec == "" then
        return false, "argspec cannot be empty"
    end

    local tokens = {}
    for t in spec:gmatch("%S+") do
        tokens[#tokens + 1] = t
    end

    for i, tok in ipairs(tokens) do
        local label = "argument " .. i

        if tok == "*" then
            if i ~= #tokens then
                return false, label .. ": text:rest (*) must be the final argument"
            end
        else
            local original = tok

            -- global
            if tok:sub(1,1) == "g" then
                tok = tok:sub(2)
                if tok == "" then
                    return false, label .. ": global prefix 'g' must precede a type"
                end
            end

            -- optional
            if tok:sub(-1) == "?" then
                tok = tok:sub(1, -2)
                if tok == "" then
                    return false, label .. ": optional '?' must follow a type"
                end
            end

            if tok == "" then
                return false, label .. ": expected a type"
            end

            -- direction token may be only ">"
            local has_dir = tok:find(">", 1, true) ~= nil
            local has_dot = tok:find("%.", 1) ~= nil

            -- validate chars
            for c in tok:gmatch(".") do
                if c ~= "#" and c ~= "$" and c ~= "&" and c ~= "@" and c ~= "." and c ~= ">" then
                    return false, label .. ": invalid type '" .. c .. "' (allowed: #object $npc &player @room >dir .wildcard)"
                end
            end

            -- if '>' is present, token must be exactly ">"
            if has_dir and tok ~= ">" then
                return false, label .. ": direction specifier must be '>' alone"
            end

            -- if '.' is present, must include '#'
            if has_dot and not tok:find("#", 1, true) then
                return false, label .. ": wildcard '.' requires #object in the same argument"
            end

            -- token cannot be only '.' (nonsense)
            if tok == "." then
                return false, label .. ": wildcard '.' must be combined with #object (use '#.')"
            end

            -- token cannot be empty of any primary type char unless it's '>'
            if tok ~= ">" then
                local has_type = tok:find("[#%$&@]", 1) ~= nil
                if not has_type then
                    return false, label .. ": expected a reference type (#object, $npc, &player, @room) or direction (>)"
                end
            end
        end
    end

    return true
end

-------------------------------------------------
-- PUZZEDITOR argspec expansion (pretty-print)
-- Preferred format:
--   - types within arg: separated by '/'
--   - args separated by ' ' (space)
--   - scope prefix: 'global:' or 'local:'
--   - optional suffix: ':optional'
-- Examples:
--   "$& #?"    -> "local:$npc/&player local:#object:optional"
--   "g#@?"     -> "global:#object/@room:optional"
-------------------------------------------------

local function expand_argspec(spec)
    local out = {}

    for rawtok in spec:gmatch("%S+") do
        -- Rest-of-input token
        if rawtok == "*" then
            out[#out + 1] = "text:rest"
        else
            local tok = rawtok

            -- Scope
            local scope = "local:"
            if tok:sub(1,1) == "g" then
                scope = "global:"
                tok = tok:sub(2)
            end

            -- Optional suffix
            local optional = false
            if tok:sub(-1) == "?" then
                optional = true
                tok = tok:sub(1, -2)
            end

            -- Direction arg
            if tok == ">" then
                local s = scope .. ">dir"
                if optional then s = s .. ":optional" end
                out[#out + 1] = s
            else
                -- Wildcard all objects marker
                local all = false
                if tok:find("%.", 1) then
                    all = true
                    tok = tok:gsub("%.", "")
                end

                -- Expand types (use '/' between types)
                local types = {}
                for c in tok:gmatch(".") do
                    if c == "#" then
                        types[#types + 1] = "#object"
                    elseif c == "$" then
                        types[#types + 1] = "$npc"
                    elseif c == "&" then
                        types[#types + 1] = "&player"
                    elseif c == "@" then
                        types[#types + 1] = "@room"
                    end
                end

                local s = scope .. table.concat(types, "/")
                if all then s = s .. ":all" end
                if optional then s = s .. ":optional" end

                out[#out + 1] = s
            end
        end
    end

    -- Arguments separated by spaces (NOT commas)
    return table.concat(out, " ")
end

-------------------------------------------------
-- OBJEDITOR implementation
-------------------------------------------------

local function obj_list(player)
    local o = player.np.editor.working_copy
    msg.to_player(player, "Object #" .. o.id .. ":")
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

local function obj_save(player)
    local o = player.np.editor.working_copy
    db.world.objects[o.id] = deep_copy(o)
    msg.system(player, "Object #" .. o.id .. " saved.")
    player.np.editor = nil
end

-------------------------------------------------
-- ROOMEDITOR implementation
-------------------------------------------------

local function room_list(player)
    local r = player.np.editor.working_copy
    msg.to_player(player, "Room @" .. r.id .. ":")
    msg.to_player(player, "  title = " .. tostring(r.title))
    msg.to_player(player, "  desc  = " .. tostring(r.desc))
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
    msg.system(player, "Exit " .. dir .. " set to " .. tostring(dest) .. ".")
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
    msg.system(player, "Room @" .. r.id .. " saved.")
    player.np.editor = nil
end

-------------------------------------------------
-- PUZZEDITOR implementation helpers
-------------------------------------------------

local function current_puzzle(ed)
    if not ed.index then return nil end
    return ed.working_copy[ed.index]
end

local function show_verb_entry(player, index, pz)
    msg.to_player(player, "[" .. index .. "] verb=" .. tostring(pz.verb))

    if pz.aliases and #pz.aliases > 0 then
        msg.to_player(player, "    Aliases: " .. table.concat(pz.aliases, " "))
    end

    if pz.argspec then
        msg.to_player(player, "    Argspec: " .. expand_argspec(pz.argspec))
    else
        msg.to_player(player, "    Argspec: (none)")
    end

    if pz.test then msg.to_player(player, "    Test: " .. pz.test) end
    if pz.effect then msg.to_player(player, "    Effect: " .. pz.effect) end

    -- Messages (asucc/afail removed; only wsucc/wfail remain)
    for _, k in ipairs({ "psucc","tsucc","rsucc","pfail","tfail","rfail","wsucc","wfail" }) do
        if pz[k] then
            msg.to_player(player, "    " .. k:upper() .. ": " .. pz[k])
        end
    end
end

-------------------------------------------------
-- Public editor entry points (injected into wizard.lua)
-------------------------------------------------

function R.start_object_editor(player, mode, id)
    if not is_wizard(player) then
        msg.system(player, "Only Wizards may use OBJEDITOR.")
        return
    end

    if mode == "create" then
        local newid = 0
        for k in pairs(db.world.objects) do
            if type(k) == "number" then
                newid = math.max(newid, k + 1)
            end
        end

        local o = {
            id = newid,
            name = "new object",
            noun = {},
            desc = "unfinished object",
            value = 0,
            power = 0,
            weight = 0,
            home = 0,
            respawn = nil,
            flags = {},
            puzzles = nil,
            np = { state = 0, location = 0 }
        }

        player.np.editor = {
            type = "object",
            working_copy = o
        }

        msg.system(player, "OBJEDITOR: creating object #" .. newid)
        return
    end

    if mode == "edit" then
        local o = db.world.objects[id]
        if not o then
            msg.system(player, "No such object.")
            return
        end

        player.np.editor = {
            type = "object",
            working_copy = deep_copy(o)
        }

        msg.system(player, "OBJEDITOR: editing object #" .. id)
        return
    end
end

function R.start_room_editor(player, mode, id)
    if not is_wizard(player) then
        msg.system(player, "Only Wizards may use ROOMEDITOR.")
        return
    end

    if mode == "create" then
        local newid = 0
        for k in pairs(db.world.rooms) do
            if type(k) == "number" then
                newid = math.max(newid, k + 1)
            end
        end

        local r = {
            id = newid,
            title = "New Room",
            desc = "An unfinished place.",
            exits = {},
            flags = {},
            puzzles = nil,
            np = { state = 0 }
        }

        player.np.editor = {
            type = "room",
            working_copy = r
        }

        msg.system(player, "ROOMEDITOR: creating room @" .. newid)
        return
    end

    if mode == "edit" then
        local r = db.world.rooms[id]
        if not r then
            msg.system(player, "No such room.")
            return
        end

        player.np.editor = {
            type = "room",
            working_copy = deep_copy(r)
        }

        msg.system(player, "ROOMEDITOR: editing room @" .. id)
        return
    end
end

function R.start_puzzle_editor(player, kind, id)
    if not is_wizard(player) then
        msg.system(player, "Only Wizards may use PUZZEDITOR.")
        return
    end

    local src =
        (kind == "room"   and db.world.rooms[id]) or
        (kind == "object" and db.world.objects[id]) or
        (kind == "npc"    and db.world.npcs[id]) or
        nil

    if not src then
        msg.system(player, "Invalid puzzle target.")
        return
    end

    src.puzzles = src.puzzles or {}

    player.np.editor = {
        type = "puzzle",
        source = src,
        working_copy = deep_copy(src.puzzles),
        index = nil
    }

    msg.system(player, "PUZZEDITOR started (" .. kind .. " " .. id .. ").")
end

-------------------------------------------------
-- REPL handler
-------------------------------------------------

function R.handle(player, input)
    local ed = player.np.editor
    if not ed then
        return false
    end

    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    rest = rest or ""

    -------------------------------------------------
    -- OBJEDITOR
    -------------------------------------------------
    if ed.type == "object" then
        if cmd == "list" then
            obj_list(player); return true
        elseif cmd == "set" then
            local f, v = rest:match("^(%S+)%s+(.+)$")
            if not f then
                msg.to_player(player, "Usage: SET <field> <value>")
            else
                obj_set(player, f, v)
            end
            return true
        elseif cmd == "find" then
            find_objects(player, rest); return true
        elseif cmd == "save" then
            obj_save(player); return true
        elseif cmd == "exit" then
            abort(player, "OBJEDITOR closed. Changes discarded."); return true
        else
            msg.system(player, "Unknown OBJEDITOR command."); return true
        end
    end

    -------------------------------------------------
    -- ROOMEDITOR
    -------------------------------------------------
    if ed.type == "room" then
        if cmd == "list" then
            room_list(player); return true
        elseif cmd == "listexits" then
            room_list_exits(player); return true
        elseif cmd == "set" then
            local f, v = rest:match("^(%S+)%s+(.+)$")
            if not f then
                msg.to_player(player, "Usage: SET <field> <value>")
            else
                room_set(player, f, v)
            end
            return true
        elseif cmd == "exitadd" then
            local d, rid = rest:match("^(%S+)%s+(%d+)$")
            if not d or not rid then
                msg.to_player(player, "Usage: EXITADD <dir> <room_id>")
            else
                room_exit_add(player, d, tonumber(rid))
            end
            return true
        elseif cmd == "exitdel" then
            if rest == "" then
                msg.to_player(player, "Usage: EXITDEL <dir>")
            else
                room_exit_del(player, rest)
            end
            return true
        elseif cmd == "findroom" then
            find_rooms(player, rest); return true
        elseif cmd == "save" then
            room_save(player); return true
        elseif cmd == "exit" then
            abort(player, "ROOMEDITOR closed. Changes discarded."); return true
        else
            msg.system(player, "Unknown ROOMEDITOR command."); return true
        end
    end

    -------------------------------------------------
    -- PUZZEDITOR
    -------------------------------------------------
    if ed.type == "puzzle" then
        if cmd == "help" then
            msg.to_player(player,
                "PUZZEDITOR commands:\n" ..
                "  NEWVERB <verb> [alias...]\n" ..
                "  EDITVERB <n>\n" ..
                "  DELVERB <n>\n" ..
                "  SHOWVERB\n" ..
                "  ARGSPEC <spec>\n" ..
                "  TEST <expr>\n" ..
                "  EFFECT <expr>\n" ..
                "  PSUCC|RSUCC|PFAIL|RFAIL|WSUCC|WFAIL <text>\n" ..
                "  FINDOBJ <string>\n" ..
                "  FINDNPC <string>\n" ..
                "  FINDROOM <string>\n" ..
                "  LIST\n" ..
                "  LIST TESTS\n" ..
                "  LIST EFFECTS\n" ..
                "  VALIDATE TEST <expr>\n" ..
                "  VALIDATE EFFECT <expr>\n" ..
                "  SAVE\n" ..
                "  EXIT")
            return true
        end

        if cmd == "findobj" then find_objects(player, rest); return true end
        if cmd == "findnpc" then find_npcs(player, rest); return true end
        if cmd == "findroom" then find_rooms(player, rest); return true end

        if cmd == "newverb" then
            if rest == "" then
                msg.to_player(player, "Usage: NEWVERB <verb> [alias...]")
                return true
            end

            local parts = {}
            for w in rest:gmatch("%S+") do parts[#parts+1] = w end

            local pz = {
                verb = parts[1],
                aliases = {},
            }
            for i = 2, #parts do
                pz.aliases[#pz.aliases+1] = parts[i]
            end

            table.insert(ed.working_copy, pz)
            ed.index = #ed.working_copy

            msg.to_player(player, "New verb created at index [" .. ed.index .. "].")
            return true
        end

        if cmd == "editverb" then
            local n = tonumber(rest)
            if not n or not ed.working_copy[n] then
                msg.to_player(player, "Invalid verb index.")
                return true
            end
            ed.index = n
            msg.to_player(player, "Editing verb [" .. n .. "]: " .. tostring(ed.working_copy[n].verb))
            return true
        end

        if cmd == "delverb" then
            local n = tonumber(rest)
            if not n or not ed.working_copy[n] then
                msg.to_player(player, "Invalid verb index.")
                return true
            end

            table.remove(ed.working_copy, n)

            if ed.index == n then
                ed.index = nil
                msg.to_player(player, "Deleted verb [" .. n .. "]. No verb selected.")
            elseif ed.index and ed.index > n then
                ed.index = ed.index - 1
                msg.to_player(player, "Deleted verb [" .. n .. "]. Now editing [" .. ed.index .. "].")
            else
                msg.to_player(player, "Deleted verb [" .. n .. "].")
            end
            return true
        end

        if cmd == "showverb" then
            local pz = current_puzzle(ed)
            if not pz then
                msg.to_player(player, "No verb selected. Use NEWVERB or EDITVERB first.")
                return true
            end
            show_verb_entry(player, ed.index, pz)
            return true
        end

        if cmd == "list" and rest == "" then
            msg.to_player(player, "Puzzles:")
            for i, pz in ipairs(ed.working_copy) do
                show_verb_entry(player, i, pz)
            end
            return true
        end

        if cmd == "list" and rest:lower() == "tests" then
            msg.to_player(player, "Available TEST functions:")
            for _, s in ipairs(PUZZLE_TEST_FUNCTIONS) do
                msg.to_player(player, "  " .. s)
            end
            msg.to_player(player, "Special vars: ARG1, ARG2, TEXT, RAW")
            return true
        end

        if cmd == "list" and rest:lower() == "effects" then
            msg.to_player(player, "Available EFFECT functions:")
            for _, s in ipairs(PUZZLE_EFFECT_FUNCTIONS) do
                msg.to_player(player, "  " .. s)
            end
            msg.to_player(player, "Special vars: ARG1, ARG2, TEXT, RAW")
            return true
        end

        if cmd == "argspec" then
            local pz = current_puzzle(ed)
            if not pz then
                msg.to_player(player, "ARGSPEC requires a verb context. Use NEWVERB or EDITVERB first.")
                return true
            end

            if rest == "" then
                msg.to_player(player, "Usage: ARGSPEC <spec>")
                return true
            end

            local ok, err = validate_argspec(rest)
            if not ok then
                msg.to_player(player, "Argspec error: " .. err)
                return true
            end

            pz.argspec = rest
            msg.to_player(player, "Argspec set: " .. expand_argspec(rest))
            return true
        end

        if cmd == "test" then
            local pz = current_puzzle(ed)
            if not pz then
                msg.to_player(player, "TEST requires a verb context. Use NEWVERB or EDITVERB first.")
                return true
            end
            if rest == "" then
                msg.to_player(player, "Usage: TEST <expression>")
                return true
            end
            local ok, err = validate_expression(rest, puzzle_test_env_stub, true)
            if not ok then
                msg.to_player(player, "TEST error: " .. err)
                return true
            end
            pz.test = rest
            msg.to_player(player, "Test expression set.")
            return true
        end

        if cmd == "effect" then
            local pz = current_puzzle(ed)
            if not pz then
                msg.to_player(player, "EFFECT requires a verb context. Use NEWVERB or EDITVERB first.")
                return true
            end
            if rest == "" then
                msg.to_player(player, "Usage: EFFECT <expression>")
                return true
            end
            local ok, err = validate_expression(rest, puzzle_effect_env_stub, false)
            if not ok then
                msg.to_player(player, "EFFECT error: " .. err)
                return true
            end
            pz.effect = rest
            msg.to_player(player, "Effect expression set.")
            return true
        end

        if cmd == "validate" then
            local kind, expr = rest:match("^(%S+)%s+(.+)$")
            if not kind then
                msg.to_player(player, "Usage: VALIDATE TEST|EFFECT <expr>")
                return true
            end
            kind = kind:lower()
            if kind == "test" then
                local ok, err = validate_expression(expr, puzzle_test_env_stub, true)
                if ok then msg.system(player, "TEST expression is valid.")
                else msg.system(player, "TEST error: " .. err) end
                return true
            elseif kind == "effect" then
                local ok, err = validate_expression(expr, puzzle_effect_env_stub, false)
                if ok then msg.system(player, "EFFECT expression is valid.")
                else msg.system(player, "EFFECT error: " .. err) end
                return true
            else
                msg.to_player(player, "Usage: VALIDATE TEST|EFFECT <expr>")
                return true
            end
        end

        -- Message setters
        for _, k in ipairs({ "psucc","tsucc","rsucc","wsucc","pfail","tfail","rfail","wfail" }) do
            if cmd == k then
                local pz = current_puzzle(ed)
                if not pz then
                    msg.to_player(player, k:upper() .. " requires a verb context. Use NEWVERB or EDITVERB first.")
                    return true
                end
                if rest == "" then
                    msg.to_player(player, "Usage: " .. k:upper() .. " <text>")
                    return true
                end
                pz[k] = rest
                msg.to_player(player, k:upper() .. " set.")
                return true
            end
        end

        if cmd == "save" then
            -- commit working copy to source
            ed.source.puzzles = deep_copy(ed.working_copy)
            msg.system(player, "Puzzles saved.")
            player.np.editor = nil
            return true
        end

        if cmd == "exit" then
            abort(player, "PUZZEDITOR closed. Changes discarded.")
            return true
        end

        msg.system(player, "Unknown PUZZEDITOR command.")
        return true
    end

    msg.system(player, "Unknown editor type.")
    return true
end

return R
