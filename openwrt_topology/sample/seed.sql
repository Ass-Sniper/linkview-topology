INSERT OR REPLACE INTO inventory_nodes(id,kind,label,ip,mac) VALUES
 ('switch:core','root','Mock Core Switch','192.168.16.118','00:0C:29:7D:06:52'),
 ('device:ipc1','device','Dahua IPC 1','192.168.16.101','00:11:22:33:44:01'),
 ('device:ipc2','device','ONVIF IPC','192.168.16.102','00:11:22:33:44:02'),
 ('device:nvr','device','Dahua NVR','192.168.16.200','00:11:22:33:44:03');

DELETE FROM fdb_entries WHERE switch_id='switch:core';
INSERT INTO fdb_entries(switch_id,port,mac,observed_at) VALUES
 ('switch:core',5,'00:11:22:33:44:01',strftime('%s','now')),
 ('switch:core',5,'00:11:22:33:44:02',strftime('%s','now')),
 ('switch:core',6,'00:11:22:33:44:03',strftime('%s','now'));
