----------------------------------------------------------------------
-- main.lua
-- Session entrypoint for a single client connection.
-- Used by orchestrator.lua: each client runs inside a coroutine.
--
-- Responsibilities:
--   • Run login/creation (login.lua)
--   • Convert persistent record → runtime player object
--   • Register in active_players
--   • Initial LOOK
--   • Run player's command loop
--   • Cleanup on disconnect
----------------------------------------------------------------------

local login      = require("login")
local world      = require("world")
local player_mod = require("player")
local commands   = require("commands")
local database   = require("database")

local main = {}

----------------------------------------------------------------------
-- handle_connection(sock)
-- Called by orchestrator for each new client socket.
----------------------------------------------------------------------

function main.handle_connection(sock)
    -- Step 1: perform CREATE/LOGIN
    local player = login.run(sock)
    if not player then
        -- Socket likely closed or login failed
        pcall(function() sock:close() end)
        return
    end

    -- Step 2: register active player
    _G.active_players = _G.active_players or {}
    _G.active_players[player.id] = player

    -- Step 3: show initial room
    world.look(player)

    -- Step 4: run command loop for this player
    player:run_game_loop()

    -- Step 5: cleanup (player:disconnect handles DB update)
    _G.active_players[player.id] = nil

    pcall(function() sock:close() end)
end

----------------------------------------------------------------------
-- Return module
----------------------------------------------------------------------

return main