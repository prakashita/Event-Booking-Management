/**
 * Shared constants for the Event Booking application.
 */

/**
 * Generate academic year labels from startYear–startYear+1 through endYear–endYear+1.
 * Default range: 2025-2026 through 2050-2051.
 */
export function generateAcademicYears(startYear = 2025, endYear = 2050) {
  const years = [];
  for (let y = startYear; y <= endYear; y++) {
    years.push(`${y}-${y + 1}`);
  }
  return years;
}

/** Pre-computed academic year options for dropdowns. */
export const ACADEMIC_YEAR_OPTIONS = generateAcademicYears();

/** Derive the "current" academic year based on the current date (June cutover). */
export function getCurrentAcademicYear() {
  const now = new Date();
  const year = now.getMonth() >= 5 ? now.getFullYear() : now.getFullYear() - 1;
  return `${year}-${year + 1}`;
}

/** Academic calendar entry categories. */
export const ACADEMIC_CATEGORY_OPTIONS = [
  "Commencement",
  "Registration",
  "Submission",
  "Instruction",
  "Examination",
  "Assessment",
  "Committee Meeting",
  "Fest",
  "Result",
  "Application",
  "Eligibility List",
  "Semester Closure",
  "Semester Start",
  "Semester End",
  "Other",
];

/** Semester type options. */
export const SEMESTER_TYPE_OPTIONS = ["Even Semester", "Odd Semester", "Summer Term"];

/** Semester options. */
export const SEMESTER_OPTIONS = [
  "Semester I",
  "Semester II",
  "Semester III",
  "Semester IV",
  "Semester V",
  "Semester VI",
  "Semester VII",
  "Semester VIII",
  "Summer Term",
];

/** Route paths (React Router). Used for navigation and deep-linking. */
export const ROUTES = {
  DASHBOARD: "/",
  MY_EVENTS: "/events",
  EVENT_REPORTS: "/event-reports",
  CALENDAR: "/calendar",
  APPROVALS: "/approvals",
  REQUIREMENTS: "/requirements",
  PUBLICATIONS: "/publications",
  IQAC_DATA: "/iqac-data",
  CALENDAR_UPDATES: "/calendar-updates",
  USER_APPROVALS: "/user-approvals",
  ADMIN: "/admin",
};

/** Map route path -> legacy activeView id for compatibility. */
export const PATH_TO_VIEW = {
  [ROUTES.DASHBOARD]: "dashboard",
  [ROUTES.MY_EVENTS]: "my-events",
  [ROUTES.EVENT_REPORTS]: "event-reports",
  [ROUTES.CALENDAR]: "calendar",
  [ROUTES.APPROVALS]: "approvals",
  [ROUTES.REQUIREMENTS]: "requirements",
  [ROUTES.PUBLICATIONS]: "publications",
  [ROUTES.IQAC_DATA]: "iqac-data",
  [ROUTES.CALENDAR_UPDATES]: "calendar-updates",
  [ROUTES.USER_APPROVALS]: "user-approvals",
  [ROUTES.ADMIN]: "admin",
};

/** Map legacy activeView id -> route path. */
export const VIEW_TO_PATH = Object.fromEntries(
  Object.entries(PATH_TO_VIEW).map(([path, view]) => [view, path])
);

export const stats = [
  { label: "Active Events", value: "128+" },
  { label: "Attendees Managed", value: "24k" },
  { label: "Automated Reminders", value: "98%" }
];

/** Route-specific SVG icon paths (24×24 viewBox, filled). */
export const MENU_ICONS = {
  "dashboard":        "M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z",
  "my-events":        "M17 12h-5v5h5v-5zM16 1v2H8V1H6v2H5c-1.11 0-1.99.9-1.99 2L3 19a2 2 0 0 0 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2h-1V1h-2zm3 18H5V8h14v11z",
  "event-reports":    "M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z",
  "calendar":         "M19 4h-1V2h-2v2H8V2H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 16H5V10h14v10zm0-12H5V6h14v2z",
  "approvals":        "M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z",
  "requirements":     "M19 3h-4.18C14.4 1.84 13.3 1 12 1s-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm2 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z",
  "publications":     "M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-1 9H9V9h10v2zm-4 4H9v-2h6v2zm4-8H9V5h10v2z",
  "iqac-data":        "M20 2H4c-1 0-2 .9-2 2v3.01c0 .72.43 1.34 1 1.69V20c0 1.1 1.1 2 2 2h14c.9 0 2-.9 2-2V8.7c.57-.35 1-.97 1-1.69V4c0-1.1-1-2-2-2zm-5 12H9v-2h6v2zm5-7H4V4h16v3z",
  "calendar-updates": "M17 12h-5v5h5v-5zm-1-11v2H8V1H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2h-1V1h-2zm3 18H5V8h14v11z",
  "user-approvals":   "M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z",
  "admin":            "M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm0 10.99h7c-.53 4.12-3.28 7.79-7 8.94V12H5V6.3l7-3.11v8.8z",
};

/** Preference-section icon paths. */
export const PREFERENCE_ICONS = {
  "users":    "M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z",
  "settings": "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.19-.15.24-.42.12-.64l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54A.48.48 0 0 0 14 2h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.49.49 0 0 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.07.62-.07.94s.02.64.07.94l-2.03 1.58c-.19.15-.24.42-.12.64l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1 1 12 8.4a3.6 3.6 0 0 1 0 7.2z",
};

/** Sidebar toggle icon paths. */
export const SIDEBAR_TOGGLE_ICONS = {
  collapse: "M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z",
  expand:   "M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z",
};

/** Folder/archive icon path for IQAC (folder with doc). */
export const MENU_ICON_IQAC = MENU_ICONS["iqac-data"];

/**
 * Roles that can access IQAC Data Collection (menu + all APIs).
 * Must match Server/routers/deps.py IQAC_ALLOWED_ROLES.
 */
export const ROLES_WITH_IQAC_ACCESS = [
  "iqac",
  "faculty",
  "admin",
  "registrar",
  "vice_chancellor",
  "deputy_registrar",
  "finance_team",
];

/** Roles that may delete IQAC uploads. Must match Server IQAC_DELETE_ALLOWED_ROLES. */
export const ROLES_WITH_IQAC_DELETE_ACCESS = [
  "iqac",
  "admin",
  "registrar",
  "vice_chancellor",
  "deputy_registrar",
  "finance_team",
];

export const menuItems = [
  { id: "dashboard", label: "Dashboard" },
  { id: "my-events", label: "My Events" },
  { id: "event-reports", label: "Event Reports" },
  { id: "calendar", label: "Calendar View" },
  { id: "approvals", label: "Approvals" },
  { id: "requirements", label: "Requirements" },
  { id: "publications", label: "Publications" },
  { id: "iqac-data", label: "IQAC Data Collection" },
  { id: "calendar-updates", label: "Calendar Updates" },
  { id: "user-approvals", label: "User Approvals" },
  { id: "admin", label: "Admin Console" }
];

export const preferenceItems = [
  { id: "users", label: "User Management" },
  { id: "settings", label: "Settings" }
];

export const inboxItems = [
  { name: "Nur Azzahra", time: "2 hours ago", message: "Lorem ipsum dolor sit amet, consectetur adipiscing elit." },
  { name: "Nur Azzahra", time: "2 hours ago", message: "Lorem ipsum dolor sit amet, consectetur adipiscing elit." },
  { name: "Nur Azzahra", time: "2 hours ago", message: "Lorem ipsum dolor sit amet, consectetur adipiscing elit." }
];

export const eventsTable = [
  { name: "Event 1", date: "11 September 2025", time: "9 am", status: "In Progress" },
  { name: "Event 2", date: "12 September 2025", time: "1 pm", status: "Ready" },
  { name: "Event 3", date: "15 October 2025", time: "2 pm", status: "Pending" },
  { name: "Event 4", date: "18 September 2025", time: "9 am", status: "Ready" },
  { name: "Event 5", date: "22 September 2025", time: "1 pm", status: "Pending" },
  { name: "Event 6", date: "1 October 2025", time: "2 pm", status: "Pending" },
  { name: "Event 7", date: "18 September 2025", time: "9 am", status: "Ready" },
  { name: "Event 8", date: "22 September 2025", time: "1 pm", status: "Pending" },
  { name: "Event 9", date: "1 October 2025", time: "2 pm", status: "Pending" }
];

export const PUB_META = {
  webpage: { icon: "🌐", label: "Webpage", color: "#2c7a7b" },
  journal_article: { icon: "📄", label: "Journal Article", color: "#553c9a" },
  book: { icon: "📚", label: "Book", color: "#c05621" },
  report: { icon: "📊", label: "Report", color: "#2b6cb0" },
  video: { icon: "🎬", label: "Video", color: "#c53030" },
  online_newspaper: { icon: "📰", label: "Online Newspaper", color: "#276749" }
};
