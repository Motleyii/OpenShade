----------------------------------------------------------------------
-- combat.lua
-- Extended: Player vs Player (PvP) combat with exact loss fractions.
-- Existing PvE functions are preserved.
----------------------------------------------------------------------

local world  = require("world")
local npc    = require("npc")
local levels = require("levels")

local combat = {}

-- Active combats:
-- For PvE: combat.active[player_id] = { type="pve", player=..., npc_id=..., initiator_id=..., next_tick=... }
-- For PvP: combat.active[slot_key]  = { type="pvp", a=playerA, b=playerB, initiator_id=..., next_tick=... }
combat.active = combat.active or {}

----------------------------------------------------------------------
-- DAMAGE FUNCTIONS (reuse your existing ones if already defined)
----------------------------------------------------------------------

local function best_weapon_power(player)
    local best = 0
    if not player.inventory then return 0 end
    for _, obj in ipairs(player.inventory) do
        if obj.power and obj.power > best then best = obj.power end
    end
    return best
end

local function weapon_in_inventory(player, obj)
    if not obj or not player.inventory then return false end
    for _, o in ipairs(player.inventory) do
        if o == obj then return true end
    end
    return false
end

local function best_weapon_power(player)
    local best = 0
    if not player.inventory then return 0 end
    for _, obj in ipairs(player.inventory) do
        if obj.power and obj.power > best then best = obj.power end
    end
    return best
end

local function get_weapon_power(player)
    -- If a wielded weapon is set and still carried, prefer it
    if player.wielded and weapon_in_inventory(player, player.wielded) then
        return player.wielded.power or 0
    end
    -- Otherwise use the highest-power weapon the player carries
    return best_weapon_power(player)
end

local function compute_player_damage(player)
    local wp   = get_weapon_power(player)
    local base = 5 + wp
    local spread = math.random(0, math.floor(base / 2))
    return math.max(1, base + spread)
end

local function compute_npc_damage(inst)
    local base = (inst.power or 5)
    local spread = math.random(0, math.floor(base / 3))
    return math.max(1, base + spread)
end

----------------------------------------------------------------------
-- ROOM BROADCAST (utility)
----------------------------------------------------------------------

local function broadcast_room(room_id, message, except_player)
    if not _G.active_players then return end
    for _, p in pairs(_G.active_players) do
        if p.location == room_id and p ~= except_player then
            p:send(message)
        end
    end
end

----------------------------------------------------------------------
-- PVP LOSS FRACTIONS (Option A: exact per-level)
-- Level indexes (0..13). Clamp unknown to nearest.
-- Adventurer (3) = 1/32, Sorcerer (10) = 1/2 (max), higher capped at 1/2.
----------------------------------------------------------------------

local PVP_LOSS_FRACTION = {
    [0]  = 1/64, [1]  = 1/48, [2]  = 1/40, [3]  = 1/32,
    [4]  = 1/28, [5]  = 1/24, [6]  = 1/20, [7]  = 1/16,
    [8]  = 1/12, [9]  = 1/8,  [10] = 1/2,  [11] = 1/2,
    [12] = 1/2,  [13] = 1/2
}

local function get_pvp_loss_fraction(player)
    local idx = levels.get_level_index(player.score or 0)
    local f = PVP_LOSS_FRACTION[idx]
    if not f then
        -- Clamp: below 0 → level 0; above 13 → 13
        f = (idx < 0) and PVP_LOSS_FRACTION[0] or PVP_LOSS_FRACTION[13]
    end
    return f
end

----------------------------------------------------------------------
-- COMMON STOP / CLEANUP HELPERS
----------------------------------------------------------------------

local function clear_player_flags(p)
    p.in_combat = false
    p.target = nil
end

local function stop_pve(slot)
    local player = slot.player
    clear_player_flags(player)
    combat.active[player.id] = nil
end

local function stop_pvp(slot)
    if slot.a then clear_player_flags(slot.a) end
    if slot.b then clear_player_flags(slot.b) end
    combat.active[slot.key] = nil
end

----------------------------------------------------------------------
-- PVE START/LOOP (kept compatible with previous version)
----------------------------------------------------------------------

function combat.start(player, npc_inst)
    if player.in_combat then
        player:send("You are already in combat.\n")
        return false
    end

    combat.active[player.id] = {
        type         = "pve",
        player       = player,
        npc_id       = npc_inst.id,
        initiator_id = player.id,
        next_tick    = os.time() + 2
    }

    player.in_combat = true
    player.target    = npc_inst.id

    player:send("You engage the " .. npc_inst.name .. " in combat!\n")
    broadcast_room(player.location, player.name .. " engages " .. npc_inst.name .. "!\n", player)
    return true
end

local function pve_round(slot, now)
    local player = slot.player
    local inst   = npc.get(slot.npc_id)

    if not player or not player.connected then stop_pve(slot); return end
    if not inst or inst.location ~= player.location then
        player:send("Your foe is no longer here.\n")
        stop_pve(slot)
        return
    end

    -- Player strikes

    -- Player damage uses weapon power when armed; otherwise level-based fist_power
    local function compute_player_damage(player)
        local wp = get_weapon_power(player)

        if wp > 0 then
            -- Armed: keep existing behavior (base 5 + weapon power)
            local base   = 5 + wp
            local spread = math.random(0, math.floor(base / 2))
            return math.max(1, base + spread)
        else
            -- Unarmed: use level-based fist_power from levels.lua
            local _, row = levels.get_level_index(player.score or 0)
            local fist   = (row and row.fist_power) or 5  -- safe fallback
            local base   = fist
            local spread = math.random(0, math.floor(base / 2))
            return math.max(1, base + spread)
        end
    end

    -- NPC strikes back
    local ndmg = compute_npc_damage(inst)
    player:sub_stamina(ndmg)
    player:send(inst.name .. " hits you for " .. ndmg .. " damage.\n")

    if player.stamina <= 0 then
        player:send("You are defeated!\n")
        broadcast_room(player.location, player.name .. " is defeated by the " .. inst.name .. "!\n", player)
        stop_pve(slot)
        return
    end

    slot.next_tick = now + 2
end

----------------------------------------------------------------------
-- PVP START/LOOP
----------------------------------------------------------------------

local function make_pvp_key(a, b)
    -- Deterministic composite key for the pair
    local lo = math.min(a.id, b.id)
    local hi = math.max(a.id, b.id)
    return "pvp:" .. lo .. "-" .. hi
end

function combat.start_pvp(attacker, defender)
    if attacker == defender then
        attacker:send("You can't attack yourself.\n")
        return false
    end
    if attacker.in_combat then
        attacker:send("You are already in combat.\n")
        return false
    end
    if defender.in_combat then
        attacker:send(defender.name .. " is already in combat.\n")
        return false
    end
    if attacker.location ~= defender.location then
        attacker:send("They are not here.\n")
        return false
    end

    local key = make_pvp_key(attacker, defender)
    if combat.active[key] then
        attacker:send("That fight is already underway.\n")
        return false
    end

    local slot = {
        type         = "pvp",
        key          = key,
        a            = attacker,
        b            = defender,
        initiator_id = attacker.id,
        next_tick    = os.time() + 2
    }
    combat.active[key] = slot

    attacker.in_combat = true; attacker.target = defender.id
    defender.in_combat = true; defender.target = attacker.id

    attacker:send("You attack " .. defender.name)
    if get_weapon_power(player) == 0 then
        attacker:send(" with your bare fists")
    end
    attacker:send("!\n")


    defender:send(attacker.name .. " attacks you!\n")
    broadcast_room(attacker.location, attacker.name .. " attacks " .. defender.name .. "!\n", nil)
    return true
end

local function resolve_pvp_victory(slot, winner, loser)
    -- Compute loss
    local frac  = get_pvp_loss_fraction(loser)
    local loss  = math.floor((loser.score or 0) * frac)

    -- If the loser started the fight, they lose double
    if loser.id == slot.initiator_id then
        loss = loss * 2
    end
    if loss < 0 then loss = 0 end
    if loss > (loser.score or 0) then loss = loser.score end

    -- Apply loss
    loser:set_score((loser.score or 0) - loss)

    -- Winner's gain:
    -- If attacker kills someone → gets 1/8 of what the loser lost.
    -- If defender kills the attacker → gets 1/4 of what the loser lost.
    local gain_ratio = (loser.id == slot.initiator_id) and 0.25 or 0.125
    local gain = math.floor(loss * gain_ratio)
    if gain > 0 then winner:add_score(gain) end

    -- Messaging
    winner:send("You defeat " .. loser.name .. " in combat!\n")
    loser:send("You are defeated by " .. winner.name .. "!\n")
    broadcast_room(winner.location,
        winner.name .. " defeats " .. loser.name .. " in combat!\n", nil)

    -- Cleanup
    stop_pvp(slot)
end

local function pvp_round(slot, now)
    local a, b = slot.a, slot.b
    if not a or not b or not a.connected or not b.connected then
        if a then clear_player_flags(a) end
        if b then clear_player_flags(b) end
        combat.active[slot.key] = nil
        return
    end
    if a.location ~= b.location then
        a:send("Your opponent is no longer here.\n")
        b:send("Your opponent is no longer here.\n")
        stop_pvp(slot); return
    end

    -- A strikes B
    local dmgA = compute_player_damage(a)
    b:sub_stamina(dmgA)
    a:send("You hit " .. b.name .. " for " .. dmgA .. " damage.\n")
    b:send(a.name .. " hits you for " .. dmgA .. " damage.\n")
    if b.stamina <= 0 then
        resolve_pvp_victory(slot, a, b)
        return
    end

    -- B strikes A
    local dmgB = compute_player_damage(b)
    a:sub_stamina(dmgB)
    b:send("You hit " .. a.name .. " for " .. dmgB .. " damage.\n")
    a:send(b.name .. " hits you for " .. dmgB .. " damage.\n")
    if a.stamina <= 0 then
        resolve_pvp_victory(slot, b, a)
        return
    end

    slot.next_tick = now + 2
end

----------------------------------------------------------------------
-- PUBLIC ATTACK HELPERS (called by commands)
----------------------------------------------------------------------

-- Attack an NPC in the same room by instance
function combat.attack_npc(player, npc_inst)
    return combat.start(player, npc_inst)
end

-- Attack another player in the same room
function combat.attack_player(attacker, defender)
    return combat.start_pvp(attacker, defender)
end

-- Optional flee: breaks off (works for either PvE or PvP slots you own)
function combat.flee(player)
    -- Find the player's slot
    -- PvE keyed by player.id; PvP keyed by composite, so scan
    local slot = combat.active[player.id]
    if slot and slot.type == "pve" then
        if math.random(1,100) <= 60 then
            player:send("You flee and break off combat.\n")
            stop_pve(slot)
            return true
        else
            player:send("You fail to escape!\n")
            return false
        end
    end

    for key, s in pairs(combat.active) do
        if s.type == "pvp" and (s.a == player or s.b == player) then
            if math.random(1,100) <= 60 then
                s.a:send("The fight is broken off.\n")
                s.b:send("The fight is broken off.\n")
                stop_pvp(s)
                return true
            else
                player:send("You fail to escape!\n")
                return false
            end
        end
    end

    player:send("You are not fighting anyone.\n")
    return false
end

----------------------------------------------------------------------
-- HEARTBEAT
----------------------------------------------------------------------

function combat.heartbeat(now)
    now = now or os.time()
    for key, slot in pairs(combat.active) do
        if now >= (slot.next_tick or now) then
            if slot.type == "pve" then
                pve_round(slot, now)
            elseif slot.type == "pvp" then
                pvp_round(slot, now)
            end
        end
    end
end

----------------------------------------------------------------------
-- DISCONNECT CLEANUP
----------------------------------------------------------------------

function combat.on_player_disconnect(player)
    -- PvE
    local s = combat.active[player.id]
    if s and s.type == "pve" then stop_pve(s) end

    -- PvP: scan
    for key, slot in pairs(combat.active) do
        if slot.type == "pvp" and (slot.a == player or slot.b == player) then
            stop_pvp(slot)
        end
    end
end

----------------------------------------------------------------------
-- Deterministic combat break-off (used by directional FLEE)
----------------------------------------------------------------------

-- Returns true if a fight was found and stopped, false otherwise.
function combat.force_breakoff(player)
    -- PvE slot keyed by player.id
    local s = combat.active[player.id]
    if s and s.type == "pve" then
        player:send("You break off the fight!\n")
        stop_pve(s)
        return true
    end

    -- PvP slots: scan
    for key, slot in pairs(combat.active) do
        if slot.type == "pvp" and (slot.a == player or slot.b == player) then
            local other = (slot.a == player) and slot.b or slot.a
            player:send("You break off the fight!\n")
            if other and other.connected then
                other:send(player.name .. " breaks off the fight!\n")
            end
            stop_pvp(slot)
            return true
        end
    end

    return false
end

return combat