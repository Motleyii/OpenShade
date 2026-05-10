-- puzzle.lua
-- Rule-based puzzle system: verb intercepts with argspec-driven parsing and
-- declarative test/effect strings evaluated in a controlled environment.
-- 
-- Argspec Grammar (Puzzle Verbs)
--     Argspec is a space-separated grammar describing the shape of arguments.
-- 
-- Core types
--     # object reference
--     $ NPC reference
--     & player reference
--     @ room reference
--     > direction reference (canonical codes: n s e w ne nw se sw u d i o)
--     * rest-of-input text (must be last token; captured as a single string)
-- 
-- Modifiers
--     g — global resolution (for that argument token)
--     ? — optional argument
-- 
-- Unions
--     Multiple types in the same argument token mean “one of these types”:
--         "$&"  means NPC or player
--         "#$&" means object or NPC or player
-- 
--     Wildcard “ALL objects”
--         "#." means “ALL objects” (player must type all)
--
-- Parser provided tagged arguments and text strings:
--   ARG1 : parsed.args[1] tagged reference string (or nil)
--   ARG2 : parsed.args[2] tagged reference string (or nil)
--   TEXT : exactly the '*' rest-of-input argument ("" if argspec has no '*')
--   RAW  : complete raw player input string
--
-- NOTE: Puzzle matching consumes the input if verb+argspec match, regardless
-- of test success, so pfail/rfail/etc. can be used without falling through to
-- normal commands.
--
-- Tagged Reference Constructors (avoids need to quote strings)
--   O(num) → #num (object)
--   N(num) → $num (NPC)
--   P(num) → &num (player)
--   R(num) → @num (room)
--   D(num) → >dir where num maps: 1 n, 2 s, 3 e, 4 w, 5 ne, 6 nw, 7 se, 8 sw, 9 u, 10 d, 11 i, 12 o
--
-- TEST Functions
--
--   Type checks (sugar)
--       IS_OBJ(x) / IS_NPC(x) / IS_PLAYER(x) / IS_ROOM(x) / IS_DIR(x)
--   
--   Location / ownership
--       HERE(x)                  — is x in the player’s current room?
--       OWNED(x)                 — is object #id in player inventory?
--       IN_ROOM(x, @room)        — is x located in @room?
--   
--   State / attributes
--       STATE(x)                 — numeric np.state for #/$/@ (0 if unsupported)
--       STAT(x, key)             — static field lookup (e.g. "weight", "power", "title")
--   
--   Exit locks (numeric exits only; strings ignored)
--       IS_LOCKED(>dir, @room)   — exit value < 0
--       IS_UNLOCKED(>dir, @room) — exit value > 0
--   
--   Randomisation
--       CHANCE(p)                — true with p% (clamped 0..100)
--       LUCKY()                  — true with same success chance as SUMMON-style spells
--   
--   Locate / self
--       LOCATE(x)                — returns @room where x is located (x must be #/$/&), else nil
--       ME()                     — returns &<you>
--   
--   Expression helper
--       IF(cond, a, b)           — expression-form if/else
--   
--   Utility
--       TRUE()
--   
-- EFFECT Functions (use in effect = "...")
--   Effects strings are Lua statements. You can separate statements with ; or newlines.
--   You can use [[ ]] multiline enclosures to include full Lua language content in these strings.
--   
--   State effects (unified)
--       STINC(x)                 — state += 1
--       STDEC(x)                 — state -= 1 (clamped to 0)
--       STSET(x, v)              — state = v
--       STRESET(x)               — state = 0
--   
--   Exit lock effects (numeric exits only; strings ignored)
--       LOCK(>dir, @room)        — make exit negative
--       UNLOCK(>dir, @room)      — make exit positive
--       TOGLOCK(>dir, @room)     — flip sign
--   
--   Movement / respawn
--       MOVE(x, @room)           — move #/$/& to room
--       RESPAWN(x)               — respawn object #id to a respawn room/home
--   
--   Score / messaging
--       SCORE(v)                 — adjust acting player score
--       SEND(&player, text)      — whisper/private message
--   
--   Object runtime description (objects only)
--       SET_DESC(#obj, text)     — sets obj.np.desc
--   
--   Timers
--       AFTER(seconds, fn)       — schedule fn later; returns timer id
--       CANCEL(timer_id)         — cancel scheduled timer
--   
--   Persistent runtime vars
--       SETVAR(x, key, value)    — store in x.np.vars[key]
--       GETVAR(x, key)           — fetch value or nil

local db      = require("database")
local msg     = require("messaging")
local parser  = require("parser")
local combat  = require("combat")
local serpent = require("serpent")

local Puzzle = {}

-------------------------------------------------
-- Message emission (success / failure)
-------------------------------------------------

local function find_target_player(parsed)
    local args = parsed.args or {}
    for i = 1, #args do
        local a = args[i]
        if type(a) == "string" and a:sub(1,1) == "&" then
            local pid = tonumber(a:sub(2))
            local p = pid and db.world.players[pid] or nil
            if p and p.np then
                return p
            end
        end
    end
    return nil
end

local function emit_messages(player, parsed, entry, success)
    local target = nil
    if entry.tsucc or entry.tfail then
        target = find_target_player(parsed)
    end

    if success then
        if entry.psucc then msg.to_player(player, msg.format(entry.psucc, player, target)) end
        if entry.tsucc then msg.to_player(target, msg.format(entry.tsucc, player, target)) end
        if entry.rsucc then msg.to_room(player.np.room, msg.format(entry.rsucc, player, target), player.id) end
        if entry.wsucc then msg.to_world(msg.format(entry.wsucc, player, target)) end
    else
        if entry.pfail then msg.to_player(player, msg.format(entry.pfail, player, target)) end
        if entry.tfail then msg.to_player(target, msg.format(entry.tfail, player, target)) end
        if entry.rfail then msg.to_room(player.np.room, msg.format(entry.rfail, player, target), player.id) end
        if entry.wfail then msg.to_world(msg.format(entry.wfail, player, target)) end
    end
end

-------------------------------------------------
-- Tagged reference helpers
-------------------------------------------------

local function ref_tag(x)
    if type(x) ~= "string" or #x == 0 then return nil end
    return x:sub(1, 1)
end

local function ref_is_wildcard_obj(x)
    return x == "#."
end

local function ref_id(x)
    -- returns numeric id for #/$/&/@, or nil for others
    if type(x) ~= "string" or #x < 2 then return nil end
    local t = x:sub(1, 1)
    if t == "#" or t == "$" or t == "&" or t == "@" then
        return tonumber(x:sub(2))
    end
    return nil
end

local function ref_dir(x)
    -- returns canonical short dir for >, e.g. "n", "sw", or nil
    if type(x) ~= "string" or #x < 2 then return nil end
    if x:sub(1, 1) ~= ">" then return nil end
    return x:sub(2)
end

local function get_room_by_ref(roomref)
    if type(roomref) == "number" then
        return db.world.rooms[roomref], roomref
    end
    if type(roomref) == "string" and roomref:sub(1, 1) == "@" then
        local rid = tonumber(roomref:sub(2))
        return rid and db.world.rooms[rid] or nil, rid
    end
    return nil, nil
end

local function get_entity_by_ref(x)
    local t = ref_tag(x)
    if not t then return nil, nil, nil end

    if t == "#" then
        local oid = ref_id(x)
        return db.world.objects[oid], t, oid
    elseif t == "$" then
        local nid = ref_id(x)
        return db.world.npcs[nid], t, nid
    elseif t == "&" then
        local pid = ref_id(x)
        return db.world.players[pid], t, pid
    elseif t == "@" then
        local rid = ref_id(x)
        return db.world.rooms[rid], t, rid
    elseif t == ">" then
        return ref_dir(x), t, nil
    end

    return nil, t, nil
end

local function get_exit_value(dirref, roomref)
    -- dirref must be ">x" and roomref must be "@id" or numeric id
    local dir = ref_dir(dirref)
    if not dir then return nil end

    local r, rid = get_room_by_ref(roomref)
    if not r or not r.exits then return nil end

    return r.exits[dir]
end

local function set_exit_value(dirref, roomref, value)
    local dir = ref_dir(dirref)
    if not dir then return end

    local r, rid = get_room_by_ref(roomref)
    if not r then return end

    r.exits = r.exits or {}
    r.exits[dir] = value
end

-------------------------------------------------
-- Build puzzle expression environment
-------------------------------------------------

local function build_env(player, parsed, raw, has_text)
    local ARG = parsed.args or {}

    -- TEXT is exactly the '*' argument when argspec ends in '*'
    local TEXT = ""
    if has_text then
        TEXT = ARG[#ARG] or ""
        if type(TEXT) ~= "string" then
            TEXT = ""
        end
    end

    local env = {}

    -------------------------------------------------
    -- Safe basic library access
    -------------------------------------------------
    env.tonumber = tonumber
    env.tostring = tostring
    env.math = math
    env.string = string

    -------------------------------------------------
    -- Special parameters
    -------------------------------------------------
    env.ARG  = ARG
    env.ARG1 = ARG[1]
    env.ARG2 = ARG[2]
    env.TEXT = TEXT or ""
    env.RAW  = raw or parsed.raw or ""

    -------------------------------------------------
    -- Tagged reference constructors (avoid quoting)
    -------------------------------------------------

    env.O = function(num)
        num = tonumber(num)
        if not num then return nil end
        return "#" .. math.floor(num)
    end

    env.N = function(num)
        num = tonumber(num)
        if not num then return nil end
        return "$" .. math.floor(num)
    end

    env.P = function(num)
        num = tonumber(num)
        if not num then return nil end
        return "&" .. math.floor(num)
    end

    env.R = function(num)
        num = tonumber(num)
        if not num then return nil end
        return "@" .. math.floor(num)
    end

    local DIR_FROM_NUM = {
        [1]  = "n",
        [2]  = "s",
        [3]  = "e",
        [4]  = "w",
        [5]  = "ne",
        [6]  = "nw",
        [7]  = "se",
        [8]  = "sw",
        [9]  = "u",
        [10] = "d",
        [11] = "i",
        [12] = "o",
    }

    env.D = function(num)
        num = tonumber(num)
        if not num then return nil end
        local d = DIR_FROM_NUM[math.floor(num)]
        if not d then return nil end
        return ">" .. d
    end

    -------------------------------------------------
    -- Utility
    -------------------------------------------------
    env.TRUE = function() return true end

    env.ID = function(x)
        print("ID(" .. x .. ")")
        return ref_id(x)
    end

    env.IF = function(cond, a, b)
        if cond then return a else return b end
    end
 
    -------------------------------------------------
    -- Type sugar (no quoted literals required)
    -------------------------------------------------
    env.IS_OBJ    = function(x) return ref_tag(x) == "#" and not ref_is_wildcard_obj(x) end
    env.IS_WILD   = function(x) return                           ref_is_wildcard_obj(x) end
    env.IS_NPC    = function(x) return ref_tag(x) == "$" end
    env.IS_PLAYER = function(x) return ref_tag(x) == "&" end
    env.IS_ROOM   = function(x) return ref_tag(x) == "@" end
    env.IS_DIR    = function(x) return ref_tag(x) == ">" end

    -------------------------------------------------
    -- Location / ownership predicates
    -------------------------------------------------
    env.HERE = function(x)
        local t = ref_tag(x)
        if not t then return false end

        if t == "#" then
            if ref_is_wildcard_obj(x) then return false end
            local o = db.world.objects[ref_id(x)]
            return o and o.np and o.np.location == player.np.room
        elseif t == "$" then
            local n = db.world.npcs[ref_id(x)]
            return n and n.np and n.np.location == player.np.room
        elseif t == "&" then
            local p = db.world.players[ref_id(x)]
            return p and p.np and p.np.room == player.np.room
        elseif t == "@" then
            local rid = ref_id(x)
            return rid == player.np.room
        end

        return false
    end

    env.OWNED = function(x)
        if ref_tag(x) ~= "#" or ref_is_wildcard_obj(x) then return false end
        local oid = ref_id(x)
        return player.np.inventory and player.np.inventory[oid] == true
    end

    env.IN_ROOM = function(x, roomref)
        local r, rid = get_room_by_ref(roomref)
        if not r or not rid then return false end
        local t = ref_tag(x)
        if t == "#" then
            if ref_is_wildcard_obj(x) then return false end
            local o = db.world.objects[ref_id(x)]
            return o and o.np and o.np.location == rid
        elseif t == "$" then
            local n = db.world.npcs[ref_id(x)]
            return n and n.np and n.np.location == rid
        elseif t == "&" then
            local p = db.world.players[ref_id(x)]
            return p and p.np and p.np.room == rid
        elseif t == "@" then
            return ref_id(x) == rid
        end
        return false
    end

    -------------------------------------------------
    -- State access (unified)
    -------------------------------------------------
    env.STATE = function(x)
        local ent, t = get_entity_by_ref(x)
        if t == "#" or t == "$" or t == "@" then
            if type(ent) == "table" and ent.np then
                print("STATE(" .. x .. ") == " .. ent.np.state)
                return ent.np.state or 0
            end
            print("STATE(" .. x .. ") == no-ent-0")
            return 0
        end
        print("STATE(" .. x .. ") == bad-type-0")
        return 0
    end

    -------------------------------------------------
    -- Static attribute access (unified)
    -------------------------------------------------
    env.STAT = function(x, key)
        local ent, t = get_entity_by_ref(x)
        if (t == "#" or t == "$" or t == "&" or t == "@") and type(ent) == "table" then
            return ent[key]
        end
        return nil
    end

    env.CHANCE = function(p)
        local n = tonumber(p) or 0
        if n < 0 then n = 0 end
        if n > 100 then n = 100 end
        return math.random(100) <= n
    end

    -- TEST / utility: LUCKY() should always succeed if wizard or lucky_until active
    env.LUCKY = function()
        local now = os.time()

        -- Wizard always succeeds
        local lvl = db.get_level(player)
        if lvl and lvl.level and lvl.level >= 13 then
            return true
        end

        -- Lucky status always succeeds
        if player.np and player.np.lucky_until and player.np.lucky_until > now then
            return true
        end

        -- Otherwise fall back to the normal spell-like chance.
        -- If you already have a shared spell success model, call it here.
        -- Minimal default: 50% (replace with your SUMMON formula/lookup).
        local p = 50
        return math.random(100) <= p
    end

    -------------------------------------------------
    -- State effects (unified naming)
    -------------------------------------------------
    local function st_target(x)
        local ent, t = get_entity_by_ref(x)
        if (t == "#" or t == "$" or t == "@") and type(ent) == "table" then
            ent.np = ent.np or {}
            ent.np.state = ent.np.state or 0
            return ent
        end
        return nil
    end

    env.STINC = function(x)
        local ent = st_target(x)
        if ent then
            ent.np.state = ent.np.state + 1
            print("STINC(" .. x .. ") <= " .. ent.np.state)
        else
            print("STINC(" .. x .. ") has no ent")
        end
    end

    env.STDEC = function(x)
        local ent = st_target(x)
        if ent then
            if ent.np.state > 0 then  -- don't decrement np.state to negative
                ent.np.state = ent.np.state - 1
            end
        end
    end

    env.STSET = function(x, v)
        local ent = st_target(x)
        if ent then ent.np.state = tonumber(v) or 0 end
    end

    env.STRESET = function(x)
        local ent = st_target(x)
        if ent then ent.np.state = 0 end
    end

    -------------------------------------------------
    -- Movement / placement
    -------------------------------------------------
    env.MOVE = function(x, roomref)
        local dest, rid = get_room_by_ref(roomref)
        if not dest or not rid then return end

        local t = ref_tag(x)
        if t == "#" then
            if ref_is_wildcard_obj(x) then return end
            local oid = ref_id(x)
            local o = db.world.objects[oid]
            if not o or not o.np then return end

            -- remove from old room set if present
            local old = o.np.location
            if old and old > 0 then
                local rold = db.world.rooms[old]
                if rold and rold.np and rold.np.objects then
                    rold.np.objects[oid] = nil
                end
            end

            o.np.location = rid
            dest.np.objects = dest.np.objects or {}
            dest.np.objects[oid] = true

        elseif t == "$" then
            local nid = ref_id(x)
            local n = db.world.npcs[nid]
            if not n or not n.np then return end

            local old = n.np.location
            if old and old > 0 then
                local rold = db.world.rooms[old]
                if rold and rold.np and rold.np.npcs then
                    rold.np.npcs[nid] = nil
                end
            end

            n.np.location = rid
            dest.np.npcs = dest.np.npcs or {}
            dest.np.npcs[nid] = true

        elseif t == "&" then
            local pid = ref_id(x)
            local p = db.world.players[pid]
            if not p or not p.np then return end

            local old = p.np.room
            if old and old > 0 then
                local rold = db.world.rooms[old]
                if rold and rold.np and rold.np.players then
                    rold.np.players[pid] = nil
                end
            end

            p.np.room = rid
            dest.np.players = dest.np.players or {}
            dest.np.players[pid] = true
        end
    end

    env.RESPAWN = function(x)
        if ref_tag(x) ~= "#" or ref_is_wildcard_obj(x) then return end
        local oid = ref_id(x)
        local o = db.world.objects[oid]
        if not o or not o.np then return end

        -- remove from inventory if carried by acting player
        if player.np.inventory and player.np.inventory[oid] then
            player.np.inventory[oid] = nil
        end

        -- remove from current room set if present
        local old = o.np.location
        if old and old > 0 then
            local rold = db.world.rooms[old]
            if rold and rold.np and rold.np.objects then
                rold.np.objects[oid] = nil
            end
        end

        local rid = 0
        if o.respawn and #o.respawn > 0 then
            rid = o.respawn[math.random(#o.respawn)]
        elseif o.home then
            rid = o.home
        end

        o.np.location = rid
        if rid > 0 and db.world.rooms[rid] then
            db.world.rooms[rid].np.objects = db.world.rooms[rid].np.objects or {}
            db.world.rooms[rid].np.objects[oid] = true
        end
    end

    -- Returns "@<room_id>" for object/npc/player, or nil if unknown/unplaced.
    env.LOCATE = function(x)
        local t = ref_tag(x)
        if t == "#" then
            if x == "#." then return nil end
            local oid = ref_id(x)
            local o = oid and db.world.objects[oid] or nil
            local rid = o and o.np and o.np.location or nil
            if type(rid) == "number" and rid > 0 then
                return "@" .. rid
            end
            return nil

        elseif t == "$" then
            local nid = ref_id(x)
            local n = nid and db.world.npcs[nid] or nil
            local rid = n and n.np and n.np.location or nil
            if type(rid) == "number" and rid > 0 then
                return "@" .. rid
            end
            return nil

        elseif t == "&" then
            local pid = ref_id(x)
            local p = pid and db.world.players[pid] or nil
            local rid = p and p.np and p.np.room or nil
            if type(rid) == "number" and rid > 0 then
                return "@" .. rid
            end
            return nil
        end

        -- Not valid for @room, >dir, text, etc.
        return nil
    end


    -- Current player reference as a tagged &player string
    env.ME = function()
        return "&" .. tostring(player.id)
    end

    -------------------------------------------------
    -- Score / messaging
    -------------------------------------------------
    env.SCORE = function(v)
        local dv = tonumber(v) or 0
        if player.score ~= nil then
            player.score = player.score + dv
        end
        if player.np and player.np.score ~= nil then
            player.np.score = player.np.score + dv
        end
    end

    env.SEND = function(x, text)
        if ref_tag(x) ~= "&" then return end
        local pid = ref_id(x)
        local p = db.world.players[pid]
        if p and p.np then
            msg.to_player(p, tostring(text or ""))
        end
    end

    -------------------------------------------------
    -- TEST: IS_LOCKED / IS_UNLOCKED
    -------------------------------------------------

    env.IS_LOCKED = function(dirref, roomref)
        local ex = get_exit_value(dirref, roomref)
        return type(ex) == "number" and ex < 0
    end

    env.IS_UNLOCKED = function(dirref, roomref)
        local ex = get_exit_value(dirref, roomref)
        return type(ex) == "number" and ex > 0
    end

    -------------------------------------------------
    -- EFFECT: LOCK / UNLOCK / TOGLOCK
    -------------------------------------------------

    env.LOCK = function(dirref, roomref)
        local ex = get_exit_value(dirref, roomref)
        if type(ex) ~= "number" then return end
        if ex > 0 then
            set_exit_value(dirref, roomref, -ex)
        end
    end

    env.UNLOCK = function(dirref, roomref)
        local ex = get_exit_value(dirref, roomref)
        if type(ex) ~= "number" then return end
        if ex < 0 then
            set_exit_value(dirref, roomref, -ex)
        end
    end

    env.TOGLOCK = function(dirref, roomref)
        local ex = get_exit_value(dirref, roomref)
        if type(ex) ~= "number" then return end
        if ex ~= 0 then
            set_exit_value(dirref, roomref, -ex)
        end
    end

    -------------------------------------------------
    -- EFFECT: SET_DESC
    -------------------------------------------------

    env.SET_DESC = function(x, text)
        print("SET_DESC(#" .. x .. ", " .. text .. ")")
        -- Only applies to objects
        if ref_tag(x) ~= "#" or x == "#." then
            return
        end 

        local oid = ref_id(x)
        if not oid then
            return
        end 

        local o = db.world.objects[oid]
        if not o then
            return
        end 

        o.np = o.np or {}
        o.np.desc = tostring(text or "")
    end

    -------------------------------------------------
    -- EFFECT: AFTER
    -------------------------------------------------

    env.AFTER = function(seconds, fn)
        return db.after(seconds, fn)
    end

    env.CANCEL = function(timer_id)
        return db.cancel_timer(timer_id)
    end

    -------------------------------------------------
    -- SETVAR / GETVAR (persistent runtime vars)
    -- Storage: entity.np.vars (table)
    -------------------------------------------------

    local function var_target(x)
        local t = ref_tag(x)
        if not t then return nil end
        if x == "#." then return nil end -- wildcard not allowed
        if t == ">" then return nil end  -- directions not allowed

        local eid = ref_id(x)
        if not eid then return nil end

        if t == "#" then
            return db.world.objects[eid]
        elseif t == "$" then
            return db.world.npcs[eid]
        elseif t == "&" then
            return db.world.players[eid]
        elseif t == "@" then
            return db.world.rooms[eid]
        end

        return nil
    end

    env.SETVAR = function(x, key, value)
        local ent = var_target(x)
        if not ent then return end

        ent.np = ent.np or {}
        ent.np.vars = ent.np.vars or {}

        local k = tostring(key)
        ent.np.vars[k] = value
    end

    env.GETVAR = function(x, key)
        local ent = var_target(x)
        if not ent or not ent.np or not ent.np.vars then
            return nil
        end

        local k = tostring(key)
        return ent.np.vars[k]
    end

    -------------------------------------------------
    -- Status effect helpers (players only)
    -- confused_until / dumb_until / frozen_until are epoch seconds
    -------------------------------------------------

    local function status_target(pref)
        -- Optional player reference (&id). If nil, use acting player.
        if pref == nil then
            return player
        end
        if type(pref) ~= "string" or pref:sub(1,1) ~= "&" then
            return nil
        end
        local pid = tonumber(pref:sub(2))
        local p = pid and db.world.players[pid] or nil
        return (p and p.np) and p or nil
    end

    local function is_active_until(p, field, now)
        if not p or not p.np then return false end
        local until_t = p.np[field]
        if type(until_t) ~= "number" then
            return false
        end
        return until_t > now
    end

    local function clear_until(p, field)
        if not p or not p.np then return end
        p.np[field] = nil
    end

    local function set_until(p, field, seconds, now)
        if not p or not p.np then return end
        local s = tonumber(seconds) or 0
        if s < 0 then s = 0 end
        p.np[field] = now + math.floor(s)
    end

    -- TEST: status active? (optional &player, defaults to ME)
    env.IS_CONFUSED = function(pref)
        local now = os.time()
        local p = status_target(pref)
        return is_active_until(p, "confused_until", now)
    end

    env.IS_DUMB = function(pref)
        local now = os.time()
        local p = status_target(pref)
        return is_active_until(p, "dumb_until", now)
    end

    env.IS_FROZEN = function(pref)
        local now = os.time()
        local p = status_target(pref)
        return is_active_until(p, "frozen_until", now)
    end

    -- EFFECT: clear status on acting player (instant cure)
    env.CLEAR_CONFUSED = function()
        clear_until(player, "confused_until")
    end

    env.CLEAR_DUMB = function()
        clear_until(player, "dumb_until")
    end

    env.CLEAR_FROZEN = function()
        clear_until(player, "frozen_until")
    end

    -- EFFECT: set status for duration seconds (optional &player, defaults to ME)
    env.SET_CONFUSED = function(seconds, pref)
        local now = os.time()
        local p = status_target(pref) or player
        set_until(p, "confused_until", seconds, now)
    end

    env.SET_DUMB = function(seconds, pref)
        local now = os.time()
        local p = status_target(pref) or player
        set_until(p, "dumb_until", seconds, now)
    end

    env.SET_FROZEN = function(seconds, pref)
        local now = os.time()
        local p = status_target(pref) or player
        set_until(p, "frozen_until", seconds, now)
    end

    -- EFFECT: set lucky for duration seconds (optional &player, defaults to ME)
    env.SET_LUCKY = function(seconds, pref)
        local now = os.time()
        local p = status_target(pref) or player
        set_until(p, "lucky_until", seconds, now)
    end

    -- EFFECT: clear lucky immediately (optional &player, defaults to ME)
    env.CLEAR_LUCKY = function(pref)
        local p = status_target(pref) or player
        clear_until(p, "lucky_until")
    end
    -------------------------------------------------
    -- HEAL(num) effect
    -- - HEAL() fully heals the acting player
    -- - HEAL(n) adds n stamina (clamped to max)
    -------------------------------------------------

    env.HEAL = function(num)
        if not player or not player.np then return end

        local level_info = db.get_level(player)
        local maxs = (level_info and tonumber(level_info.max_stamina)) or (player.max_stamina or 0)
        if maxs < 0 then maxs = 0 end

        -- Ensure stamina exists
        player.np.stamina = tonumber(player.np.stamina) or 0

        if num == nil then
            -- Full heal
            player.np.stamina = maxs
            return
        end

        local n = tonumber(num) or 0
        player.np.stamina = player.np.stamina + n

        if player.np.stamina > maxs then
            player.np.stamina = maxs
        end
        if player.np.stamina < 0 then
            player.np.stamina = 0
        end
    end

    -------------------------------------------------
    -- HURT(x?) effect
    -- Damages a player or npc. Target defaults to ME().
    -- Damage amount is derived from STAT(ARG1,"power") (object power).
    -------------------------------------------------

    local function hurt_target_ref(x)
        -- x may be nil (default ME), or $id or &id
        if x == nil then
            return "&" .. tostring(player.id)
        end
        if type(x) ~= "string" then
            return nil
        end
        local t = x:sub(1,1)
        if t == "$" or t == "&" then
            return x
        end
        return nil
    end

    local function get_damage_from_arg1()
        -- derive damage from the acting object power (ARG1)
        local pwr = env.STAT and env.STAT(env.ARG1, "power") or nil
        local dmg = tonumber(pwr) or 0
        if dmg < 0 then dmg = 0 end
        return dmg
    end

    env.HURT = function(x)
        local target_ref = hurt_target_ref(x)
        if not target_ref then return end

        local dmg = get_damage_from_arg1()
        if dmg <= 0 then return end

        local tag = target_ref:sub(1,1)
        local id  = tonumber(target_ref:sub(2))
        if not id then return end

        if tag == "&" then
            local p = db.world.players[id]
            if not p or not p.np then return end

            p.np.stamina = tonumber(p.np.stamina) or 0
            p.np.stamina = p.np.stamina - dmg
            if p.np.stamina < 0 then p.np.stamina = 0 end

            msg.to_player(p, "You are hurt for " .. dmg .. " stamina!")

            if p.np.stamina <= 0 then
                -- Prefer central death handling if you have it
                if combat and combat.handle_death then
                    combat.handle_death(p, player)  -- killer is acting player (or self for bombs)
                else
                    -- Fallback: simple message (replace with your real player death flow)
                    msg.to_room(p.np.room, p.name .. " collapses.", nil)
                end
            end

        elseif tag == "$" then
            local n = db.world.npcs[id]
            if not n or not n.np then return end

            n.np.stamina = tonumber(n.np.stamina) or 0
            n.np.stamina = n.np.stamina - dmg
            if n.np.stamina < 0 then n.np.stamina = 0 end

            msg.to_room(player.np.room, n.name .. " is hit for " .. dmg .. "!", nil)

            if n.np.stamina <= 0 then
                if combat and combat.handle_death then
                    combat.handle_death(n, player)
                else
                    -- Fallback removal
                    local r = db.world.rooms[n.np.location]
                    if r and r.np and r.np.npcs then
                        r.np.npcs[id] = nil
                    end
                end
            end
        end
    end

    -------------------------------------------------
    -- NAME(x) helper
    -- Returns the display name of an object/npc/player.
    -- x must be #id, $id, or &id. Returns "" if unknown.
    -------------------------------------------------

    env.NAME = function(x)
        if type(x) ~= "string" then
            return ""
        end

        local t = x:sub(1,1)
        if t == "#" then
            if x == "#." then return "" end
            local oid = tonumber(x:sub(2))
            local o = oid and db.world.objects[oid] or nil
            return (o and o.name) or ""

        elseif t == "$" then
            local nid = tonumber(x:sub(2))
            local n = nid and db.world.npcs[nid] or nil
            return (n and n.name) or ""

        elseif t == "&" then
            local pid = tonumber(x:sub(2))
            local p = pid and db.world.players[pid] or nil
            return (p and p.name) or ""
        end

        -- Not meaningful for @room, >dir, etc.
        return ""
    end

    return env
end

-------------------------------------------------
-- Expression evaluation
-------------------------------------------------

local function eval_test(expr, env)
    if not expr or expr == "" then
        return true
    end
    local fn, err = load("return (" .. expr .. ")", "puzzle_test", "t", env)
    if not fn then
        return false
    end
    local ok, result = pcall(fn)
    if not ok then
        return false
    end
    return result and true or false
end

local function eval_effect(code, env)
    if not code or code == "" then
        return true
    end

    local fn, err = load(code, "puzzle_effect", "t", env)
    if not fn then
        return false
    end
    local ok = pcall(fn)

    return ok and true or false
end

-------------------------------------------------
-- Try a single puzzle entry
-------------------------------------------------

local function try_puzzle(player, raw, entry)
    if not entry or not entry.verb or not entry.argspec then
        return false
    end

    local parsed = parser.parse_with_argspec(player, raw, entry.argspec)
    if not parsed then
        return false
    end

    if parsed.verb ~= entry.verb then
        return false
    end

    local has_text = entry.argspec:match("%*%s*$") ~= nil
    local env = build_env(player, parsed, raw, has_text)

    local success = eval_test(entry.test, env)

    emit_messages(player, parsed, entry, success)

    if success and entry.effect then
        eval_effect(entry.effect, env)
    end

    return success
end

-------------------------------------------------
-- Public API: process player input through puzzles
-------------------------------------------------

function Puzzle.process(player, raw)
    local room = db.world.rooms[player.np.room]
    if not room then
        return false
    end

    -- 1) room puzzles
    for _, pz in ipairs(room.puzzles or {}) do
        if try_puzzle(player, raw, pz) then
            return true
        end
    end

    -- 2) object puzzles (for objects present)
    for oid in pairs(room.np.objects or {}) do
        local o = db.world.objects[oid]
        if o and o.puzzles then
            for _, pz in ipairs(o.puzzles) do
                if try_puzzle(player, raw, pz) then
                    return true
                end
            end
        end
    end

    -- 3) npc puzzles (for npcs present)
    for nid in pairs(room.np.npcs or {}) do
        local n = db.world.npcs[nid]
        if n and n.puzzles then
print("Puzz: trying puzzles for " .. n.name)
            for _, pz in ipairs(n.puzzles) do
                if try_puzzle(player, raw, pz) then
                    return true
                end
            end
        else
print("Puzz: no puzzles on " .. n.name)
        end
    end

    return false
end

return Puzzle
