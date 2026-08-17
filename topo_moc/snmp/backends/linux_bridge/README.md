# Linux bridge backend reservation

Place idempotent network setup and teardown scripts here. The target topology is:

```text
br-core port 5 -> br-dumb -> IPC 1, IPC 2
br-core port 6 -> NVR
```

Future code should read the kernel FDB using JSON output from `bridge -j fdb` and map
bridge interfaces to stable SNMP port numbers. Network migration must preserve the
VM management address and provide an explicit rollback path.
