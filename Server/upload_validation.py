"""
Shared PDF upload validation constants and helpers.

Single source of truth for the 15 MB PDF size limit used across all upload
endpoints.  Import these instead of defining local magic numbers.
"""
from fastapi import HTTPException, status

# 15 MB maximum for any PDF upload across the entire application.
MAX_PDF_UPLOAD_BYTES: int = 15 * 1024 * 1024

PDF_SIZE_ERROR_DETAIL: str = (
    "PDF size exceeds 15 MB. Please reduce the file size and try again."
)


def _is_pdf(filename: str, content_type: str) -> bool:
    """Return True if the file appears to be a PDF based on name or MIME type."""
    return (
        (content_type or "").lower() == "application/pdf"
        or (filename or "").lower().endswith(".pdf")
    )


def validate_pdf_size(content: bytes, filename: str = "", content_type: str = "") -> None:
    """Raise HTTP 413 if *content* is a PDF that exceeds MAX_PDF_UPLOAD_BYTES.

    Call this after reading the uploaded bytes and before writing to storage /
    Google Drive.  Non-PDF files are silently ignored so callers do not need to
    branch on file type.
    """
    if _is_pdf(filename, content_type) and len(content) > MAX_PDF_UPLOAD_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=PDF_SIZE_ERROR_DETAIL,
        )
