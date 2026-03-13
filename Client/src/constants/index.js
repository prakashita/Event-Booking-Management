/**
 * Shared constants for the Event Booking application.
 */

/** Route paths (React Router). Used for navigation and deep-linking. */
export const ROUTES = {
  DASHBOARD: "/",
  MY_EVENTS: "/events",
  EVENT_REPORTS: "/event-reports",
  CALENDAR: "/calendar",
  APPROVALS: "/approvals",
  REQUIREMENTS: "/requirements",
  PUBLICATIONS: "/publications",
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

export const menuItems = [
  { id: "dashboard", label: "Dashboard" },
  { id: "my-events", label: "My Events" },
  { id: "event-reports", label: "Event Reports" },
  { id: "calendar", label: "Calendar View" },
  { id: "approvals", label: "Approvals" },
  { id: "requirements", label: "Requirements" },
  { id: "publications", label: "Publications" },
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
