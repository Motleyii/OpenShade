----------------------------------------------------------------------
-- startup.lua
-- Boot script combining orchestrator + database + world init.
----------------------------------------------------------------------

local orchestrator = require("orchestrator")
local database     = require("database")
local init         = require("init")
local engine       = require("engine")

-- 1) Load persistent DB exactly once
database.load("players.db")

-- 2) Load all world/NPC/object data exactly once
init.load_all()

-- 3) Enable autosave (e.g., every 600s)
engine.enable_autosave(600, "players.db")

-- 4) Start orchestrator main loop on port 4000
orchestrator.start(4000)