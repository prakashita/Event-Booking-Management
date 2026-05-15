import io
import json
import logging
import os
import re as _re
import traceback
import unicodedata as _unicodedata
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


# ---------------------------------------------------------------------------
# Enterprise folder hierarchy helpers
# ---------------------------------------------------------------------------

DRIVE_FOLDER_MIME = "application/vnd.google-apps.folder"
_MAX_FOLDER_NAME_LEN = 100

# Module-level in-process cache: (parent_id, folder_name) → folder_id.
# Avoids redundant Drive API list calls within the same server process.
_folder_cache: dict[tuple[str, str], str] = {}


def sanitize_folder_name(name: str) -> str:
    """Return a Drive-safe folder name derived from *name*.

    Rules applied in order:
    1. Unicode normalisation (NFKD → ASCII-safe characters where possible).
    2. Spaces and path separators (/ \\\\) → underscores.
    3. Characters invalid in Drive / filesystem names are stripped.
    4. Multiple consecutive underscores collapsed to one.
    5. Leading / trailing underscores and dots trimmed.
    6. Result truncated to _MAX_FOLDER_NAME_LEN characters.
    7. Falls back to ``"Untitled"`` if the result would be empty.

    Example: ``"AI/ML Workshop 2026"`` → ``"AI_ML_Workshop_2026"``
    """
    if not name:
        return "Untitled"
    # Normalise unicode and drop non-ASCII combining marks
    normalized = _unicodedata.normalize("NFKD", name)
    ascii_str = normalized.encode("ascii", "ignore").decode("ascii")
    # Replace whitespace and path separators with underscores
    cleaned = _re.sub(r"[\s/\\]+", "_", ascii_str)
    # Strip characters invalid in Drive names
    cleaned = _re.sub(r'[*?"<>|:;,]+', "", cleaned)
    # Collapse multiple underscores
    cleaned = _re.sub(r"_+", "_", cleaned)
    # Strip leading / trailing underscores and dots
    cleaned = cleaned.strip("_.")
    # Enforce max length
    cleaned = cleaned[:_MAX_FOLDER_NAME_LEN]
    return cleaned or "Untitled"


def _build_sa_service():
    """Build a Drive v3 service object using service account credentials.

    Returns ``(service, None)`` on success, ``(None, error_string)`` on failure.
    Never raises — all errors are logged and suppressed.
    """
    creds = _get_sa_credentials()
    if creds is None:
        return None, "Service account credentials unavailable"
    try:
        from googleapiclient.discovery import build  # noqa: PLC0415
        service = build("drive", "v3", credentials=creds, cache_discovery=False)
        return service, None
    except Exception:
        logger.error(
            "drive: failed to build SA Drive service for folder ops:\n%s",
            traceback.format_exc(),
        )
        return None, "Failed to build Drive service"


def get_or_create_folder(service, name: str, parent_id: str) -> str:
    """Return the Drive folder ID for *name* inside *parent_id*, creating it if absent.

    Uses a module-level cache keyed by ``(parent_id, name)`` to minimise
    redundant Drive API calls within the same server process.

    Raises ``RuntimeError`` if both the lookup and the creation fail.
    """
    cache_key = (parent_id, name)
    if cache_key in _folder_cache:
        logger.debug(
            "drive: folder cache hit  name=%r  parent=%r  id=%s",
            name, parent_id, _folder_cache[cache_key],
        )
        return _folder_cache[cache_key]

    # Search for an existing folder with this name under parent_id
    try:
        q = (
            f"name={json.dumps(name)}"
            f" and mimeType={json.dumps(DRIVE_FOLDER_MIME)}"
            f" and {json.dumps(parent_id)} in parents"
            f" and trashed=false"
        )
        result = (
            service.files()
            .list(
                q=q,
                fields="files(id,name)",
                pageSize=1,
                supportsAllDrives=True,
                includeItemsFromAllDrives=True,
            )
            .execute()
        )
        files = result.get("files", [])
        if files:
            folder_id = files[0]["id"]
            logger.info(
                "drive: folder reused  name=%r  parent=%r  id=%s",
                name, parent_id, folder_id,
            )
            _folder_cache[cache_key] = folder_id
            return folder_id
    except Exception:
        logger.warning(
            "drive: folder lookup failed  name=%r  parent=%r:\n%s",
            name, parent_id, traceback.format_exc(),
        )

    # Create a new folder
    try:
        folder_meta = {
            "name": name,
            "mimeType": DRIVE_FOLDER_MIME,
            "parents": [parent_id],
        }
        created = (
            service.files()
            .create(body=folder_meta, fields="id", supportsAllDrives=True)
            .execute()
        )
        folder_id = created["id"]
        logger.info(
            "drive: folder created  name=%r  parent=%r  id=%s",
            name, parent_id, folder_id,
        )
        _folder_cache[cache_key] = folder_id
        return folder_id
    except Exception:
        logger.error(
            "drive: folder creation failed  name=%r  parent=%r:\n%s",
            name, parent_id, traceback.format_exc(),
        )
        raise RuntimeError(
            f"Failed to get or create Drive folder {name!r} in parent {parent_id!r}"
        )


def create_nested_folder_structure(service, path_parts: list[str], root_id: str) -> str:
    """Walk *path_parts*, creating or reusing a Drive folder at each level.

    Returns the final leaf folder's Drive ID.
    """
    current_id = root_id
    for part in path_parts:
        current_id = get_or_create_folder(service, part, current_id)
    return current_id


def upload_file_to_nested_folder(
    *,
    access_token: str,
    file_name: str,
    file_bytes: bytes,
    mime_type: str,
    root_folder_id: str,
    folder_path_parts: list[str],
    replace_file_id: str | None = None,
    allow_root_fallback: bool = False,
) -> dict:
    """Upload *file_bytes* into a nested Drive folder hierarchy, creating folders as needed.

    Folder path: ``root_folder_id → folder_path_parts[0] → … → folder_path_parts[-1]``

    If folder creation fails (e.g. SA unavailable, insufficient permissions) the file is
    uploaded directly into *root_folder_id* so that the existing upload flow is preserved.

    Returns the Drive file metadata dict (``id``, ``name``, ``webViewLink``).
    """
    logger.info(
        "drive: upload_file_to_nested_folder  file=%r  path=%r  root=%r  size=%d bytes",
        file_name,
        "/".join(folder_path_parts),
        root_folder_id,
        len(file_bytes),
    )

    target_folder_id = root_folder_id  # safe fallback

    if folder_path_parts:
        service, err = _build_sa_service()
        if service is None:
            logger.warning(
                "drive: SA service unavailable for folder creation (%s); "
                "uploading directly to root folder %r",
                err,
                root_folder_id,
            )
        else:
            try:
                target_folder_id = create_nested_folder_structure(
                    service, folder_path_parts, root_folder_id
                )
                logger.info(
                    "drive: upload target resolved  path=%r  folder_id=%s",
                    "/".join(folder_path_parts),
                    target_folder_id,
                )
            except Exception:
                logger.warning(
                    "drive: nested folder creation failed; "
                    "falling back to root folder %r:\n%s",
                    root_folder_id,
                    traceback.format_exc(),
                )
                target_folder_id = root_folder_id

    result = upload_report_file(
        access_token=access_token,
        file_name=file_name,
        file_bytes=file_bytes,
        mime_type=mime_type,
        folder_id=target_folder_id,
        replace_file_id=replace_file_id,
        allow_root_fallback=allow_root_fallback,
    )
    logger.info(
        "drive: upload_file_to_nested_folder complete  file=%r  folder=%s  drive_id=%s",
        file_name,
        target_folder_id,
        result.get("id"),
    )
    return result
