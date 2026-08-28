# TaskStrip clipboard transport (v1)

Phone → desktop, over the local network. The **desktop listens**, the phone pushes: Android
kills long-running servers unless an app holds a foreground service with a permanent
notification, while a desktop menu-bar process can listen indefinitely for free.

## Discovery

The desktop advertises Bonjour/mDNS:

    service type : _taskstrip._tcp
    port         : 47653 (default, configurable)

Android resolves it with `NsdManager`. No IP addresses are ever typed in.

## Transport

Plain HTTP on the LAN. The body is encrypted, so TLS (and its self-signed-certificate misery)
buys nothing here.

### `GET /health`

Unauthenticated, carries no user data. Used to confirm a resolved service is really us.

    {"ok": true, "service": "taskstrip", "version": 1}

### `POST /clip`

Body is the encrypted envelope below. Responses:

| Status | Meaning |
|--------|---------|
| 200    | `{"ok": true}` — accepted, now on the desktop clipboard |
| 400    | malformed JSON, or missing envelope fields |
| 401    | decryption failed — wrong pairing code, or tampered payload |
| 408    | `sentAt` outside the freshness window (replay defence) |
| 413    | body over the size cap |

## Encryption

Deliberately identical to `BackupCrypto.kt`, so the Android side reuses code that already
ships rather than growing a second crypto path:

- PBKDF2WithHmacSHA256, **120,000** iterations, 256-bit key
- Key derived from the **pairing code** — a shared secret both ends know
- AES/GCM/NoPadding, 128-bit auth tag
- Fresh random 16-byte salt and 12-byte IV per message
- All three fields Base64, **no wrapping** (`Base64.NO_WRAP` on Android)

### Envelope (the POST body)

    {"salt": "<b64>", "iv": "<b64>", "cipher": "<b64>"}

### Plaintext inside the envelope

    {
      "text":   "the snippet",
      "label":  "optional short name",
      "sentAt": 1756150000000,          // epoch millis
      "source": "taskstrip-android"
    }

GCM's auth tag means a wrong pairing code fails cleanly as "couldn't decrypt" rather than
yielding garbage — the same property `BackupCrypto.decrypt` already relies on.

## Replay defence

`sentAt` must be within **±300 s** of the desktop's clock, or the message is rejected 408.
Cheap, and it stops a captured payload being re-sent later. Clock skew beyond five minutes
between your own phone and laptop is the real problem to fix if this ever trips.

## Deliberately not in v1

- **Desktop → phone.** Needs the phone to listen; a later addition.
- **Files.** Text only. Documents keep going through the storage library.
- **Pairing handshake.** The code is entered by hand on both ends. A QR flow is the obvious
  next step and changes nothing above.
