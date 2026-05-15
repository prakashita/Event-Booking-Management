/**
 * Shared upload configuration for chat file attachments and PDF uploads.
 * Single source of truth — referenced by both validation logic and UI components.
 * Keep in sync with MAX_CHAT_UPLOAD_BYTES / _CHAT_ALLOWED_CT_EXACT in Server/routers/chat.py
 * and MAX_PDF_UPLOAD_BYTES in Server/upload_validation.py.
 */

/** Maximum allowed file size for any PDF upload across the application (15 MB). */
export const MAX_PDF_FILE_SIZE = 15 * 1024 * 1024;

/** User-facing error message when a PDF exceeds the size limit. */
export const PDF_SIZE_ERROR_MESSAGE =
  "PDF size exceeds 15 MB. Please reduce the file size and try again.";

/** Maximum allowed file size for chat attachments (5 MB). */
export const MAX_CHAT_FILE_SIZE = 5 * 1024 * 1024;

/** Human-readable label for the size limit. */
export const MAX_CHAT_FILE_SIZE_LABEL = "5MB";

/**
 * MIME types accepted for chat uploads.
 * Must match _CHAT_ALLOWED_CT_EXACT in Server/routers/chat.py.
 */
export const ALLOWED_CHAT_MIME_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "application/pdf",
]);

/**
 * `accept` attribute string for <input type="file"> elements.
 * Lists both MIME types and common extensions for maximum browser compatibility.
 */
export const CHAT_FILE_INPUT_ACCEPT =
  "image/jpeg,image/jpg,image/png,image/webp,application/pdf,.jpg,.jpeg,.png,.webp,.pdf";

/** User-facing error messages for chat upload failures. */
export const UPLOAD_ERRORS = {
  FILE_TOO_LARGE:
    "File size exceeds 5MB. Please upload a smaller file or share a Drive link.",
  UNSUPPORTED_TYPE:
    "Unsupported file type. Please upload an image (JPEG, PNG, WebP) or PDF only.",
  UPLOAD_FAILED: "Upload failed. Please try again.",
};
