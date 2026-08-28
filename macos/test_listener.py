#!/usr/bin/env python3
"""Exercises the listener end to end over a real socket: correct payloads, wrong pairing code,
tampering, replay, and malformed input. Run with `python3 test_listener.py`."""

import json
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

from taskstrip_listener import ClipHandler, encrypt_payload

PAIRING_CODE = "correct-horse-battery-staple"


def post(url, body):
    request = urllib.request.Request(
        url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(request) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


class ListenerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        ClipHandler.pairing_code = PAIRING_CODE
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), ClipHandler)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def envelope(self, text, label="", sent_at=None, code=PAIRING_CODE):
        payload = {
            "text": text,
            "label": label,
            "sentAt": sent_at if sent_at is not None else int(time.time() * 1000),
            "source": "taskstrip-android",
        }
        return encrypt_payload(json.dumps(payload), code)

    def test_health_needs_no_pairing_code(self):
        with urllib.request.urlopen(f"{self.base}/health") as response:
            self.assertEqual(200, response.status)
            self.assertEqual({"ok": True, "service": "taskstrip", "version": 1},
                             json.loads(response.read()))

    def test_round_trip_delivers_exact_text(self):
        ClipHandler.received = None
        text = "ssh -i ~/.ssh/id_ed25519 saud@10.0.0.4   # unicode: café 🧾 مرحبا"
        status, body = post(f"{self.base}/clip", self.envelope(text, label="server"))
        self.assertEqual(200, status)
        self.assertTrue(body["ok"])
        self.assertEqual(text, ClipHandler.received["text"])
        self.assertEqual("server", ClipHandler.received["label"])

    def test_large_snippet_within_cap(self):
        text = "x" * 200_000
        status, _ = post(f"{self.base}/clip", self.envelope(text))
        self.assertEqual(200, status)
        self.assertEqual(text, ClipHandler.received["text"])

    def test_wrong_pairing_code_is_rejected(self):
        status, body = post(f"{self.base}/clip", self.envelope("secret", code="wrong-code"))
        self.assertEqual(401, status)
        self.assertFalse(body["ok"])

    def test_tampered_ciphertext_is_rejected(self):
        envelope = self.envelope("secret")
        raw = bytearray(__import__("base64").b64decode(envelope["cipher"]))
        raw[0] ^= 0xFF                                  # flip a bit; GCM's tag must notice
        envelope["cipher"] = __import__("base64").b64encode(bytes(raw)).decode()
        status, _ = post(f"{self.base}/clip", envelope)
        self.assertEqual(401, status)

    def test_replayed_old_message_is_rejected(self):
        stale = int((time.time() - 600) * 1000)
        status, body = post(f"{self.base}/clip", self.envelope("old", sent_at=stale))
        self.assertEqual(408, status)
        self.assertEqual("stale message", body["error"])

    def test_future_timestamp_is_rejected(self):
        ahead = int((time.time() + 600) * 1000)
        status, _ = post(f"{self.base}/clip", self.envelope("early", sent_at=ahead))
        self.assertEqual(408, status)

    def test_malformed_body_is_rejected(self):
        request = urllib.request.Request(f"{self.base}/clip", data=b"not json at all")
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(request)
        self.assertEqual(400, caught.exception.code)

    def test_envelope_missing_fields_is_rejected(self):
        status, _ = post(f"{self.base}/clip", {"salt": "AAAA"})
        self.assertEqual(401, status)

    def test_unknown_path_is_404(self):
        status, _ = post(f"{self.base}/nope", self.envelope("x"))
        self.assertEqual(404, status)


if __name__ == "__main__":
    unittest.main(verbosity=2)
