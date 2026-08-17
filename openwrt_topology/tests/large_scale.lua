#!/usr/bin/lua
local source = debug.getinfo(1, "S").source:sub(2)
local home = source:match("^(.*)/tests/[^/]+$") or "."
package.path = home .. "/src/?.lua;" .. package.path

local sqlite3 = require("lsqlite3")
local dbutil = require("db")
local topology = require("topology")
local config = dofile(home .. "/config.lua")

local path = arg[1] or "/tmp/topology-large.db"
-- Router-safe default. Run larger cases on a VM, not on production OpenWrt.
local count = tonumber(arg[2]) or 2000
os.remove(path)
config.database = path
local db = dbutil.open(path)
dbutil.exec_file(db, home .. "/schema.sql")

dbutil.transaction(db, function()
    assert(db:exec([[INSERT INTO inventory_nodes(id,kind,label,ip,mac)
        VALUES('switch:core','root','Scale Test Core','192.168.16.118','02:00:00:00:00:01')]]) == sqlite3.OK)
    local node = assert(db:prepare([[
        INSERT INTO inventory_nodes(id,kind,label,mac) VALUES(?, 'device', ?, ?)]]))
    local fdb = assert(db:prepare([[
        INSERT INTO fdb_entries(switch_id,port,mac,observed_at)
        VALUES('switch:core',5,?,?)]]))
    local now = os.time()
    for index = 1, count do
        local mac = string.format("02:AA:%02X:%02X:%02X:%02X",
            math.floor(index / 16777216) % 256,
            math.floor(index / 65536) % 256,
            math.floor(index / 256) % 256,
            index % 256)
        node:reset(); node:bind_values(string.format("device:%08d", index),
            "Scale Device " .. index, mac)
        assert(node:step() == sqlite3.DONE, db:errmsg())
        fdb:reset(); fdb:bind_values(mac, now)
        assert(fdb:step() == sqlite3.DONE, db:errmsg())
    end
    node:finalize(); fdb:finalize()
end)

math.randomseed(os.time())
local started = os.clock()
local result = topology.rebuild(db, config)
result.input_devices = count
result.elapsed_cpu_seconds = os.clock() - started
local json = require("json")
print(json.encode(result))
db:close()
