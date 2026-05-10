--============================================================--
-- movement.lua
--
-- PURPOSE:
--   Handles player movement and room presentation.
--   This module defines the logic for moving a player between
--   rooms via exits and for describing the current room to
--   the player.
--
--   movement.lua does not parse input or resolve arguments.
--   It is invoked by command handlers once input has been
--   parsed and validated.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Implements the GO movement command
--   - Acts as the single source of truth for room display
--   - Handles room entry output and visibility
--
--   This module is intentionally minimal and will be expanded
--   only when additional movement mechanics (NPC movement,
--   teleportation, room triggers) are required.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- describe_room(player)
--   Displays the player’s current room, including the room
--   title, optional description (based on verbosity), and
--   visible contents such as objects, NPCs, and other players.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * All room presentation must go through describe_room()
--     to prevent duplicated output logic.
--
--   * Movement rules are currently limited to player-driven
--     navigation via exits.
--
--   * Additional movement-related behavior should be added
--     here only when required by gameplay.
--
--============================================================--

local db  = require("database")
local msg = require("messaging")
local serpent = require("serpent")

local Movement = {}

local function is_wizard(player)
    return db.get_level(player).level >= 13
end

function Movement.describe_room(player, r, opts)
    opts = opts or {}

    -- Always show title
    local title = r.title
    if is_wizard(player) then
        title = title .. " (" .. r.id .. ")"
    end
    msg.to_player(player, title)

    -- Description depends on verbosity
    local force_desc = opts.force_desc or false
    if force_desc or player.flags.verbose and r.desc then
        msg.to_player(player, r.desc)
    end

    -- objects
    for oid in pairs(r.np.objects) do
        local o = db.world.objects[oid]
        if o then
            msg.to_player(player, db.get_object_desc(o))
        end
    end

    -- other players
    for pid in pairs(r.np.players) do
        if pid ~= player.id then
            local p = db.world.players[pid]
            if p and not p.flags.isinvis then
                local pn = p.name
                if (p.adverb and p.adverb ~= "") then
                    pn = pn .. " the " .. p.adverb
                end
                msg.to_player(player, pn .. " is here.")
            end
        end
    end

    -- NPCs
    for nid in pairs(r.np.npcs) do
        local n = db.world.npcs[nid]
        if n then
            msg.to_player(player, n.here)
        end
    end
end

return Movement
