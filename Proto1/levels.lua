----------------------------------------------------------------------
-- levels.lua
-- Level definitions: thresholds, sex-appropriate titles, max carry.
-- Levels are indexed 0..13 (14 levels).
----------------------------------------------------------------------

local levels = {
    --level,    threshold,        male,               female,                 max_weight 
    { level=0,  threshold=0,      male="Novice",      female="Novice",        max_weight=2500,  max_stamina=100,  fist_power=5 },
    { level=1,  threshold=125,    male="Innocent",    female="Pure",          max_weight=2750,  max_stamina=115,  fist_power=6 },
    { level=2,  threshold=250,    male="Quester",     female="Searcher",      max_weight=3000,  max_stamina=130,  fist_power=7 },
    { level=3,  threshold=500,    male="Adventurer",  female="Adventuress",   max_weight=3250,  max_stamina=145,  fist_power=8 },
    { level=4,  threshold=1000,   male="Explorer",    female="Seeker",        max_weight=3500,  max_stamina=160,  fist_power=9 },
    { level=5,  threshold=2000,   male="Gallant",     female="Dauntless",     max_weight=3750,  max_stamina=170,  fist_power=10 },
    { level=6,  threshold=4000,   male="Valiant",     female="Amazon",        max_weight=4000,  max_stamina=180,  fist_power=11 },
    { level=7,  threshold=8000,   male="Seer",        female="Mystical",      max_weight=4250,  max_stamina=190,  fist_power=12 },
    { level=8,  threshold=15000,  male="Soothsayer",  female="Spellbinder",   max_weight=4500,  max_stamina=200,  fist_power=13 },
    { level=9,  threshold=30000,  male="Enchanter",   female="Enchantress",   max_weight=4750,  max_stamina=210,  fist_power=14 },
    { level=10, threshold=50000,  male="Sorcerer",    female="Sorceress",     max_weight=5000,  max_stamina=220,  fist_power=15 },
    { level=11, threshold=80000,  male="Necromancer", female="Necromancess",  max_weight=5000,  max_stamina=230,  fist_power=16 },
    { level=12, threshold=125000, male="Warlock",     female="Bewitcher",     max_weight=5000,  max_stamina=240,  fist_power=17 },
    { level=13, threshold=200000, male="Wizard",      female="Witch",         max_weight=99999, max_stamina=9999, fist_power=100 }
}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function get_level_for_score(score)
    local last = levels[1] -- level 0 row
    for _, row in ipairs(levels) do
        if score >= row.threshold then
            last = row
        else
            break
        end
    end
    return last
end

-- Returns numeric level index (0..13) and the level row
local function get_level_index(score)
    local idx = 0
    local row = levels[1]
    for _, r in ipairs(levels) do
        if score >= r.threshold then
            idx = r.level
            row = r
        else
            break
        end
    end
    return idx, row
end

-- Sex-appropriate title for a player
local function get_title_for_player(player)
    local _, row = get_level_index(player.score or 0)
    local sex = (player.gender or "male"):lower()
    return (sex == "female") and row.female or row.male
end

-- Next level threshold and points remaining (or nil if at max)
local function get_next_threshold(score)
    local idx, row = get_level_index(score)
    local next_row = levels[idx + 2] -- +1 for 1-based array, +1 for next level
    if not next_row then return nil, nil end
    local next_thresh = next_row.threshold
    local to_go = math.max(0, next_thresh - score)
    return next_thresh, to_go
end

return {
    all                  = levels,
    get_level_for_score  = get_level_for_score,
    get_level_index      = get_level_index,
    get_title_for_player = get_title_for_player,
    get_next_threshold   = get_next_threshold
}