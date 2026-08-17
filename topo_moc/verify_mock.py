#!/usr/bin/env python3
import json
import socket
import urllib.request
import uuid


def dh_probe(ip):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    sock.sendto(b"DHDiscover", (ip, 37810))
    data, addr = sock.recvfrom(65535)
    info = json.loads(data.decode())["params"]["deviceInfo"]
    print(f"DH_OK target={ip} from={addr[0]} model={info['deviceType']} mac={info['mac']}")


def dh_broadcast_probe():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(3)
    sock.bind(("0.0.0.0", 0))
    sock.sendto(b"DHDiscover", ("192.168.16.255", 37810))
    discovered = {}
    while len(discovered) < 2:
        try:
            data, addr = sock.recvfrom(65535)
        except socket.timeout:
            break
        info = json.loads(data.decode())["params"]["deviceInfo"]
        discovered[addr[0]] = info["mac"]
    assert discovered == {
        "192.168.16.101": "00:11:22:33:44:01",
        "192.168.16.200": "00:11:22:33:44:03",
    }, discovered
    print(f"DH_BROADCAST_OK devices={discovered}")


def onvif_probe():
    message_id = "urn:uuid:" + str(uuid.uuid4())
    probe = f'''<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
 xmlns:a="http://www.w3.org/2005/08/addressing"
 xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
 xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
 <s:Header><a:MessageID>{message_id}</a:MessageID>
 <a:To s:mustUnderstand="1">urn:schemas-xmlsoap-org:ws:2005:04:discovery</a:To>
 <a:Action s:mustUnderstand="1">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</a:Action></s:Header>
 <s:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></s:Body>
</s:Envelope>'''.encode()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.settimeout(4)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton("192.168.16.103"))
    sock.sendto(probe, ("239.255.255.250", 3702))
    data, addr = sock.recvfrom(65535)
    text = data.decode(errors="replace")
    assert "ProbeMatches" in text and "192.168.16.102/onvif/device_service" in text
    print(f"ONVIF_DISCOVERY_OK from={addr[0]} bytes={len(data)}")


def onvif_http():
    with urllib.request.urlopen("http://192.168.16.102/onvif/device_service", timeout=4) as response:
        body = response.read().decode(errors="replace")
    assert "ONVIF-NVT-102" in body and "GetDeviceInformationResponse" in body
    print(f"ONVIF_HTTP_OK status=200 bytes={len(body)}")


dh_probe("192.168.16.101")
dh_probe("192.168.16.200")
dh_broadcast_probe()
onvif_probe()
onvif_http()
