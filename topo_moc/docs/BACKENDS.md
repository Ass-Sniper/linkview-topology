# SNMP FDB backend layout

The FDB data contract lives in `snmp/data/fdb.json`. Backends consume that data or
replace it with a live kernel source while preserving the BRIDGE-MIB OID contract.

## Active: pass_persist

`snmp/backends/pass_persist/fdb_agent.py` is the default backend. It is a long-running
Net-SNMP child process and supports `PING`, `get`, and lexicographically correct
`getnext`. Reload changed JSON with `docker compose restart mock-switch`.

## Reserved: AgentX

Use `snmp/backends/agentx/` for a future AgentX subagent. It should expose
`dot1dTpFdbAddress` and `dot1dTpFdbPort`, initially using the same JSON schema. Enable
`master agentx` in `snmp/config/snmpd.conf` when this backend is implemented.

## Reserved: Linux bridge

Use `snmp/backends/linux_bridge/` for namespace/veth/bridge provisioning and a native
FDB adapter. The intended data source is `bridge -j fdb show br br-core`. This backend
will eventually replace static JSON with MAC learning and ageing from the kernel.

Only one FDB backend should own `.1.3.6.1.2.1.17.4.3.1` at a time.
