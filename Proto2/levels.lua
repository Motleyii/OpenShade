-- levels.lua
-- Persistent player level definitions
-- Indexed by numeric level ID (0 .. N)

return {

    [0] = {
        level = 0,
        threshold = 0,        -- minimum score to reach this level
        male = "Novice",
        female = "Novicette",
        max_weight = 2500,
        max_stamina = 100,
        fist_power = 5
    },

    [1] = {
        level = 1,
        threshold = 125,
        male = "Innocent",
        female = "Pure",
        max_weight = 2750,
        max_stamina = 115,
        fist_power = 6
    },

    [2] = {
        level = 2,
        threshold = 250,
        male = "Quester",
        female = "Searcher",
        max_weight = 3000,
        max_stamina = 130,
        fist_power = 7
    },

    [3] = {
        level = 3,
        threshold = 500,
        male = "Adventurer",
        female = "Adventuress",
        max_weight = 3250,
        max_stamina = 145,
        fist_power = 8
    },

    [4] = {
        level = 4,
        threshold = 1000,
        male = "Explorer",
        female = "Seeker",
        max_weight = 3500,
        max_stamina = 160,
        fist_power = 9
    },

    [5] = {
        level = 5,
        threshold = 2000,
        male = "Gallant",
        female = "Dauntless",
        max_weight = 3750,
        max_stamina = 170,
        fist_power = 10
    },

    [6] = {
        level = 6,
        threshold = 4000,
        male = "Valiant",
        female = "Amazon",
        max_weight = 4000,
        max_stamina = 180,
        fist_power = 11
    },

    [7] = {
        level = 7,
        threshold = 8000,
        male = "Seer",
        female = "Mystical",
        max_weight = 4250,
        max_stamina = 190,
        fist_power = 12
    },

    [8] = {
        level = 8,
        threshold = 15000,
        male = "Soothsayer",
        female = "Spellbinder",
        max_weight = 4500,
        max_stamina = 200,
        fist_power = 13
    },

    [9] = {
        level = 9,
        threshold = 30000,
        male = "Enchanter",
        female = "Enchantress",
        max_weight = 4750,
        max_stamina = 210,
        fist_power = 14
    },

    [10] = {
        level = 10,
        threshold = 50000,
        male = "Sorcerer",
        female = "Sorceress",
        max_weight = 5000,
        max_stamina = 220,
        fist_power = 15
    },

    [11] = {
        level = 11,
        threshold = 80000,
        male = "Necromancer",
        female = "Necromancess",
        max_weight = 5000,
        max_stamina = 230,
        fist_power = 16
    },

    [12] = {
        level = 12,
        threshold = 125000,
        male = "Warlock",
        female = "Bewitcher",
        max_weight = 5000,
        max_stamina = 240,
        fist_power = 17
    },

    [13] = {
        level = 13,
        threshold = 200000,
        male = "Wizard",
        female = "Witch",
        max_weight = 99999,
        max_stamina = 9999,
        fist_power = 100
    },

    [14] = {
        level = 14,
        threshold = 999999,
        male = "Archwizard",
        female = "Archwitch",
        max_weight = 99999,
        max_stamina = 9999,
        fist_power = 1000
    }

}
