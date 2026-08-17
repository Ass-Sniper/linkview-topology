#!/usr/bin/env python3
"""Net-SNMP pass_persist backend for BRIDGE-MIB dot1dTpFdbTable."""

import argparse
import bisect
import json
import sys
from pathlib import Path


ENTRY_BASE = ".1.3.6.1.2.1.17.4.3.1"
ADDR_BASE = ENTRY_BASE + ".1"
PORT_BASE = ENTRY_BASE + ".2"


def normalize_oid(value):
    value = value.strip()
    return value if value.startswith(".") else "." + value


def oid_key(value):
    return tuple(int(part) for part in normalize_oid(value).lstrip(".").split("."))


def parse_mac(value):
    parts = value.replace("-", ":").split(":")
    if len(parts) != 6:
        raise ValueError(f"invalid MAC address: {value}")
    octets = tuple(int(part, 16) for part in parts)
    if any(octet < 0 or octet > 255 for octet in octets):
        raise ValueError(f"invalid MAC address: {value}")
    return octets


def load_objects(path):
    document = json.loads(Path(path).read_text(encoding="utf-8"))
    if document.get("schema_version") != 1:
        raise ValueError("unsupported fdb.json schema_version")

    objects = {}
    seen_macs = set()
    for entry in document.get("entries", []):
        octets = parse_mac(entry["mac"])
        if octets in seen_macs:
            raise ValueError(f"duplicate MAC address: {entry['mac']}")
        seen_macs.add(octets)
        port = int(entry["port"])
        if port <= 0:
            raise ValueError(f"invalid bridge port for {entry['mac']}: {port}")
        suffix = "." + ".".join(str(octet) for octet in octets)
        mac_text = " ".join(f"{octet:02X}" for octet in octets)
        objects[ADDR_BASE + suffix] = ("string", mac_text)
        objects[PORT_BASE + suffix] = ("integer", str(port))

    if not objects:
        raise ValueError("fdb.json contains no entries")
    return objects


def emit_object(oid, objects):
    kind, value = objects[oid]
    sys.stdout.write(f"{oid}\n{kind}\n{value}\n")
    sys.stdout.flush()


def emit_none():
    sys.stdout.write("NONE\n")
    sys.stdout.flush()


def serve(objects):
    ordered = sorted(objects, key=oid_key)
    ordered_keys = [oid_key(oid) for oid in ordered]
    while True:
        command = sys.stdin.readline()
        if not command:
            return
        command = command.strip()

        if command == "PING":
            sys.stdout.write("PONG\n")
            sys.stdout.flush()
            continue

        if command in ("get", "getnext"):
            requested_line = sys.stdin.readline()
            if not requested_line:
                return
            requested = normalize_oid(requested_line)
            if command == "get":
                if requested in objects:
                    emit_object(requested, objects)
                else:
                    emit_none()
                continue

            position = bisect.bisect(ordered_keys, oid_key(requested))
            if position < len(ordered):
                emit_object(ordered[position], objects)
            else:
                emit_none()
            continue

        if command == "set":
            # Consume the complete SET request to keep the stream synchronized.
            for _ in range(3):
                if not sys.stdin.readline():
                    return
            emit_none()
            continue

        emit_none()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True)
    args = parser.parse_args()
    try:
        objects = load_objects(args.data)
        serve(objects)
    except Exception as exc:
        print(f"fdb_agent fatal: {exc}", file=sys.stderr, flush=True)
        raise


if __name__ == "__main__":
    main()
