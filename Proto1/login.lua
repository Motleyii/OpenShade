----------------------------------------------------------------------
-- login.lua
-- CREATE / LOGIN system using non-blocking net.lua helpers.
-- On login, all non-wizard players start at location 1.
----------------------------------------------------------------------

local net        = require("net")
local database   = require("database")
local player_mod = require("player")
local levels     = require("levels")   -- <-- added

local login = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function fmt_id(num)
    return string.format("%05d", num)
end

local function prompt(sock, text)
    return net.prompt(sock, text)
end

----------------------------------------------------------------------
-- CREATE WORKFLOW (unchanged, new players already start at location 1)
----------------------------------------------------------------------

local function create_player(sock)
    -- Name
    local name = prompt(sock, "Enter character name:\n> ")
    if not name then return nil end

    if database.get_player_by_name(name) then
        net.send(sock, "That name already exists. Try another.\n")
        return create_player(sock)
    end

    -- Sex
    local sex = prompt(sock, "Enter sex (male/female):\n> ")
    if not sex then return nil end
    sex = sex:lower()
    if sex ~= "male" and sex ~= "female" then
        net.send(sock, "Invalid sex. Use 'male' or 'female'.\n")
        return create_player(sock)
    end

    -- Class
    local class = prompt(sock, "Enter class (fighter/pacifist):\n> ")
    if not class then return nil end
    class = class:lower()
    if class ~= "fighter" and class ~= "pacifist" then
        net.send(sock, "Invalid class. Use 'fighter' or 'pacifist'.\n")
        return create_player(sock)
    end

    -- Create player record (ID assigned; PIN not set yet)
    local id_num, persistent = database.create_player(name, sex, nil)
    if not id_num then
        net.send(sock, "Name conflict. Please try again.\n")
        return create_player(sock)
    end

    local id_str = fmt_id(id_num)

    -- PIN
    local pin = prompt(sock, "Enter a 6-digit PIN:\n> ")
    if not pin or not pin:match("^%d%d%d%d%d%d$") then
        net.send(sock, "Invalid PIN. Must be exactly 6 digits.\n")
        return create_player(sock)
    end

    -- Fill missing fields and save
    persistent.pin   = pin
    persistent.class = class
    database.save("players.db")

    -- Confirmation
    net.send(sock,
        "Character created!\n" ..
        "Your player-id is: " .. id_str .. "\n" ..
        "Use: LOGIN " .. id_str .. " " .. pin .. " next time.\n\n"
    )

    -- New players are non-wizards; they already have location = 1 by default
    return player_mod.new(persistent, sock)
end

----------------------------------------------------------------------
-- LOGIN WORKFLOW
----------------------------------------------------------------------

local function attempt_login(sock, id_str, pin)
    if not id_str or not pin then
        net.send(sock, "Format: LOGIN player-id player-pin\n> ")
        return nil
    end

    if not id_str:match("^%d%d%d%d%d$") then
        net.send(sock, "Player-id must be a 5-digit number.\n> ")
        return nil
    end

    local id_num = tonumber(id_str)
    if not id_num then
        net.send(sock, "Invalid player-id format.\n> ")
        return nil
    end

    if not database.authenticate(id_num, pin) then
        net.send(sock, "Incorrect player-id or PIN.\n> ")
        return nil
    end

    local persistent = database.get_player(id_num)

    -- ─────────────────────────────────────────────────────────────
    -- NEW BEHAVIOR: non-wizards always start at location 1 on login
    -- ─────────────────────────────────────────────────────────────
    local level_idx = levels.get_level_index(persistent.score or 0)
    if level_idx ~= 13 then
        persistent.location = 1
    end
    -- Wizards/Witches (level 13) keep their saved location
    -- ─────────────────────────────────────────────────────────────

    return player_mod.new(persistent, sock)
end

----------------------------------------------------------------------
-- ENTRYPOINT
----------------------------------------------------------------------

function login.run(sock)
    net.send(sock,
        "Welcome to the game!\n" ..
        "Enter one of the following:\n" ..
        "  CREATE\n" ..
        "  LOGIN player-id player-pin\n> "
    )

    while true do
        local line = net.read_line(sock)
        if not line then return nil end

        local cmd, a, b = line:match("^(%S+)%s*(%S*)%s*(%S*)$")
        cmd = cmd and cmd:upper()

        if cmd == "CREATE" then
            return create_player(sock)

        elseif cmd == "LOGIN" then
            return attempt_login(sock, a, b)

        else
            net.send(sock, "Unknown command. Use CREATE or LOGIN.\n> ")
        end
    end
end

----------------------------------------------------------------------
-- MODULE EXPORT
----------------------------------------------------------------------

return login