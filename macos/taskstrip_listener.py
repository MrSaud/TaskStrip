#!/usr/bin/env python3
"""
TaskStrip clipboard listener — receives snippets pushed from the Android app over the LAN and
puts them on this machine's clipboard.

This is the reference implementation of PROTOCOL.md. It exists so the wire format can be proven
with something runnable before any of it is rewritten as a Swift menu-bar app; keep the two in
step, and treat this file as the spec's executable half.

    pip3 install cryptography
    TASKSTRIP_PAIRING_CODE='your-code' ./taskstrip_listener.py

Bonjour advertising uses macOS's built-in `dns-sd`, so there is no dependency for it. On other
platforms advertising is skipped and the listener still works if you point the phone at this
host directly.
"""

import argparse
import base64
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.hashes import SHA256
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

SERVICE_TYPE = "_taskstrip._tcp"
DEFAULT_PORT = 47653
PROTOCOL_VERSION = 1

# Must match BackupCrypto.kt exactly, or the two ends silently stop understanding each other.
PBKDF2_ITERATIONS = 120_000
KEY_LENGTH_BYTES = 32
GCM_TAG_LENGTH_BYTES = 16

MAX_BODY_BYTES = 1 << 20          # 1 MiB: a clipboard snippet, not a file transfer
FRESHNESS_WINDOW_SECONDS = 300


def derive_key(pairing_code: str, salt: bytes) -> bytes:
    return PBKDF2HMAC(
        algorithm=SHA256(), length=KEY_LENGTH_BYTES, salt=salt, iterations=PBKDF2_ITERATIONS
    ).derive(pairing_code.encode("utf-8"))


def decrypt_envelope(envelope: dict, pairing_code: str):
    """Returns the plaintext string, or None if this wasn't sealed with our pairing code.

    Mirrors BackupCrypto.decrypt: any failure is None rather than an exception, because GCM's
    auth tag makes a wrong key reliably detectable and the caller only needs the one bit.
    """
    try:
        salt = base64.b64decode(envelope["salt"])
        iv = base64.b64decode(envelope["iv"])
        ciphertext = base64.b64decode(envelope["cipher"])
    except (KeyError, ValueError, TypeError):
        return None
    try:
        # Java appends GCM's tag to the ciphertext, which is also what AESGCM.decrypt expects.
        return AESGCM(derive_key(pairing_code, salt)).decrypt(iv, ciphertext, None).decode("utf-8")
    except Exception:
        return None


def encrypt_payload(plaintext: str, pairing_code: str) -> dict:
    """Only used by the test suite and by --self-test; the phone is the real sender."""
    salt = os.urandom(16)
    iv = os.urandom(12)
    ciphertext = AESGCM(derive_key(pairing_code, salt)).encrypt(iv, plaintext.encode("utf-8"), None)
    return {
        "salt": base64.b64encode(salt).decode(),
        "iv": base64.b64encode(iv).decode(),
        "cipher": base64.b64encode(ciphertext).decode(),
    }


def copy_to_clipboard(text: str) -> bool:
    """pbcopy on macOS, xclip/wl-copy if present elsewhere. False when there's nowhere to put it,
    so a headless run (CI, this repo's own tests) still exercises everything else."""
    if platform.system() == "Darwin":
        command = ["pbcopy"]
    elif shutil.which("wl-copy"):
        command = ["wl-copy"]
    elif shutil.which("xclip"):
        command = ["xclip", "-selection", "clipboard"]
    else:
        return False
    try:
        subprocess.run(command, input=text.encode("utf-8"), check=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


class ClipHandler(BaseHTTPRequestHandler):
    server_version = "TaskStripListener/1.0"
    pairing_code = ""
    received = None                # test hook: last accepted payload

    def _reply(self, status: int, body: dict):
        encoded = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if self.path != "/health":
            self._reply(404, {"ok": False})
            return
        self._reply(200, {"ok": True, "service": "taskstrip", "version": PROTOCOL_VERSION})

    def do_POST(self):
        if self.path != "/clip":
            self._reply(404, {"ok": False})
            return

        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY_BYTES:
            self._reply(413, {"ok": False, "error": "payload too large"})
            return
        try:
            envelope = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            self._reply(400, {"ok": False, "error": "malformed body"})
            return
        if not isinstance(envelope, dict):
            self._reply(400, {"ok": False, "error": "malformed body"})
            return

        plaintext = decrypt_envelope(envelope, type(self).pairing_code)
        if plaintext is None:
            self._reply(401, {"ok": False, "error": "decryption failed"})
            return
        try:
            payload = json.loads(plaintext)
            text = payload["text"]
            sent_at = int(payload["sentAt"])
        except (ValueError, KeyError, TypeError):
            self._reply(400, {"ok": False, "error": "malformed payload"})
            return

        if abs(time.time() - sent_at / 1000.0) > FRESHNESS_WINDOW_SECONDS:
            self._reply(408, {"ok": False, "error": "stale message"})
            return

        type(self).received = payload
        copied = copy_to_clipboard(text)
        label = payload.get("label") or "clip"
        print(f"[{time.strftime('%H:%M:%S')}] {label}: {len(text)} chars"
              f"{'' if copied else ' (no clipboard tool — not copied)'}", flush=True)
        self._reply(200, {"ok": True})

    def log_message(self, *args):
        pass                        # the prints above are the log we actually want


def advertise(port: int, name: str):
    """macOS ships dns-sd, so Bonjour costs no dependency. Returns the process to kill on exit,
    or None where advertising isn't available."""
    if not shutil.which("dns-sd"):
        print("dns-sd not found — skipping Bonjour; point the phone at this host directly.")
        return None
    process = subprocess.Popen(
        ["dns-sd", "-R", name, SERVICE_TYPE, "local", str(port)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    print(f"Advertising {name} on {SERVICE_TYPE} port {port}")
    return process


def main():
    parser = argparse.ArgumentParser(description="Receive TaskStrip clipboard snippets over the LAN.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--name", default=platform.node() or "TaskStrip")
    parser.add_argument("--no-advertise", action="store_true")
    args = parser.parse_args()

    pairing_code = os.environ.get("TASKSTRIP_PAIRING_CODE", "")
    if not pairing_code:
        # Refusing beats defaulting: an empty code would derive a key anyone could reproduce.
        sys.exit("Set TASKSTRIP_PAIRING_CODE to the same code entered in the app.")

    ClipHandler.pairing_code = pairing_code
    server = ThreadingHTTPServer(("0.0.0.0", args.port), ClipHandler)
    advertiser = None if args.no_advertise else advertise(args.port, args.name)
    print(f"Listening on port {args.port}. Ctrl-C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping.")
    finally:
        if advertiser:
            advertiser.terminate()
        server.server_close()


if __name__ == "__main__":
    main()
