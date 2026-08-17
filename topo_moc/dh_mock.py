import socket
import json

def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('0.0.0.0', 37810))
    print("[DH Mock] Listening on UDP 37810...")

    while True:
        data, addr = sock.recvfrom(2048)
        if b"DHDiscover" in data:
            resp = {
                "id": 1,
                "result": True,
                "params": {
                    "deviceInfo": {
                        "mac": "00:11:22:33:44:01",
                        "deviceType": "DH-IPC-HDW2431T",
                        "version": "V2.800.0000000.0.R"
                    }
                }
            }
            sock.sendto(json.dumps(resp).encode('utf-8'), addr)
            print(f"[DH Mock] Sent response to {addr}")

if __name__ == "__main__":
    main()
