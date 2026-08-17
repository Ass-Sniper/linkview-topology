#!/usr/bin/lua
local source = debug.getinfo(1, "S").source:sub(2)
local home = source:match("^(.*)/bin/[^/]+$") or "."
package.path = home .. "/src/?.lua;" .. package.path

local dbutil = require("db")
local topology = require("topology")
local json = require("json")
local config = dofile(home .. "/config.lua")

local command = arg[1]
if not command then
    io.stderr:write("usage: topology-cli.lua init|rebuild|latest [database]\n")
    io.stderr:write("       topology-cli.lua collect-fdb SWITCH_ID HOST COMMUNITY [database]\n")
    io.stderr:write("       topology-cli.lua refresh [database]\n")
    io.stderr:write("       topology-cli.lua upsert-node ID KIND LABEL IP MAC [database]\n")
    os.exit(2)
end
if command == "collect-fdb" then
    if not arg[2] or not arg[3] or not arg[4] then
        io.stderr:write("collect-fdb requires SWITCH_ID HOST COMMUNITY [database]\n")
        os.exit(2)
    end
    if arg[5] then config.database = arg[5] end
elseif command == "upsert-node" then
    if not arg[2] or not arg[3] or not arg[4] or not arg[5] or not arg[6] then
        io.stderr:write("upsert-node requires ID KIND LABEL IP MAC [database]\n")
        os.exit(2)
    end
    if arg[7] then config.database = arg[7] end
elseif arg[2] then
    config.database = arg[2]
end

local db = dbutil.open(config.database)
if command == "init" then
    dbutil.exec_file(db, home .. "/schema.sql")
    print("initialized " .. config.database)
elseif command == "rebuild" then
    math.randomseed(os.time())
    local result = topology.rebuild(db, config)
    print(json.encode(result))
elseif command == "latest" then
    local row = dbutil.one(db, "SELECT * FROM snapshots WHERE status='ready' ORDER BY id DESC LIMIT 1")
    print(json.encode(row))
elseif command == "collect-fdb" then
    local collector = require("collector")
    local count = collector.collect_fdb(db, arg[2], arg[3], arg[4])
    print(json.encode({ switch_id=arg[2], fdb_entries=count }))
elseif command == "refresh" then
    local collector = require("collector")
    local collected = {}
    for _, item in ipairs(config.switches or {}) do
        collected[item.id] = collector.collect_fdb(db, item.id, item.host, item.community)
    end
    math.randomseed(os.time())
    local result = topology.rebuild(db, config)
    result.collected = collected
    print(json.encode(result))
elseif command == "upsert-node" then
    local sqlite3 = require("lsqlite3")
    local stmt = assert(db:prepare([[
        INSERT INTO inventory_nodes(id,kind,label,ip,mac,metadata_json,enabled)
        VALUES(?,?,?,?,?,'{}',1)
        ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,label=excluded.label,
          ip=excluded.ip,mac=excluded.mac,enabled=1]]))
    stmt:bind_values(arg[2],arg[3],arg[4],arg[5],arg[6])
    assert(stmt:step() == sqlite3.DONE, db:errmsg())
    stmt:finalize()
    print(json.encode({ id=arg[2], updated=true }))
else
    io.stderr:write("unknown command: " .. command .. "\n")
    db:close(); os.exit(2)
end
db:close()
