return {
    database = "/var/lib/linkview/topology.db",
    root_id = "switch:core",
    page_size_default = 1000,
    page_size_max = 5000,
    graph_max_items = 10000,
    snapshot_retention = 3,
    infer_unmanaged_min_devices = 2,
    include_unknown_macs = true,
    switches = {
        { id="switch:core", host="192.168.16.118", community="public" },
    },
}
