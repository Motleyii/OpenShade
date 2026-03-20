----------------------------------------------------------------------
-- net.lua
-- Non-blocking socket helpers using coroutines.
-- Works with LuaSocket; sockets must be settimeout(0).
----------------------------------------------------------------------

local net = {}

----------------------------------------------------------------------
-- Send all data (handles partial sends, yields on 'timeout')
----------------------------------------------------------------------

function net.send(sock, data)
    local i = 1
    while i <= #data do
        local sent, err, last = sock:send(data, i)
        if sent then
            i = i + sent
        elseif err == "timeout" then
            coroutine.yield() -- give other sessions a chance
        else
            return nil, err or "send_failed"
        end
    end
    return true
end

----------------------------------------------------------------------
-- Read a single line ('*l'), yields on 'timeout'
----------------------------------------------------------------------

function net.read_line(sock)
    while true do
        local line, err = sock:receive("*l")
        if line then
            return line
        elseif err == "timeout" then
            coroutine.yield() -- try again later
        else
            return nil, err -- 'closed' or other error
        end
    end
end

----------------------------------------------------------------------
-- Convenience: prompt + line
----------------------------------------------------------------------

function net.prompt(sock, text)
    local ok, perr = net.send(sock, text)
    if not ok then return nil, perr end
    return net.read_line(sock)
end

return net