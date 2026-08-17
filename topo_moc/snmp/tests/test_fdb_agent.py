#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


AGENT = Path(__file__).resolve().parents[1] / "backends" / "pass_persist" / "fdb_agent.py"


class FdbAgentProtocolTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.data = Path(self.tempdir.name) / "fdb.json"
        self.data.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "entries": [
                        {"mac": "00:11:22:33:44:01", "port": 5},
                        {"mac": "00:11:22:33:44:03", "port": 6},
                    ],
                }
            ),
            encoding="utf-8",
        )
        self.proc = subprocess.Popen(
            [sys.executable, "-u", str(AGENT), "--data", str(self.data)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )

    def tearDown(self):
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            self.proc.terminate()
            self.proc.wait(timeout=3)
        self.proc.stdout.close()
        self.tempdir.cleanup()

    def request(self, *lines, count=1):
        self.proc.stdin.write("\n".join(lines) + "\n")
        self.proc.stdin.flush()
        return [self.proc.stdout.readline().rstrip("\n") for _ in range(count)]

    def test_ping(self):
        self.assertEqual(self.request("PING"), ["PONG"])

    def test_get_and_getnext_order(self):
        first = ".1.3.6.1.2.1.17.4.3.1.1.0.17.34.51.68.1"
        second = ".1.3.6.1.2.1.17.4.3.1.1.0.17.34.51.68.3"
        self.assertEqual(self.request("get", first, count=3), [first, "string", "00 11 22 33 44 01"])
        self.assertEqual(self.request("getnext", first, count=3)[0], second)
        port_first = self.request("getnext", second, count=3)
        self.assertEqual(port_first[0], ".1.3.6.1.2.1.17.4.3.1.2.0.17.34.51.68.1")
        self.assertEqual(port_first[1:], ["integer", "5"])

    def test_unknown_oid(self):
        self.assertEqual(self.request("get", ".1.3.6.1.2.1.17.4.3.1.99"), ["NONE"])


if __name__ == "__main__":
    unittest.main()
