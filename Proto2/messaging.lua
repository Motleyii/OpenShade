--============================================================--
-- messaging.lua
--
-- PURPOSE:
--   Centralized message delivery and output routing system.
--   This module provides a unified interface for sending
--   text output to players, rooms, or the entire game world.
--
--   messaging.lua abstracts away connection handling and
--   audience selection so that gameplay systems can emit
--   messages without concern for where or how they are sent.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Owns all message fanout logic
--   - Routes text to the appropriate recipients
--   - Handles exclusion rules (e.g. “everyone except player X”)
--   - Provides a consistent messaging API for all subsystems
--   - Does not inspect or modify game state
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- to_player(player, message)
--   Sends a message directly to a single player.
--   Handles connection safety and output formatting.
--
-- to_room(room_id, message, exclude_player_id)
--   Sends a message to all players currently in the given
--   room. Optionally excludes a specific player (typically
--   the message originator).
--
-- to_world(message)
--   Broadcasts a message to all connected players in
--   the game world.
--
-- system(player, message)
--   Sends a system-level message to the player, typically
--   used for errors, notifications, or engine feedback.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * messaging.lua must not perform game logic, validation,
--     or permission checks.
--
--   * All strings passed into this module are assumed to be
--     final, player-visible text.
--
--   * This module should remain dependency-light and must
--     not require parser, dispatcher, combat, or editor code.
--
--   * Any future output features (color codes, formatting,
--     localization) should be implemented here so that all
--     callers benefit uniformly.
--
--============================================================--

local db = require("database")

local M = {}

-------------------------------------------------
-- Low-level send
-------------------------------------------------

local function raw_send(player, msg)
    if not player or not player.np or not player.np.conn then return end
    player.np.conn:send(msg .. "\n")
end

-------------------------------------------------
-- Pronoun handling
-------------------------------------------------

local function pronouns(entity)
    if not entity or not entity.flags then
        return {
            s = "it", o = "it", v = "its", r = "itself"
        }
    end

    if entity.flags.isplural then
        return { s="they", o="them", v="their", r="themselves" }
    end

    if entity.flags.ismale then
        return { s="he", o="him", v="his", r="himself" }
    end

    return { s="she", o="her", v="her", r="herself" }
end

local function cap(s)
    return s:sub(1,1):upper() .. s:sub(2)
end

-------------------------------------------------
-- Message substitution
-------------------------------------------------

function M.format(msg, actor, target)
    if not msg then return nil end

    local apron = pronouns(actor)
    local tpron = pronouns(target)

    msg = msg:gsub("%%n", actor and actor.name or "")
    msg = msg:gsub("%%p", target and target.name or "")

    msg = msg:gsub("%%s", tpron.s)
    msg = msg:gsub("%%o", tpron.o)
    msg = msg:gsub("%%v", tpron.v)
    msg = msg:gsub("%%r", tpron.r)

    msg = msg:gsub("%%S", cap(tpron.s))
    msg = msg:gsub("%%O", cap(tpron.o))
    msg = msg:gsub("%%P", cap(tpron.v))
    msg = msg:gsub("%%R", cap(tpron.r))

    return msg
end

-------------------------------------------------
-- Player messaging
-------------------------------------------------

function M.to_player(player, msg, actor, target)
    raw_send(player, M.format(msg, actor, target))

    -- snoopers hear everything
    if player.np and player.np.snooped_by then
        for snooper_id in pairs(player.np.snooped_by) do
            local snooper = db.world.players[snooper_id]
            if snooper then
                raw_send(
                    snooper,
                    "[snoop:" .. player.name .. "] " .. msg
                )
            end
        end
    end
end

-------------------------------------------------
-- Room messaging
-------------------------------------------------

function M.to_room(room_id, msg, exclude_id, actor, target)
    local room = db.world.rooms[room_id]
    if not room then return end

    for pid in pairs(room.np.players) do
        if pid ~= exclude_id then
            local p = db.world.players[pid]
            if p then
                raw_send(p, M.format(msg, actor, target))
            end
        end
    end
end

-------------------------------------------------
-- World messaging
-------------------------------------------------

function M.to_world(msg, actor, target)
    for _, p in pairs(db.world.players) do
        if p.np and p.np.conn then
            raw_send(p, M.format(msg, actor, target))
        end
    end
end

-------------------------------------------------
-- Convenience helpers
-------------------------------------------------

function M.player_say(player, msg)
    M.to_room(
        player.np.room,
        player.name .. " says: " .. msg,
        nil,
        player,
        nil
    )
end

function M.player_emote(player, msg)
    M.to_room(
        player.np.room,
        player.name .. " " .. msg,
        nil,
        player,
        nil
    )
end

function M.player_shout(player, msg)
    M.to_world(player.name .. " shouts: " .. msg, player, nil)
end

-------------------------------------------------
-- Snoop control (wizard)
-------------------------------------------------

function M.start_snoop(wizard, target)
    target.np.snooped_by = target.np.snooped_by or {}
    wizard.np.snoop_targets = wizard.np.snoop_targets or {}

    target.np.snooped_by[wizard.id] = true
    wizard.np.snoop_targets[target.id] = true

    raw_send(wizard, "You begin snooping " .. target.name .. ".")
end

function M.stop_snoop(wizard)
    if not wizard.np.snoop_targets then return end

    for tid in pairs(wizard.np.snoop_targets) do
        local t = db.world.players[tid]
        if t and t.np and t.np.snooped_by then
            t.np.snooped_by[wizard.id] = nil
        end
    end

    wizard.np.snoop_targets = nil
    raw_send(wizard, "Snoop disabled.")
end

-------------------------------------------------
-- System / debug
-------------------------------------------------

function M.system(player, msg)
    raw_send(player, "[SYSTEM] " .. msg)
end

return M