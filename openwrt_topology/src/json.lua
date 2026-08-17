local M = {}

local escapes = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f',
                  ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }

local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
        return escapes[c] or string.format('\\u%04x', c:byte())
    end) .. '"'
end

local function is_array(value)
    local count, max = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        if key > max then max = key end
        count = count + 1
    end
    return max == count
end

function M.encode(value)
    local kind = type(value)
    if value == nil then return "null" end
    if kind == "boolean" or kind == "number" then return tostring(value) end
    if kind == "string" then return quote(value) end
    if kind ~= "table" then error("unsupported JSON type: " .. kind) end
    local out = {}
    if is_array(value) then
        for i = 1, #value do out[i] = M.encode(value[i]) end
        return "[" .. table.concat(out, ",") .. "]"
    end
    for key, item in pairs(value) do
        out[#out + 1] = quote(tostring(key)) .. ":" .. M.encode(item)
    end
    table.sort(out)
    return "{" .. table.concat(out, ",") .. "}"
end

function M.write(value)
    io.write(M.encode(value))
end

return M
