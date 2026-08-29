#!/usr/bin/env python3
"""Regenerates the fixture archives BackupArchiveTests reads.

Two of them. android_backup.zip is an ordinary backup. android_backup_zip64.zip holds the same
bytes but describes them the way a zip past 4 GB has to — every size and offset in the central
directory replaced by the 0xFFFFFFFF sentinel with the real values in a zip64 extra field, and a
zip64 end record behind a locator. That path matters because a backup with videos in it will take
it, and it can be exercised here without producing four gigabytes of fixture.


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


def streamed_entry(name, payload, offset, zip64=False):
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

    if zip64:
        # Sizes and offset move into the extra field, exactly as they must past 4 GB.
        extra = struct.pack("<HHQQQ", 0x0001, 24, len(payload), len(compressed), offset)
        central = struct.pack(
            "<IHHHHHHIIIHHHHHII",
            0x02014B50, 45, 45, flags, 8, DOS_TIME, DOS_DATE,
            crc, 0xFFFFFFFF, 0xFFFFFFFF,
            len(name), len(extra), 0, 0, 0, 0, 0xFFFFFFFF,
        ) + name + extra
    else:
        central = struct.pack(
            "<IHHHHHHIIIHHHHHII",
            0x02014B50, 20, 20, flags, 8, DOS_TIME, DOS_DATE,
            crc, len(compressed), len(payload),
            len(name), 0, 0, 0, 0, 0, offset,
        ) + name
    return local, central


def build_zip(entries, zip64=False):
    body, directory, offset = b"", b"", 0
    for name, payload in entries:
        local, central = streamed_entry(name, payload, offset, zip64=zip64)
        body += local
        directory += central
        offset += len(local)

    if not zip64:
        eocd = struct.pack(
            "<IHHHHIIH", 0x06054B50, 0, 0, len(entries), len(entries), len(directory), len(body), 0
        )
        return body + directory + eocd

    zip64_end = struct.pack(
        "<IQHHIIQQQQ",
        0x06064B50, 44, 45, 45, 0, 0,
        len(entries), len(entries), len(directory), len(body),
    )
    locator = struct.pack("<IIQI", 0x07064B50, 0, len(body) + len(directory), 1)
    eocd = struct.pack(
        "<IHHHHIIH", 0x06054B50, 0, 0, 0xFFFF, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0
    )
    return body + directory + zip64_end + locator + eocd


def main():
    manifest_bytes = json.dumps(MANIFEST, ensure_ascii=False).encode("utf-8")
    # Two of the three files the manifest references are actually in the archive. The third,
    # documents/checklist.pdf, is deliberately absent: a real backup can name a file whose bytes
    # never made it in, and the import has to cope rather than trust the manifest.
    entries = [
        (MANIFEST_NAME, manifest_bytes),
        (b"media/images/passport.jpg", b"\xff\xd8\xff\xe0 not a real jpeg " * 64),
        (b"media/images/form.jpg", b"\xff\xd8\xff\xe0 also not a jpeg " * 32),
    ]

    for filename, zip64 in (("android_backup.zip", False), ("android_backup_zip64.zip", True)):
        blob = build_zip(entries, zip64=zip64)
        with open(filename, "wb") as out:
            out.write(blob)
        print("wrote {} ({} bytes)".format(filename, len(blob)))


if __name__ == "__main__":
    main()
