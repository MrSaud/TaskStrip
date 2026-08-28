# TaskStrip desktop listener

Receives clipboard snippets pushed from the Android app over your local network and puts them on
this machine's clipboard.

This Python listener is the **reference implementation** of [PROTOCOL.md](PROTOCOL.md), not a
throwaway. It exists so the wire format could be proven with something runnable before being
rewritten as a Swift menu-bar app — and it stays here afterwards as the spec's executable half
and the thing to test against when the two ends disagree.

## Run it

    pip3 install cryptography
    export TASKSTRIP_PAIRING_CODE='pick-something-long'
    ./taskstrip_listener.py

The same pairing code goes into the app. It never travels over the network — both ends derive
the same AES key from it independently.

On macOS the listener advertises itself over Bonjour using the built-in `dns-sd`, so the phone
finds it with no IP address typed in. macOS will ask once for local-network permission.

Options: `--port` (default 47653), `--name`, `--no-advertise`.

## Check it works before involving the phone

    curl localhost:47653/health
    → {"ok": true, "service": "taskstrip", "version": 1}

## Tests

    python3 test_listener.py

Ten tests over a real socket: round trip with unicode, a 200 KB snippet, wrong pairing code,
tampered ciphertext, replayed and future timestamps, malformed bodies, unknown paths.

## Cross-language check

The encryption mirrors `BackupCrypto.kt` exactly — PBKDF2-HMAC-SHA256 at 120,000 iterations,
AES-256-GCM, 128-bit tag, unwrapped Base64. If those drift apart the two ends stop understanding
each other, with nothing but a 401 to say why.

`fixtures/crypto_vector.json` pins it down: a Python-generated envelope that
`BackupCrypto.decrypt` must turn back into the stored plaintext. Run `verify_vector.py` for the
other direction. Worth doing once on a machine that has both toolchains — see that file's
docstring.

## Status

Working and tested. What it does **not** have yet is anything to talk to: the Android side that
pushes to it is the next piece. Until then `test_listener.py` and `curl` are the only clients.

Desktop → phone is deliberately out of scope for v1 (it needs the phone to listen). Files are
too — text only; documents keep going through the storage library.
