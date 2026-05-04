/**
 * Formatting utilities for dates, times, and display values.
 */

/**
 * Format a time string (HH:mm or HH:mm:ss) to 12-hour AM/PM format.
 * Supports IST timezone when passed as ISO string.
 */
export function formatISTTime(value) {
  if (!value) return "";
  const raw = String(value).trim();
  const timeMatch = raw.match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
  if (timeMatch) {
    const hours24 = Number(timeMatch[1]);
    const minutes = timeMatch[2];
    if (Number.isNaN(hours24) || hours24 > 23) return raw;
    const period = hours24 >= 12 ? "PM" : "AM";
    const hours12 = hours24 % 12 || 12;
    return `${hours12}:${minutes} ${period}`;
  }
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return raw;
  return parsed
    .toLocaleTimeString("en-IN", {
      timeZone: "Asia/Kolkata",
      hour: "numeric",
      minute: "2-digit",
      hour12: true
    })
    .toUpperCase();
}

/**
 * Parse a 24h time string (HH:mm) into parts: { hour, minute, period }.
 */
export function parse24ToTimeParts(value) {
  const raw = String(value || "").trim();
  const match = raw.match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
  if (!match) return { hour: "", minute: "", period: "AM" };
  const hours24 = Number(match[1]);
  if (Number.isNaN(hours24) || hours24 > 23) return { hour: "", minute: "", period: "AM" };
  const minute = match[2];
  const period = hours24 >= 12 ? "PM" : "AM";
  const hour12 = hours24 % 12 || 12;
  return { hour: String(hour12), minute, period };
}

/**
 * Normalize a time string to HH:mm:ss for consistent ISO datetime parsing.
 * Accepts "HH:mm" or "HH:mm:ss" (with optional leading zero).
 */
export function normalizeTimeToHHMMSS(value) {
  if (value == null || value === "") return "00:00:00";
  const raw = String(value).trim();
  const match = raw.match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?$/);
  if (!match) return "00:00:00";
  const h = String(parseInt(match[1], 10)).padStart(2, "0");
  const m = match[2];
  const s = (match[3] || "00").padStart(2, "0");
  return `${h}:${m}:${s}`;
}

/**
 * Convert time parts to 24h string.
 */
export function timePartsTo24(parts) {
  if (!parts?.hour || !parts?.minute || !parts?.period) return "";
  const hour12 = Number(parts.hour);
  if (Number.isNaN(hour12) || hour12 < 1 || hour12 > 12) return "";
  const m = String(parts.minute).padStart(2, "0");
  if (!/^\d{2}$/.test(m)) return "";
  const h = hour12;
  if (parts.period === "PM" && h < 12) {
    return `${h + 12}:${m}`;
  }
  if (parts.period === "AM" && h === 12) {
    return `00:${m}`;
  }
  return `${String(h).padStart(2, "0")}:${m}`;
}

/**
 * Facility / marketing / IT / Transport requests use status "approved" in the API; show "Noted" in the UI.
 * Registrar approval keeps the raw "approved" label elsewhere.
 */
export function formatRequirementDecisionStatusLabel(status) {
  if (status == null || status === "") return "";
  const s = String(status).trim().toLowerCase();
  if (s === "approved" || s === "accepted") return "Noted";
  return String(status).trim();
}
