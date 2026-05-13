import io
import json
import logging
import os
import traceback
import uuid

import requests

logger = logging.getLogger("event-booking.drive")

DRIVE_UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3/files"
DRIVE_FILES_URL = "https://www.googleapis.com/drive/v3/files"

_SA_SCOPES = ["https://www.googleapis.com/auth/drive"]


class _SAQuotaError(RuntimeError):
    """Raised when the SA upload is blocked by personal-Drive storage quota.

    The caller should skip the full traceback log and go straight to the
    user-OAuth fallback path.
    """


# ---------------------------------------------------------------------------
# Service-account helpers
# ---------------------------------------------------------------------------

def _get_sa_credentials():
    """Load service account credentials from GOOGLE_APPLICATION_CREDENTIALS.

    Returns a Credentials object, or None if not configured / invalid.
    Never raises — all failures are logged and suppressed so the user-OAuth
    fallback path can still be attempted.
    """
    sa_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if not sa_path:
        logger.warning("drive: GOOGLE_APPLICATION_CREDENTIALS is not set; service account unavailable")
        return None
    if not os.path.isfile(sa_path):
        logger.error("drive: service account file not found at path: %s", sa_path)
        return None
    try:
        from google.oauth2 import service_account  # noqa: PLC0415
        creds = service_account.Credentials.from_service_account_file(sa_path, scopes=_SA_SCOPES)
        logger.info("drive: service account credentials loaded from %s", sa_path)
        return creds
    except Exception:
        logger.error(
            "drive: failed to load service account credentials from %s:\n%s",
            sa_path,
            traceback.format_exc(),
        )
        return None


def _upload_with_service_account(
    *,
    file_name: str,
    file_bytes: bytes,
    mime_type: str,
    folder_id: str | None = None,
    replace_file_id: str | None = None,
) -> dict:
    """Upload (or replace) a Drive file using service account credentials.

    Raises RuntimeError if credentials are unavailable or upload fails.
    """
    creds = _get_sa_credentials()
    if creds is None:
        raise RuntimeError("Service account credentials are not configured or could not be loaded")

    logger.info(
        "drive[sa]: uploading file_name=%r mime=%r folder_id=%r replace=%r size=%d bytes",
        file_name, mime_type, folder_id, replace_file_id, len(file_bytes),
    )

    try:
        from googleapiclient.discovery import build          # noqa: PLC0415
        from googleapiclient.http import MediaIoBaseUpload   # noqa: PLC0415
    except ImportError:
        logger.error("drive[sa]: google-api-python-client is not installed")
        raise RuntimeError("google-api-python-client package missing")

    try:
        service = build("drive", "v3", credentials=creds, cache_discovery=False)
    except Exception:
        logger.error("drive[sa]: failed to build Drive service:\n%s", traceback.format_exc())
        raise RuntimeError("Failed to initialise Google Drive service with service account")

    # Best-effort delete of the old file before replacing
    if replace_file_id:
        try:
            service.files().delete(
                fileId=replace_file_id,
                supportsAllDrives=True,
            ).execute()
            logger.info("drive[sa]: deleted previous file id=%s", replace_file_id)
        except Exception:
            logger.warning(
                "drive[sa]: could not delete previous file %s (non-fatal):\n%s",
                replace_file_id,
                traceback.format_exc(),
            )

    file_metadata: dict = {"name": file_name}
    if folder_id:
        file_metadata["parents"] = [folder_id]

    media = MediaIoBaseUpload(io.BytesIO(file_bytes), mimetype=mime_type, resumable=False)

    try:
        result = (
            service.files()
            .create(
                body=file_metadata,
                media_body=media,
                fields="id,name,webViewLink",
                supportsAllDrives=True,
            )
            .execute()
        )
    except Exception as exc:
        exc_str = str(exc)
        # "storageQuotaExceeded" means the target folder is a personal My Drive —
        # service accounts have no storage quota there.  Raise a recognisable
        # subclass so the caller can fall through to user-OAuth without logging
        # a misleading full traceback.
        if "storageQuotaExceeded" in exc_str or "storage quota" in exc_str.lower():
            logger.warning(
                "drive[sa]: target folder is a personal My Drive — "
                "service accounts have no storage quota there; falling back to user OAuth"
            )
            raise _SAQuotaError("Service account has no storage quota on personal My Drive") from exc
        logger.error("drive[sa]: file upload failed:\n%s", traceback.format_exc())
        raise RuntimeError(f"Drive upload via service account failed: {traceback.format_exc()}") from exc

    if not result or not result.get("id"):
        logger.error("drive[sa]: upload returned unexpected response: %r", result)
        raise RuntimeError("Drive upload via service account returned an empty or invalid response")

    logger.info(
        "drive[sa]: upload succeeded id=%s webViewLink=%s",
        result.get("id"),
        result.get("webViewLink"),
    )
    return result


# ---------------------------------------------------------------------------
# Public upload helper (service account → user-token fallback)
# ---------------------------------------------------------------------------

def upload_report_file(
    *,
    access_token: str,
    file_name: str,
    file_bytes: bytes,
    mime_type: str,
    folder_id: str | None = None,
    replace_file_id: str | None = None,
    allow_root_fallback: bool = False,
) -> dict:
    # --- Defensive pre-flight checks ---
    if not file_bytes:
        raise RuntimeError("upload_report_file: file_bytes is empty — nothing to upload")
    if not file_name:
        raise RuntimeError("upload_report_file: file_name is missing")
    if not mime_type:
        raise RuntimeError("upload_report_file: mime_type is missing")

    logger.info(
        "drive: upload_report_file called  file_name=%r  folder_id=%r  size=%d bytes  replace=%r",
        file_name, folder_id, len(file_bytes), replace_file_id,
    )

    # --- Primary path: service account ---
    sa_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    if sa_path and os.path.isfile(sa_path):
        try:
            return _upload_with_service_account(
                file_name=file_name,
                file_bytes=file_bytes,
                mime_type=mime_type,
                folder_id=folder_id,
                replace_file_id=replace_file_id,
            )
        except _SAQuotaError:
            # Personal My Drive folder — silently fall through to user-OAuth path.
            pass
        except Exception:
            logger.error(
                "drive: service account upload failed — falling back to user OAuth token:\n%s",
                traceback.format_exc(),
            )
            # Fall through to user-token path below
    else:
        logger.warning(
            "drive: no valid GOOGLE_APPLICATION_CREDENTIALS file found (%r); using user OAuth token",
            sa_path,
        )

    # --- Fallback path: user OAuth access token ---
    if not access_token:
        raise RuntimeError(
            "Drive upload failed: service account unavailable and no user OAuth token provided"
        )

    logger.info("drive: attempting upload with user OAuth token")

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
    metadata: dict = {"name": file_name}
    if folder_id:
        metadata["parents"] = [folder_id]
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
        logger.error(
            "drive: user-token upload failed  status=%d  body=%s",
            response.status_code,
            response.text[:500],
        )
        if allow_root_fallback and folder_id and "insufficientParentPermissions" in response.text:
            return upload_report_file(
                access_token=access_token,
                file_name=file_name,
                file_bytes=file_bytes,
                mime_type=mime_type,
                folder_id=None,
                replace_file_id=None,
                allow_root_fallback=False,
            )
        raise RuntimeError(response.text)

    result = response.json()
    logger.info(
        "drive: user-token upload succeeded  id=%s  webViewLink=%s",
        result.get("id"),
        result.get("webViewLink"),
    )
    return result


def delete_drive_file(access_token: str, file_id: str | None) -> None:
    """Best-effort delete of a Drive file (e.g. rollback after a dependent step fails)."""
    if not file_id:
        return
    try:
        requests.delete(
            f"{DRIVE_FILES_URL}/{file_id}",
            headers={"Authorization": f"Bearer {access_token}"},
            params={"supportsAllDrives": "true"},
            timeout=15,
        )
    except Exception:
        pass
