----------------------------------------------------------------------
-- room_loader.lua
-- Loads a room table from a Lua data file and feeds it to world.lua
----------------------------------------------------------------------

local world = require("world")

local room_loader = {}

function room_loader.load(filename)
    local ok, data = pcall(dofile, filename)
    if not ok then
        print("room_loader: NOT-OK - failed to load " .. tostring(filename))
        return false
    elseif type(data) ~= "table" then
        print("room_loader: NOT-TABLE failed to load " .. tostring(filename))
        return false
    end

    world.load_rooms(data)
    return true
end

return room_loader