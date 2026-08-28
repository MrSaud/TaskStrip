#!/usr/bin/env python3
"""Closes the cross-language loop that can only be closed on a machine with both toolchains.

  python3 verify_vector.py                    # check the stored vector round-trips in Python
  python3 verify_vector.py kotlin_out.json    # check an envelope produced by BackupCrypto

For the second form, have the Android side encrypt any JSON payload with the pairing code below
and write {"salt":..,"iv":..,"cipher":..} to a file. If this prints the plaintext back, Kotlin and
Python agree and the transport is safe to build on.
"""
import json
import sys

from taskstrip_listener import decrypt_envelope

vector = json.load(open("fixtures/crypto_vector.json"))
code = vector["pairingCode"]

if len(sys.argv) > 1:
    envelope = json.load(open(sys.argv[1]))
    plaintext = decrypt_envelope(envelope, code)
    if plaintext is None:
        sys.exit("FAIL — could not decrypt. The two ends disagree on the crypto parameters.")
    print("OK — decrypted Kotlin's envelope:\n" + plaintext)
else:
    plaintext = decrypt_envelope(vector["envelope"], code)
    if plaintext != vector["expectedPlaintext"]:
        sys.exit("FAIL — stored vector did not round-trip.")
    print("OK — stored vector round-trips in Python.")
    print("Now run the Kotlin half; see this file's docstring.")
