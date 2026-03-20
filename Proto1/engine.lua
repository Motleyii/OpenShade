----------------------------------------------------------------------
-- engine.lua
-- World heartbeat and timed systems
-- Runs once every orchestrator loop via engine.tick().
-- Handles:
--   • NPC movement/AI heartbeat
--   • Combat heartbeat
--   • Autosave heartbeat
--   • Additional scheduled tickers
----------------------------------------------------------------------

local npc      = require("npc")
local combat   = require("combat")
local database = require("database")

local engine = {}

----------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------

-- Heartbeat tick rate is event‑driven (1 call per orchestrator loop)
-- but timers (like autosave) use os.time() internally.
engine.autosave_interval = 600    -- seconds
engine.next_autosave     = os.time() + engine.autosave_interval

-- Additional tickers (optional)
engine.extra_tickers = {}   -- list of functions(now)

----------------------------------------------------------------------
-- Autosave control
----------------------------------------------------------------------

function engine.enable_autosave(seconds, filename)
    engine.autosave_interval = seconds or 600
    engine.autosave_file     = filename or "players.db"
    engine.next_autosave     = os.time() + engine.autosave_interval
end

----------------------------------------------------------------------
-- Heartbeat
-- Called every orchestrator loop, typically ~10–20 times per second
----------------------------------------------------------------------

function engine.tick()
    local now = os.time()

    ------------------------------------------------------------------
    -- 1) NPC heartbeat
    ------------------------------------------------------------------
    npc.heartbeat(now)

    ------------------------------------------------------------------
    -- 2) Combat heartbeat (PvE and PvP rounds)
    ------------------------------------------------------------------
    combat.heartbeat(now)

    ------------------------------------------------------------------
    -- 3) Autosave timer
    ------------------------------------------------------------------
    if engine.autosave_file and now >= engine.next_autosave then
        -- Save all persistent player data to DB
        database.save(engine.autosave_file)
        engine.next_autosave = now + engine.autosave_interval
    end

    ------------------------------------------------------------------
    -- 4) Extra tickers (optional features may be added here)
    ------------------------------------------------------------------
    for _, fn in ipairs(engine.extra_tickers) do
        fn(now)
    end
end

----------------------------------------------------------------------
-- Stop engine
-- Called by orchestrator.stop() before shutdown
----------------------------------------------------------------------

function engine.stop()
    -- Force final autosave if configured
    if engine.autosave_file then
        database.save(engine.autosave_file)
    end
end

return engine