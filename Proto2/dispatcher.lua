--============================================================--
-- dispatcher.lua
--
-- PURPOSE:
--   Generic verb dispatch and metadata registry.
--   This module provides a reusable dispatch mechanism that
--   maps verbs (and aliases) to handler functions and their
--   associated argument grammars (argspec strings).
--
--   dispatcher.lua is intentionally dumb: it does not parse
--   user input, resolve arguments, enforce permissions, or
--   contain any game logic. It simply stores verb metadata
--   and invokes handlers when asked.
--
-- ARCHITECTURAL ROLE:
--   - Owns verb → handler mappings
--   - Owns verb → argspec mappings
--   - Supports aliases transparently
--   - Used independently by commands.lua, spells.lua,
--     and wizard.lua
--   - Does not depend on parser, editor, or game logic
--
--============================================================--
--
-- DESIGN OVERVIEW:
--
--   Each Dispatcher instance is an isolated namespace of
--   verbs. Different subsystems (commands, spells, wizard
--   commands) each create their own dispatcher instance.
--
--   All argument grammar is expressed declaratively as
--   argspec strings and stored here, but never interpreted
--   by this module.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- Dispatcher.new()
--   Creates and returns a new dispatcher instance with an
--   empty verb registry.
--
-- Dispatcher:register(verb, def)
--   Registers a new verb with the dispatcher.
--   `def` must contain a handler function (def.fn) and may
--   optionally define:
--     - def.argspec : the argument grammar string
--     - def.aliases : a list of alternate verb names
--
-- dispatcher:handle(player, parsed)
--   Attempts to dispatch a previously parsed command.
--   Looks up the verb in the registry and, if found,
--   invokes the associated handler function.
--   Returns true if the verb was handled, false otherwise.
--
-- dispatcher:get_verbs()
--   Returns a set-like table of all registered verbs and
--   aliases owned by this dispatcher.
--
-- dispatcher:get_argspec(verb)
--   Returns the argspec string associated with the given
--   verb, or nil if the verb is not registered in this
--   dispatcher.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * Dispatcher instances are intentionally isolated; there
--     is no global dispatcher.
--
--   * This module performs no validation of argspec strings.
--     Validation is the responsibility of the parser and
--     editor tooling.
--
--   * Dispatcher does not know or care whether a verb is a
--     command, spell, or wizard action.
--
--   * This module must remain free of circular dependencies
--     and must not require higher-level modules.
--
--============================================================--

local Dispatcher = {}
Dispatcher.__index = Dispatcher

-------------------------------------------------
-- Constructor
-------------------------------------------------

function Dispatcher.new()
    return setmetatable({
        buckets = {}  -- first-letter -> verb -> def
    }, Dispatcher)
end

-------------------------------------------------
-- Register a verb
-------------------------------------------------
-- def fields:
--   fn       : function(player, parsed)
--   aliases  : { "alias1", "alias2", ... } (optional)
--   argspec  : string describing argument grammar (optional)
-------------------------------------------------

function Dispatcher:register(verb, def)
    if type(verb) ~= "string" or verb == "" then
        error("Dispatcher.register: verb must be a non-empty string")
    end
    if type(def) ~= "table" or type(def.fn) ~= "function" then
        error("Dispatcher.register: def.fn must be a function")
    end

    -- store primary verb
    local key = verb:sub(1, 1)
    self.buckets[key] = self.buckets[key] or {}
    self.buckets[key][verb] = def

    -- store aliases (same def table)
    if def.aliases then
        for _, alias in ipairs(def.aliases) do
            if type(alias) == "string" and alias ~= "" then
                local akey = alias:sub(1, 1)
                self.buckets[akey] = self.buckets[akey] or {}
                self.buckets[akey][alias] = def
            end
        end
    end

    if def.argspec then
        print("Verb: " .. verb .. " (" .. def.argspec .. ")")
    else
        print("Verb: " .. verb .. " (no args)")
    end
end

-------------------------------------------------
-- Dispatch a parsed command
-------------------------------------------------

function Dispatcher:handle(player, parsed)
    if not parsed or not parsed.verb then
        return false
    end

    local verb = parsed.verb
    local bucket = self.buckets[verb:sub(1, 1)]
    if not bucket then
        return false
    end

    local def = bucket[verb]
    if not def then
        return false
    end

    def.fn(player, parsed)
    return true
end

-------------------------------------------------
-- Metadata accessors
-------------------------------------------------

-- Return a set-like table of all verbs and aliases
function Dispatcher:get_verbs()
    local verbs = {}
    for _, bucket in pairs(self.buckets) do
        for verb, def in pairs(bucket) do
            verbs[verb] = true
            if def.aliases then
                for _, a in ipairs(def.aliases) do
                    verbs[a] = true
                end
            end
        end
    end
    return verbs
end

-- Return the argspec string for a verb (or nil)
function Dispatcher:get_argspec(verb)
    if not verb then return nil end
    local bucket = self.buckets[verb:sub(1, 1)]
    if not bucket then return nil end
    local def = bucket[verb]
    return def and def.argspec or nil
end

-------------------------------------------------

return Dispatcher