local sqlite3 = require("lsqlite3")
local dbutil = require("db")

local M = {}

local function normalize_mac(mac)
    if not mac then return nil end
    return mac:upper():gsub("-", ":")
end

local function synthetic_id(switch_id, port)
    return string.format("unmanaged:%s:%d", switch_id, port)
end

local function stage_inventory(db, build_id)
    local stmt = assert(db:prepare([[
        INSERT INTO build_nodes(build_id,node_id,kind,label,ip,mac,metadata_json)
        SELECT ?,id,kind,label,ip,UPPER(REPLACE(mac,'-',':')),metadata_json
          FROM inventory_nodes WHERE enabled=1
    ]]))
    stmt:bind_values(build_id)
    assert(stmt:step() == sqlite3.DONE, db:errmsg())
    stmt:finalize()
end

local function stage_edge(db, stmt, build_id, source, target, kind, port, sort_key)
    stmt:reset()
    stmt:bind_values(build_id, source, target, kind, port, sort_key)
    assert(stmt:step() == sqlite3.DONE, db:errmsg())
end

local function stage_fdb_graph(db, build_id, config)
    local insert_node = assert(db:prepare([[
        INSERT OR IGNORE INTO build_nodes
          (build_id,node_id,kind,label,ip,mac,metadata_json)
        VALUES(?,?,?,?,?,?,?)]]))
    local insert_edge = assert(db:prepare([[
        INSERT OR IGNORE INTO build_edges
          (build_id,source_id,target_id,kind,port,sort_key)
        VALUES(?,?,?,?,?,?)]]))
    -- The number of switch ports is small even when the FDB is large, so only this
    -- compact group summary is held in Lua. Members are streamed one row at a time.
    local groups = {}
    local group_query = assert(db:prepare([[
        SELECT f.switch_id,f.port,COUNT(*) AS total_count,
               SUM(CASE WHEN n.kind IN ('managed_switch','root') THEN 1 ELSE 0 END)
                   AS managed_count
          FROM fdb_entries f
          LEFT JOIN inventory_nodes n
            ON UPPER(REPLACE(n.mac,'-',':'))=UPPER(REPLACE(f.mac,'-',':'))
         WHERE EXISTS (SELECT 1 FROM inventory_nodes s
                        WHERE s.id=f.switch_id AND s.enabled=1)
         GROUP BY f.switch_id,f.port ORDER BY f.switch_id,f.port]]))
    for row in group_query:nrows() do groups[#groups + 1] = row end
    group_query:finalize()

    for _, group in ipairs(groups) do
        local attachment_count = group.managed_count > 0 and
            group.managed_count or group.total_count
        local use_unmanaged = attachment_count >= config.infer_unmanaged_min_devices
        local parent = group.switch_id
        if use_unmanaged then
            local dumb = synthetic_id(group.switch_id, group.port)
            insert_node:reset()
            insert_node:bind_values(build_id, dumb, "unmanaged_switch",
                "Unmanaged switch (port " .. group.port .. ")", nil, nil,
                string.format('{"inferred":true,"upstream_port":%d}', group.port))
            assert(insert_node:step() == sqlite3.DONE, db:errmsg())
            stage_edge(db, insert_edge, build_id, group.switch_id, dumb,
                "physical", group.port, string.format("%08d:0:%s", group.port, dumb))
            parent = dumb
        end

        local member_query = assert(db:prepare([[
            SELECT UPPER(REPLACE(f.mac,'-',':')) AS mac,n.id AS node_id,n.kind
              FROM fdb_entries f LEFT JOIN inventory_nodes n
                ON UPPER(REPLACE(n.mac,'-',':'))=UPPER(REPLACE(f.mac,'-',':'))
             WHERE f.switch_id=? AND f.port=?
               AND (?=0 OR n.kind IN ('managed_switch','root'))
             ORDER BY mac]]))
        member_query:bind_values(group.switch_id, group.port,
            group.managed_count > 0 and 1 or 0)
        for member in member_query:nrows() do
            member.mac = normalize_mac(member.mac)
            local target = member.node_id
            if not target and config.include_unknown_macs then
                target = "unknown:" .. member.mac
                insert_node:reset()
                insert_node:bind_values(build_id, target, "unknown_device",
                    member.mac, nil, member.mac, '{"inferred":true}')
                assert(insert_node:step() == sqlite3.DONE, db:errmsg())
            end
            if target and target ~= group.switch_id then
                local edge_port = group.port
                if use_unmanaged then edge_port = nil end
                stage_edge(db, insert_edge, build_id, parent, target,
                    "physical", edge_port,
                    string.format("%08d:1:%s", group.port, target))
            end
        end
        member_query:finalize()
    end
    insert_node:finalize(); insert_edge:finalize()
end

local function persist_dfs(db, build_id, snapshot_id, root_id)
    local insert_node = assert(db:prepare([[
        INSERT INTO topology_nodes
          (snapshot_id,seq,node_id,kind,label,ip,mac,depth,metadata_json)
        SELECT ?,?,node_id,kind,label,ip,mac,?,metadata_json
          FROM build_nodes WHERE build_id=? AND node_id=?]]))
    local insert_edge = assert(db:prepare([[
        INSERT INTO topology_edges
          (snapshot_id,seq,edge_id,source_id,target_id,kind,port)
        VALUES(?,?,?,?,?,?,?)]]))
    local push = assert(db:prepare([[
        INSERT OR IGNORE INTO build_stack
          (build_id,node_id,parent_id,edge_kind,port,depth,ordinal)
        SELECT ?,?,?,?,?,?,?
         WHERE NOT EXISTS (SELECT 1 FROM topology_nodes
                            WHERE snapshot_id=? AND node_id=?)]]))
    local delete = assert(db:prepare("DELETE FROM build_stack WHERE build_id=? AND node_id=?"))
    local node_seq, edge_seq, ordinal = 0, 0, 1
    push:bind_values(build_id,root_id,nil,nil,nil,0,ordinal,snapshot_id,root_id)
    assert(push:step() == sqlite3.DONE, db:errmsg())

    while true do
        local frame = dbutil.one(db, [[
            SELECT * FROM build_stack WHERE build_id=? ORDER BY ordinal DESC LIMIT 1]],
            build_id)
        if not frame then break end
        delete:reset(); delete:bind_values(build_id,frame.node_id)
        assert(delete:step() == sqlite3.DONE, db:errmsg())
        local seen = dbutil.one(db,
            "SELECT 1 AS found FROM topology_nodes WHERE snapshot_id=? AND node_id=?",
            snapshot_id,frame.node_id)
        if not seen then
            node_seq = node_seq + 1
            insert_node:reset()
            insert_node:bind_values(snapshot_id,node_seq,frame.depth,build_id,frame.node_id)
            assert(insert_node:step() == sqlite3.DONE, "missing build node: " .. frame.node_id)
            if frame.parent_id then
                edge_seq = edge_seq + 1
                local edge_id = frame.parent_id .. "->" .. frame.node_id
                insert_edge:reset()
                insert_edge:bind_values(snapshot_id,edge_seq,edge_id,frame.parent_id,
                    frame.node_id,frame.edge_kind,frame.port)
                assert(insert_edge:step() == sqlite3.DONE, db:errmsg())
            end

            -- Reverse order plus LIFO ordinal preserves deterministic DFS order.
            local child_query = assert(db:prepare([[
                SELECT target_id,kind,port FROM build_edges
                 WHERE build_id=? AND source_id=? ORDER BY sort_key DESC,target_id DESC]]))
            child_query:bind_values(build_id,frame.node_id)
            for child in child_query:nrows() do
                ordinal = ordinal + 1
                push:reset()
                push:bind_values(build_id,child.target_id,frame.node_id,child.kind,
                    child.port,frame.depth + 1,ordinal,snapshot_id,child.target_id)
                assert(push:step() == sqlite3.DONE, db:errmsg())
            end
            child_query:finalize()
        end
    end
    insert_node:finalize(); insert_edge:finalize(); push:finalize(); delete:finalize()
    return node_seq, edge_seq
end

function M.rebuild(db, config)
    local now = os.time()
    local build_id = string.format("%d-%06d", now, math.random(0, 999999))
    return dbutil.transaction(db, function()
        local root = dbutil.one(db,
            "SELECT id FROM inventory_nodes WHERE id=? AND enabled=1", config.root_id)
        assert(root, "configured root_id does not exist or is disabled: " .. config.root_id)
        db:exec("DELETE FROM build_nodes; DELETE FROM build_edges; DELETE FROM build_stack;")
        stage_inventory(db, build_id)
        stage_fdb_graph(db, build_id, config)
        local version = build_id
        local stmt = assert(db:prepare([[
            INSERT INTO snapshots(version,root_id,created_at,status)
            VALUES(?,?,?,'building')]]))
        stmt:bind_values(version, config.root_id, now)
        assert(stmt:step() == sqlite3.DONE, db:errmsg())
        stmt:finalize()
        local snapshot_id = db:last_insert_rowid()
        local nodes, edges = persist_dfs(db, build_id, snapshot_id, config.root_id)
        stmt = assert(db:prepare([[
            UPDATE snapshots SET status='ready',node_count=?,edge_count=? WHERE id=?]]))
        stmt:bind_values(nodes, edges, snapshot_id)
        assert(stmt:step() == sqlite3.DONE, db:errmsg())
        stmt:finalize()
        db:exec("DELETE FROM build_nodes; DELETE FROM build_edges; DELETE FROM build_stack;")
        local cutoff = snapshot_id - config.snapshot_retention
        stmt = assert(db:prepare("DELETE FROM snapshots WHERE id<=?"))
        stmt:bind_values(cutoff); stmt:step(); stmt:finalize()
        return { id=snapshot_id, version=version, nodes=nodes, edges=edges }
    end)
end

return M
