----------------------------------------------------------------------
-- help_loader.lua
-- Loads help messages and provides lookup/listing helpers.
--
-- Accepted data formats:
--   (A) help_messages = { {"topic","text"}, {"topic2","text2"}, ... }
--   (B) return { {"topic","text"}, {"topic2","text2"}, ... }
----------------------------------------------------------------------

local help_loader = {}

-- Internal store: { [lower_topic] = { topic="OriginalCase", text="..." }, ... }
local HELP_INDEX = {}
-- Preserves insertion or post-load sorted order for listing
local HELP_TOPICS = {}

local function normalize(data)
    -- Data is expected to be an array of {topic, text}
    HELP_INDEX = {}
    HELP_TOPICS = {}
    for _, pair in ipairs(data or {}) do
        local topic, text = pair[1], pair[2]
        if type(topic) == "string" and type(text) == "string" then
            local key = topic:lower()
            if not HELP_INDEX[key] then
                HELP_INDEX[key] = { topic = topic, text = text }
                table.insert(HELP_TOPICS, topic)
            end
        end
    end
    table.sort(HELP_TOPICS, function(a, b) return a:lower() < b:lower() end)
end

-- Load from file; returns true/false
function help_loader.load(filename)
    local ok, ret = pcall(dofile, filename)
    if ok then
        -- Case B: file returned the table directly
        if type(ret) == "table" then
            normalize(ret)
            return true
        end
        -- Case A: file executed and created global help_messages
        if type(_G.help_messages) == "table" then
            normalize(_G.help_messages)
            return true
        end
    else
        print("help_loader: error loading " .. tostring(filename) .. ": " .. tostring(ret))
    end
    print("help_loader: failed to load " .. tostring(filename))
    return false
end

-- Returns alphabetical list of original‑case topics
function help_loader.topics()
    return HELP_TOPICS
end

-- Returns the help text (string) for a topic (case‑insensitive), or nil
function help_loader.lookup(topic)
    if not topic or topic == "" then return nil end
    local row = HELP_INDEX[topic:lower()]
    return row and row.text or nil
end

return help_loader