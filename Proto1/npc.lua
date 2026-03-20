----------------------------------------------------------------------
-- npc.lua
-- Handles NPC prototypes, live instances, movement, and room presence.
----------------------------------------------------------------------

local world = require("world")

local npc = {}

-- Prototypes:
--   npc.prototypes[proto_id] = {
--     name, power, stamina, value,
--     enters, exits, here,
--     path = {room_id, ...}, speed = seconds
--   }
npc.prototypes = {}

-- Live instances:
--   npc.live[id] = {
--     id, proto_id, name, power, stamina, value,
--     enters, exits, here,
--     path, path_index, speed, next_move,
--     location
--   }
npc.live    = {}
npc.next_id = 1

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

local function broadcast_room(room_id, msg, except)
    if not _G.active_players then return end
    for _, p in pairs(_G.active_players) do
        if p.connected and p.location == room_id and p ~= except then
            p:send(msg)
        end
    end
end

local function remove_from_room(room_id, inst)
    if not room_id then return end
    local room = world.get_room(room_id)
    if not room or not room.npcs then return end
    for i, n in ipairs(room.npcs) do
        if n == inst then
            table.remove(room.npcs, i)
            break
        end
    end
end

local function add_to_room(room_id, inst)
    if not room_id then return end
    local room = world.get_room(room_id)
    if not room then return end
    room.npcs = room.npcs or {}
    table.insert(room.npcs, inst)
end

----------------------------------------------------------------------
-- Prototypes
----------------------------------------------------------------------

function npc.load_prototypes(tbl)
    npc.prototypes = tbl or {}
end

----------------------------------------------------------------------
-- Spawning / Despawning
----------------------------------------------------------------------

function npc.spawn(proto_id, room_id)
    local proto = npc.prototypes[proto_id]
    if not proto then
        print("npc.spawn: unknown proto_id " .. tostring(proto_id))
        return nil
    end

    local id = npc.next_id
    npc.next_id = id + 1

    local inst = {
        id        = id,
        proto_id  = proto_id,

        -- core stats
        name      = proto.name    or "Someone",
        power     = proto.power   or 0,
        stamina   = proto.stamina or 0,
        value     = proto.value   or 0,

        -- presence/messaging
        enters    = proto.enters, -- string or nil
        exits     = proto.exits,  -- string or nil
        here      = proto.here,   -- string or nil (REQUIRED for world.look)

        -- movement
        path       = proto.path,  -- optional array of room ids
        path_index = 1,
        speed      = proto.speed, -- seconds between moves
        next_move  = nil,

        -- location
        location   = room_id
    }

    npc.live[id] = inst
    add_to_room(room_id, inst)

    if inst.speed and inst.speed > 0 then
        inst.next_move = os.time() + inst.speed
    end

    return inst
end

function npc.despawn(id)
    local inst = npc.live[id]
    if not inst then return end
    remove_from_room(inst.location, inst)
    npc.live[id] = nil
end

----------------------------------------------------------------------
-- Lookups
----------------------------------------------------------------------

function npc.get(id)
    return npc.live[id]
end

function npc.find_in_room_by_name(room_id, name)
    if not room_id or not name then return nil end
    local room = world.get_room(room_id)
    if not room or not room.npcs then return nil end
    local target = name:lower()
    for _, inst in ipairs(room.npcs) do
        if (inst.name or ""):lower() == target then
            return inst
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Movement (path patrol) with exits/enters broadcasts
----------------------------------------------------------------------

local function move_along_path(inst, now)
    local path = inst.path
    if not path or #path == 0 then return end

    local old_room = inst.location
    local idx      = (inst.path_index or 1) + 1
    if idx > #path then idx = 1 end
    inst.path_index = idx

    local new_room = path[idx]

    -- Announce leaving
    if inst.exits and old_room then
        broadcast_room(old_room, inst.exits .. "\n", nil)
    end

    -- Move rooms (update room.npcs lists)
    remove_from_room(old_room, inst)
    inst.location = new_room
    add_to_room(new_room, inst)

    -- Announce arrival
    if inst.enters then
        broadcast_room(new_room, inst.enters .. "\n", nil)
    end

    -- Schedule next step
    inst.next_move = now + (inst.speed or 10)
end

----------------------------------------------------------------------
-- Heartbeat (called from engine.tick(now))
----------------------------------------------------------------------

function npc.heartbeat(now)
    now = now or os.time()
    for _, inst in pairs(npc.live) do
        if inst.speed and inst.next_move and now >= inst.next_move then
            move_along_path(inst, now)
        end
    end
end

return npc