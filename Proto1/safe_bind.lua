----------------------------------------------------------------------
-- safe_bind.lua
-- Safe wrapper for socket.bind() with:
--   • Graceful retry
--   • Optional fallback port
--   • Port owner detection
----------------------------------------------------------------------

local socket = require("socket")

local safe_bind = {}

----------------------------------------------------------------------
-- Detect which process owns the port (platform-dependent)
----------------------------------------------------------------------

local function detect_port_owner(port)
    -- Try Linux / macOS: lsof
    local cmd = "lsof -iTCP:" .. port .. " -sTCP:LISTEN -n -P 2>/dev/null"
    local f = io.popen(cmd)
    if f then
        local data = f:read("*a")
        f:close()
        if data and data:match("LISTEN") then
            return data
        end
    end

    -- Try netstat (Windows / cross-platform fallback)
    local cmd2 = "netstat -ano 2>/dev/null | grep ':" .. port .. " '"
    local f2 = io.popen(cmd2)
    if f2 then
        local data2 = f2:read("*a")
        f2:close()
        if data2 and data2 ~= "" then
            return data2
        end
    end

    return nil
end

----------------------------------------------------------------------
-- Safe bind with retry + fallback + port owner detection
----------------------------------------------------------------------

function safe_bind.bind(host, port, opts)
    opts = opts or {}
    local retries     = opts.retries or 0
    local retry_delay = opts.retry_delay or 1
    local fallback    = opts.fallback or nil

    local function try_bind(p)
        local listener, err = socket.bind(host, p)
        if listener then
            listener:settimeout(0)
            return listener, p
        end
        return nil, err
    end

    -- Initial attempt
    local listener, err = try_bind(port)
    if listener then return listener, port end

    -- Show owner if "address already in use"
    if err and err:lower():find("already") then
        local owner = detect_port_owner(port)
        if owner then
            print("Port " .. port .. " is already in use by:")
            print(owner)
        end
    end

    -- Retry attempts
    for _ = 1, retries do
        socket.sleep(retry_delay)
        listener, err = try_bind(port)
        if listener then return listener, port end
    end

    -- Fallback
    if fallback and fallback ~= port then
        listener, err = try_bind(fallback)
        if listener then
            print("Using fallback port " .. fallback)
            return listener, fallback
        end
    end

    return nil, err
end

return safe_bind