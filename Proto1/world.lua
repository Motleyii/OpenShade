----------------------------------------------------------------------
-- world.lua
-- World/room handling:
--   • Store and fetch rooms
--   • LOOK and EXITS
--   • Movement between rooms
--   • Place objects and NPCs in rooms
----------------------------------------------------------------------

local world = {}

world.rooms = {}

function world.get_room(id)
    return world.rooms[id]
end

local function is_treasure_room(room)
    local flags = room and room.flags
    return flags and (flags.is_troom ~= nil) and (flags.is_troom ~= false)
end


function world.load_rooms(room_table)
    if type(room_table) ~= "table" then
        print("world.load_rooms: invalid room table")
        return false
    end

    -- Load the rooms
    world.rooms = room_table

    -- Verify and report treasure rooms
    local found = 0
    for id, room in pairs(world.rooms) do
        if is_treasure_room(room) then
            found = found + 1
            local title = room.title or "Untitled"
            print(string.format("Treasure Room: %s (Room %s)", title, tostring(id)))
        end
    end

    if found == 0 then
        print("WARNING: No treasure rooms found. Scoring is not possible.")
    end

    return true
end

function world.look(player)
    local room = world.rooms[player.location]
    if not room then
        player:send("You are lost in the void - this is very bad!\n")
        return
    end

    -- Title + description
    player:send("\n" .. (room.title or "Unknown Place") .. " (" .. player.location .. ")\n")
    player:send((room.description or "It is indescribable here.") .. "\n")

    -- Exits (show only those whose destination is numeric)
    player:send("Exits: ")
    do
        local first = true
        for dir, dest in pairs(room.exits or {}) do
            -- Only list exits that point to a numeric room id
            if type(dest) == "number" then
                if not first then player:send(", ") end
                player:send(dir)
                first = false
            end
        end
        player:send("\n\n")
    end

    -- Objects
    if room.objects and #room.objects > 0 then
        for _, obj in ipairs(room.objects) do
            player:send((obj.desc or ("You see a " .. (obj.name or "thing") .. ".")) .. "\n")
        end
        player:send("\n")
    end

    -- NPCs (use ONLY the 'here' field)
    if room.npcs and #room.npcs > 0 then
        for _, n in ipairs(room.npcs) do
            player:send((n.here or ("A " .. (n.name or "thing") .. " is here.")) .. "\n")
        end
        player:send("\n")
    end

    -- Other players (exclude the viewer and anyone invisible)
    if _G.active_players then
        local names = {}
        for _, p in pairs(_G.active_players) do
            if p ~= player and p.connected and p.location == player.location then
                if not (p.flags and p.flags.invisible) then
                    table.insert(names, p.name)
                end
            end
        end
        if #names > 0 then
            player:send("Also here: " .. table.concat(names, ", ") .. "\n")
        end
    end
end

function world.move(player, direction)
    local room = world.rooms[player.location]
    if not room then
        player:send("There is nowhere to go.\n")
        return
    end

    local dest = (room.exits or {})[direction]
    if not dest then
        player:send("You cannot go that way.\n")
        return
    end

    player.location = dest
    world.look(player)
end

function world.place_object(room_id, object)
    local room = world.rooms[room_id]
    if not room then return end
    room.objects = room.objects or {}
    table.insert(room.objects, object)
end

function world.add_npc(room_id, npc)
    local room = world.rooms[room_id]
    if not room then return end
    room.npcs = room.npcs or {}
    table.insert(room.npcs, npc)
end

function world.remove_npc(room_id, npc)
    local room = world.rooms[room_id]
    if not room or not room.npcs then return end
    for i, n in ipairs(room.npcs) do
        if n == npc then
            table.remove(room.npcs, i)
            return
        end
    end
end

function world.get_exits(room_id)
    local room = world.rooms[room_id]
    if not room then return {} end
    return room.exits or {}
end

return world