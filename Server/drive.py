import json
import uuid

import requests

DRIVE_UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3/files"
DRIVE_FILES_URL = "https://www.googleapis.com/drive/v3/files"


def upload_report_file(
    *,
    access_token: str,
    file_name: str,
    file_bytes: bytes,
    mime_type: str,
    folder_id: str,
    replace_file_id: str | None = None,
) -> dict:
    if replace_file_id:
        try:
            requests.delete(
                f"{DRIVE_FILES_URL}/{replace_file_id}",
                headers={"Authorization": f"Bearer {access_token}"},
                params={"supportsAllDrives": "true"},
                timeout=15,
            )
        except Exception:
            pass

    boundary = f"===============/{uuid.uuid4().hex}"
    metadata = {
        "name": file_name,
        "parents": [folder_id],
    }
    multipart_body = (
        f"--{boundary}\r\n"
        "Content-Type: application/json; charset=UTF-8\r\n\r\n"
        f"{json.dumps(metadata)}\r\n"
        f"--{boundary}\r\n"
        f"Content-Type: {mime_type}\r\n\r\n"
    ).encode("utf-8") + file_bytes + f"\r\n--{boundary}--\r\n".encode("utf-8")

    response = requests.post(
        f"{DRIVE_UPLOAD_URL}?uploadType=multipart&fields=id,name,webViewLink&supportsAllDrives=true",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": f"multipart/related; boundary={boundary}",
        },
        data=multipart_body,
        timeout=30,
    )

    if response.status_code not in {200, 201}:
        raise RuntimeError(response.text)

    return response.json()
