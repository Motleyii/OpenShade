----------------------------------------------------------------------
-- init.lua
-- Aggregates all loaders so the world is initialized before start.
----------------------------------------------------------------------

local room_loader   = require("room_loader")
local npc_loader    = require("npc_loader")
local object_loader = require("object_loader")
local help_loader   = require("help_loader")

local init = {}

function init.load_all()
    print("--- INIT.LUA - room_loader ---")
    room_loader.load("rooms.lua")

    print("--- INIT.LUA - npc_loader ---")
    npc_loader.load("npc_data.lua")

    print("--- INIT.LUA - object_loader ---")
    object_loader.load("object_data.lua")

    print("--- INIT.LUA - help_loader ---")
    help_loader.load("help_data.lua")
end

return init