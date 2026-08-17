local sqlite3 = require("lsqlite3")
local dbutil = require("db")

local M = {}

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function walk(host, community, oid)
    local command = table.concat({
        "snmpwalk -v2c -On -c", shell_quote(community), shell_quote(host), shell_quote(oid),
        "2>/dev/null"
    }, " ")
    local pipe = assert(io.popen(command, "r"))
    local rows = {}
    for line in pipe:lines() do rows[#rows + 1] = line end
    local ok = pipe:close()
    assert(ok, "snmpwalk failed for " .. host .. " " .. oid)
    return rows
end

local function parse_walk(lines, column)
    local values = {}
    local prefix = ".1.3.6.1.2.1.17.4.3.1." .. column .. "."
    for _, line in ipairs(lines) do
        local oid, value = line:match("^(%S+)%s+=%s+.-:%s*(.-)%s*$")
        if oid and oid:sub(1, #prefix) == prefix then
            local suffix = oid:sub(#prefix + 1)
            values[suffix] = value:gsub('^"', ''):gsub('"$', '')
        end
    end
    return values
end

function M.collect_fdb(db, switch_id, host, community)
    local addresses = parse_walk(walk(host, community, ".1.3.6.1.2.1.17.4.3.1.1"), "1")
    local ports = parse_walk(walk(host, community, ".1.3.6.1.2.1.17.4.3.1.2"), "2")
    local now, entries = os.time(), {}
    for suffix, mac in pairs(addresses) do
        local port = tonumber(ports[suffix])
        if port then entries[#entries + 1] = { mac=mac:gsub("%s+", ":"), port=port } end
    end
    dbutil.transaction(db, function()
        local delete = assert(db:prepare("DELETE FROM fdb_entries WHERE switch_id=?"))
        delete:bind_values(switch_id); assert(delete:step() == sqlite3.DONE); delete:finalize()
        local insert = assert(db:prepare([[
            INSERT INTO fdb_entries(switch_id,port,mac,observed_at) VALUES(?,?,?,?)]]))
        for _, entry in ipairs(entries) do
            insert:reset()
            insert:bind_values(switch_id,entry.port,entry.mac,now)
            assert(insert:step() == sqlite3.DONE, db:errmsg())
        end
        insert:finalize()
    end)
    return #entries
end

return M
