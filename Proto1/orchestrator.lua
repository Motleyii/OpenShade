----------------------------------------------------------------------
-- orchestrator.lua
-- Unified main loop for:
--   • Non-blocking multi-client accept
--   • Coroutine-based session scheduling
--   • Combat + NPC heartbeat (via engine.tick)
--   • Autosave (via engine tickers)
--   • Safe socket binding with port-owner detection
--
-- NOTE:
--   Database loading and world initialization are handled in startup.lua.
----------------------------------------------------------------------

local socket       = require("socket")
local safe_bind    = require("safe_bind")
local engine       = require("engine")
local database     = require("database")  -- only for final save in stop()
local main         = require("main")

local orchestrator = {}

local PORT      = 4000
local SLEEP_MS  = 0.01
local sessions  = {}
local listener  = nil

----------------------------------------------------------------------
-- Accept new client (non-blocking)
----------------------------------------------------------------------

local function accept_new()
    local client = listener:accept()
    if not client then return end
    client:settimeout(0)

    local co = coroutine.create(function()
        main.handle_connection(client)
    end)

    table.insert(sessions, { co = co, sock = client })
end

----------------------------------------------------------------------
-- Resume all sessions cooperatively
----------------------------------------------------------------------

local function run_sessions()
    local i = 1
    while i <= #sessions do
        local s = sessions[i]
        local ok, _ = coroutine.resume(s.co)
        if not ok or coroutine.status(s.co) == "dead" then
            pcall(function() s.sock:close() end)
            table.remove(sessions, i)
        else
            i = i + 1
        end
    end
end

----------------------------------------------------------------------
-- PUBLIC API
----------------------------------------------------------------------

function orchestrator.start(port)
    -- Binding only; DB/world are initialized in startup.lua
    print("Boot: binding listener on port " .. tostring(port or PORT) .. "...")

    local err
    listener, err = safe_bind.bind("*", port or PORT, {
        retries     = 5,
        retry_delay = 1,
        fallback    = (port or PORT) + 1
    })

    if not listener then
        print("Fatal: could not bind port: " .. tostring(err))
        os.exit(1)
    end

    print("Listener active on port " .. tostring(port or PORT))

    -- Wrap the main loop so we can catch Ctrl-C (SIGINT) or any runtime error
    local ok, caught_err = xpcall(function()
        while true do
            engine.tick()
            accept_new()
            run_sessions()
            socket.sleep(SLEEP_MS)
        end
    end, debug.traceback)

    -- If we exit the loop due to an error (including Ctrl-C), handle it here
    if not ok then
        -- Ctrl-C in Lua typically raises an "interrupted" error message
        if type(caught_err) == "string" and caught_err:lower():match("interrupted") then
            io.write("\n^C caught: initiating graceful shutdown...\n")
            orchestrator.stop()
            return
        end

        -- Any other unexpected error: log, attempt graceful stop, then exit non-zero
        io.write("Runtime error: ", tostring(caught_err), "\n")
        orchestrator.stop()
        os.exit(1)
    end
end

function orchestrator.stop()
    print("Stopping orchestrator...")

    engine.stop()

    if listener then
        pcall(function() listener:close() end)
        listener = nil
    end

    if _G.active_players then
        for _, p in pairs(_G.active_players) do
            p:disconnect()
        end
    end

    for _, session in pairs(sessions) do
        pcall(function() session.sock:close() end)
    end

    -- Final DB save (startup.lua owns loading; orchestrator ensures one last save)
    database.save("players.db")

    print("Shutdown complete.")
end

return orchestrator
