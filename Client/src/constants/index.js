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
  STUDENT_ACHIEVEMENTS: "/student-achievements",
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
  [ROUTES.STUDENT_ACHIEVEMENTS]: "student-achievements",
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
  "student-achievements": "M12 2l2.7 5.47 6.03.88-4.36 4.25 1.03 6-5.4-2.84-5.4 2.84 1.03-6-4.36-4.25 6.03-.88L12 2zm0 11.5l2.45 1.29-.47-2.73 1.98-1.93-2.74-.4L12 6.25l-1.22 2.48-2.74.4 1.98 1.93-.47 2.73L12 13.5z",
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
];

/** Roles that may delete IQAC uploads. Must match Server IQAC_DELETE_ALLOWED_ROLES. */
export const ROLES_WITH_IQAC_DELETE_ACCESS = [
  "iqac",
];

export const menuItems = [
  { id: "dashboard", label: "Dashboard" },
  { id: "my-events", label: "My Events" },
  { id: "event-reports", label: "Event Reports" },
  { id: "calendar", label: "Calendar View" },
  { id: "approvals", label: "Approvals" },
  { id: "requirements", label: "Requirements" },
  { id: "publications", label: "Publications" },
  { id: "student-achievements", label: "Student Achievements" },
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

export const PUBLICATION_FIELD_DEFINITIONS = {
  title: { label: "Title", type: "text", placeholder: "Main title of the cited item" },
  content: { label: "Content", type: "textarea", placeholder: "Post or comment text" },
  issued_date: { label: "Issued", type: "date" },
  accessed_date: { label: "Accessed", type: "date", todayShortcut: true },
  composed_date: { label: "Composed", type: "date" },
  submitted_date: { label: "Submitted", type: "date" },
  container_title: { label: "Container title", type: "text", placeholder: "Website, journal, book, platform, or publication name" },
  collection_title: { label: "Collection title", type: "text", placeholder: "Podcast or TV series name" },
  medium: { label: "Medium", type: "text", placeholder: "e.g. Painting, PDF, Video, Slides" },
  archive_collection: { label: "Archive / museum / collection", type: "text" },
  place_country: { label: "Country", type: "text" },
  place_region: { label: "Region", type: "text" },
  place_locality: { label: "Locality", type: "text" },
  publisher: { label: "Publisher", type: "text", placeholder: "Publisher, producer, institution, or organization" },
  publisher_place: { label: "Publisher place", type: "text" },
  source: { label: "Source", type: "text", placeholder: "Database, channel, platform, or source" },
  url: { label: "URL", type: "url", placeholder: "https://..." },
  doi: { label: "DOI", type: "text", placeholder: "10.1000/example" },
  pdf_url: { label: "PDF URL", type: "url", placeholder: "https://..." },
  note: { label: "Note", type: "textarea", placeholder: "Optional citation note" },
  edition: { label: "Edition", type: "text", placeholder: "e.g. 3rd" },
  volume: { label: "Volume", type: "text" },
  issue: { label: "Issue", type: "text" },
  number: { label: "Number / article number", type: "text" },
  pages: { label: "Page / page range", type: "text", placeholder: "e.g. 45-60" },
  original_publication_date: { label: "Original publication date", type: "date" },
  event: { label: "Event", type: "text", placeholder: "Conference, talk, class, or event" },
  event_name: { label: "Event name", type: "text" },
  version: { label: "Version", type: "text" },
  status: { label: "Status", type: "select", options: ["Published", "In press", "Unpublished"] },
  jurisdiction: { label: "Jurisdiction", type: "text" },
  authority: { label: "Authority", type: "text" },
  season: { label: "Season", type: "text" },
  episode: { label: "Episode", type: "text" },
  genre: { label: "Genre", type: "text", placeholder: "e.g. PhD dissertation, Master's thesis" },
  section: { label: "Section", type: "text" }
};

const commonWebOptional = ["accessed_date", "note"];
const placeFields = ["place_country", "place_region", "place_locality"];

export const FEATURED_SOURCE_TYPE_KEYS = [
  "webpage",
  "journal_article",
  "book",
  "report",
  "video",
  "online_newspaper_article"
];

export const SOURCE_TYPE_CONFIG = {
  artwork: {
    sourceType: "Artwork",
    label: "Artwork",
    icon: "🎨",
    color: "#7c3aed",
    desc: "Artwork, museum objects, and collection items",
    requiredFields: ["title"],
    recommendedFields: ["composed_date"],
    optionalFields: ["medium", "archive_collection", ...placeFields, "note"]
  },
  blog_post: {
    sourceType: "Blog Post",
    label: "Blog Post",
    icon: "✍️",
    color: "#0f766e",
    desc: "Posts from blogs and editorial feeds",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: commonWebOptional
  },
  book: {
    sourceType: "Book",
    label: "Book",
    icon: "📚",
    color: "#c05621",
    desc: "Printed books and e-books",
    requiredFields: ["title"],
    recommendedFields: ["medium", "issued_date", "publisher"],
    optionalFields: ["edition", "volume", "original_publication_date", "publisher_place", "doi", "pdf_url", "url", "note"]
  },
  book_chapter: {
    sourceType: "Book Chapter",
    label: "Book Chapter",
    icon: "📖",
    color: "#a16207",
    desc: "A chapter or section within a book",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["pages"],
    optionalFields: ["edition", "volume", "medium", "issued_date", "original_publication_date", "publisher", "publisher_place", "doi", "pdf_url", "url", "note"]
  },
  comment: {
    sourceType: "Comment",
    label: "Comment",
    icon: "💬",
    color: "#64748b",
    desc: "Comments on posts, articles, videos, or threads",
    requiredFields: ["content"],
    recommendedFields: ["container_title", "issued_date", "source", "url"],
    optionalFields: commonWebOptional
  },
  conference_proceeding: {
    sourceType: "Conference Proceeding",
    label: "Conference Proceeding",
    icon: "📄",
    color: "#4f46e5",
    desc: "Papers published in proceedings",
    requiredFields: ["title"],
    recommendedFields: ["issued_date"],
    optionalFields: ["container_title", "edition", "volume", "medium", "publisher", "publisher_place", "doi", "pdf_url", "url", "note"]
  },
  conference_session: {
    sourceType: "Conference Session",
    label: "Conference Session",
    icon: "🎤",
    color: "#0891b2",
    desc: "Talks, sessions, and conference presentations",
    requiredFields: ["title"],
    recommendedFields: ["medium", "event", "url"],
    optionalFields: ["container_title", "event_name", ...placeFields, "note"]
  },
  dataset: {
    sourceType: "Dataset",
    label: "Dataset",
    icon: "🧮",
    color: "#047857",
    desc: "Datasets from repositories or projects",
    requiredFields: ["title"],
    recommendedFields: ["url"],
    optionalFields: ["container_title", "version", "medium", "status", "issued_date", "publisher", "doi", "pdf_url", "note"]
  },
  film: {
    sourceType: "Film",
    label: "Film",
    icon: "🎞️",
    color: "#b91c1c",
    desc: "Films and movies",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "publisher"],
    optionalFields: ["version", "medium", "url", "note"]
  },
  forum_post: {
    sourceType: "Forum Post",
    label: "Forum Post",
    icon: "🧵",
    color: "#475569",
    desc: "Posts from forums and discussion boards",
    requiredFields: ["title"],
    recommendedFields: ["container_title", "issued_date", "url"],
    optionalFields: commonWebOptional
  },
  image: {
    sourceType: "Image",
    label: "Image",
    icon: "🖼️",
    color: "#7c2d12",
    desc: "Online images, figures, and photographs",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["container_title", "note"]
  },
  journal_article: {
    sourceType: "Journal Article",
    label: "Journal Article",
    icon: "📄",
    color: "#553c9a",
    desc: "Peer-reviewed academic and scholarly articles",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["status", "issued_date", "pages", "doi"],
    optionalFields: ["volume", "issue", "number", "source", "pdf_url", "url", "note"]
  },
  online_dictionary_entry: {
    sourceType: "Online Dictionary Entry",
    label: "Online Dictionary Entry",
    icon: "🔤",
    color: "#2563eb",
    desc: "Dictionary entries published online",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["container_title", "accessed_date", "note"]
  },
  online_encyclopedia_entry: {
    sourceType: "Online Encyclopedia Entry",
    label: "Online Encyclopedia Entry",
    icon: "🌐",
    color: "#1d4ed8",
    desc: "Online encyclopedia entries",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["container_title", "accessed_date", "note"]
  },
  online_magazine_article: {
    sourceType: "Online Magazine Article",
    label: "Online Magazine Article",
    icon: "🗞️",
    color: "#be123c",
    desc: "Magazine articles published online",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["original_publication_date", "accessed_date", "publisher", "note"]
  },
  online_newspaper_article: {
    sourceType: "Online Newspaper Article",
    label: "Online Newspaper Article",
    icon: "📰",
    color: "#276749",
    desc: "News articles published online",
    aliases: ["online_newspaper"],
    requiredFields: ["title", "container_title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["publisher", "note"]
  },
  patent: {
    sourceType: "Patent",
    label: "Patent",
    icon: "⚙️",
    color: "#0f172a",
    desc: "Patents with number, jurisdiction, and authority",
    requiredFields: ["title", "number", "jurisdiction", "authority", "issued_date"],
    recommendedFields: [],
    optionalFields: ["container_title", "url", "note"]
  },
  podcast: {
    sourceType: "Podcast",
    label: "Podcast",
    icon: "🎙️",
    color: "#9333ea",
    desc: "A podcast series",
    requiredFields: ["title"],
    recommendedFields: ["url"],
    optionalFields: ["publisher", "source", "note"]
  },
  podcast_episode: {
    sourceType: "Podcast Episode",
    label: "Podcast Episode",
    icon: "🎧",
    color: "#7e22ce",
    desc: "One episode from a podcast",
    requiredFields: ["collection_title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["title", "season", "episode", "accessed_date", "publisher", "source", "note"]
  },
  presentation_slides: {
    sourceType: "Presentation Slides",
    label: "Presentation Slides",
    icon: "📊",
    color: "#0369a1",
    desc: "Slide decks and presentation materials",
    requiredFields: ["title"],
    recommendedFields: ["medium", "issued_date", "event", "url"],
    optionalFields: ["container_title", "original_publication_date", "event_name", ...placeFields, "pages", "note"]
  },
  press_release: {
    sourceType: "Press Release",
    label: "Press Release",
    icon: "📣",
    color: "#b45309",
    desc: "Organization announcements and press releases",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: commonWebOptional
  },
  print_dictionary_entry: {
    sourceType: "Print Dictionary Entry",
    label: "Print Dictionary Entry",
    icon: "📘",
    color: "#334155",
    desc: "Dictionary entries in print sources",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["issued_date", "publisher"],
    optionalFields: ["edition", "volume", "number", "original_publication_date", "publisher_place", "pages", "note"]
  },
  print_encyclopedia_entry: {
    sourceType: "Print Encyclopedia Entry",
    label: "Print Encyclopedia Entry",
    icon: "📚",
    color: "#1e40af",
    desc: "Encyclopedia entries in print sources",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["issued_date", "publisher"],
    optionalFields: ["edition", "volume", "original_publication_date", "publisher_place", "note"]
  },
  print_magazine_article: {
    sourceType: "Print Magazine Article",
    label: "Print Magazine Article",
    icon: "📰",
    color: "#9f1239",
    desc: "Magazine articles from print issues",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["issued_date", "pages"],
    optionalFields: ["issue", "original_publication_date", "source", "note"]
  },
  print_newspaper_article: {
    sourceType: "Print Newspaper Article",
    label: "Print Newspaper Article",
    icon: "🗞️",
    color: "#166534",
    desc: "Newspaper articles from print editions",
    requiredFields: ["title", "container_title"],
    recommendedFields: ["issued_date", "pages"],
    optionalFields: ["edition", "section", "original_publication_date", "publisher", "publisher_place", "note"]
  },
  report: {
    sourceType: "Report",
    label: "Report",
    icon: "📊",
    color: "#2b6cb0",
    desc: "Research, policy, and organization reports",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["container_title", "number", "accessed_date", "publisher", "publisher_place", "doi", "pdf_url", "note"]
  },
  social_media_post: {
    sourceType: "Social Media Post",
    label: "Social Media Post",
    icon: "#",
    color: "#0ea5e9",
    desc: "Posts from social platforms",
    requiredFields: ["content"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["container_title", "accessed_date", "note"]
  },
  software: {
    sourceType: "Software",
    label: "Software",
    icon: "⌘",
    color: "#0f766e",
    desc: "Software packages, apps, and tools",
    requiredFields: ["title"],
    recommendedFields: ["version", "issued_date"],
    optionalFields: ["container_title", "publisher", "url", "note"]
  },
  speech: {
    sourceType: "Speech",
    label: "Speech",
    icon: "🎤",
    color: "#c2410c",
    desc: "Speeches and public addresses",
    requiredFields: ["title"],
    recommendedFields: ["event", "url"],
    optionalFields: ["container_title", "issued_date", "event_name", ...placeFields, "note"]
  },
  thesis: {
    sourceType: "Thesis",
    label: "Thesis",
    icon: "🎓",
    color: "#4338ca",
    desc: "Theses and dissertations",
    requiredFields: ["title"],
    recommendedFields: ["genre", "submitted_date", "publisher"],
    optionalFields: ["doi", "pdf_url", "note"]
  },
  tv_show: {
    sourceType: "TV Show",
    label: "TV Show",
    icon: "📺",
    color: "#be123c",
    desc: "A television show or series",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "publisher"],
    optionalFields: ["medium", "source", "url", "note"]
  },
  tv_show_episode: {
    sourceType: "TV Show Episode",
    label: "TV Show Episode",
    icon: "📺",
    color: "#e11d48",
    desc: "One episode from a TV series",
    requiredFields: ["collection_title"],
    recommendedFields: ["issued_date"],
    optionalFields: ["title", "season", "episode", "medium", "accessed_date", "publisher", "source", "url", "note"]
  },
  video: {
    sourceType: "Video",
    label: "Video",
    icon: "🎬",
    color: "#c53030",
    desc: "Online videos from YouTube, Vimeo, or platforms",
    requiredFields: ["title"],
    recommendedFields: ["container_title", "issued_date"],
    optionalFields: ["accessed_date", "url", "note"]
  },
  webpage: {
    sourceType: "Webpage",
    label: "Webpage",
    icon: "🌐",
    color: "#2c7a7b",
    desc: "A specific page on a website",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "url"],
    optionalFields: ["container_title", "accessed_date", "note"]
  },
  website: {
    sourceType: "Website",
    label: "Website",
    icon: "🌍",
    color: "#0284c7",
    desc: "A full website, not just one page",
    requiredFields: ["title"],
    recommendedFields: ["issued_date", "accessed_date", "url"],
    optionalFields: ["publisher", "note"]
  },
  wiki_entry: {
    sourceType: "Wiki Entry",
    label: "Wiki Entry",
    icon: "W",
    color: "#475569",
    desc: "Wiki or Wikipedia articles",
    requiredFields: ["title"],
    recommendedFields: ["container_title", "issued_date", "url"],
    optionalFields: ["accessed_date", "note"]
  }
};

export const SOURCE_TYPE_OPTIONS = Object.entries(SOURCE_TYPE_CONFIG).map(([key, config]) => ({
  key,
  ...config
}));

export const PUB_META = Object.fromEntries(
  SOURCE_TYPE_OPTIONS.flatMap((type) => {
    const meta = { icon: type.icon, label: type.label, color: type.color };
    return [[type.key, meta], ...(type.aliases || []).map((alias) => [alias, meta])];
  })
);

export const CITATION_FORMAT_OPTIONS = [
  { value: "mla", label: "MLA" },
  { value: "apa", label: "APA" },
  { value: "harvard", label: "Harvard" },
  { value: "chicago", label: "Chicago" },
  { value: "ieee", label: "IEEE" },
];
