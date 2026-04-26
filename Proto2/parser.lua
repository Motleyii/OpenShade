--============================================================--
-- parser.lua
--
-- PURPOSE:
--   Central command and puzzle input parsing system.
--   This module is responsible for transforming raw player
--   input strings into structured, validated command forms
--   based on declarative argument specifications (argspecs).
--
--   parser.lua performs no gameplay logic and invokes no
--   command, spell, or puzzle effects itself. Its sole role
--   is to interpret input text and resolve references to
--   world entities in a consistent, reliable manner.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Tokenizes raw player input
--   - Identifies the verb being invoked
--   - Retrieves argument grammar (argspec) from higher-level
--     systems (commands, spells, wizard commands)
--   - Resolves textual arguments into tagged entity references
--     (#object, $npc, &player, @room)
--   - Enforces local vs global resolution rules
--   - Rejects malformed input before gameplay logic runs
--
--   This module is intentionally dependency-light and must
--   not require high-level gameplay or editor modules.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- tokenize(input)
--   Splits a raw input string into an ordered list of
--   whitespace-delimited tokens.
--
-- matches_name_or_noun(entity, word)
--   Returns true if the given word matches the entity’s
--   primary name or any of its alternative noun identifiers.
--
-- resolve_local(player, type_char, word)
--   Attempts to resolve an argument word to a locally visible
--   entity of the specified type (object, NPC, player, room)
--   relative to the player’s current context.
--
-- resolve_global(type_char, word)
--   Attempts to resolve an argument word to an entity of the
--   specified type anywhere in the world.
--
-- parse_spec_token(token)
--   Parses a single argspec token and returns a structured
--   description including allowed entity types, optionality,
--   scope (local/global), and rest-of-input semantics.
--
-- parse(player, input)
--   Parses raw player input using argspecs registered by
--   commands, spells, and wizard subsystems.
--   Returns a parsed command table on success or nil on
--   failure. Used for normal player command execution.
--
-- parse_with_argspec(player, input, argspec)
--   Parses raw input against an explicit argspec string.
--   Used exclusively by the puzzle system to test whether
--   a given puzzle grammar matches player input.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * parser.lua must never invoke command handlers or
--     gameplay effects.
--
--   * All argument grammar is declarative and externalized
--     via argspec strings.
--
--   * The parser must remain independent of editor and UI
--     systems to avoid circular dependencies.
--
--   * All returned parsed arguments are guaranteed to be
--     valid, resolved, and correctly typed.
--
--============================================================--


local db       = require("database")
local serpent  = require("serpent")
local commands = require("commands")
local spells   = require("spells")
local wizard   = require("wizard")

local Parser = {}

-------------------------------------------------
-- Known verbs
-------------------------------------------------

local registered_verbs = {}

local function merge_registered(dst, src)
    for k in pairs(src) do
        dst[k:lower()] = true
    end
end

merge_registered(registered_verbs, commands.get_verbs())
merge_registered(registered_verbs, spells.get_verbs())
merge_registered(registered_verbs, wizard.get_verbs())

-------------------------------------------------
-- Direction vocabulary (canonical short codes)
-------------------------------------------------

local DIRECTIONS = {
    -- Cardinal
    north = "n",  n = "n",
    south = "s",  s = "s",
    east  = "e",  e = "e",
    west  = "w",  w = "w",

    -- Diagonals
    northeast = "ne", ne = "ne",
    northwest = "nw", nw = "nw",
    southeast = "se", se = "se",
    southwest = "sw", sw = "sw",

    -- Vertical
    up   = "u",  u = "u",
    down = "d",  d = "d",

    -- In / Out
    ["in"] = "i", inside = "i", i = "i",
    out = "o", outside = "o", o = "o",
}

-------------------------------------------------
-- Connective / filler words (arguments only)
-------------------------------------------------

local CONNECTIVES = {
    with  = true,
    using = true,
    to    = true,
    at    = true,
    from  = true,
    on    = true,
    into  = true,
    upon  = true,
}

-------------------------------------------------
-- Tokenizer
-------------------------------------------------

local function tokenize(input)
    local t = {}
    for w in input:gmatch("%S+") do
        t[#t + 1] = w
    end
    return t
end

-------------------------------------------------
-- Name / noun matching
-------------------------------------------------

local function matches_name_or_noun(entity, word)
    if not entity or not word then return false end
    word = word:lower()

    if entity.name and entity.name:lower() == word then
        return true
    end

    if entity.noun then
        for _, n in ipairs(entity.noun) do
            if n:lower() == word then
                return true
            end
        end
    end

    return false
end

-------------------------------------------------
-- Resolution helpers
-------------------------------------------------

local function resolve_local(player, ch, word)
    word = word:lower()

    if ch == "#" then
        -- Inventory first
        for oid in pairs(player.np.inventory or {}) do
            if matches_name_or_noun(db.world.objects[oid], word) then
                return "#" .. oid
            end
        end
        -- Then room objects
        local r = db.world.rooms[player.np.room]
        for oid in pairs(r.np.objects or {}) do
            if matches_name_or_noun(db.world.objects[oid], word) then
                return "#" .. oid
            end
        end

    elseif ch == "$" then
        local r = db.world.rooms[player.np.room]
        for nid in pairs(r.np.npcs or {}) do
            if matches_name_or_noun(db.world.npcs[nid], word) then
                return "$" .. nid
            end
        end

    elseif ch == "&" then
        local r = db.world.rooms[player.np.room]
        for pid in pairs(r.np.players or {}) do
            local p = db.world.players[pid]
            if p and p.name and p.name:lower() == word then
                return "&" .. pid
            end
        end
    end
end

local function resolve_global(ch, word)
    word = word:lower()

    if ch == "#" then
        for oid, o in pairs(db.world.objects) do
            if matches_name_or_noun(o, word) then
                return "#" .. oid
            end
        end

    elseif ch == "$" then
        for nid, n in pairs(db.world.npcs) do
            if matches_name_or_noun(n, word) then
                return "$" .. nid
            end
        end

    elseif ch == "&" then
        for pid, p in pairs(db.world.players) do
            if p and p.name and p.name:lower() == word then
                return "&" .. pid
            end
        end

    elseif ch == "@" then
        local rid = tonumber(word)
        if rid and db.world.rooms[rid] then
            return "@" .. rid
        end
    end
end

-------------------------------------------------
-- Argspec token parser
-------------------------------------------------

local function parse_spec_token(tok)
    -- Rest-of-input
    if tok == "*" then
        return {
            kind = "rest"
        }
    end

    local spec = {
        allow     = {},
        global    = false,
        optional  = false,
        wildcard  = false,   -- '.' for ALL objects
        direction = false,   -- '>' for direction
    }

    -- Global modifier
    if tok:sub(1, 1) == "g" then
        spec.global = true
        tok = tok:sub(2)
    end

    -- Optional modifier
    if tok:sub(-1) == "?" then
        spec.optional = true
        tok = tok:sub(1, -2)
    end

    -- Allowed types and specials
    for c in tok:gmatch(".") do
        if c == "." then
            spec.wildcard = true
        elseif c == ">" then
            spec.direction = true
        else
            spec.allow[c] = true
        end
    end

    return spec
end

-------------------------------------------------
-- Common parser core used by parse / parse_with_argspec
-------------------------------------------------

local function parse_core(player, input, argspec)
    if not input or input == "" then return nil end
    input = input:lower()

    local words = tokenize(input)
    if #words == 0 then return nil end

    -- Remove connective words from ARGUMENTS ONLY
    local filtered = { words[1] }
    for i = 2, #words do
        if not CONNECTIVES[words[i]] then
            filtered[#filtered + 1] = words[i]
        end
    end
    words = filtered

    -- No argspec → trivial command
    if not argspec then
        return {
            verb = words[1],
            args = {},
            raw  = input
        }
    end

    -- Parse argspec tokens
    local spec_tokens = {}
    for tok in argspec:gmatch("%S+") do
        spec_tokens[#spec_tokens + 1] = parse_spec_token(tok)
    end

    local args   = {}
    local arg_i  = 2
    local spec_i = 1

    while spec_i <= #spec_tokens do
        local spec = spec_tokens[spec_i]

        -- Rest-of-input
        if spec.kind == "rest" then
            args[#args + 1] = input:match("^%S+%s+(.*)$") or ""
            return {
                verb = words[1],
                args = args,
                raw  = input
            }
        end

        local word = words[arg_i]

        -- Missing argument
        if not word then
            if spec.optional then
                spec_i = spec_i + 1
                goto continue
            else
                return nil
            end
        end

        -- Direction argspec '>'
        if spec.direction then
            local dir = DIRECTIONS[word]
            if not dir then
                return nil
            end
            args[#args + 1] = ">" .. dir
            arg_i  = arg_i + 1
            spec_i = spec_i + 1
            goto continue
        end

        -- Wildcard ALL for objects ('.')
        if spec.wildcard and word == "all" then
            args[#args + 1] = "#."
            arg_i  = arg_i + 1
            spec_i = spec_i + 1
            goto continue
        end

        -- Normal resolution
        local resolved
        if spec.global then
            resolved = false
            for ch in pairs(spec.allow) do
                resolved = resolve_global(ch, word)
                if resolved then break end
            end
        else
            resolved = false
            for ch in pairs(spec.allow) do
                resolved = resolve_local(player, ch, word)
                if resolved then break end
            end
        end

        if not resolved then
            if spec.optional then
                spec_i = spec_i + 1
                goto continue
            else
                return nil
            end
        end

        args[#args + 1] = resolved
        arg_i  = arg_i + 1
        spec_i = spec_i + 1

        ::continue::
    end

    -- Extra words without '*' → invalid
    if arg_i <= #words then
        return nil
    end

    return {
        verb = words[1],
        args = args,
        raw  = input
    }
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function Parser.parse(player, input)
    if not input or input == "" then return nil end

    local words = tokenize(input:lower())
    if #words == 0 then return nil end

    -- Single-word direction shortcut
    if #words == 1 then
        local dir = DIRECTIONS[words[1]]
        if dir then
            return {verb = "go", args = { ">" .. dir }, raw  = input}
        end
    end

    local verb = words[1]

    local argspec =
           wizard.get_argspec(verb)
        or spells.get_argspec(verb)
        or commands.get_argspec(verb)

    return parse_core(player, input, argspec)
end

function Parser.parse_with_argspec(player, input, argspec)
    return parse_core(player, input, argspec)
end

return Parser