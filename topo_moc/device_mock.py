#!/usr/bin/env python3
import json
import os
import re
import socket
import threading
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


DEVICE_IP = os.getenv("DEVICE_IP", "127.0.0.1")
DEVICE_MAC = os.getenv("DEVICE_MAC", "00:00:00:00:00:00")
DEVICE_MODEL = os.getenv("DEVICE_MODEL", "Mock-Device")
DEVICE_NAME = os.getenv("DEVICE_NAME", DEVICE_MODEL)
ENABLE_DH = os.getenv("ENABLE_DH", "0") == "1"
ENABLE_ONVIF = os.getenv("ENABLE_ONVIF", "0") == "1"
DEVICE_UUID = str(uuid.uuid5(uuid.NAMESPACE_DNS, DEVICE_MAC.lower()))


def log(message):
    print(f"[{DEVICE_NAME}] {message}", flush=True)


def dahua_discovery():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind(("0.0.0.0", 37810))
    log("Dahua discovery listening on UDP 37810")
    while True:
        data, addr = sock.recvfrom(65535)
        text = data.decode("utf-8", errors="ignore")
        if not any(token in text for token in ("DHDiscover", "SearchDevices", "deviceDiscovery")):
            continue
        response = {
            "id": 1,
            "result": True,
            "params": {
                "deviceInfo": {
                    "DeviceType": DEVICE_MODEL,
                    "deviceType": DEVICE_MODEL,
                    "DeviceClass": "NVR" if "NVR" in DEVICE_MODEL else "IPC",
                    "IPv4Address": DEVICE_IP,
                    "ip": DEVICE_IP,
                    "MAC": DEVICE_MAC,
                    "mac": DEVICE_MAC,
                    "Name": DEVICE_NAME,
                    "version": "V2.800.0000000.0.R",
                    "HttpPort": 80,
                }
            },
        }
        sock.sendto(json.dumps(response, separators=(",", ":")).encode(), addr)
        log(f"Dahua discovery response sent to {addr[0]}:{addr[1]}")


def soap_envelope(body):
    return (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">'
        f"<s:Body>{body}</s:Body></s:Envelope>"
    ).encode()


class OnvifHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log("HTTP " + (fmt % args))

    def _send(self, payload, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/soap+xml; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        payload = soap_envelope(
            '<tds:GetDeviceInformationResponse xmlns:tds="http://www.onvif.org/ver10/device/wsdl">'
            f"<tds:Manufacturer>MockLab</tds:Manufacturer><tds:Model>{DEVICE_MODEL}</tds:Model>"
            '<tds:FirmwareVersion>1.0.0</tds:FirmwareVersion>'
            f"<tds:SerialNumber>{DEVICE_MAC.replace(':', '')}</tds:SerialNumber>"
            f"<tds:HardwareId>{DEVICE_UUID}</tds:HardwareId>"
            "</tds:GetDeviceInformationResponse>"
        )
        self._send(payload)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        request = self.rfile.read(length).decode("utf-8", errors="ignore")
        if "GetCapabilities" in request:
            body = (
                '<tds:GetCapabilitiesResponse xmlns:tds="http://www.onvif.org/ver10/device/wsdl" '
                'xmlns:tt="http://www.onvif.org/ver10/schema">'
                '<tds:Capabilities><tt:Device>'
                f'<tt:XAddr>http://{DEVICE_IP}/onvif/device_service</tt:XAddr>'
                "</tt:Device></tds:Capabilities></tds:GetCapabilitiesResponse>"
            )
        else:
            body = (
                '<tds:GetDeviceInformationResponse xmlns:tds="http://www.onvif.org/ver10/device/wsdl">'
                f"<tds:Manufacturer>MockLab</tds:Manufacturer><tds:Model>{DEVICE_MODEL}</tds:Model>"
                '<tds:FirmwareVersion>1.0.0</tds:FirmwareVersion>'
                f"<tds:SerialNumber>{DEVICE_MAC.replace(':', '')}</tds:SerialNumber>"
                f"<tds:HardwareId>{DEVICE_UUID}</tds:HardwareId>"
                "</tds:GetDeviceInformationResponse>"
            )
        self._send(soap_envelope(body))


def onvif_http():
    server = ThreadingHTTPServer(("0.0.0.0", 80), OnvifHandler)
    log("ONVIF device service listening on TCP 80")
    server.serve_forever()


def onvif_discovery():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("", 3702))
    membership = socket.inet_aton("239.255.255.250") + socket.inet_aton(DEVICE_IP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
    log("ONVIF WS-Discovery listening on 239.255.255.250:3702")
    while True:
        data, addr = sock.recvfrom(65535)
        text = data.decode("utf-8", errors="ignore")
        if "Probe" not in text:
            continue
        match = re.search(r"<(?:\w+:)?MessageID>(.*?)</(?:\w+:)?MessageID>", text)
        relates_to = match.group(1) if match else "urn:uuid:" + str(uuid.uuid4())
        message_id = "urn:uuid:" + str(uuid.uuid4())
        response = f'''<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
 xmlns:a="http://www.w3.org/2005/08/addressing"
 xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
 xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
 <s:Header>
  <a:MessageID>{message_id}</a:MessageID>
  <a:RelatesTo>{relates_to}</a:RelatesTo>
  <a:To s:mustUnderstand="1">http://www.w3.org/2005/08/addressing/anonymous</a:To>
  <a:Action s:mustUnderstand="1">http://schemas.xmlsoap.org/ws/2005/04/discovery/ProbeMatches</a:Action>
 </s:Header>
 <s:Body><d:ProbeMatches><d:ProbeMatch>
  <a:EndpointReference><a:Address>urn:uuid:{DEVICE_UUID}</a:Address></a:EndpointReference>
  <d:Types>dn:NetworkVideoTransmitter</d:Types>
  <d:Scopes>onvif://www.onvif.org/type/video_encoder onvif://www.onvif.org/name/{DEVICE_NAME}</d:Scopes>
  <d:XAddrs>http://{DEVICE_IP}/onvif/device_service</d:XAddrs>
  <d:MetadataVersion>1</d:MetadataVersion>
 </d:ProbeMatch></d:ProbeMatches></s:Body>
</s:Envelope>'''.encode()
        sock.sendto(response, addr)
        log(f"ONVIF ProbeMatch sent to {addr[0]}:{addr[1]}")


def main():
    workers = []
    if ENABLE_DH:
        workers.append(threading.Thread(target=dahua_discovery, daemon=True))
    if ENABLE_ONVIF:
        workers.extend(
            [
                threading.Thread(target=onvif_discovery, daemon=True),
                threading.Thread(target=onvif_http, daemon=True),
            ]
        )
    for worker in workers:
        worker.start()
    if not workers:
        raise SystemExit("no discovery protocol enabled")
    log(f"ready ip={DEVICE_IP} mac={DEVICE_MAC} model={DEVICE_MODEL}")
    workers[0].join()


if __name__ == "__main__":
    main()
