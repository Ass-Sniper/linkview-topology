#!/usr/bin/lua
local base = os.getenv("TOPOLOGY_HOME") or "/usr/lib/linkview-topology"
package.path = base .. "/src/?.lua;" .. package.path

local sqlite3 = require("lsqlite3")
local json = require("json")
local dbutil = require("db")
local config = dofile(base .. "/config.lua")
config.database = os.getenv("TOPOLOGY_DB") or config.database

local function query_params(text)
    local result = {}
    for key, value in (text or ""):gmatch("([^&=?]+)=?([^&]*)") do
        value = value:gsub("+", " "):gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        result[key] = value
    end
    return result
end

local params = query_params(os.getenv("QUERY_STRING"))
local action = params.action or "metadata"

local function header(status, content_type, extra)
    io.write("Status: ", status, "\r\n")
    io.write("Content-Type: ", content_type or "application/json", "\r\n")
    io.write("Cache-Control: no-cache\r\n")
    if extra then for key, value in pairs(extra) do io.write(key, ": ", value, "\r\n") end end
    io.write("\r\n")
end

local function fail(status, code, message)
    header(status, "application/json")
    json.write({ error=code, message=message })
    io.write("\n")
    os.exit(0)
end

local db = dbutil.open(config.database)
local snapshot
if params.snapshot_id then
    snapshot = dbutil.one(db, [[SELECT * FROM snapshots WHERE id=? AND status='ready']],
        tonumber(params.snapshot_id))
else
    snapshot = dbutil.one(db, [[SELECT * FROM snapshots WHERE status='ready' ORDER BY id DESC LIMIT 1]])
end
if not snapshot then db:close(); fail("404 Not Found", "snapshot_not_found", "no ready topology snapshot") end

if action == "metadata" then
    header("200 OK", "application/json", { ETag='"' .. snapshot.version .. '"' })
    json.write({ snapshot_id=snapshot.id, version=snapshot.version,
        created_at=snapshot.created_at, root_id=snapshot.root_id,
        node_count=snapshot.node_count, edge_count=snapshot.edge_count,
        endpoints={ nodes="?action=nodes", edges="?action=edges" } })
    io.write("\n"); db:close(); return
end

local function page(kind)
    local cursor = math.max(0, tonumber(params.cursor) or 0)
    local limit = tonumber(params.limit) or config.page_size_default
    limit = math.max(1, math.min(limit, config.page_size_max))
    local table_name = kind == "nodes" and "topology_nodes" or "topology_edges"
    local stmt = assert(db:prepare("SELECT * FROM " .. table_name ..
        " WHERE snapshot_id=? AND seq>? ORDER BY seq LIMIT ?"))
    stmt:bind_values(snapshot.id, cursor, limit + 1)
    local rows, next_cursor = {}, nil
    for row in stmt:nrows() do
        if #rows < limit then rows[#rows + 1] = row else next_cursor = rows[#rows].seq; break end
    end
    stmt:finalize()
    header("200 OK", "application/json", { ETag='"' .. snapshot.version .. '"' })
    io.write('{"snapshot_id":', tostring(snapshot.id), ',"version":')
    json.write(snapshot.version)
    io.write(',"items":[')
    for index, row in ipairs(rows) do
        if index > 1 then io.write(",") end
        if kind == "nodes" then
            json.write({ seq=row.seq,id=row.node_id,kind=row.kind,label=row.label,
                ip=row.ip,mac=row.mac,depth=row.depth,metadata_json=row.metadata_json })
        else
            json.write({ seq=row.seq,id=row.edge_id,source=row.source_id,
                target=row.target_id,kind=row.kind,port=row.port })
        end
        if index % 256 == 0 then io.flush() end
    end
    io.write('],"next_cursor":')
    json.write(next_cursor)
    io.write("}\n")
end

local function ndjson(kind)
    local cursor = math.max(0, tonumber(params.cursor) or 0)
    local table_name = kind == "nodes" and "topology_nodes" or "topology_edges"
    local stmt = assert(db:prepare("SELECT * FROM " .. table_name ..
        " WHERE snapshot_id=? AND seq>? ORDER BY seq"))
    stmt:bind_values(snapshot.id, cursor)
    header("200 OK", "application/x-ndjson", { ETag='"' .. snapshot.version .. '"' })
    local count = 0
    for row in stmt:nrows() do
        json.write(row); io.write("\n"); count = count + 1
        if count % 256 == 0 then io.flush() end
    end
    stmt:finalize()
end

if action == "nodes" or action == "edges" then
    if params.format == "ndjson" then ndjson(action) else page(action) end
elseif action == "graph" then
    if snapshot.node_count + snapshot.edge_count > config.graph_max_items then
        db:close(); fail("413 Payload Too Large", "graph_too_large",
            "use the paginated nodes and edges endpoints")
    end
    header("200 OK", "application/json", { ETag='"' .. snapshot.version .. '"' })
    io.write('{"snapshot_id":', snapshot.id, ',"version":'); json.write(snapshot.version)
    for _, kind in ipairs({"nodes", "edges"}) do
        local table_name = kind == "nodes" and "topology_nodes" or "topology_edges"
        io.write(',"', kind, '":[')
        local first = true
        for row in db:nrows("SELECT * FROM " .. table_name .. " WHERE snapshot_id=" ..
                            tonumber(snapshot.id) .. " ORDER BY seq") do
            if not first then io.write(",") end; first = false; json.write(row)
        end
        io.write("]")
    end
    io.write("}\n")
else
    db:close(); fail("400 Bad Request", "invalid_action", "supported actions: metadata,nodes,edges,graph")
end
db:close()
