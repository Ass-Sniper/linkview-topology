PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;

CREATE TABLE IF NOT EXISTS inventory_nodes (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL CHECK(kind IN ('root','managed_switch','device')),
    label TEXT NOT NULL,
    ip TEXT,
    mac TEXT UNIQUE,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    enabled INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS fdb_entries (
    switch_id TEXT NOT NULL,
    port INTEGER NOT NULL,
    mac TEXT NOT NULL,
    observed_at INTEGER NOT NULL,
    PRIMARY KEY (switch_id, port, mac),
    FOREIGN KEY (switch_id) REFERENCES inventory_nodes(id)
);
CREATE INDEX IF NOT EXISTS idx_fdb_mac ON fdb_entries(mac);
CREATE INDEX IF NOT EXISTS idx_fdb_switch_port ON fdb_entries(switch_id, port, mac);

CREATE TABLE IF NOT EXISTS snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    version TEXT NOT NULL UNIQUE,
    root_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('building','ready','failed')),
    node_count INTEGER NOT NULL DEFAULT 0,
    edge_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_snapshots_ready ON snapshots(status, id DESC);

CREATE TABLE IF NOT EXISTS topology_nodes (
    snapshot_id INTEGER NOT NULL,
    seq INTEGER NOT NULL,
    node_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    label TEXT NOT NULL,
    ip TEXT,
    mac TEXT,
    depth INTEGER NOT NULL,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    PRIMARY KEY (snapshot_id, node_id),
    UNIQUE (snapshot_id, seq),
    FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_nodes_page ON topology_nodes(snapshot_id, seq);

CREATE TABLE IF NOT EXISTS topology_edges (
    snapshot_id INTEGER NOT NULL,
    seq INTEGER NOT NULL,
    edge_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    port INTEGER,
    PRIMARY KEY (snapshot_id, edge_id),
    UNIQUE (snapshot_id, seq),
    FOREIGN KEY (snapshot_id) REFERENCES snapshots(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_edges_page ON topology_edges(snapshot_id, seq);

CREATE TABLE IF NOT EXISTS build_nodes (
    build_id TEXT NOT NULL,
    node_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    label TEXT NOT NULL,
    ip TEXT,
    mac TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}',
    PRIMARY KEY (build_id, node_id)
);

CREATE TABLE IF NOT EXISTS build_edges (
    build_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    port INTEGER,
    sort_key TEXT NOT NULL,
    PRIMARY KEY (build_id, source_id, target_id)
);
CREATE INDEX IF NOT EXISTS idx_build_edges_dfs
    ON build_edges(build_id, source_id, sort_key, target_id);

CREATE TABLE IF NOT EXISTS build_stack (
    build_id TEXT NOT NULL,
    node_id TEXT NOT NULL,
    parent_id TEXT,
    edge_kind TEXT,
    port INTEGER,
    depth INTEGER NOT NULL,
    ordinal INTEGER NOT NULL,
    PRIMARY KEY (build_id, node_id)
);
CREATE INDEX IF NOT EXISTS idx_build_stack_pop
    ON build_stack(build_id, ordinal DESC);
