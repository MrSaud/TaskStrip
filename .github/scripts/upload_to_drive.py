#!/usr/bin/env python3
"""Put a build in the TaskStripBackups folder the two apps already share.

Mirrors DriveApi.kt and DriveClient.swift: same folder name, same ensure-then-create, same
multipart upload. Nothing here is clever; it exists so a build can reach the phone without going
through GitHub's artifact page on a small screen.

Needs DRIVE_CLIENT_ID and DRIVE_REFRESH_TOKEN in the environment. The client is the app's own
OAuth client, which is an installed/desktop client and therefore has no secret — a refresh token
is enough. Its drive.file scope means this can only see files the project's apps created.
"""

import json
import os
import ssl
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

FOLDER_NAME = "TaskStripBackups"
FOLDER_MIME = "application/vnd.google-apps.folder"
BASE = "https://www.googleapis.com/drive/v3"
UPLOAD_BASE = "https://www.googleapis.com/upload/drive/v3"


def request(url, *, method="GET", headers=None, body=None):
    req = urllib.request.Request(url, data=body, method=method)
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    with urllib.request.urlopen(req, context=ssl.create_default_context()) as response:
        return json.loads(response.read().decode() or "{}")


def access_token(client_id, refresh_token):
    body = urllib.parse.urlencode(
        {
            "client_id": client_id,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        }
    ).encode()
    reply = request(
        "https://oauth2.googleapis.com/token",
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        body=body,
    )
    token = reply.get("access_token")
    if not token:
        raise SystemExit("Drive refused the refresh token. Has it been revoked?")
    return token


def ensure_folder(token):
    auth = {"Authorization": f"Bearer {token}"}
    query = urllib.parse.quote(
        f"mimeType='{FOLDER_MIME}' and name='{FOLDER_NAME}' and trashed=false"
    )
    found = request(f"{BASE}/files?q={query}&spaces=drive&fields=files(id,name)", headers=auth)
    files = found.get("files") or []
    if files:
        return files[0]["id"]

    created = request(
        f"{BASE}/files?fields=id",
        method="POST",
        headers={**auth, "Content-Type": "application/json; charset=UTF-8"},
        body=json.dumps({"name": FOLDER_NAME, "mimeType": FOLDER_MIME}).encode(),
    )
    return created["id"]


def upload(token, folder_id, path, name):
    boundary = "taskstrip-ci-boundary"
    metadata = json.dumps({"name": name, "parents": [folder_id]}).encode()
    with open(path, "rb") as handle:
        payload = handle.read()

    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            b"Content-Type: application/json; charset=UTF-8\r\n\r\n",
            metadata,
            f"\r\n--{boundary}\r\n".encode(),
            b"Content-Type: application/vnd.android.package-archive\r\n\r\n",
            payload,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    return request(
        f"{UPLOAD_BASE}/files?uploadType=multipart&fields=id,name",
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": f"multipart/related; boundary={boundary}",
        },
        body=body,
    )


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: upload_to_drive.py <file>")
    path = sys.argv[1]
    if not os.path.exists(path):
        raise SystemExit(f"nothing to upload at {path}")

    client_id = os.environ["DRIVE_CLIENT_ID"]
    refresh_token = os.environ["DRIVE_REFRESH_TOKEN"]

    # Named by date and commit so successive builds sit beside each other rather than replacing
    # one another — on a phone, "which one is this?" is a question you can't answer from an icon.
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
    sha = (os.environ.get("GITHUB_SHA") or "local")[:7]
    name = f"TaskStrip-{stamp}-{sha}.apk"

    token = access_token(client_id, refresh_token)
    folder_id = ensure_folder(token)
    result = upload(token, folder_id, path, name)
    print(f"Uploaded {result.get('name')} to {FOLDER_NAME} (id {result.get('id')})")


if __name__ == "__main__":
    main()
