----------------------------------------------------------------------
-- player.lua
-- Runtime player object
--  • Non-blocking loop via net.lua
--  • Level integration (titles, level-up messages)
--  • Inventory & carry-weight helpers (drop-all clears wielded)
--  • Noun-only wielding (matches objects' noun-only parsing)
--  • Clean disconnect (persist + drop + clear combat)
----------------------------------------------------------------------

local net      = require("net")
local database = require("database")
local world    = require("world")
local levels   = require("levels")
local commands = require("commands")
local combat   = require("combat")

local player = {}

----------------------------------------------------------------------
-- Local helpers
----------------------------------------------------------------------

-- Broadcast a message to everyone in the same room (optional except_player)
local function broadcast_room(room_id, msg, except_player)
    if not _G.active_players then return end
    for _, p in pairs(_G.active_players) do
        if p.location == room_id and p ~= except_player then
            p:send(msg)
        end
    end
end

-- noun-only tokenization
local function tokenize(s)
    local t = {}
    if type(s) ~= "string" then return t end
    for w in s:gmatch("%S+") do
        table.insert(t, w:lower())
    end
    return t
end

-- match parser arg against an object's noun list (case-insensitive)
local function matches_by_noun(obj, term)
    if not obj or not obj.noun then return false end
    local nouns = obj.noun
    if #nouns == 0 then return false end
    local tokens = tokenize(term)
    if #tokens == 0 then return false end
    local set = {}
    for _, n in ipairs(nouns) do set[n:lower()] = true end
    for _, tok in ipairs(tokens) do
        if set[tok] then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------

function player.new(persistent_data, sock)
    local self = {
        -- Identity/persistent fields
        id        = persistent_data.id,
        name      = persistent_data.name,
        gender    = persistent_data.gender,
        pin       = persistent_data.pin,
        created   = persistent_data.created,

        -- Persistent state
        location  = persistent_data.location,
        score     = persistent_data.score or 0,
        stamina   = persistent_data.stamina or 0,
        flags     = persistent_data.flags or {},

        -- Runtime-only state
        inventory = {},      -- session-only inventory (empty on login)
        wielded   = nil,     -- currently wielded object reference (if any)
        in_combat = false,
        target    = nil,
        socket    = sock,
        connected = true
    }

    if self.flags.invisible == nil then
        self.flags.invisible = false  -- default on login
    end

    -- Cache current level index for level-up detection
    self.last_level_index = levels.get_level_index(self.score)

    setmetatable(self, { __index = player })
    return self
end

----------------------------------------------------------------------
-- Messaging
----------------------------------------------------------------------

function player:send(msg)
    if self.socket then
        self.socket:send(msg)
    end
end

----------------------------------------------------------------------
-- Flags / stamina helpers
----------------------------------------------------------------------

function player:set_flag(key, value) self.flags[key] = value end
function player:get_flag(key) return self.flags[key] end

function player:add_stamina(n) self.stamina = (self.stamina or 0) + (n or 0) end
function player:sub_stamina(n) self.stamina = math.max(0, (self.stamina or 0) - (n or 0)) end

----------------------------------------------------------------------
-- Score + level-up detection
----------------------------------------------------------------------

function player:set_score(new_score)
    self.score = new_score
    self:maybe_level_up()
end

function player:add_score(delta)
    self.score = (self.score or 0) + (delta or 0)
    self:maybe_level_up()
end

function player:maybe_level_up()
    local idx = levels.get_level_index(self.score or 0)
    if idx > (self.last_level_index or 0) then
        self.last_level_index = idx
        local title = levels.get_title_for_player(self)
        self:send("You have advanced in rank!\n")
        self:send("You are now a " .. title .. ".\n")
        broadcast_room(self.location, self.name .. " has advanced in rank to " .. title .. "!\n", self)
    end
end

----------------------------------------------------------------------
-- Inventory & carry-weight helpers
----------------------------------------------------------------------

function player:get_carry_weight()
    if not self.inventory or #self.inventory == 0 then return 0 end
    local total = 0
    for _, obj in ipairs(self.inventory) do
        total = total + (obj.weight or 0)
    end
    return total
end

function player:get_max_carry()
    local row = levels.get_level_for_score(self.score or 0)
    return row.max_weight or 0
end

-- Drop ALL carried objects into the current room and clear wielded
function player:drop_all_inventory()
    if not self.inventory or #self.inventory == 0 then return end
    for _, obj in ipairs(self.inventory) do
        obj.location = self.location
        world.place_object(self.location, obj)
    end
    self.inventory = {}
    self.wielded = nil
end

-- Print inventory (with total vs max)
function player:list_inventory()
    if not self.inventory or #self.inventory == 0 then
        self:send("You are carrying nothing.\n")
        return
    end
    self:send("You are carrying:\n")
    for _, obj in ipairs(self.inventory) do
        local w = obj.weight or 0
        self:send(" - " .. (obj.name or "item") .. " [" .. w .. "]\n")
    end
    self:send("Total weight: " .. self:get_carry_weight() ..
              " / " .. self:get_max_carry() .. "\n")
end

----------------------------------------------------------------------
-- Noun-only wielding
--  • Matches by noun words only (never by name/desc)
--  • Leaves the selection in self.wielded (used by combat damage)
----------------------------------------------------------------------

function player:wield_weapon_by_name(term)
    if not term or term == "" then
        return false, "You must specify a weapon."
    end
    if not self.inventory or #self.inventory == 0 then
        return false, "You are not carrying that."
    end

    for _, obj in ipairs(self.inventory) do
        if matches_by_noun(obj, term) then
            self.wielded = obj
            return true, obj
        end
    end
    return false, "You are not carrying that."
end

function player:get_wielded_weapon()
    return self.wielded
end

----------------------------------------------------------------------
-- Disconnect (persist + drop + clear combat)
----------------------------------------------------------------------

function player:disconnect()
    if not self.connected then return end
    self.connected = false

    -- Break off any active combat cleanly
    combat.on_player_disconnect(self)

    -- Drop any carried items into the current room
    self:drop_all_inventory()

    -- Persist core state
    database.update_player(self)
    database.save("players.db")

    -- Remove from global list
    if _G.active_players then _G.active_players[self.id] = nil end

    -- Close socket
    if self.socket then pcall(function() self.socket:close() end) end
    self.socket = nil
end

----------------------------------------------------------------------
-- Command loop (non-blocking, net.read_line)
----------------------------------------------------------------------

function player:handle_command(line)
    commands.handle(self, line)
end

function player:run_game_loop()
    local title = levels.get_title_for_player(self)
    self:send("Welcome, " .. self.name .. " (" .. title .. ")!\n")

    while self.connected do
        local line = net.read_line(self.socket)
        if not line then
            self:disconnect()
            return
        end
        self:handle_command(line)
    end
end

return player