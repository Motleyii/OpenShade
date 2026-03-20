----------------------------------------------------------------------
-- object_loader.lua
-- Loads object prototypes and spawns initial object instances.
-- After loading, prints each spawned object's details:
--   id, name, power, weight, value, starting room title and id.
----------------------------------------------------------------------

local objects = require("objects")
local world   = require("world")

local object_loader = {}

-- Expected file format:
-- return {
--   prototypes = {
--      [id] = { name=..., desc=..., power=..., weight=..., value=..., noun={...} },
--      ...
--   },
--   spawns = {
--      { proto_id=1, room=2 },
--      { proto_id=2, room=1 },
--      ...
--   }
-- }

function object_loader.load(filename)
    local ok, data = pcall(dofile, filename)
    if not ok or type(data) ~= "table" then
        print("object_loader: failed to load " .. tostring(filename))
        return false
    end

    -- 1) Load prototypes (includes noun lists for noun-only matching)
    if type(data.prototypes) == "table" then
        objects.load_prototypes(data.prototypes)
    end

    -- 2) Spawn runtime instances at their starting rooms
    if type(data.spawns) == "table" then
        for _, s in ipairs(data.spawns) do
            if s.proto_id and s.room then
                objects.new_instance(s.proto_id, s.room)
            end
        end
    end

    -- 3) Print a report of all *current* live objects and their starting locations.
    --    (On a normal startup, this will correspond to every object we just spawned.)
    print("== Object Loader Report ==")
    for id, obj in pairs(objects.live or {}) do
        local room_id = obj.location
        local room    = world.get_room and world.get_room(room_id) or (world.rooms and world.rooms[room_id]) or nil
        local room_title = room and room.title or "Unknown"
        local name    = obj.name   or "Unnamed"
        local power   = obj.power  or 0
        local weight  = obj.weight or 0
        local value   = obj.value  or 0

        -- Format: [id] name | PWR power | WGT weight | VAL value | ROOM room_title (room_id)
        print(string.format(
            "[%d] %s | PWR %s | WGT %s | VAL %s | ROOM %s (Room %s)",
            id, tostring(name), tostring(power), tostring(weight),
            tostring(value), tostring(room_title), tostring(room_id or "nil")
        ))
    end
    print("== End of Object Loader Report ==")

    return true
end

return object_loader