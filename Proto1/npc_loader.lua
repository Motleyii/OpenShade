----------------------------------------------------------------------
-- npc_loader.lua
-- Loads NPC prototypes and spawns initial NPCs.
-- After loading, prints a summary of each prototype:
--   name, power, stamina, value, speed, has_enters?, has_exits?, has_here?
----------------------------------------------------------------------

local npc   = require("npc")
local world = require("world")

local npc_loader = {}

function npc_loader.load(filename)
    local ok, data = pcall(dofile, filename)
    if not ok or type(data) ~= "table" then
        print("npc_loader: failed to load " .. tostring(filename))
        return false
    end

    ------------------------------------------------------------------
    -- 1. Load prototypes
    ------------------------------------------------------------------
    if type(data.prototypes) == "table" then
        npc.load_prototypes(data.prototypes)
    end

    ------------------------------------------------------------------
    -- 2. Spawn instances
    ------------------------------------------------------------------
    if type(data.spawns) == "table" then
        for _, s in ipairs(data.spawns) do
            if s.proto_id and s.room then
                npc.spawn(s.proto_id, s.room)
            end
        end
    end

    ------------------------------------------------------------------
    -- 3. Print NPC summary (per prototype)
    ------------------------------------------------------------------
    print("== NPC Loader Report ==")
    for proto_id, proto in pairs(npc.prototypes) do
        local name     = proto.name    or "Unnamed"
        local power    = proto.power   or 0
        local stamina  = proto.stamina or 0
        local value    = proto.value   or 0
        local speed    = proto.speed   or 0

        local has_enters = proto.enters and "YES" or "no"
        local has_exits  = proto.exits  and "YES" or "no"
        local has_here   = proto.here   and "YES" or "no"

        print(string.format(
            "Proto %d: %s | PWR %d | STA %d | VAL %d | SPD %d | enters=%s | exits=%s | here=%s",
            proto_id,
            tostring(name),
            power,
            stamina,
            value,
            speed,
            has_enters,
            has_exits,
            has_here
        ))
    end
    print("== End of NPC Loader Report ==")

    return true
end

return npc_loader