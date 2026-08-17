# OpenWrt topology service

Lua 5.1 + lsqlite3 topology snapshot service for uHTTPd CGI. It converts inventory
and switch FDB observations into a deterministic DFS tree. When two or more device
MACs are learned on the same managed-switch port, an inferred unmanaged-switch node
is inserted between the managed switch and those devices.

## Why snapshots

Rebuilds write a new immutable snapshot in one SQLite transaction while the API keeps
serving the previous ready snapshot under WAL mode. Frontends therefore never mix
nodes and edges from different calculations. Keep the `snapshot_id` returned by the
metadata endpoint on every paginated request.

## Data flow

1. Discovery collectors upsert `inventory_nodes` and `fdb_entries`.
2. `topology-cli.lua rebuild` groups FDB entries by managed switch and port.
3. Synthetic unmanaged switches are created for shared downstream ports.
4. Iterative, stack-based DFS writes ordered nodes and tree edges.
5. The API serves a stable snapshot using cursor pagination or NDJSON streaming.

## Development smoke test

```sh
lua bin/topology-cli.lua init /tmp/topology.db
sqlite3 /tmp/topology.db < sample/seed.sql
lua bin/topology-cli.lua rebuild /tmp/topology.db
```

The sample produces `switch:core -> unmanaged:switch:core:5 -> ipc1,ipc2` and a
direct `switch:core -> nvr` edge on port 6.

Collect the BRIDGE-MIB FDB directly from the mock switch, then rebuild:

```sh
lua bin/topology-cli.lua collect-fdb switch:core 192.168.16.118 public /tmp/topology.db
lua bin/topology-cli.lua rebuild /tmp/topology.db
```

Production refresh uses the managed switches listed in `config.lua`:

```sh
lua bin/topology-cli.lua refresh /var/lib/linkview/topology.db
```

Discovery processes can update inventory without writing SQL directly:

```sh
lua bin/topology-cli.lua upsert-node device:ipc1 device "Dahua IPC 1" \
  192.168.16.101 00:11:22:33:44:01 /var/lib/linkview/topology.db
```

## API

```text
GET /cgi-bin/topology?action=metadata
GET /cgi-bin/topology?action=nodes&snapshot_id=1&cursor=0&limit=1000
GET /cgi-bin/topology?action=edges&snapshot_id=1&cursor=0&limit=1000
GET /cgi-bin/topology?action=nodes&snapshot_id=1&format=ndjson
GET /cgi-bin/topology?action=graph
```

`graph` is intentionally rejected with HTTP 413 above `graph_max_items`. Large
frontends should request metadata first, then fetch nodes and edges in parallel pages.

## Scaling properties

- SQLite WAL permits readers during collection and snapshot builds.
- Ordered composite indexes back FDB grouping and cursor pages.
- DFS is iterative, so deep topologies cannot exhaust the Lua call stack.
- Candidate edges remain in SQLite; only the visited set, DFS stack, and one node's
  children are held in Lua memory.
- NDJSON avoids building a full response document in router memory.

## Deployment prerequisites

- Lua 5.1-compatible runtime
- lsqlite3 Lua module
- uHTTPd CGI support
- writable `/var/lib/linkview`

Run `scripts/install.sh` only after confirming package/module names on the target
ImmortalWrt build.
