----------------------------------------------------------------------
-- objects.lua
-- Runtime object manager with "noun-only" matching.
--
-- Matching rules:
--   • We ONLY use the nouns defined on each object for parsing.
--   • We NEVER use 'name' or 'desc' for matching parser arguments.
--   • Parser arguments are tokenized (split by spaces); if ANY token
--     matches ANY noun (case-insensitive), we consider it a match.
--
-- Prototypes must include a 'noun' array, e.g.:
--   noun = {"SWORD","RUSTY"}
----------------------------------------------------------------------

local world   = require("world")

local objects = {}

----------------------------------------------------------------------
-- PROTOTYPES (static) and LIVE INSTANCES
----------------------------------------------------------------------

objects.prototypes = {}  -- [proto_id] = { name, desc, power, weight, noun={...}, ... }
objects.live       = {}  -- [obj_id]   = { id, proto_id, name, desc, power, weight, noun={...}, location }
objects.next_id    = 1

----------------------------------------------------------------------
-- INTERNAL HELPERS (noun handling)
----------------------------------------------------------------------

local function normalize_noun_list(list)
    -- returns a new array of lowercase strings; filters out non-strings
    local out = {}
    if type(list) == "table" then
        for _, v in ipairs(list) do
            if type(v) == "string" then
                table.insert(out, v:lower())
            end
        end
    end
    return out
end

local function tokenize(s)
    local t = {}
    if type(s) ~= "string" then return t end
    for w in s:gmatch("%S+") do
        table.insert(t, w:lower())
    end
    return t
end

local function obj_matches_arg_by_noun(obj, arg)
    -- Match if ANY token in arg matches ANY noun in obj.noun (case-insensitive)
    if not obj or not obj.noun then return false end
    local nouns = obj.noun
    if #nouns == 0 then return false end

    local tokens = tokenize(arg)
    if #tokens == 0 then return false end

    -- Build a fast set of nouns for equality matching
    local set = {}
    for _, n in ipairs(nouns) do set[n] = true end

    for _, tok in ipairs(tokens) do
        if set[tok] then
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- PROTOTYPE LOADER
----------------------------------------------------------------------

function objects.load_prototypes(proto_table)
    objects.prototypes = proto_table or {}

    -- Validate/normalize nouns on all prototypes
    for id, proto in pairs(objects.prototypes) do
        proto.noun = normalize_noun_list(proto.noun)

        -- Optional: warn if nouns missing/empty (safer to enforce design-time)
        if #proto.noun == 0 then
            -- You can print a warning or even assert here if desired
            print(("objects.load_prototypes: proto_id=%s has no nouns; matching will fail."):format(tostring(id)))
        end
    end

    -- Reset live registry IDs if desired; we keep them as-is
    print("Loaded " .. tostring(#objects.prototypes) .. " object prototypes.")
end

----------------------------------------------------------------------
-- CREATE A NEW OBJECT INSTANCE
----------------------------------------------------------------------

function objects.new_instance(proto_id, room_id)
    local proto = objects.prototypes[proto_id]
    if not proto then
        print("Warning: Unknown object proto_id: " .. tostring(proto_id))
        return nil
    end

    local id = objects.next_id
    objects.next_id = id + 1

    local obj = {
        id       = id,
        proto_id = proto_id,
        name     = proto.name,   -- still used for display
        noun     = normalize_noun_list(proto.noun),  -- copy normalized nouns
        desc     = proto.desc,
        power    = proto.power,
        value    = proto.value,
        weight   = proto.weight,
        home     = proto.home,
        respawn  = proto.respawn,
        male     = proto.male,
        plural   = proto.plural,
        vowel    = proto.vowel,
        location = room_id
    }

    objects.live[id] = obj

    if room_id then
        world.place_object(room_id, obj)
    end

    return obj
end

----------------------------------------------------------------------
-- QUERY LIVE OBJECTS
----------------------------------------------------------------------

function objects.get(id)
    return objects.live[id]
end

----------------------------------------------------------------------
-- REMOVE OBJECT INSTANCE
----------------------------------------------------------------------

function objects.remove(id)
    local obj = objects.live[id]
    if not obj then return end

    if obj.location then
        local room = world.get_room(obj.location)
        if room and room.objects then
            for i, o in ipairs(room.objects) do
                if o.id == id then
                    table.remove(room.objects, i)
                    break
                end
            end
        end
    end

    objects.live[id] = nil
end


function objects.remove_from_room(room_id, obj_id)
    local room = world.get_room(room_id)
    if not room or not room.objects then return end
    for i, o in ipairs(room.objects) do
        if o.id == obj_id then
            table.remove(room.objects, i)
            return
        end
    end
end

----------------------------------------------------------------------
-- ROOM OBJECT LOOKUP (noun-only matching)
----------------------------------------------------------------------

function objects.find_in_room_by_name(room_id, arg)
    local room = world.get_room(room_id)
    if not room or not room.objects then return nil end

    for _, obj in ipairs(room.objects) do
        if obj_matches_arg_by_noun(obj, arg) then
            return obj
        end
    end
    return nil
end

----------------------------------------------------------------------
-- INVENTORY LOOKUP (noun-only matching)
----------------------------------------------------------------------

local function find_in_inventory_by_noun(player, arg)
    if not player or not player.inventory then return nil end
    for _, obj in ipairs(player.inventory) do
        if obj_matches_arg_by_noun(obj, arg) then
            return obj
        end
    end
    return nil
end

----------------------------------------------------------------------
-- PICKUP
----------------------------------------------------------------------

function objects.player_pickup(player, obj_id)
    local obj = objects.live[obj_id]
    if not obj then
        player:send("You cannot find that object.\n")
        return false
    end

    player.inventory = player.inventory or {}
    table.insert(player.inventory, obj)

    -- Remove from room
    if obj.location then
        local room = world.get_room(obj.location)
        if room and room.objects then
            for i, o in ipairs(room.objects) do
                if o.id == obj_id then
                    table.remove(room.objects, i)
                    break
                end
            end
        end
    end

    obj.location = nil
    return true
end

----------------------------------------------------------------------
-- DROP (noun-only)
-- Auto-unwield if dropping the currently wielded weapon.
----------------------------------------------------------------------

function objects.player_drop(player, arg)
    if not player.inventory or #player.inventory == 0 then
        player:send("You are not carrying anything.\n")
        return false
    end

    local obj = find_in_inventory_by_noun(player, arg)
    if not obj then
        player:send("You don't have that.\n")
        return false
    end

    -- Remove from inventory
    local idx_to_remove = nil
    for i, o in ipairs(player.inventory) do
        if o == obj then idx_to_remove = i; break end
    end
    if idx_to_remove then table.remove(player.inventory, idx_to_remove) end

    -- Auto-unwield if it was wielded
    local unwielded = false
    if player.wielded == obj then
        player.wielded = nil
        unwielded = true
    end

    -- Place into room
    obj.location = player.location
    world.place_object(player.location, obj)

    -- Feedback
    if unwielded then
        player:send("You stop wielding the " .. (obj.name or "item") .. " and drop it.\n")
    else
        player:send("You drop the " .. (obj.name or "item") .. ".\n")
    end

    return true
end

----------------------------------------------------------------------
-- DROP-IN-ROOM (used by other systems if needed)
----------------------------------------------------------------------

function objects.drop_in_room(room_id, obj)
    obj.location = room_id
    world.place_object(room_id, obj)
end

----------------------------------------------------------------------
-- STEAL (noun-only)
-- Moves a noun-matched object from victim's inventory to thief's inventory.
-- Auto-unwield if victim had it wielded.
----------------------------------------------------------------------

function objects.steal_from_player(thief, victim, arg)
    if not arg or arg == "" then
        return false, "You must specify an object to steal."
    end
    if not victim or not victim.inventory or #victim.inventory == 0 then
        return false, victim and (victim.name .. " is not carrying that.") or "No such victim."
    end

    local obj = find_in_inventory_by_noun(victim, arg)
    if not obj then
        return false, victim.name .. " is not carrying that."
    end

    -- Remove from victim
    local idx_to_remove = nil
    for i, o in ipairs(victim.inventory) do
        if o == obj then idx_to_remove = i; break end
    end
    if idx_to_remove then table.remove(victim.inventory, idx_to_remove) end

    -- Auto-unwield if victim had it wielded
    if victim.wielded == obj then
        victim.wielded = nil
    end

    -- Give to thief
    thief.inventory = thief.inventory or {}
    table.insert(thief.inventory, obj)
    obj.location = nil

    return true, obj
end

----------------------------------------------------------------------
-- DESCRIBE OBJECTS IN ROOM (unchanged; still uses desc for display)
----------------------------------------------------------------------

function objects.describe_room_objects(player)
    local room = world.get_room(player.location)
    if not room or not room.objects or #room.objects == 0 then return end

    for _, obj in ipairs(room.objects) do
        player:send((obj.desc or ("You see a " .. (obj.name or "thing") .. ".")) .. "\n")
    end
end

return objects