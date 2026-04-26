--============================================================--
-- server.lua
--
-- PURPOSE:
--   Network server and connection management layer.
--   This module owns all socket-level responsibilities,
--   including accepting client connections, managing
--   connected sessions, receiving raw input, and sending
--   output to clients.
--
--   server.lua acts as the boundary between the outside
--   network world and the internal game engine. It does
--   not implement gameplay logic, parsing, or commands.
--
--============================================================--
--
-- ARCHITECTURAL ROLE:
--
--   - Creates and manages the listening server socket
--   - Accepts and tracks client connections
--   - Associates network connections with player records
--   - Receives raw input from clients
--   - Forwards input to game.lua for processing
--   - Handles graceful connection shutdown
--
--   server.lua must remain isolated from gameplay systems
--   such as commands, spells, combat, puzzles, and editors.
--
--============================================================--
--
-- FUNCTION OVERVIEW:
--
-- start(port)
--   Starts the game server, creates the listening socket,
--   and begins accepting incoming client connections.
--
-- accept_connection()
--   Accepts a new client connection and initializes any
--   per-connection state required before login.
--
-- handle_connection(conn)
--   Processes I/O readiness for a connected client,
--   including receiving input and sending queued output.
--
-- receive_input(conn)
--   Reads raw input from a client connection and returns
--   complete input lines suitable for further processing.
--
-- send_output(conn, text)
--   Sends text output to a client connection, handling
--   buffering and connection safety.
--
-- attach_player(conn, player)
--   Associates a logged-in player record with a connection.
--
-- detach_player(conn)
--   Cleans up and detaches a player from a connection when
--   disconnecting or logging out.
--
-- disconnect(conn, reason)
--   Gracefully closes a client connection, optionally
--   sending a final message or reason for disconnection.
--
-- shutdown()
--   Performs an orderly shutdown of the server, closing
--   all connections and releasing network resources.
--
--============================================================--
--
-- DESIGN NOTES:
--
--   * server.lua must not parse commands or inspect gameplay
--     state beyond identifying the associated player.
--
--   * All player-visible messaging should go through the
--     messaging.lua subsystem, not directly to sockets.
--
--   * Connection handling must be robust against malformed
--     input and unexpected disconnects.
--
--   * This module is intentionally dependency-light and may
--     only depend on networking libraries and top-level
--     orchestration code (e.g. game.lua).
--
--============================================================--

local socket   = require("socket")
local serpent  = require("serpent")

local db       = require("database")
local game     = require("game")
local msg      = require("messaging")
local commands = require("commands")
local spells   = require("spells")
local wizard   = require("wizard")
local Movement = require("movement")

local RESERVED_NAMES = {}

local function merge_reserved(dst, src)
    for k in pairs(src) do
        dst[k:lower()] = true
    end
end

merge_reserved(RESERVED_NAMES, commands.get_verbs())
merge_reserved(RESERVED_NAMES, spells.get_verbs())
merge_reserved(RESERVED_NAMES, wizard.get_verbs())

-- Optional: directions explicitly (defensive)
merge_reserved(RESERVED_NAMES, {
    north=true,south=true,east=true,west=true,
    northeast=true,northwest=true,southeast=true,southwest=true,
    down=true,up=true,
    ["in"]=true,into=true,inside=true,out=true,outside=true
})

-------------------------------------------------
-- Configuration
-------------------------------------------------

local HOST = "*"
local PORT = 4000
local SELECT_TIMEOUT = 0.1

local PLAYER_DB_FILE = "players.lua"

-------------------------------------------------
-- Server state
-------------------------------------------------

local server_socket

-- client socket -> player (authenticated only)
local clients = {}

-- client socket -> login state (unauthenticated)
local login_state = {}

-- sockets monitored by select()
local read_sockets = {}

local shutting_down = false

local LOGIN_NAME = 1
local LOGIN_PIN = 2
local NEW_NAME = 3
local NEW_PIN = 4

-------------------------------------------------
-- Logging
-------------------------------------------------

local function log(msg)
    print(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg)
end

-------------------------------------------------
-- Socket list helpers
-------------------------------------------------

local function add_socket(sock)
    read_sockets[#read_sockets + 1] = sock
end

local function remove_socket(sock)
    for i = #read_sockets, 1, -1 do
        if read_sockets[i] == sock then
            table.remove(read_sockets, i)
        end
    end
end

local function rebuild_select_list()
    read_sockets = { server_socket }
    for sock in pairs(login_state) do
        add_socket(sock)
    end
    for sock in pairs(clients) do
        add_socket(sock)
    end
end

-------------------------------------------------
-- Safe select wrapper
-- (handles LuaSocket builds that THROW on SIGINT)
-------------------------------------------------

local function safe_select(read, write, timeout)
    local ok, r, w, err = pcall(socket.select, read, write, timeout)
    if not ok then
        return nil, nil, r   -- r is error string (e.g. "interrupted!")
    end
    return r, w, err
end

-------------------------------------------------
-- Player helpers
-------------------------------------------------

local function find_player_by_name(name)
    for _, p in pairs(db.world.players) do
        if p.name:lower() == name:lower() then
            return p
        end
    end
    return nil
end

local function create_player(name, pin)
    local id = 0
    for k in pairs(db.world.players) do
        id = math.max(id, k + 1)
    end

    local p = {
        id      = id,
        name    = name,
        adverb  = nil,
        pin     = pin,
        created = os.time(),
        home    = nil,
        score   = 0,
        flags   = { ismale = true, isinvis = false },
        np      = nil
    }

    db.world.players[id] = p
    log("Created new player: " .. name)
    return p
end

local function init_player_connection(player, conn)
    -- initialise runtime (np) data and attach socket
    db.init_online_player(player).conn = conn
    clients[conn] = player

    -- place player in starting room
    local r = db.world.rooms[player.np.room]
    r.np.players[player.id] = true

    -- greet player and show room
    local adverb = player.adverb or ""
    local lvlname = db.get_level_name(player)
    msg.to_player(player, "Welcome, " .. player.name .. " the " .. adverb .. " " .. lvlname)

    local reset_in_mins = game.get_minutes_to_next_reset()
    msg.to_player(player,"Next Game Reset is in " .. reset_in_mins .. " minute(s).\n")

    Movement.describe_room(player, r, {force_desc = true})
end

-------------------------------------------------
-- Central disconnect (ONLY place sockets close)
-------------------------------------------------

local function disconnect(sock, reason)
    local player = clients[sock]

    if player then
        log("Disconnected: " .. player.name .. (reason and (" (" .. reason .. ")") or ""))

        -- persist score
        if player.np then
            player.score = player.np.score
        end

        -- remove from room
        local room = db.world.rooms[player.np.room]
        if room then
            room.np.players[player.id] = nil
            msg.to_room(room.id, player.name .. " has disconnected.", player.id)
        end

        player.np = nil
        clients[sock] = nil
    end

    login_state[sock] = nil
    remove_socket(sock)
    pcall(sock.close, sock)
end

-------------------------------------------------
-- Login handling
-------------------------------------------------

local function normalize_name(name)
    name = name:lower()
    return name:sub(1,1):upper() .. name:sub(2)
end

local function validate_new_player_name(raw)
    if #raw < 3 then
        return false, "Name must be at least 3 letters long."
    end

    if not raw:match("^[A-Za-z]+$") then
        return false, "Names may only contain letters."
    end

    local canon = raw:lower()

    if RESERVED_NAMES[canon] then
        return false, "That name is reserved. Choose another."
    end

    if find_player_by_name(raw) then
        return false, "That name is already taken."
    end

    return true, normalize_name(raw)
end

local function begin_login(conn)
    login_state[conn] = { step = LOGIN_NAME }
    conn:send("Enter player name or 0 to create a new player: ")
end

local function handle_login(conn)
    local line, err = conn:receive("*l")
    if not line then
        if err == "closed" then
            disconnect(conn, "login closed")
        end
        return
    end

    line = line:match("^%s*(.-)%s*$")
    local state = login_state[conn]

    if state.step == LOGIN_NAME then
        if line == "0" then
            state.step = NEW_NAME
            conn:send("Enter new player name: ")
            return
        end

        local player = find_player_by_name(line)
        if not player then
            conn:send("No such player. Enter name or 0 to create new: ")
            return
        end

        state.player = player
        state.step = LOGIN_PIN
        conn:send("PIN: ")
        return
    end

    if state.step == LOGIN_PIN then
        if state.player.pin ~= line then
            conn:send("Invalid PIN.\n")
            disconnect(conn, "bad PIN")
            return
        end

        login_state[conn] = nil
        init_player_connection(state.player, conn)
        return
    end

    if state.step == NEW_NAME then
        local ok, result = validate_new_player_name(line)

        if not ok then
            conn:send(result .. "\nEnter a different name: ")
            return
        end

        state.new_name = result   -- already normalized
        state.step = NEW_PIN
        conn:send("Choose a PIN (6 digits): ")
        return
    end

    if state.step == NEW_PIN then
        if not line:match("^%d%d%d%d%d%d$") then
            conn:send("PIN must be exactly 6 digits. Try again: ")
            return
        end

        local player = create_player(state.new_name, line)
        login_state[conn] = nil
        init_player_connection(player, conn)
        return
    end
end

-------------------------------------------------
-- Client input
-------------------------------------------------

local function handle_client(sock)
    if login_state[sock] then
        handle_login(sock)
        return
    end

    local player = clients[sock]
    if not player then
        disconnect(sock, "unknown socket")
        return
    end

    local line, err = sock:receive("*l")
    if not line then
        if err == "closed" then
            disconnect(sock, "client closed")
        end
        return
    end

    game.handle_player_input(player, line)
end

-------------------------------------------------
-- Game reset handling
-------------------------------------------------

local function perform_world_reset()
    log("World reset starting")

    -- 1. Save active players
    for _, p in pairs(db.world.players) do
        if p.np then
            p.score = p.np.score
        end
    end
    db.save_players(PLAYER_DB_FILE)

    -- 2. Backup world databases
    db.backup("rooms", db.world.rooms)
    db.backup("objects", db.world.objects)
    db.backup("npcs", db.world.npcs)

    -- 3. Disconnect all players
    for sock, player in pairs(clients) do
        pcall(function()
            sock:send("The world dissolves...\n")
        end)
        disconnect(sock, "world reset")
    end

    -- 4. Reload world
    db.load_rooms("rooms.lua")
    db.load_objects("objects.lua")
    db.load_npcs("npcs.lua")
    db.load_players(PLAYER_DB_FILE)
    db.load_levels("levels.lua")

    -- 5. Reset game scheduler
    game.reset()

    log("World reset completed")
end

game.on_reset = function()
    perform_world_reset()
end

-------------------------------------------------
-- Graceful shutdown (SIGINT)
-------------------------------------------------

local function shutdown()
    if shutting_down then return end
    shutting_down = true

    log("Shutting down server (SIGINT)")

    for sock, player in pairs(clients) do
        pcall(function()
            sock:send("Server shutting down. Please reconnect later.\n")
        end)

        if player.np then
            player.score = player.np.score
        end

        pcall(sock.close, sock)
    end

    clients = {}
    login_state = {}
    read_sockets = {}

    log("Saving player database...")
    db.save_players(PLAYER_DB_FILE)

    if server_socket then
        pcall(server_socket.close, server_socket)
    end

    log("Shutdown complete.")
end

-------------------------------------------------
-- Main loop
-------------------------------------------------

local function main_loop()
    while not shutting_down do
        local readable, _, err =
            safe_select(read_sockets, nil, SELECT_TIMEOUT)

        if err then
            local msg_err = tostring(err)
            if msg_err:match("interrupted") then
                -- SIGINT (Ctrl-C)
                shutdown()
                break
            elseif msg_err ~= "timeout" then
                log("select error (" .. msg_err .. "), rebuilding socket list")
                rebuild_select_list()
            end
        end

        for _, sock in ipairs(readable or {}) do
            if sock == server_socket then
                local conn = server_socket:accept()
                if conn then
                    conn:settimeout(0)
                    conn:send("Welcome to LuaMUD!\n")
                    add_socket(conn)
                    begin_login(conn)
                end
            else
                handle_client(sock)
            end
        end

        game.tick()
    end
end

-------------------------------------------------
-- Startup
-------------------------------------------------

local function main()
    db.load_help("help.lua")
    db.load_rooms("rooms.lua")
    db.load_objects("objects.lua")
    db.load_npcs("npcs.lua")
    db.load_players(PLAYER_DB_FILE)
    db.load_levels("levels.lua")

    print("Registered verbs: " .. serpent.line(RESERVED_NAMES))

    server_socket = assert(socket.bind(HOST, PORT))
    server_socket:settimeout(0)

    read_sockets = { server_socket }

    log("LuaMUD listening on port " .. PORT)
    main_loop()
end

main()
