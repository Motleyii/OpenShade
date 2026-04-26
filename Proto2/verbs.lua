--============================================================--
-- verbs.lua
--
-- PURPOSE:
--   Central registry for verb metadata used across the engine.
--   This module records declarative information about verbs,
--   primarily their argument grammar (argspec) and whether
--   they require global or local resolution.
--
--   verbs.lua does not execute verbs, parse input, or enforce
--   permissions. It exists solely to provide a dependency-safe
--   source of verb metadata for parsing, help systems, and
--   introspection.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Stores verb → argspec mappings
--   - Determines whether a verb is global via its argspec
--   - Provides read-only introspection of registered verbs
--   - Avoids circular dependencies with parser, dispatcher,
--     commands, spells, wizard, and editor modules
--
--   This module is intentionally simple and side-effect light.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- register(name, argspec)
--   Registers a verb and its argspec grammar string in the
--   registry. The verb is automatically marked as global if
--   the argspec contains the 'g' modifier.
--
-- get_argspec(name)
--   Returns the argspec string associated with the given verb,
--   or nil if the verb is not registered.
--
-- is_global(name)
--   Returns true if the verb’s argspec declares global
--   resolution (contains 'g'), false otherwise.
--
-- is_registered(name)
--   Returns true if the verb exists in the registry.
--
-- list()
--   Returns a sorted list of all registered verb names.
--   Intended for debugging, help systems, and diagnostics.
--
-- clear()
--   Removes all registered verbs from the registry.
--   Intended for testing or controlled reinitialization.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * verbs.lua stores metadata only; it must never execute
--     verbs or depend on gameplay systems.
--
--   * The dispatcher remains authoritative for execution,
--     while verbs.lua provides a neutral view of grammar.
--
--   * This module should not be required by high-level UI or
--     editor code.
--
--============================================================--

local Verbs = {}

-------------------------------------------------
-- Internal storage
-------------------------------------------------

-- verb_name -> {
--   argspec  = string,
--   global   = boolean
-- }
local registry = {}

-------------------------------------------------
-- Register a verb
-------------------------------------------------
-- name     : verb string
-- argspec  : argspec grammar string
--
-- The verb is recorded as "global" if its argspec contains
-- the 'g' global-resolution modifier.
-------------------------------------------------

function Verbs.register(name, argspec)
    if type(name) ~= "string" or name == "" then
        error("verbs.register: name must be a non-empty string")
    end

    if argspec ~= nil and type(argspec) ~= "string" then
        error("verbs.register: argspec must be a string or nil")
    end

    local is_global = false
    if argspec and argspec:find("g", 1, true) then
        is_global = true
    end

    registry[name] = {
        argspec = argspec,
        global  = is_global
    }
end

-------------------------------------------------
-- Lookup helpers
-------------------------------------------------

function Verbs.get_argspec(name)
    local v = registry[name]
    return v and v.argspec or nil
end

function Verbs.is_global(name)
    local v = registry[name]
    return v and v.global or false
end

-------------------------------------------------
-- Introspection helpers
-------------------------------------------------

function Verbs.is_registered(name)
    return registry[name] ~= nil
end

function Verbs.list()
    local out = {}
    for name in pairs(registry) do
        table.insert(out, name)
    end
    table.sort(out)
    return out
end

-------------------------------------------------
-- Debug / maintenance
-------------------------------------------------

function Verbs.clear()
    registry = {}
end

-------------------------------------------------

return Verbs