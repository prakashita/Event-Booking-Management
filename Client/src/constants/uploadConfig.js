/**
 * Shared upload configuration for chat file attachments.
 * Single source of truth — referenced by both validation logic and UI components.
 * Keep in sync with MAX_CHAT_UPLOAD_BYTES / resolve_allowed_chat_mime in Server/routers/chat.py.
 */

/** Maximum allowed file size for chat attachments (5 MB). */
export const MAX_CHAT_FILE_SIZE = 5 * 1024 * 1024;

/** Human-readable label for the size limit. */
export const MAX_CHAT_FILE_SIZE_LABEL = "5MB";

/**
 * MIME types accepted for chat uploads.
 * Must match allowed types in Server/routers/chat.py (_CHAT_ALLOWED_CT_EXACT).
 */
export const ALLOWED_CHAT_MIME_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
  "application/pdf",
]);

const CHAT_EXT_TO_MIME = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".pdf": "application/pdf",
};

/**
 * Resolve an allowed chat MIME for a File, using the browser-reported type when possible
 * and falling back to the filename extension (many browsers send PDFs as octet-stream or "").
 * @param {File} file
 * @returns {string|null} canonical MIME if allowed, else null
 */
export function resolveChatFileMime(file) {
  if (!file) return null;
  const raw = (file.type || "").split(";")[0].trim().toLowerCase();
  if (raw && raw !== "application/octet-stream" && raw !== "binary/octet-stream") {
    if (raw === "image/pjpeg") return "image/jpeg";
    if (ALLOWED_CHAT_MIME_TYPES.has(raw)) return raw;
    return null;
  }
  const name = (file.name || "").toLowerCase();
  const dot = name.lastIndexOf(".");
  const ext = dot >= 0 ? name.slice(dot) : "";
  const guessed = CHAT_EXT_TO_MIME[ext];
  return guessed && ALLOWED_CHAT_MIME_TYPES.has(guessed) ? guessed : null;
}

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
