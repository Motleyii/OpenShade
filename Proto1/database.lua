----------------------------------------------------------------------
-- database.lua
-- Persistent player database layer.
--   • In-memory store
--   • Auto-increment player-id starting at 1
--   • Save to / load from file
--   • Create / lookup / authenticate / update
----------------------------------------------------------------------

local database = {}

local player_db = {
    next_id = 1,
    players = {},     -- [id] = player record
    by_name = {}      -- [name] = id
}

local function serialize_table(t)
    local s = "{"
    for k, v in pairs(t) do
        local key = "[" .. string.format("%q", k) .. "]"
        if type(v) == "string" then
            s = s .. key .. "=" .. string.format("%q", v) .. ","
        else
            s = s .. key .. "=" .. tostring(v) .. ","
        end
    end
    return s .. "}"
end

function database.save(filename)
    local f = assert(io.open(filename, "w"))

    f:write("return {\n")
    f:write("    next_id = " .. tostring(player_db.next_id) .. ",\n")
    f:write("    players = {\n")

    for id, p in pairs(player_db.players) do
        f:write("        [" .. id .. "] = {\n")
        f:write("            id="       ..p.id..",\n")
        f:write("            name="     ..string.format("%q", p.name)..",\n")
        f:write("            gender="   ..string.format("%q", p.gender)..",\n")
        f:write("            pin="      ..string.format("%q", p.pin)..",\n")
        f:write("            created="  ..p.created..",\n")
        f:write("            location=" ..p.location..",\n")
        f:write("            score="    ..p.score..",\n")
        f:write("            stamina="  ..p.stamina..",\n")
        f:write("            flags="    ..serialize_table(p.flags)..",\n")
        f:write("        },\n")
    end

    f:write("    },\n")
    f:write("}\n")

    f:close()
end

function database.load(filename)
    local ok, data = pcall(dofile, filename)
    if not ok or not data then
        print("No existing database or failed to load; using empty DB.")
        return
    end

    player_db.next_id = data.next_id or 1
    player_db.players = data.players or {}
    player_db.by_name = {}

    for id, p in pairs(player_db.players) do
        player_db.by_name[p.name] = id
    end

    print("Loaded player database (" .. tostring(#player_db.players) .. " players).")
end

function database.create_player(name, gender, pin)
    if player_db.by_name[name] then
        return nil, "NAME_TAKEN"
    end

    local id = player_db.next_id
    player_db.next_id = id + 1

    local player = {
        id       = id,
        name     = name,
        gender   = gender,
        pin      = pin,
        created  = os.time(),
        location = 1,
        score    = 0,
        stamina  = 100,
        flags    = {}
    }

    player_db.players[id] = player
    player_db.by_name[name] = id

    return id, player
end

function database.get_player(id)
    return player_db.players[id]
end

function database.get_player_by_name(name)
    local id = player_db.by_name[name]
    if id then return player_db.players[id] end
    return nil
end

function database.authenticate(id, pin)
    local p = player_db.players[id]
    if not p then return false end
    return p.pin == pin
end

function database.update_player(p)
    local record = player_db.players[p.id]
    if not record then return end

    record.location = p.location
    record.score    = p.score
    record.stamina  = p.stamina
    record.flags    = p.flags
end

function database.raw()
    return player_db
end

return database