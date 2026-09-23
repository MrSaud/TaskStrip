# CloudKit schema — version 1

How Task Strips stores the board in iCloud, for the sync in Phase 5. Written before anything
is deployed, because in CloudKit's **Production** environment a schema can only grow: record
types and fields can be added, never renamed, retyped or removed. Everything here is meant to
last.

The code that implements this is `Sources/Core/Sync/CloudSchema.swift` (names) and
`CloudRecordCoding.swift` (model ⇄ record), tested in `CloudRecordCodingTests`.

## Where

| | |
|---|---|
| Container | `iCloud.com.saud.taskstrip` |
| Database | private (the user's own; nothing is shared or public) |
| Zone | `Board` — one custom zone for everything |

A custom zone is what CKSyncEngine needs to fetch only what changed, and one zone keeps every
change to the board in one ordered stream.

## Rules that apply to every record type

1. **Record name = the item's own id.** A strip's record is named by its UUID, a sketch's by its
   folder name. Two devices can therefore never create two records for the same item — the
   duplication that ended the Drive sync can't happen by construction.
2. **CloudKit field names are not Swift property names.** They're listed below and live in
   `CloudSchema`, so renaming a Swift property never touches the schema.
3. **`schemaVersion`** (Int64) on every record: the version of this document it was written
   under, currently 1. A device that reads a higher version than it knows keeps the fields it
   doesn't understand — it edits the record it received rather than building a fresh one — so an
   older device can never erase what a newer one added.
4. **User-written text is end-to-end encrypted** (`CKRecord.encryptedValues`): titles, notes,
   names, tags, contacts, links, log entries, reminder text, credential details. Only structural
   values stay plain: dates, flags, priority, order, counts, references, `schemaVersion`.
   Encrypted fields can't be queried, and nothing here needs to be — CKSyncEngine fetches by zone.
5. **Files are CKAssets**, encrypted by Apple at rest and end-to-end with Advanced Data
   Protection. Each file is its own record, so editing a strip doesn't re-upload its files.
6. **Passwords are never in CloudKit.** They're in iCloud Keychain (Phase 2), keyed by the
   credential's record name.
7. **No tombstone field.** Deleting an item deletes its record; CKSyncEngine delivers the
   deletion to the other devices. Children with a parent reference go with their parent.
8. **Merging** (Phase 5) is field by field against the last copy each device received from the
   server, so no per-field timestamps are stored: a field this device changed since that copy
   wins, every other field takes the server's value.

## Record types

`E` = encrypted, `—` = plain. Types are CloudKit's.

### `Strip`

| Field | Type | | From `TaskItem` |
|---|---|---|---|
| `title` | String | E | title |
| `notes` | String | E | notes |
| `notesRTL` | Int64 (0/1) | — | notesRtl |
| `priority` | String | — | priorityRaw (`URGENT` `HIGH` `NORMAL` `LOW`) |
| `dueAt` | Date | — | dueAt |
| `sortKey` | String | — | new in Phase 5: a fractional index, so two devices reordering at once don't renumber each other's strips |
| `done` | Int64 | — | isDone |
| `archived` | Int64 | — | isArchived |
| `progress` | Int64 | — | progress (0–100) |
| `completedAt` | Date | — | completedAt |
| `blockedBy` | String | — | blockedByID (a strip's record name; a plain string, not a reference, so a strip can arrive before its blocker) |
| `waitingOn` | String | E | waitingOnName |
| `waitingSince` | Date | — | waitingOnSince |
| `followUpDays` | Int64 | — | waitingOnFollowUpDays |
| `sketchID` | String | — | linkedSketchID |
| `tags` | [String] | E | tags |
| `contacts` | Bytes (JSON) | E | contacts |
| `links` | Bytes (JSON) | E | links |
| `log` | Bytes (JSON) | E | actionLog |
| `remindBefore` | Int64 | — | reminderMinutesBefore |
| `repeatDays` | Int64 | — | repeatIntervalDays |
| `createdAt` | Date | — | createdAt |
| `checklist` | Bytes (JSON) | E | added 2026-09-23: the strip's steps. When there are any they decide `progress`. |
| `deferUntil` | Date | — | added 2026-09-23: the day the strip comes back onto the board. |
| `sessions` | Bytes (JSON) | — | added 2026-09-23: stretches of time spent on the strip. Times rather than words, so not encrypted. |
| `tallies` | Bytes (JSON) | E | added 2026-09-23: the strip's running totals — hours, money, anything counted — with their entries and targets. Encrypted: what somebody called a total and what they spent is as much their business as the strip's own words. |
| `waitingOnChasedAt` | Date/Time | — | added 2026-09-23: when the person this strip waits on was last chased. The follow-up counts from here, so a chase buys another round of days. |
| `calendarEvent` | String | — | added 2026-09-23: the calendar event blocked out for the strip, by its external identifier so it means the same event on every device. |

### `Attachment` — a file on a strip

| Field | Type | | From `TaskAttachment` |
|---|---|---|---|
| `strip` | Reference → Strip, delete-self | — | the strip it belongs to |
| `kind` | String | — | kind (`image` `voiceNote` `document` `video`) |
| `name` | String | E | name |
| `addedAt` | Date | — | addedAt |
| `file` | Asset | | the file |

Record name = the attachment's UUID. Where the file sits on disk is each device's own business
and isn't synced.

### `Reminder`

| Field | Type | | From `Reminder` |
|---|---|---|---|
| `text` | String | E | text |
| `details` | String | E | details |
| `triggerAt` | Date | — | triggerAt |
| `leadMinutes` | Int64 | — | leadMinutesBefore |
| `repeatAmount` | Int64 | — | repeatAmount |
| `repeatUnit` | String | — | repeatUnitRaw (`DAILY` `WEEKLY` `MONTHLY` `YEARLY`) |
| `tag` | String | E | tag |
| `tagEmoji` | String | E | tagEmoji |
| `done` | Int64 | — | isDone |
| `createdAt` | Date | — | createdAt |
| `checklist` | Bytes (JSON) | E | added 2026-09-23: the strip's steps. When there are any they decide `progress`. |
| `deferUntil` | Date | — | added 2026-09-23: the day the strip comes back onto the board. |
| `sessions` | Bytes (JSON) | — | added 2026-09-23: stretches of time spent on the strip. Times rather than words, so not encrypted. |
| `tallies` | Bytes (JSON) | E | added 2026-09-23: the strip's running totals — hours, money, anything counted — with their entries and targets. Encrypted: what somebody called a total and what they spent is as much their business as the strip's own words. |
| `waitingOnChasedAt` | Date/Time | — | added 2026-09-23: when the person this strip waits on was last chased. The follow-up counts from here, so a chase buys another round of days. |
| `calendarEvent` | String | — | added 2026-09-23: the calendar event blocked out for the strip, by its external identifier so it means the same event on every device. |

### `Note` — a quick note

| Field | Type | | From `Note` |
|---|---|---|---|
| `text` | String | E | text |
| `createdAt` | Date | — | createdAt |
| `checklist` | Bytes (JSON) | E | added 2026-09-23: the strip's steps. When there are any they decide `progress`. |
| `deferUntil` | Date | — | added 2026-09-23: the day the strip comes back onto the board. |
| `sessions` | Bytes (JSON) | — | added 2026-09-23: stretches of time spent on the strip. Times rather than words, so not encrypted. |
| `tallies` | Bytes (JSON) | E | added 2026-09-23: the strip's running totals — hours, money, anything counted — with their entries and targets. Encrypted: what somebody called a total and what they spent is as much their business as the strip's own words. |
| `waitingOnChasedAt` | Date/Time | — | added 2026-09-23: when the person this strip waits on was last chased. The follow-up counts from here, so a chase buys another round of days. |
| `calendarEvent` | String | — | added 2026-09-23: the calendar event blocked out for the strip, by its external identifier so it means the same event on every device. |

Sync Notes aren't a type of their own: they're folded into Notes (decided 2026-09-22), and
Android's Sync Note text arrives as an ordinary note in Phase 6.

### `StorageFile` — the storage library

| Field | Type | | From `StorageItem` |
|---|---|---|---|
| `name` | String | E | name |
| `type` | String | — | typeRaw (`IMAGE` `VIDEO` `DOCUMENT`) |
| `mimeType` | String | — | mimeType |
| `size` | Int64 | — | sizeBytes |
| `tag` | String | E | tag |
| `tagEmoji` | String | E | tagEmoji |
| `createdAt` | Date | — | createdAt |
| `checklist` | Bytes (JSON) | E | added 2026-09-23: the strip's steps. When there are any they decide `progress`. |
| `deferUntil` | Date | — | added 2026-09-23: the day the strip comes back onto the board. |
| `sessions` | Bytes (JSON) | — | added 2026-09-23: stretches of time spent on the strip. Times rather than words, so not encrypted. |
| `tallies` | Bytes (JSON) | E | added 2026-09-23: the strip's running totals — hours, money, anything counted — with their entries and targets. Encrypted: what somebody called a total and what they spent is as much their business as the strip's own words. |
| `waitingOnChasedAt` | Date/Time | — | added 2026-09-23: when the person this strip waits on was last chased. The follow-up counts from here, so a chase buys another round of days. |
| `calendarEvent` | String | — | added 2026-09-23: the calendar event blocked out for the strip, by its external identifier so it means the same event on every device. |
| `file` | Asset | | the file |

### `Credential`

| Field | Type | | From `Credential` |
|---|---|---|---|
| `title` | String | E | title |
| `username` | String | E | username |
| `url` | String | E | url |
| `notes` | String | E | notes |
| `createdAt` | Date | — | createdAt |
| `checklist` | Bytes (JSON) | E | added 2026-09-23: the strip's steps. When there are any they decide `progress`. |
| `deferUntil` | Date | — | added 2026-09-23: the day the strip comes back onto the board. |
| `sessions` | Bytes (JSON) | — | added 2026-09-23: stretches of time spent on the strip. Times rather than words, so not encrypted. |
| `tallies` | Bytes (JSON) | E | added 2026-09-23: the strip's running totals — hours, money, anything counted — with their entries and targets. Encrypted: what somebody called a total and what they spent is as much their business as the strip's own words. |
| `waitingOnChasedAt` | Date/Time | — | added 2026-09-23: when the person this strip waits on was last chased. The follow-up counts from here, so a chase buys another round of days. |
| `calendarEvent` | String | — | added 2026-09-23: the calendar event blocked out for the strip, by its external identifier so it means the same event on every device. |

### `Sketch` and `SketchPage`

Sketches stay PNG pages (decided 2026-09-22).

| `Sketch` field | Type | | |
|---|---|---|---|
| `name` | String | E | the optional name |
| `createdAt` | Date | — | |
| `paper` | String | — | added 2026-09-23: which paper the note is drawn on (`clean`, `lined`, `grid`, `dots`, `legal`, `mint`, `sky`, `graph`). Never baked into the pages, so it can change at any time. A device that doesn't know the value shows plain paper. |

| `SketchPage` field | Type | | |
|---|---|---|---|
| `sketch` | Reference → Sketch, delete-self | — | |
| `number` | Int64 | — | page1.png is 1 |
| `image` | Asset | | the PNG |

Record names: the sketch's folder name, and `<folder>/page<n>` for a page.

## Limits to respect in Phase 5

- A record's non-asset fields must stay under 1 MB. The largest candidate is a strip's action
  log; one past a few hundred KB is trimmed oldest-first on the device, never silently cut
  server-side.
- A file too large for an asset stays on the device it was added on and is marked as not
  synced, rather than failing the whole batch.

## Changing this later

Production is add-only. A new field is added with a default that means "not set", and a
`schemaVersion` bump; old devices ignore it and preserve it. A field is never repurposed: a
changed meaning gets a new name.
