#!/usr/bin/env python3
"""Regenerates android_backup.zip, the fixture BackupArchiveTests reads.

Hand-rolls the zip rather than using zipfile because the point of the fixture is to match what
Java's ZipOutputStream actually emits from BackupHelper.createBackupZip: entries deflated with
general purpose bit 3 set, which leaves the sizes as 0 in the local header and writes them to a
trailing data descriptor instead. Python's zipfile writes real sizes into the local header, so a
zipfile-made fixture would never exercise the path the Android backups take.

Run from this directory:  python3 make_fixture.py
"""

import json
import struct
import zlib

MANIFEST_NAME = b"backup.json"
MEDIA_NAME = b"media/images/passport.jpg"
# Fixed so regenerating the fixture produces an identical file.
DOS_TIME, DOS_DATE = 0x9C00, 0x5919

MANIFEST = {
    "version": 1,
    "tasks": [
        {
            "title": "Renew passport",
            "route": "",
            "notes": "تجديد جواز السفر",
            "notesRtl": True,
            "priority": "URGENT",
            "dueAt": 1789000000000,
            "orderIndex": 2,
            "isDone": False,
            "isArchived": False,
            "progress": 40,
            "images": ["images/passport.jpg", "images/form.jpg"],
            "voiceNotes": [],
            "documents": ["documents/checklist.pdf"],
            "videos": [],
            "reminderMinutesBefore": 60,
            "repeatIntervalDays": None,
            "contacts": [{"name": "Consulate", "email": "visa@example.com", "phone": "+966500000000"}],
            "tags": ["admin", "travel"],
            "completedAt": None,
            "blockedByIndex": None,
            "waitingOnName": "",
            "waitingOnSince": None,
            "waitingOnFollowUpDays": None,
            "linkedSketchId": None,
            "actionLog": [
                {"text": "Booked appointment", "timestamp": 1787000000000},
                {"text": "Paid fee", "timestamp": 1787600000000},
            ],
            "links": [{"url": "https://example.com/renew", "label": "Renewal portal"}],
            "createdAt": 1786000000000,
        },
        {
            "title": "Book flights",
            "route": "",
            "notes": "",
            "notesRtl": False,
            "priority": "HIGH",
            "dueAt": None,
            "orderIndex": 0,
            "isDone": False,
            "isArchived": False,
            "progress": 0,
            "images": [],
            "voiceNotes": [],
            "documents": [],
            "videos": [],
            "reminderMinutesBefore": None,
            "repeatIntervalDays": None,
            "contacts": [],
            "tags": ["travel"],
            "completedAt": None,
            # Blocked by "Renew passport" — index 0 in this array, not an id.
            "blockedByIndex": 0,
            "waitingOnName": "Travel desk",
            "waitingOnSince": 1787200000000,
            "waitingOnFollowUpDays": 3,
            "linkedSketchId": None,
            "actionLog": [],
            "links": [],
            "createdAt": 1786100000000,
        },
        {
            "title": "File expenses",
            "route": "",
            "notes": "",
            "notesRtl": False,
            "priority": "LOW",
            "dueAt": None,
            "orderIndex": 1,
            "isDone": True,
            "isArchived": True,
            "progress": 100,
            "images": [],
            "voiceNotes": [],
            "documents": [],
            "videos": [],
            "reminderMinutesBefore": None,
            "repeatIntervalDays": None,
            "contacts": [],
            "tags": [],
            "completedAt": 1787900000000,
            "blockedByIndex": None,
            "waitingOnName": "",
            "waitingOnSince": None,
            "waitingOnFollowUpDays": None,
            "linkedSketchId": None,
            "actionLog": [],
            "links": [],
            "createdAt": 1786200000000,
        },
    ],
    "credentials": [],
    "notes": [{"title": "Packing list", "body": "socks"}, {"title": "Ideas", "body": ""}],
    "reminders": [{"label": "Standup", "at": 1788000000000}],
    "storageItems": [
        {"path": "media/images/passport.jpg", "tags": ["travel"]},
        {"path": "media/images/form.jpg", "tags": []},
        {"path": "documents/checklist.pdf", "tags": []},
    ],
}


def streamed_entry(name, payload, offset):
    """One deflated entry written the way Java's ZipOutputStream writes it."""
    compressor = zlib.compressobj(-1, zlib.DEFLATED, -zlib.MAX_WBITS)
    compressed = compressor.compress(payload) + compressor.flush()
    crc = zlib.crc32(payload) & 0xFFFFFFFF
    flags = 0x8  # bit 3: sizes live in the data descriptor, not this header

    local = struct.pack(
        "<IHHHHHIIIHH",
        0x04034B50, 20, flags, 8, DOS_TIME, DOS_DATE,
        0, 0, 0,  # crc + both sizes unknown at header-write time
        len(name), 0,
    ) + name + compressed + struct.pack("<IIII", 0x08074B50, crc, len(compressed), len(payload))

    central = struct.pack(
        "<IHHHHHHIIIHHHHHII",
        0x02014B50, 20, 20, flags, 8, DOS_TIME, DOS_DATE,
        crc, len(compressed), len(payload),
        len(name), 0, 0, 0, 0, 0, offset,
    ) + name
    return local, central


def main():
    manifest_bytes = json.dumps(MANIFEST, ensure_ascii=False).encode("utf-8")
    # A second entry after the manifest, so the test proves the reader stops at the end of the
    # deflate stream instead of running on into whatever follows.
    entries = [(MANIFEST_NAME, manifest_bytes), (MEDIA_NAME, b"\xff\xd8\xff\xe0 not a real jpeg " * 64)]

    body, directory, offset = b"", b"", 0
    for name, payload in entries:
        local, central = streamed_entry(name, payload, offset)
        body += local
        directory += central
        offset += len(local)

    eocd = struct.pack(
        "<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries), len(directory), len(body), 0
    )
    with open("android_backup.zip", "wb") as out:
        out.write(body + directory + eocd)
    print("wrote android_backup.zip ({} bytes)".format(len(body + directory + eocd)))


if __name__ == "__main__":
    main()
