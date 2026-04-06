import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { jsPDF } from "jspdf";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import interactionPlugin from "@fullcalendar/interaction";
import tippy from "tippy.js";
import "tippy.js/dist/tippy.css";
import {
  menuItems,
  preferenceItems,
  inboxItems,
  eventsTable,
  PUB_META,
  PATH_TO_VIEW,
  ROUTES,
  ROLES_WITH_IQAC_ACCESS,
  ROLES_WITH_IQAC_DELETE_ACCESS
} from "./constants";
import {
  formatISTTime,
  normalizeTimeToHHMMSS,
  parse24ToTimeParts,
  timePartsTo24
} from "./utils/format";
import { formatInboxDecisionStatusLabel } from "./utils/eventDetailsView";
import { GoogleIcon, SimpleIcon, PlaceholderCard } from "./components/icons";
import { LoginPage, Sidebar } from "./components/layout";
import { Modal, StatusMessage } from "./components/ui";
import PremiumDatePicker from "./components/ui/PremiumDatePicker";
import PremiumTimePicker from "./components/ui/PremiumTimePicker";
import SearchableSelect from "./components/ui/SearchableSelect";
import IqacDataPage from "./components/IqacDataPage";
import EventDetailsModalBody from "./components/EventDetailsModalBody";
import { ConnectedApprovalDetailsModalBody } from "./components/ApprovalDetailsModalBody";
import { MessengerProvider, FloatingMessenger } from "./components/messenger";
import api from "./services/api";

/** Normalize path so "/event reports" or "/event%20reports" map to canonical routes. */
function normalizePathname(pathname) {
  if (!pathname || typeof pathname !== "string") return pathname;
  const decoded = decodeURIComponent(pathname);
  if (decoded === "/event reports") return ROUTES.EVENT_REPORTS;
  return pathname;
}

function canActOnWorkflowRow(status) {
  const s = String(status || "").toLowerCase();
  return s === "pending" || s === "clarification_requested";
}

function workflowInboxAttentionCount(items) {
  if (!Array.isArray(items)) return 0;
  return items.filter((i) => canActOnWorkflowRow(i?.status)).length;
}

function transportRequestTypeLabel(type) {
  if (type === "guest_cab") return "Guest cab";
  if (type === "students_off_campus") return "Students (off-campus)";
  if (type === "both") return "Guest cab & students";
  return type ? String(type) : "—";
}

export default function App() {
  const location = useLocation();
  const navigate = useNavigate();
  const pathname = normalizePathname(location.pathname);
  const activeView = PATH_TO_VIEW[pathname] ?? "dashboard";

  useEffect(() => {
    if (pathname !== location.pathname && PATH_TO_VIEW[pathname]) {
      navigate(pathname, { replace: true });
    }
  }, [pathname, location.pathname, navigate]);

  useEffect(() => {
    setMobileMenuOpen(false);
  }, [pathname]);

  const googleButtonRef = useRef(null);
  const [status, setStatus] = useState({ type: "idle", message: "" });
  const [searchInput, setSearchInput] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [myEventsTab, setMyEventsTab] = useState("all");
  const [isEventModalOpen, setIsEventModalOpen] = useState(false);
  const [venuesState, setVenuesState] = useState({ status: "idle", items: [], error: "" });
  const [eventsState, setEventsState] = useState({ status: "idle", items: [], error: "" });
  const [approvalsState, setApprovalsState] = useState({ status: "idle", items: [], error: "" });
  const [marketingState, setMarketingState] = useState({ status: "idle", items: [], error: "" });
  const [itState, setItState] = useState({ status: "idle", items: [], error: "" });
  const [facilityState, setFacilityState] = useState({ status: "idle", items: [], error: "" });
  const [transportState, setTransportState] = useState({ status: "idle", items: [], error: "" });
  const [eventForm, setEventForm] = useState({
    start_date: "",
    end_date: "",
    start_time: "",
    end_time: "",
    name: "",
    facilitator: "",
    venue_name: "",
    intendedAudience: "",
    description: "",
    budget: ""
  });
  const [eventTimeParts, setEventTimeParts] = useState({
    start_time: { hour: "", minute: "", period: "AM" },
    end_time: { hour: "", minute: "", period: "AM" }
  });
  const [eventFormStatus, setEventFormStatus] = useState({ status: "idle", error: "" });
  const [budgetBreakdownFile, setBudgetBreakdownFile] = useState(null);
  const budgetBreakdownInputRef = useRef(null);
  const [conflictState, setConflictState] = useState({ open: false, items: [] });
  const [approvalModal, setApprovalModal] = useState({ open: false, status: "idle", error: "" });
  const [approvalForm, setApprovalForm] = useState({
    requirements: {
      venue: true,
      refreshments: false
    },
    other_notes: ""
  });
  const [overrideConflict, setOverrideConflict] = useState(false);
  const [inviteModal, setInviteModal] = useState({ open: false, status: "idle", error: "" });
  const [inviteForm, setInviteForm] = useState({
    to: "",
    subject: "",
    description: ""
  });
  const [inviteContext, setInviteContext] = useState({
    eventId: "",
    eventName: "",
    startDate: "",
    startTime: ""
  });
  const [pendingEvent, setPendingEvent] = useState(null);
  const [marketingModal, setMarketingModal] = useState({ open: false, status: "idle", error: "" });
  const defaultMarketingRequirements = () => ({
    pre_event: {
      poster: true,
      social_media: false
    },
    during_event: {
      photo: false,
      video: false
    },
    post_event: {
      social_media: false,
      photo_upload: false,
      video: false
    }
  });
  const [marketingForm, setMarketingForm] = useState({
    to: "",
    marketing_requirements: defaultMarketingRequirements(),
    other_notes: ""
  });
  const [itModal, setItModal] = useState({ open: false, status: "idle", error: "" });
  const [itForm, setItForm] = useState({
    to: "",
    event_mode: "offline",
    pa_system: true,
    projection: false,
    other_notes: ""
  });
  const [facilityModal, setFacilityModal] = useState({ open: false, status: "idle", error: "" });
  const [facilityForm, setFacilityForm] = useState({
    to: "",
    venue_required: true,
    refreshments: false,
    other_notes: ""
  });
  const [transportModal, setTransportModal] = useState({ open: false, status: "idle", error: "" });
  const [transportForm, setTransportForm] = useState({
    to: "",
    include_guest_cab: true,
    include_students: false,
    guest_pickup_location: "",
    guest_pickup_date: "",
    guest_pickup_time: "",
    guest_dropoff_location: "",
    guest_dropoff_date: "",
    guest_dropoff_time: "",
    student_count: "",
    student_transport_kind: "",
    student_date: "",
    student_time: "",
    student_pickup_point: "",
    other_notes: ""
  });
  const [requirementsModal, setRequirementsModal] = useState({ open: false, event: null });
  const [approvalsTab, setApprovalsTab] = useState("approval-requests");
  const [reportModal, setReportModal] = useState({
    open: false,
    status: "idle",
    error: "",
    eventId: "",
    eventName: "",
    startDate: "",
    eventVenue: "",
    eventFacilitator: "",
    hasReport: false
  });
  const REQUIREMENT_OPTIONS = [
    { key: "poster_required", type: "poster", label: "Poster" },
    { key: "video_required", type: "video", label: "Videoshoot" },
    { key: "linkedin_post", type: "linkedin", label: "Social Media Post" },
    { key: "photography", type: "photography", label: "Photoshoot / Photo upload" },
    { key: "recording", type: "recording", label: "Video Upload" }
  ];
  const MARKETING_REQUIREMENT_GROUPS = [
    {
      key: "pre_event",
      title: "Pre-Event",
      fields: [
        { key: "poster", label: "Poster" },
        { key: "social_media", label: "Social Media Post" }
      ]
    },
    {
      key: "during_event",
      title: "During Event",
      fields: [
        { key: "photo", label: "Photoshoot" },
        { key: "video", label: "Videoshoot" }
      ]
    },
    {
      key: "post_event",
      title: "Post-Event",
      fields: [
        { key: "social_media", label: "Social Media Post" },
        { key: "photo_upload", label: "Photo Upload" },
        { key: "video", label: "Video Upload" }
      ]
    }
  ];
  const [marketingDeliverableModal, setMarketingDeliverableModal] = useState({
    open: false,
    request: null,
    requirements: {}, // { poster: { na: false, file: null }, ... }
    status: "idle",
    error: ""
  });
  const [eventDetailsModal, setEventDetailsModal] = useState({
    open: false,
    event: null,
    details: null,
    status: "idle",
    error: ""
  });
  const [approvalDetailsModal, setApprovalDetailsModal] = useState({
    open: false,
    request: null,
    eventDetails: null,
    detailsStatus: "idle",
    detailsError: ""
  });
  const [workflowActionModal, setWorkflowActionModal] = useState({
    open: false,
    channel: null,
    requestId: null,
    status: null,
    actionLabel: "",
    comment: "",
    error: "",
    submitting: false
  });
  const [publicationTypeModal, setPublicationTypeModal] = useState({ open: false });
  const [publicationModal, setPublicationModal] = useState({
    open: false,
    status: "idle",
    error: ""
  });
  const [publicationForm, setPublicationForm] = useState({
    name: "",
    title: "",
    pubType: "",
    file: null,
    others: "",
    // Shared
    author_first_name: "",
    author_last_name: "",
    publication_date: "",
    url: "",
    // Journal Article
    article_title: "",
    journal_name: "",
    volume: "",
    issue: "",
    pages: "",
    doi: "",
    year: "",
    // Book
    book_title: "",
    publisher: "",
    edition: "",
    page_number: "",
    // Report
    organization: "",
    report_title: "",
    // Video
    creator: "",
    video_title: "",
    platform: "",
    // Newspaper / Webpage
    newspaper_name: "",
    website_name: "",
    page_title: ""
  });

  const [reportForm, setReportForm] = useState({
    executiveSummary: "",
    attendance: "",
    programAgenda: "",
    outcomesLearnings: "",
    followUp: "",
    appendix: ""
  });
  const [reportAppendixPhotos, setReportAppendixPhotos] = useState([]);
  const [reportIqacCriteria, setReportIqacCriteria] = useState({ status: "idle", items: [], error: "" });
  const [reportIqacSelection, setReportIqacSelection] = useState({
    criterionId: "",
    subFolderId: "",
    itemId: "",
    description: ""
  });
  const [calendarState, setCalendarState] = useState({
    status: "idle",
    events: [],
    error: ""
  });
  const [calendarDetailModal, setCalendarDetailModal] = useState({ open: false, event: null });
  const [publicationsState, setPublicationsState] = useState({
    status: "idle",
    items: [],
    error: ""
  });
  const [publicationSort, setPublicationSort] = useState("date_desc");
  const [publicationTypeFilter, setPublicationTypeFilter] = useState("");

  const [adminTab, setAdminTab] = useState("users");
  const [adminOverview, setAdminOverview] = useState({ status: "idle", data: null, error: "" });
  const [adminUsersState, setAdminUsersState] = useState({ status: "idle", items: [], error: "" });
  const [adminVenuesState, setAdminVenuesState] = useState({ status: "idle", items: [], error: "" });
  const [adminEventsState, setAdminEventsState] = useState({ status: "idle", items: [], error: "" });
  const [adminApprovalsState, setAdminApprovalsState] = useState({ status: "idle", items: [], error: "" });
  const [adminMarketingState, setAdminMarketingState] = useState({ status: "idle", items: [], error: "" });
  const [adminItState, setAdminItState] = useState({ status: "idle", items: [], error: "" });
  const [adminTransportState, setAdminTransportState] = useState({ status: "idle", items: [], error: "" });
  const [adminInvitesState, setAdminInvitesState] = useState({ status: "idle", items: [], error: "" });
  const [adminPublicationsState, setAdminPublicationsState] = useState({ status: "idle", items: [], error: "" });
  const [adminVenueName, setAdminVenueName] = useState("");
  const [addUserModal, setAddUserModal] = useState({
    open: false,
    email: "",
    role: "registrar",
    status: "idle",
    error: ""
  });
  const [googleScopeModal, setGoogleScopeModal] = useState({
    open: false,
    missing: []
  });
  const [registrarEmail, setRegistrarEmail] = useState("");
  const [facilityManagerEmail, setFacilityManagerEmail] = useState("");
  const [marketingEmail, setMarketingEmail] = useState("");
  const [itEmail, setItEmail] = useState("");
  const [transportEmail, setTransportEmail] = useState("");
  const loadEventsRef = useRef(null);
  const requirementsFlowQueueRef = useRef([]);
  const [user, setUser] = useState(() => {
    const storedToken = localStorage.getItem("auth_token");
    const stored = localStorage.getItem("auth_user");
    if (!storedToken || !stored) {
      return null;
    }

    try {
      return JSON.parse(stored);
    } catch (err) {
      return null;
    }
  });
  const normalizedUserRole = (user?.role || "").toLowerCase();
  const isAdmin = normalizedUserRole === "admin";
  const isRegistrar = normalizedUserRole === "registrar";
  const isApproverRole = normalizedUserRole === "approver" || isRegistrar;
  const isFacilityManagerRole = normalizedUserRole === "facility_manager";
  const isMarketingRole = normalizedUserRole === "marketing";
  const isItRole = normalizedUserRole === "it";
  const isTransportRole = normalizedUserRole === "transport";
  const canAccessAdminConsole = isAdmin || isRegistrar;
  const canAccessApprovals = isRegistrar;
  const canAccessRequirements =
    isFacilityManagerRole || isMarketingRole || isItRole || isTransportRole;
  const canAccessIqac = ROLES_WITH_IQAC_ACCESS.includes(normalizedUserRole);
  const canDeleteIqacFiles = ROLES_WITH_IQAC_DELETE_ACCESS.includes(normalizedUserRole);
  const defaultFacilitator = (user?.name || "").trim();

  const googleClientId =
    import.meta.env.VITE_GOOGLE_CLIENT_ID ||
    "947113013769-dsal8c7k52irs6eokfnvl6o1a6v2rvea.apps.googleusercontent.com";

  useEffect(() => {
    if (activeView === "event-reports") {
      setMyEventsTab("closed");
    }
  }, [activeView]);

  const handleSessionExpired = useCallback(() => {
    localStorage.removeItem("auth_token");
    localStorage.removeItem("auth_user");
    setUser(null);
    navigate(ROUTES.DASHBOARD);
    setStatus({ type: "error", message: "Session expired. Please log in again." });
  }, [navigate]);

  useEffect(() => {
    const onUnauthorized = () => handleSessionExpired();
    window.addEventListener(api.UNAUTHORIZED_EVENT, onUnauthorized);
    return () => window.removeEventListener(api.UNAUTHORIZED_EVENT, onUnauthorized);
  }, [handleSessionExpired]);

  const apiBaseUrl = api.getBaseUrl();

  const apiFetch = useCallback(async (input, init = {}) => {
    const token = api.getToken();
    if (!token) {
      handleSessionExpired();
      throw new Error("Missing auth token.");
    }
    const url = typeof input === "string" ? input : input.url;
    const base = api.getBaseUrl();
    const path = url.startsWith(base) ? url.slice(base.length) || "/" : url.replace(/^https?:\/\/[^/]+/, "") || "/";
    const method = (init.method || "GET").toUpperCase();
    const body = init.body;
    const options = init.headers ? { headers: init.headers } : {};
    if (method === "GET") return api.get(path, options);
    if (method === "POST") return api.post(path, body, options);
    if (method === "PATCH") return api.patch(path, body, options);
    if (method === "DELETE") return api.delete(path, options);
    return api.get(path, options);
  }, [handleSessionExpired]);

  const generateIdempotencyKey = () => (typeof crypto !== "undefined" && crypto.randomUUID) ? crypto.randomUUID() : "";

  const loadPublications = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setPublicationsState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }
    setPublicationsState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const [sortBy, order] = publicationSort.split("_");
      const params = new URLSearchParams({ sort: sortBy, order: order || "desc" });
      const res = await apiFetch(`${apiBaseUrl}/publications?${params.toString()}`);
      if (!res.ok) {
        throw new Error("Unable to load publications.");
      }
      const data = await res.json();
      const items = Array.isArray(data) ? data : (data.items ?? []);
      setPublicationsState({ status: "ready", items, error: "" });
    } catch (err) {
      setPublicationsState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load publications."
      });
    }
  }, [apiBaseUrl, apiFetch, publicationSort]);

  const loadAdminOverview = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminOverview({ status: "loading", data: null, error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/overview`);
      if (!res.ok) {
        throw new Error("Unable to load admin overview.");
      }
      const data = await res.json();
      setAdminOverview({ status: "ready", data, error: "" });
    } catch (err) {
      setAdminOverview({
        status: "error",
        data: null,
        error: err?.message || "Unable to load admin overview."
      });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminUsers = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminUsersState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/users`);
      if (!res.ok) {
        throw new Error("Unable to load users.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : (Array.isArray(data) ? data : []);
      setAdminUsersState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminUsersState({ status: "error", items: [], error: err?.message || "Unable to load users." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminVenues = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminVenuesState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/venues`);
      if (!res.ok) {
        throw new Error("Unable to load venues.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : (Array.isArray(data) ? data : []);
      setAdminVenuesState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminVenuesState({ status: "error", items: [], error: err?.message || "Unable to load venues." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminEvents = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminEventsState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/events`);
      if (!res.ok) {
        throw new Error("Unable to load events.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setAdminEventsState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminEventsState({ status: "error", items: [], error: err?.message || "Unable to load events." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminApprovals = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminApprovalsState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/approvals`);
      if (!res.ok) {
        throw new Error("Unable to load approvals.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setAdminApprovalsState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminApprovalsState({ status: "error", items: [], error: err?.message || "Unable to load approvals." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminMarketing = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminMarketingState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/marketing`);
      if (!res.ok) {
        throw new Error("Unable to load marketing requests.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setAdminMarketingState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminMarketingState({ status: "error", items: [], error: err?.message || "Unable to load marketing requests." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminIt = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminItState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/it`);
      if (!res.ok) {
        throw new Error("Unable to load IT requests.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setAdminItState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminItState({ status: "error", items: [], error: err?.message || "Unable to load IT requests." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminInvites = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminInvitesState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/invites`);
      if (!res.ok) {
        throw new Error("Unable to load invites.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setAdminInvitesState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminInvitesState({ status: "error", items: [], error: err?.message || "Unable to load invites." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const loadAdminPublications = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminPublicationsState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/publications`);
      if (!res.ok) {
        throw new Error("Unable to load publications.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setAdminPublicationsState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminPublicationsState({ status: "error", items: [], error: err?.message || "Unable to load publications." });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);


  const handleAdminRoleChange = useCallback(
    async (targetUserId, role) => {
      if (!canAccessAdminConsole) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/users/${targetUserId}/role`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ role })
        });
        if (!res.ok) {
          throw new Error("Unable to update role.");
        }
        const updated = await res.json();
        setAdminUsersState((prev) => ({
          ...prev,
          items: prev.items.map((item) => (item.id === updated.id ? updated : item))
        }));
        if (user?.id === updated.id) {
          const nextUser = { ...user, role: updated.role };
          setUser(nextUser);
          localStorage.setItem("auth_user", JSON.stringify(nextUser));
        }
      } catch (err) {
        setAdminUsersState((prev) => ({
          ...prev,
          error: err?.message || "Unable to update role."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole, user]
  );

  const handleAddUserModalOpen = useCallback(() => {
    setAddUserModal({ open: true, email: "", role: "registrar", status: "idle", error: "" });
  }, []);

  const handleAddUserModalClose = useCallback(() => {
    setAddUserModal({ open: false, email: "", role: "registrar", status: "idle", error: "" });
  }, []);

  const handleAddUserSubmit = useCallback(
    async (e) => {
      e?.preventDefault();
      if (!canAccessAdminConsole) return;
      const email = (addUserModal.email || "").trim();
      if (!email) {
        setAddUserModal((prev) => ({ ...prev, error: "Email is required.", status: "error" }));
        return;
      }
      setAddUserModal((prev) => ({ ...prev, status: "loading", error: "" }));
      try {
        const res = await apiFetch(`${apiBaseUrl}/users/add`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ email, role: addUserModal.role })
        });
        const data = res.ok ? await res.json().catch(() => ({})) : null;
        const errBody = !res.ok ? await res.json().catch(() => ({})) : null;
        if (!res.ok) {
          throw new Error(errBody?.detail || "Unable to add user.");
        }
        setAddUserModal({ open: false, email: "", role: "registrar", status: "idle", error: "" });
        setStatus({
          type: "success",
          message: data?.detail || (data?.id ? "User role updated." : "User added. They will get this role when they first sign in.")
        });
        loadAdminUsers();
        if (data?.id) {
          setAdminUsersState((prev) => ({
            ...prev,
            items: prev.items.some((u) => u.id === data.id)
              ? prev.items.map((u) => (u.id === data.id ? data : u))
              : [...prev.items, data]
          }));
        }
      } catch (err) {
        setAddUserModal((prev) => ({
          ...prev,
          status: "error",
          error: err?.message || "Unable to add user."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole, addUserModal.email, addUserModal.role, loadAdminUsers]
  );

  const handleAdminDeleteUser = useCallback(
    async (targetUserId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this user? This cannot be undone.")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/users/${targetUserId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete user.");
        }
        setAdminUsersState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== targetUserId)
        }));
      } catch (err) {
        setAdminUsersState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete user."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminCreateVenue = useCallback(
    async (name) => {
      if (!canAccessAdminConsole) {
        return;
      }
      const trimmed = (name || "").trim();
      if (!trimmed) {
        setAdminVenuesState((prev) => ({
          ...prev,
          error: "Venue name is required."
        }));
        return;
      }
      setAdminVenuesState((prev) => ({ ...prev, status: "loading", error: "" }));
      try {
        const res = await apiFetch(`${apiBaseUrl}/venues`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: trimmed })
        });
        if (!res.ok) {
          const payload = await res.json().catch(() => ({}));
          throw new Error(payload.detail || "Unable to add venue.");
        }
        const created = await res.json();
        setAdminVenuesState((prev) => ({
          status: "ready",
          items: [created, ...prev.items],
          error: ""
        }));
        setAdminVenueName("");
      } catch (err) {
        setAdminVenuesState((prev) => ({
          ...prev,
          status: "error",
          error: err?.message || "Unable to add venue."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminDeleteVenue = useCallback(
    async (venueId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this venue?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/venues/${venueId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete venue.");
        }
        setAdminVenuesState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== venueId)
        }));
      } catch (err) {
        setAdminVenuesState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete venue."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminDeleteEvent = useCallback(
    async (eventId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this event?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/admin/events/${eventId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete event.");
        }
        setAdminEventsState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== eventId)
        }));
        loadEventsRef.current?.();
      } catch (err) {
        setAdminEventsState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete event."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminDeleteApproval = useCallback(
    async (requestId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this approval request?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/admin/approvals/${requestId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete approval request.");
        }
        setAdminApprovalsState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== requestId)
        }));
      } catch (err) {
        setAdminApprovalsState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete approval request."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminDeleteMarketing = useCallback(
    async (requestId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this marketing request?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/admin/marketing/${requestId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete marketing request.");
        }
        setAdminMarketingState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== requestId)
        }));
      } catch (err) {
        setAdminMarketingState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete marketing request."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminDeleteIt = useCallback(
    async (requestId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this IT request?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/admin/it/${requestId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete IT request.");
        }
        setAdminItState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== requestId)
        }));
      } catch (err) {
        setAdminItState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete IT request."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const loadAdminTransport = useCallback(async () => {
    if (!canAccessAdminConsole) {
      return;
    }
    setAdminTransportState({ status: "loading", items: [], error: "" });
    try {
      const res = await apiFetch(`${apiBaseUrl}/admin/transport`);
      if (!res.ok) {
        throw new Error("Unable to load transport requests.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setAdminTransportState({ status: "ready", items, error: "" });
    } catch (err) {
      setAdminTransportState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load transport requests."
      });
    }
  }, [apiBaseUrl, apiFetch, canAccessAdminConsole]);

  const handleAdminDeleteTransport = useCallback(
    async (requestId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this transport request?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/admin/transport/${requestId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete transport request.");
        }
        setAdminTransportState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== requestId)
        }));
      } catch (err) {
        setAdminTransportState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete transport request."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminDeleteInvite = useCallback(
    async (inviteId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this invite?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/admin/invites/${inviteId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete invite.");
        }
        setAdminInvitesState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== inviteId)
        }));
      } catch (err) {
        setAdminInvitesState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete invite."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  const handleAdminDeletePublication = useCallback(
    async (publicationId) => {
      if (!canAccessAdminConsole) {
        return;
      }
      if (!window.confirm("Delete this publication?")) {
        return;
      }
      try {
        const res = await apiFetch(`${apiBaseUrl}/admin/publications/${publicationId}`, { method: "DELETE" });
        if (!res.ok) {
          throw new Error("Unable to delete publication.");
        }
        setAdminPublicationsState((prev) => ({
          ...prev,
          items: prev.items.filter((item) => item.id !== publicationId)
        }));
      } catch (err) {
        setAdminPublicationsState((prev) => ({
          ...prev,
          error: err?.message || "Unable to delete publication."
        }));
      }
    },
    [apiBaseUrl, apiFetch, canAccessAdminConsole]
  );

  useEffect(() => {
    setEventTimeParts({
      start_time: parse24ToTimeParts(eventForm.start_time),
      end_time: parse24ToTimeParts(eventForm.end_time)
    });
  }, [eventForm.start_time, eventForm.end_time, parse24ToTimeParts]);

  useEffect(() => {
    if (!defaultFacilitator) {
      return;
    }
    setEventForm((prev) => (prev.facilitator ? prev : { ...prev, facilitator: defaultFacilitator }));
  }, [defaultFacilitator]);

  const handleGoogleCredential = useCallback(
    async (response) => {
      if (!response?.credential) {
        setStatus({ type: "error", message: "Missing Google credential." });
        return;
      }

      setStatus({ type: "loading", message: "Signing you in..." });

      try {
        const res = await fetch(`${apiBaseUrl}/auth/google`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ token: response.credential })
        });

        if (!res.ok) {
          throw new Error("Login failed. Please try again.");
        }

        const data = await res.json();
        localStorage.setItem("auth_token", data.access_token);
        localStorage.setItem("auth_user", JSON.stringify(data.user));
        setUser(data.user);
        navigate(ROUTES.DASHBOARD);
        setStatus({ type: "success", message: "Signed in successfully." });
      } catch (err) {
        setStatus({
          type: "error",
          message: err?.message || "Unable to sign in right now."
        });
      }
    },
    [apiBaseUrl]
  );

  const loadVenues = useCallback(async () => {
    setVenuesState({ status: "loading", items: [], error: "" });
    try {
      const res = await fetch(`${apiBaseUrl}/venues`);
      if (!res.ok) {
        throw new Error("Unable to load venues.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : (Array.isArray(data) ? data : []);
      setVenuesState({ status: "ready", items, error: "" });
    } catch (err) {
      setVenuesState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load venues."
      });
    }
  }, [apiBaseUrl]);

  const fetchCalendarEvents = useCallback(async (range) => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setCalendarState({
        status: "needs_auth",
        events: [],
        error: "Missing auth token."
      });
      return;
    }

    setCalendarState((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      const params = new URLSearchParams();
      if (range?.start) {
        params.set("start", range.start.toISOString());
      }
      if (range?.end) {
        params.set("end", range.end.toISOString());
      }
      const query = params.toString();
      const url = query
        ? `${apiBaseUrl}/calendar/app-events?${query}`
        : `${apiBaseUrl}/calendar/app-events`;
      const res = await apiFetch(url);

      if (!res.ok) {
        throw new Error("Unable to load events.");
      }

      const data = await res.json();
      const mappedEvents = (data.events || []).map((event) => ({
        id: event.id,
        title: event.summary || "Untitled event",
        start: event.start,
        end: event.end,
        url: event.htmlLink || undefined,
        extendedProps: {
          location: event.location
        }
      }));
      setCalendarState({
        status: "ready",
        events: mappedEvents,
        error: ""
      });
    } catch (err) {
      setCalendarState({
        status: "error",
        events: [],
        error: err?.message || "Unable to load events."
      });
    }
  }, [apiBaseUrl]);

  const loadEvents = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setEventsState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }

    setEventsState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const role = (user?.role || "").toLowerCase();
      const isAdminOrRegistrar = role === "admin" || role === "registrar";
      if (activeView === "event-reports" && user && isAdminOrRegistrar) {
        const reportsRes = await apiFetch(`${apiBaseUrl}/admin/event-reports`);
        if (!reportsRes.ok) {
          throw new Error("Unable to load event reports.");
        }
        const reportsData = await reportsRes.json();
        const items = Array.isArray(reportsData?.items) ? reportsData.items : [];
        setEventsState({ status: "ready", items, error: "" });
        return;
      }

      const [eventsRes, approvalsRes, facilityRes, marketingRes, itRes, transportRes, invitesRes] =
        await Promise.all([
          apiFetch(`${apiBaseUrl}/events`),
          apiFetch(`${apiBaseUrl}/approvals/me`),
          apiFetch(`${apiBaseUrl}/facility/requests/me`),
          apiFetch(`${apiBaseUrl}/marketing/requests/me`),
          apiFetch(`${apiBaseUrl}/it/requests/me`),
          apiFetch(`${apiBaseUrl}/transport/requests/me`),
          apiFetch(`${apiBaseUrl}/invites/me`)
        ]);

      if (!eventsRes.ok) {
        throw new Error("Unable to load events.");
      }
      if (!approvalsRes.ok) {
        throw new Error("Unable to load approval requests.");
      }

      const eventsPayload = await eventsRes.json();
      const eventsData = Array.isArray(eventsPayload)
        ? eventsPayload
        : (eventsPayload?.items ?? []);
      const approvalsPayload = await approvalsRes.json();
      const approvalsData = Array.isArray(approvalsPayload)
        ? approvalsPayload
        : (approvalsPayload?.items ?? []);
      const facilityData = facilityRes.ok ? await facilityRes.json() : [];
      const marketingData = marketingRes.ok ? await marketingRes.json() : [];
      const itData = itRes.ok ? await itRes.json() : [];
      const transportData = transportRes.ok ? await transportRes.json() : [];
      const invitesData = invitesRes.ok ? await invitesRes.json() : [];
      const approvalByEventId = new Map();
      const facilityByEventId = new Map();
      const marketingByEventId = new Map();
      const itByEventId = new Map();
      const transportByEventId = new Map();
      const inviteByEventId = new Map();
      const approvalByEventKey = new Map();
      const facilityByEventKey = new Map();
      const marketingByEventKey = new Map();
      const itByEventKey = new Map();
      const transportByEventKey = new Map();

      const normalizeTime = (value) => {
        if (!value) {
          return "";
        }
        return value.split(":").slice(0, 2).join(":");
      };

      const buildEventKey = (item) =>
        [
          item?.event_name || "",
          item?.start_date || "",
          normalizeTime(item?.start_time || ""),
          item?.end_date || "",
          normalizeTime(item?.end_time || "")
        ].join("|");
      approvalsData.forEach((item) => {
        if (item.event_id) {
          approvalByEventId.set(item.event_id, item.status);
        }
        approvalByEventKey.set(buildEventKey(item), item.status);
      });
      facilityData.forEach((item) => {
        if (item.event_id) {
          facilityByEventId.set(item.event_id, item.status);
        }
        facilityByEventKey.set(buildEventKey(item), item.status);
      });
      marketingData.forEach((item) => {
        if (item.event_id) {
          marketingByEventId.set(item.event_id, item.status);
        }
        marketingByEventKey.set(buildEventKey(item), item.status);
      });
      itData.forEach((item) => {
        if (item.event_id) {
          itByEventId.set(item.event_id, item.status);
        }
        itByEventKey.set(buildEventKey(item), item.status);
      });
      transportData.forEach((item) => {
        if (item.event_id) {
          transportByEventId.set(item.event_id, item.status);
        }
        transportByEventKey.set(buildEventKey(item), item.status);
      });
      invitesData.forEach((invite) => {
        if (invite.event_id) {
          inviteByEventId.set(invite.event_id, invite.status);
        }
      });
      const approvalItems = approvalsData
        .filter((item) => item.status !== "approved")
        .map((item) => ({
          ...item,
          id: `approval-${item.id}`,
          name: item.event_name,
          start_date: item.start_date,
          start_time: item.start_time,
          end_date: item.end_date,
          end_time: item.end_time,
          status: item.status,
          approval_request_id: item.id
        }));

      const enrichedEvents = eventsData.map((event) => {
        const eventKey = [
          event?.name || "",
          event?.start_date || "",
          normalizeTime(event?.start_time || ""),
          event?.end_date || "",
          normalizeTime(event?.end_time || "")
        ].join("|");
        return {
          ...event,
          approval_status:
            approvalByEventId.get(event.id) || approvalByEventKey.get(eventKey),
          facility_status:
            facilityByEventId.get(event.id) || facilityByEventKey.get(eventKey),
          marketing_status:
            marketingByEventId.get(event.id) || marketingByEventKey.get(eventKey),
          it_status: itByEventId.get(event.id) || itByEventKey.get(eventKey),
          transport_status:
            transportByEventId.get(event.id) || transportByEventKey.get(eventKey),
          invite_status: inviteByEventId.get(event.id)
        };
      });

      const items = [...approvalItems, ...enrichedEvents];
      const isEventStartedCheck = (e) => {
        if (!e?.start_date) return false;
        const startStr = `${e.start_date}T${normalizeTimeToHHMMSS(e.start_time)}`;
        const start = new Date(startStr);
        return !Number.isNaN(start.getTime()) && start <= new Date();
      };
      const eventNeedingRequirements = enrichedEvents.find(
        (e) =>
          !String(e.id || "").startsWith("approval-") &&
          e.approval_status === "approved" &&
          !isEventStartedCheck(e) &&
          ((e.facility_status !== "approved" && e.facility_status !== "pending") ||
            (e.transport_status !== "approved" && e.transport_status !== "pending") ||
            (e.marketing_status !== "approved" && e.marketing_status !== "pending") ||
            (e.it_status !== "approved" && e.it_status !== "pending"))
      );
      setEventsState({
        status: "ready",
        items,
        error: ""
      });
      if (eventNeedingRequirements && activeView === "my-events") {
        setRequirementsModal({ open: true, event: eventNeedingRequirements });
        setPendingEvent({ ...eventNeedingRequirements, event_id: eventNeedingRequirements.id });
      }
    } catch (err) {
      setEventsState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load events."
      });
    }
  }, [apiBaseUrl, apiFetch, activeView, user]);

  const loadApprovalsInbox = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setApprovalsState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }

    setApprovalsState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await apiFetch(`${apiBaseUrl}/approvals/inbox`);
      if (!res.ok) {
        throw new Error("Unable to load approvals.");
      }
      const data = await res.json();
      const items = Array.isArray(data?.items) ? data.items : [];
      setApprovalsState({ status: "ready", items, error: "" });
    } catch (err) {
      setApprovalsState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load approvals."
      });
    }
  }, [apiBaseUrl]);

  const loadMarketingInbox = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setMarketingState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }

    setMarketingState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await apiFetch(`${apiBaseUrl}/marketing/inbox`);
      if (!res.ok) {
        throw new Error("Unable to load marketing requests.");
      }
      const data = await res.json();
      setMarketingState({ status: "ready", items: data, error: "" });
    } catch (err) {
      setMarketingState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load marketing requests."
      });
    }
  }, [apiBaseUrl]);

  const loadFacilityInbox = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setFacilityState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }
    setFacilityState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await apiFetch(`${apiBaseUrl}/facility/inbox`);
      if (!res.ok) {
        throw new Error("Unable to load facility requests.");
      }
      const data = await res.json();
      setFacilityState({ status: "ready", items: data, error: "" });
    } catch (err) {
      setFacilityState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load facility requests."
      });
    }
  }, [apiBaseUrl, apiFetch]);

  const loadItInbox = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setItState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }

    setItState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await apiFetch(`${apiBaseUrl}/it/inbox`);
      if (!res.ok) {
        throw new Error("Unable to load IT requests.");
      }
      const data = await res.json();
      setItState({ status: "ready", items: data, error: "" });
    } catch (err) {
      setItState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load IT requests."
      });
    }
  }, [apiBaseUrl]);

  const loadTransportInbox = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setTransportState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }
    setTransportState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await apiFetch(`${apiBaseUrl}/transport/inbox`);
      if (!res.ok) {
        throw new Error("Unable to load transport requests.");
      }
      const data = await res.json();
      setTransportState({ status: "ready", items: Array.isArray(data) ? data : [], error: "" });
    } catch (err) {
      setTransportState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load transport requests."
      });
    }
  }, [apiBaseUrl, apiFetch]);

  const loadRegistrarEmail = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) return;
    try {
      const res = await apiFetch(`${apiBaseUrl}/auth/registrar-email`);
      if (res.ok) {
        const data = await res.json();
        setRegistrarEmail(data?.email || "");
      }
    } catch {
      setRegistrarEmail("");
    }
  }, [apiBaseUrl, apiFetch]);

  const loadFacilityManagerEmail = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) return;
    try {
      const res = await apiFetch(`${apiBaseUrl}/auth/facility-manager-email`);
      if (res.ok) {
        const data = await res.json();
        setFacilityManagerEmail(data?.email || "");
      }
    } catch {
      setFacilityManagerEmail("");
    }
  }, [apiBaseUrl, apiFetch]);

  const loadMarketingEmail = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) return;
    try {
      const res = await apiFetch(`${apiBaseUrl}/auth/marketing-email`);
      if (res.ok) {
        const data = await res.json();
        setMarketingEmail(data?.email || "");
      }
    } catch {
      setMarketingEmail("");
    }
  }, [apiBaseUrl, apiFetch]);

  const loadItEmail = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) return;
    try {
      const res = await apiFetch(`${apiBaseUrl}/auth/it-email`);
      if (res.ok) {
        const data = await res.json();
        setItEmail(data?.email || "");
      }
    } catch {
      setItEmail("");
    }
  }, [apiBaseUrl, apiFetch]);

  const loadTransportEmail = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) return;
    try {
      const res = await apiFetch(`${apiBaseUrl}/auth/transport-email`);
      if (res.ok) {
        const data = await res.json();
        setTransportEmail(data?.email || "");
      }
    } catch {
      setTransportEmail("");
    }
  }, [apiBaseUrl, apiFetch]);

  const checkGoogleScopes = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token || !user?.id) {
      return;
    }

    try {
      const res = await apiFetch(`${apiBaseUrl}/auth/google/status`);
      if (!res.ok) {
        return;
      }
      const data = await res.json();
      const missing = data?.missing_scopes || [];
      const connected = data?.connected === true;

      if (connected) {
        // User has already granted permission; clear any prior prompt flag and never show modal
        localStorage.removeItem(`google_connect_prompted_${user.id}`);
        setGoogleScopeModal({ open: false, missing: [] });
        return;
      }

      if (missing.length > 0) {
        // Only show modal on first login (first time we detect missing scopes for this user)
        const promptedKey = `google_connect_prompted_${user.id}`;
        const alreadyPrompted = localStorage.getItem(promptedKey);
        if (!alreadyPrompted) {
          localStorage.setItem(promptedKey, "true");
          setGoogleScopeModal({ open: true, missing });
        } else {
          setGoogleScopeModal({ open: false, missing: [] });
        }
      } else {
        setGoogleScopeModal({ open: false, missing: [] });
      }
    } catch (err) {
      // Keep silent to avoid blocking the UI on a status check
    }
  }, [apiBaseUrl, apiFetch, user?.id]);

  useEffect(() => {
    if (user) {
      return;
    }

    if (!googleClientId) {
      setStatus({
        type: "error",
        message: "Missing Google Client ID."
      });
      return;
    }

    let timerId;

    const tryInit = () => {
      if (!window.google?.accounts?.id || !googleButtonRef.current) {
        return false;
      }

      window.google.accounts.id.initialize({
        client_id: googleClientId,
        callback: handleGoogleCredential
      });

      window.google.accounts.id.renderButton(googleButtonRef.current, {
        theme: "outline",
        size: "large",
        text: "continue_with",
        shape: "pill",
        width: 320
      });
      googleButtonRef.current.classList.add("google-ready");

      window.google.accounts.id.prompt();
      return true;
    };

    if (!tryInit()) {
      timerId = window.setInterval(() => {
        if (tryInit()) {
          window.clearInterval(timerId);
        }
      }, 300);
    }

    return () => {
      if (timerId) {
        window.clearInterval(timerId);
      }
    };
  }, [googleClientId, handleGoogleCredential, user]);

  useEffect(() => {
    if (user && activeView === "calendar") {
      fetchCalendarEvents();
    }
  }, [activeView, fetchCalendarEvents, user]);

  useEffect(() => {
    if (user) {
      checkGoogleScopes();
    }
  }, [checkGoogleScopes, user]);

  useEffect(() => {
    if (user) {
      loadRegistrarEmail();
      loadFacilityManagerEmail();
      loadMarketingEmail();
      loadItEmail();
      loadTransportEmail();
    } else {
      setRegistrarEmail("");
      setFacilityManagerEmail("");
      setMarketingEmail("");
      setItEmail("");
      setTransportEmail("");
    }
  }, [user, loadRegistrarEmail, loadFacilityManagerEmail, loadMarketingEmail, loadItEmail, loadTransportEmail]);

  useEffect(() => {
    if (!user) return;
    const onVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        checkGoogleScopes();
      }
    };
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => document.removeEventListener("visibilitychange", onVisibilityChange);
  }, [user, checkGoogleScopes]);

  useEffect(() => {
    loadEventsRef.current = loadEvents;
  }, [loadEvents]);

  useEffect(() => {
    if (
      !user ||
      (activeView !== "my-events" && activeView !== "dashboard" && activeView !== "event-reports")
    ) {
      return;
    }
    loadEvents();
    if (activeView === "my-events") {
      loadVenues();
    }
  }, [activeView, loadEvents, loadVenues, user]);

  useEffect(() => {
    if (!user || activeView !== "publications") {
      return;
    }
    loadPublications();
  }, [activeView, loadPublications, user]);

  useEffect(() => {
    const isApprovalsOrRequirements = activeView === "approvals" || activeView === "requirements";
    if (!user || !isApprovalsOrRequirements) {
      return;
    }
    if (isApproverRole && approvalsState.status === "idle") {
      loadApprovalsInbox();
    }
    if (isFacilityManagerRole && facilityState.status === "idle") {
      loadFacilityInbox();
    }
    if (isMarketingRole && marketingState.status === "idle") {
      loadMarketingInbox();
    }
    if (isItRole && itState.status === "idle") {
      loadItInbox();
    }
    if (isTransportRole && transportState.status === "idle") {
      loadTransportInbox();
    }
  }, [
    activeView,
    approvalsState.status,
    facilityState.status,
    isApproverRole,
    isFacilityManagerRole,
    isItRole,
    isMarketingRole,
    isTransportRole,
    loadApprovalsInbox,
    loadFacilityInbox,
    loadItInbox,
    loadMarketingInbox,
    loadTransportInbox,
    itState.status,
    marketingState.status,
    transportState.status,
    user
  ]);

  useEffect(() => {
    if (
      (activeView === "approvals" && !canAccessApprovals) ||
      (activeView === "requirements" && !canAccessRequirements) ||
      (activeView === "event-reports" && !isAdmin && !isRegistrar) ||
      (activeView === "iqac-data" && !canAccessIqac)
    ) {
      navigate(ROUTES.DASHBOARD);
    }
  }, [activeView, canAccessApprovals, canAccessRequirements, canAccessIqac, isAdmin, isRegistrar, navigate]);

  useEffect(() => {
    const showApprovalsOrRequirements =
      (activeView === "approvals" && canAccessApprovals) || (activeView === "requirements" && canAccessRequirements);
    if (showApprovalsOrRequirements) {
      if (isApproverRole) setApprovalsTab("approval-requests");
      else if (isFacilityManagerRole) setApprovalsTab("facility");
      else if (isMarketingRole) setApprovalsTab("marketing");
      else if (isItRole) setApprovalsTab("it");
      else if (isTransportRole) setApprovalsTab("transport");
    }
  }, [
    activeView,
    canAccessApprovals,
    canAccessRequirements,
    isApproverRole,
    isFacilityManagerRole,
    isMarketingRole,
    isItRole,
    isTransportRole
  ]);

  useEffect(() => {
    if (!user || !canAccessAdminConsole || activeView !== "admin") {
      return;
    }
    loadAdminOverview();
    loadAdminUsers();
    loadAdminVenues();
    loadAdminEvents();
    loadAdminApprovals();
    loadAdminMarketing();
    loadAdminIt();
    loadAdminTransport();
    loadAdminInvites();
    loadAdminPublications();
  }, [
    activeView,
    canAccessAdminConsole,
    loadAdminApprovals,
    loadAdminEvents,
    loadAdminIt,
    loadAdminMarketing,
    loadAdminTransport,
    loadAdminOverview,
    loadAdminPublications,
    loadAdminInvites,
    loadAdminUsers,
    loadAdminVenues,
    user
  ]);

  const handleLogout = () => {
    localStorage.removeItem("auth_token");
    localStorage.removeItem("auth_user");
    setUser(null);
    setStatus({ type: "idle", message: "" });
  };

  const handleEventModalOpen = () => {
    setBudgetBreakdownFile(null);
    if (budgetBreakdownInputRef.current) {
      budgetBreakdownInputRef.current.value = "";
    }
    setEventForm((prev) => ({
      ...prev,
      facilitator: prev.facilitator || defaultFacilitator
    }));
    setIsEventModalOpen(true);
    setEventFormStatus({ status: "idle", error: "" });
  };

  const handleEventModalClose = () => {
    setBudgetBreakdownFile(null);
    if (budgetBreakdownInputRef.current) {
      budgetBreakdownInputRef.current.value = "";
    }
    setIsEventModalOpen(false);
    setConflictState({ open: false, items: [] });
  };

  // Lock body scroll when Create Event modal is open
  useEffect(() => {
    if (isEventModalOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => { document.body.style.overflow = ""; };
  }, [isEventModalOpen]);

  const handleApprovalModalOpen = () => {
    setApprovalForm({
      requirements: {
        venue: true,
        refreshments: false
      },
      other_notes: ""
    });
    setApprovalModal({ open: true, status: "idle", error: "" });
  };

  const handleApprovalModalClose = () => {
    setApprovalModal({ open: false, status: "idle", error: "" });
  };

  const handleInviteOpen = (item) => {
    const eventId = item?.id || item?.event_id || "";
    const eventName = item?.event_name || item?.name || "";
    const startDate = item?.start_date || "";
    const startTime = formatISTTime(item?.start_time || "");
    setInviteContext({ eventId, eventName, startDate, startTime });
    setInviteForm({
      to: "",
      subject: eventName ? `Event Invitation: ${eventName}` : "Event Invitation",
      description: eventName
        ? `You are invited to ${eventName} on ${startDate} at ${startTime} IST.`
        : ""
    });
    setInviteModal({ open: true, status: "idle", error: "" });
  };

  const handleInviteClose = () => {
    setInviteModal({ open: false, status: "idle", error: "" });
  };

  const handleMarketingModalOpen = () => {
    setMarketingForm({
      to: marketingEmail,
      marketing_requirements: defaultMarketingRequirements(),
      other_notes: ""
    });
    setMarketingModal({ open: true, status: "idle", error: "" });
  };

  const handleMarketingModalClose = () => {
      const queue = requirementsFlowQueueRef.current;
      if (queue[0] === "marketing") {
        requirementsFlowQueueRef.current = queue.slice(1);
        const next = requirementsFlowQueueRef.current[0];
        if (next === "transport") handleTransportModalOpen();
      } else {
        requirementsFlowQueueRef.current = [];
      }
      setMarketingModal({ open: false, status: "idle", error: "" });
  };

  const handleFacilityModalOpen = () => {
    setFacilityForm({
      to: facilityManagerEmail,
      venue_required: true,
      refreshments: false,
      other_notes: ""
    });
    setFacilityModal({ open: true, status: "idle", error: "" });
  };

  const handleFacilityModalClose = () => {
    requirementsFlowQueueRef.current = [];
    setFacilityModal({ open: false, status: "idle", error: "" });
  };

  const handleFacilitySkip = () => {
    setFacilityModal({ open: false, status: "idle", error: "" });
    const queue = requirementsFlowQueueRef.current;
    if (queue[0] === "facility") {
      requirementsFlowQueueRef.current = queue.slice(1);
      const next = requirementsFlowQueueRef.current[0];
      if (next === "it") handleItModalOpen();
      else if (next === "marketing") handleMarketingModalOpen();
      else if (next === "transport") handleTransportModalOpen();
    } else {
      requirementsFlowQueueRef.current = [];
    }
  };

  const handleTransportModalOpen = () => {
    setTransportForm({
      to: transportEmail,
      include_guest_cab: true,
      include_students: false,
      guest_pickup_location: "",
      guest_pickup_date: "",
      guest_pickup_time: "",
      guest_dropoff_location: "",
      guest_dropoff_date: "",
      guest_dropoff_time: "",
      student_count: "",
      student_transport_kind: "",
      student_date: "",
      student_time: "",
      student_pickup_point: "",
      other_notes: ""
    });
    setTransportModal({ open: true, status: "idle", error: "" });
  };

  const handleTransportModalClose = () => {
    requirementsFlowQueueRef.current = [];
    setTransportModal({ open: false, status: "idle", error: "" });
  };

  const handleTransportSkip = () => {
    setTransportModal({ open: false, status: "idle", error: "" });
    const queue = requirementsFlowQueueRef.current;
    if (queue[0] === "transport") {
      requirementsFlowQueueRef.current = queue.slice(1);
    } else {
      requirementsFlowQueueRef.current = [];
    }
  };

  const handleItModalOpen = () => {
    setItForm({
      to: itEmail,
      event_mode: "offline",
      pa_system: true,
      projection: false,
      other_notes: ""
    });
    setItModal({ open: true, status: "idle", error: "" });
  };

  const handleItModalClose = () => {
    requirementsFlowQueueRef.current = [];
    setItModal({ open: false, status: "idle", error: "" });
  };

  const resetEventFormState = () => {
    setPendingEvent(null);
    setOverrideConflict(false);
    setEventTimeParts({
      start_time: { hour: "", minute: "", period: "AM" },
      end_time: { hour: "", minute: "", period: "AM" }
    });
    setEventForm({
      start_date: "",
      end_date: "",
      start_time: "",
      end_time: "",
      name: "",
      facilitator: defaultFacilitator,
      venue_name: "",
      intendedAudience: "",
      description: "",
      budget: ""
    });
    setBudgetBreakdownFile(null);
    if (budgetBreakdownInputRef.current) {
      budgetBreakdownInputRef.current.value = "";
    }
  };

  const handleMarketingSkip = () => {
    setMarketingModal({ open: false, status: "idle", error: "" });
    const queue = requirementsFlowQueueRef.current;
    if (queue[0] === "marketing") {
      requirementsFlowQueueRef.current = queue.slice(1);
      const next = requirementsFlowQueueRef.current[0];
      if (next === "transport") handleTransportModalOpen();
    } else {
      requirementsFlowQueueRef.current = [];
    }
  };

  const handleItSkip = () => {
    setItModal({ open: false, status: "idle", error: "" });
    const queue = requirementsFlowQueueRef.current;
    if (queue[0] === "it") {
      requirementsFlowQueueRef.current = queue.slice(1);
      const next = requirementsFlowQueueRef.current[0];
      if (next === "marketing") handleMarketingModalOpen();
      else if (next === "transport") handleTransportModalOpen();
      else requirementsFlowQueueRef.current = [];
    } else {
      requirementsFlowQueueRef.current = [];
    }
  };

  const handleRequirementsModalClose = () => {
    setRequirementsModal({ open: false, event: null });
  };

  const handleFacilityRequestForEvent = (eventItem) => {
    setPendingEvent({ ...eventItem, event_id: eventItem?.id || eventItem?.event_id || "" });
    handleFacilityModalOpen();
  };

  const handleMarketingRequestForEvent = (eventItem) => {
    setPendingEvent({ ...eventItem, event_id: eventItem?.id || eventItem?.event_id || "" });
    handleMarketingModalOpen();
  };

  const handleItRequestForEvent = (eventItem) => {
    setPendingEvent({ ...eventItem, event_id: eventItem?.id || eventItem?.event_id || "" });
    handleItModalOpen();
  };

  const handleSendRequirements = (eventItem) => {
    if (isEventStarted(eventItem)) return;
    setPendingEvent({ ...eventItem, event_id: eventItem?.id || eventItem?.event_id || "" });
    const queue = [];
    if (eventItem.facility_status !== "approved" && eventItem.facility_status !== "pending") queue.push("facility");
    if (eventItem.it_status !== "approved" && eventItem.it_status !== "pending") queue.push("it");
    if (eventItem.marketing_status !== "approved" && eventItem.marketing_status !== "pending") queue.push("marketing");
    if (eventItem.transport_status !== "approved" && eventItem.transport_status !== "pending") {
      queue.push("transport");
    }
    requirementsFlowQueueRef.current = queue;
    if (queue[0] === "facility") handleFacilityModalOpen();
    else if (queue[0] === "it") handleItModalOpen();
    else if (queue[0] === "marketing") handleMarketingModalOpen();
    else if (queue[0] === "transport") handleTransportModalOpen();
  };

  const getExpectedReportFilename = (eventName, startDate) => {
    const sanitized = (eventName || "Event")
      .replace(/[^\w\s-]/g, "")
      .replace(/\s+/g, "_")
      .trim() || "Event";
    const datePart = (startDate || "").trim() || "0000-00-00";
    return `${sanitized}_${datePart}_Report.pdf`;
  };

  const uploadBudgetBreakdown = async (approvalId, file) => {
    if (!approvalId || !file) {
      throw new Error("Missing approval reference or budget file.");
    }
    const fd = new FormData();
    fd.append("file", file, file.name);
    const res = await api.post(`/approvals/${approvalId}/budget-breakdown`, fd);
    if (!res.ok) {
      const data = await res.json().catch(() => ({}));
      const detail = data?.detail;
      const message =
        typeof detail === "string"
          ? detail
          : Array.isArray(detail)
            ? detail.map((d) => d.msg || d).join(" ")
            : "Budget breakdown upload failed.";
      throw new Error(message);
    }
  };

  const handleReportOpen = (eventItem) => {
    setReportForm({
      executiveSummary: "",
      attendance: "",
      programAgenda: "",
      outcomesLearnings: "",
      followUp: "",
      appendix: ""
    });
    setReportAppendixPhotos([]);
    setReportIqacSelection({ criterionId: "", subFolderId: "", itemId: "", description: "" });
    setReportIqacCriteria(
      canAccessIqac ? { status: "loading", items: [], error: "" } : { status: "idle", items: [], error: "" }
    );
    setReportModal({
      open: true,
      status: "idle",
      error: "",
      eventId: eventItem.id,
      eventName: eventItem.name,
      startDate: eventItem.start_date || "",
      eventVenue: eventItem.venue_name || "",
      eventFacilitator: eventItem.facilitator || "",
      hasReport: Boolean(eventItem.report_file_id)
    });
    if (canAccessIqac) {
      (async () => {
        try {
          const res = await apiFetch(`${apiBaseUrl}/iqac/criteria`);
          if (!res.ok) {
            const data = await res.json().catch(() => ({}));
            throw new Error(data?.detail || "Could not load IQAC criteria.");
          }
          const data = await res.json();
          setReportIqacCriteria({
            status: "ready",
            items: Array.isArray(data) ? data : [],
            error: ""
          });
        } catch (err) {
          setReportIqacCriteria({
            status: "error",
            items: [],
            error: err?.message || "Could not load IQAC criteria."
          });
        }
      })();
    }
  };

  const handleEventDetailsOpen = async (eventItem) => {
    if (!eventItem?.id) return;
    if (String(eventItem.id).startsWith("approval-")) {
      handleApprovalDetailsOpen(eventItem);
      return;
    }
    setEventDetailsModal({
      open: true,
      event: eventItem,
      details: null,
      status: "loading",
      error: ""
    });
    try {
      const res = await apiFetch(`${apiBaseUrl}/events/${eventItem.id}/details`);
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data?.detail || "Failed to load event details");
      }
      const details = await res.json();
      setEventDetailsModal((prev) => ({
        ...prev,
        details,
        status: "ready",
        error: ""
      }));
    } catch (err) {
      setEventDetailsModal((prev) => ({
        ...prev,
        details: null,
        status: "error",
        error: err?.message || "Failed to load event details"
      }));
    }
  };

  const handleEventDetailsClose = () => {
    setEventDetailsModal({
      open: false,
      event: null,
      details: null,
      status: "idle",
      error: ""
    });
  };

  const handleApprovalDetailsOpen = async (requestItem) => {
    const approvalId = requestItem?.approval_request_id || requestItem?.id;
    const detailsUrl = requestItem?.event_id
      ? `${apiBaseUrl}/events/${requestItem.event_id}/details`
      : approvalId
        ? `${apiBaseUrl}/events/approval-${String(approvalId).replace(/^approval-/, "")}/details`
        : null;

    setApprovalDetailsModal({
      open: true,
      request: requestItem,
      eventDetails: null,
      detailsStatus: detailsUrl ? "loading" : "idle",
      detailsError: ""
    });
    if (!detailsUrl) return;
    try {
      const res = await apiFetch(detailsUrl);
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data?.detail || "Could not load event details");
      }
      const eventDetails = await res.json();
      setApprovalDetailsModal((prev) => ({
        ...prev,
        eventDetails,
        detailsStatus: "ready",
        detailsError: ""
      }));
    } catch (err) {
      setApprovalDetailsModal((prev) => ({
        ...prev,
        eventDetails: null,
        detailsStatus: "error",
        detailsError: err?.message || "Could not load event details"
      }));
    }
  };

  const handleApprovalDetailsClose = () => {
    setApprovalDetailsModal({
      open: false,
      request: null,
      eventDetails: null,
      detailsStatus: "idle",
      detailsError: ""
    });
  };

  const refreshApprovalDetails = useCallback(async () => {
    const requestItem = approvalDetailsModal.request;
    if (!requestItem?.id) return;
    const refreshApprovalId = requestItem.approval_request_id || requestItem.id;
    const detailsUrl = requestItem.event_id
      ? `${apiBaseUrl}/events/${requestItem.event_id}/details`
      : `${apiBaseUrl}/events/approval-${String(refreshApprovalId).replace(/^approval-/, "")}/details`;
    try {
      const res = await apiFetch(detailsUrl);
      if (!res.ok) return;
      const eventDetails = await res.json();
      setApprovalDetailsModal((prev) => ({
        ...prev,
        eventDetails,
        detailsStatus: "ready",
        detailsError: ""
      }));
    } catch {
      // ignore
    }
  }, [approvalDetailsModal.request, apiBaseUrl]);

  const isDepartmentRole =
    isFacilityManagerRole || isMarketingRole || isItRole || isTransportRole;

  const approvalDiscussionCanReply = useMemo(() => {
    const r = approvalDetailsModal.request;
    if (!r?.id || !user) return false;
    const st = String(r.status || "").toLowerCase();
    if (!["pending", "clarification_requested"].includes(st)) return false;
    if (String(user.id) === String(r.requester_id)) return true;
    if (isAdmin || isRegistrar) return true;
    const assigned = (r.requested_to || "").trim().toLowerCase();
    const em = (user.email || "").trim().toLowerCase();
    if (assigned && assigned === em && isApproverRole) return true;
    if (isDepartmentRole) return true;
    return false;
  }, [approvalDetailsModal.request, user, isAdmin, isRegistrar, isApproverRole, isDepartmentRole]);

  const normalizeMarketingRequirements = (request) => {
    const req = request?.marketing_requirements || {};
    const pre = req.pre_event || {};
    const during = req.during_event || {};
    const post = req.post_event || {};
    return {
      pre_event: {
        poster: Boolean(pre.poster ?? request?.poster_required),
        social_media: Boolean(pre.social_media ?? request?.linkedin_post)
      },
      during_event: {
        photo: Boolean(during.photo ?? request?.photography),
        video: Boolean(during.video ?? request?.video_required)
      },
      post_event: {
        social_media: Boolean(post.social_media),
        photo_upload: Boolean(post.photo_upload),
        video: Boolean(post.video ?? request?.recording)
      }
    };
  };

  const getMarketingRequirementFlags = (request) => {
    const normalized = normalizeMarketingRequirements(request);
    return {
      poster_required: normalized.pre_event.poster,
      video_required: normalized.during_event.video,
      linkedin_post: normalized.pre_event.social_media || normalized.post_event.social_media,
      photography: normalized.during_event.photo || normalized.post_event.photo_upload,
      recording: normalized.post_event.video
    };
  };

  /** Types marketing must upload (excludes during-event videoshoot and on-site photoshoot only). */
  const getMarketingDeliverableUploadFlags = (request) => {
    const normalized = normalizeMarketingRequirements(request);
    const flags = getMarketingRequirementFlags(request);
    return {
      poster_required: flags.poster_required,
      video_required: false,
      linkedin_post: flags.linkedin_post,
      photography: Boolean(normalized.post_event.photo_upload),
      recording: flags.recording
    };
  };

  const getMarketingDeliverableLabel = (deliverableType) =>
    REQUIREMENT_OPTIONS.find((o) => o.type === deliverableType)?.label || deliverableType;

  /** When uploads for this deliverable type are blocked (must match server _enforce_deliverable_upload_window). */
  const getMarketingDeliverableRowLock = (type, request) => {
    if (!request?.start_date) {
      return { locked: true, hint: "Event schedule unavailable." };
    }
    const req = normalizeMarketingRequirements(request);
    const started = isEventStarted(request);
    const ended = isEventEnded(request);
    const preSocial = req.pre_event.social_media;
    const postSocial = req.post_event.social_media;
    if (type === "poster") {
      return started
        ? { locked: true, hint: "Upload before the event starts." }
        : { locked: false, hint: "" };
    }
    if (type === "linkedin") {
      if (preSocial && !postSocial) {
        return started
          ? { locked: true, hint: "Pre-event social posts: upload before the event starts." }
          : { locked: false, hint: "" };
      }
      if (postSocial && !preSocial) {
        return !ended
          ? { locked: true, hint: "Post-event social posts: upload after the event has ended." }
          : { locked: false, hint: "" };
      }
      return started && !ended
        ? { locked: true, hint: "Upload before the event starts or after it ends (not during)." }
        : { locked: false, hint: "" };
    }
    if (type === "recording") {
      return !ended
        ? { locked: true, hint: "Post-event video: upload after the event has ended." }
        : { locked: false, hint: "" };
    }
    if (type === "photography") {
      return !ended
        ? { locked: true, hint: "Post-event photo: upload after the event has ended." }
        : { locked: false, hint: "" };
    }
    return { locked: false, hint: "" };
  };

  const hasMarketingModalActionableChoice = (request, requirements) =>
    REQUIREMENT_OPTIONS.some((opt) => {
      if (!getMarketingDeliverableUploadFlags(request || {})[opt.key]) return false;
      const r = requirements?.[opt.type];
      if (!r?.na && !r?.file) return false;
      return !getMarketingDeliverableRowLock(opt.type, request).locked;
    });

  const openMarketingDeliverableModal = (request) => {
    const uploadFlags = getMarketingDeliverableUploadFlags(request);
    const hasUploadable = REQUIREMENT_OPTIONS.some((opt) => uploadFlags[opt.key]);
    if (!hasUploadable) {
      setStatus({
        type: "info",
        message:
          "This request only includes during-event marketing (videoshoot / on-site photoshoot). No file uploads are required."
      });
      return;
    }
    const requirements = {};
    REQUIREMENT_OPTIONS.forEach(({ key, type }) => {
      if (uploadFlags[key]) {
        const existing = request.deliverables?.find((d) => d.deliverable_type === type);
        requirements[type] = {
          na: !!existing?.is_na,
          file: null
        };
      }
    });
    setMarketingDeliverableModal({
      open: true,
      request,
      requirements,
      status: "idle",
      error: ""
    });
  };

  const closeMarketingDeliverableModal = () => {
    setMarketingDeliverableModal({
      open: false,
      request: null,
      requirements: {},
      status: "idle",
      error: ""
    });
  };

  const submitMarketingDeliverable = async (e) => {
    e.preventDefault();
    const { request, requirements } = marketingDeliverableModal;
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setMarketingDeliverableModal((prev) => ({ ...prev, status: "error", error: "Please sign in again." }));
      return;
    }
    if (!request?.id || !hasMarketingModalActionableChoice(request, requirements)) {
      setMarketingDeliverableModal((prev) => ({
        ...prev,
        status: "error",
        error: "For at least one deliverable that is open for upload now, select NA or choose a file."
      }));
      return;
    }
    setMarketingDeliverableModal((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const formData = new FormData();
      const uploadFlags = getMarketingDeliverableUploadFlags(request);
      REQUIREMENT_OPTIONS.forEach(({ key, type }) => {
        if (!uploadFlags[key]) return;
        const r = requirements?.[type];
        if (!r) return;
        if (r.na) {
          formData.append(`na_${type}`, "1");
        } else if (r.file) {
          formData.append(`file_${type}`, r.file);
        }
      });
      const res = await apiFetch(`${apiBaseUrl}/marketing/requests/${request.id}/deliverables/batch`, {
        method: "POST",
        body: formData
      });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        const msg = data?.detail || "Unable to upload deliverables.";
        throw new Error(typeof msg === "string" ? msg : JSON.stringify(msg));
      }
      closeMarketingDeliverableModal();
      loadMarketingInbox();
      setStatus({ type: "success", message: "Deliverables saved." });
    } catch (err) {
      setMarketingDeliverableModal((prev) => ({
        ...prev,
        status: "error",
        error: err?.message || "Unable to upload deliverables."
      }));
    }
  };

  const handleReportClose = () => {
    setReportForm({
      executiveSummary: "",
      attendance: "",
      programAgenda: "",
      outcomesLearnings: "",
      followUp: "",
      appendix: ""
    });
    setReportAppendixPhotos([]);
    setReportIqacSelection({ criterionId: "", subFolderId: "", itemId: "", description: "" });
    setReportIqacCriteria({ status: "idle", items: [], error: "" });
    setReportModal({ open: false, status: "idle", error: "", eventId: "", eventName: "", startDate: "", eventVenue: "", eventFacilitator: "", hasReport: false });
  };

  const handleAppendixPhotosChange = (e) => {
    const files = e.target.files ? Array.from(e.target.files) : [];
    const imageFiles = files.filter((f) => f.type.startsWith("image/"));
    setReportAppendixPhotos((prev) => [...prev, ...imageFiles]);
    e.target.value = "";
  };

  const removeAppendixPhoto = (index) => {
    setReportAppendixPhotos((prev) => prev.filter((_, i) => i !== index));
  };

  const handleReportFormChange = (field) => (e) => {
    setReportForm((prev) => ({ ...prev, [field]: e.target.value }));
  };

  const handleReportIqacCriterionChange = (e) => {
    const v = e.target.value;
    setReportIqacSelection((prev) => ({
      criterionId: v,
      subFolderId: "",
      itemId: "",
      description: prev.description
    }));
  };

  const handleReportIqacSubChange = (e) => {
    setReportIqacSelection((prev) => ({ ...prev, subFolderId: e.target.value, itemId: "" }));
  };

  const handleReportIqacItemChange = (e) => {
    setReportIqacSelection((prev) => ({ ...prev, itemId: e.target.value }));
  };

  const handleReportIqacDescChange = (e) => {
    setReportIqacSelection((prev) => ({ ...prev, description: e.target.value }));
  };

  const buildReportPdf = (eventInfo, form) => {
    const doc = new jsPDF({ format: "a4", unit: "mm" });
    const margin = 20;
    const pageW = doc.internal.pageSize.getWidth();
    const maxW = pageW - margin * 2;
    let y = margin;
    const lineHeight = 5;
    const sectionGap = 10;

    const wrapText = (text, maxWidth) => {
      if (typeof doc.splitTextToSize === "function") {
        return doc.splitTextToSize(String(text).trim(), maxWidth);
      }
      const charsPerLine = Math.floor(maxWidth / 3.5);
      const words = String(text).trim().split(/\s+/);
      const lines = [];
      let line = "";
      for (const word of words) {
        if (line.length + word.length + 1 <= charsPerLine) {
          line += (line ? " " : "") + word;
        } else {
          if (line) lines.push(line);
          line = word;
        }
      }
      if (line) lines.push(line);
      return lines;
    };

    const addSection = (title, text, isSubsection = false) => {
      if (y > 270) {
        doc.addPage();
        y = margin;
      }
      doc.setFontSize(isSubsection ? 10 : 12);
      doc.setFont("helvetica", isSubsection ? "normal" : "bold");
      doc.text(title, margin, y);
      y += lineHeight + 2;
      doc.setFont("helvetica", "normal");
      doc.setFontSize(10);
      if (text && String(text).trim()) {
        const lines = wrapText(text, maxW);
        doc.text(lines, margin, y);
        y += lines.length * lineHeight;
      }
      y += sectionGap;
    };

    const reportDate = new Date().toISOString().slice(0, 10);

    addSection("Cover", "");
    doc.setFontSize(10);
    doc.setFont("helvetica", "normal");
    doc.text(`Event: ${eventInfo.eventName || "—"}`, margin, y); y += lineHeight;
    doc.text(`Date: ${eventInfo.startDate || "—"}`, margin, y); y += lineHeight;
    doc.text(`Venue: ${eventInfo.eventVenue || "—"}`, margin, y); y += lineHeight;
    doc.text(`Facilitator: ${eventInfo.eventFacilitator || "—"}`, margin, y); y += lineHeight;
    doc.text(`Report submitted on: ${reportDate}`, margin, y); y += sectionGap + lineHeight;

    addSection("Executive Summary", form.executiveSummary);
    addSection("Attendance", form.attendance);
    addSection("Program / Agenda", form.programAgenda);
    addSection("Outcomes and Learnings", form.outcomesLearnings);
    if (form.followUp && form.followUp.trim()) addSection("Follow-up", form.followUp);
    const hasAppendixText = form.appendix && form.appendix.trim();
    const appendixImages = eventInfo.appendixImages || [];
    if (hasAppendixText || appendixImages.length > 0) {
      addSection("Appendix", form.appendix || "");
      if (appendixImages.length > 0) {
        const imgMaxW = maxW;
        const imgMaxH = 60;
        const pxToMm = 25.4 / 96;
        for (let i = 0; i < appendixImages.length; i++) {
          if (y > 270) {
            doc.addPage();
            y = margin;
          }
          const { dataUrl, width: pw, height: ph } = appendixImages[i];
          const format = dataUrl.startsWith("data:image/png") ? "PNG" : dataUrl.startsWith("data:image/webp") ? "WEBP" : dataUrl.startsWith("data:image/gif") ? "GIF" : "JPEG";
          try {
            let wMm = pw * pxToMm;
            let hMm = ph * pxToMm;
            if (wMm > imgMaxW || hMm > imgMaxH) {
              const r = Math.min(imgMaxW / wMm, imgMaxH / hMm);
              wMm = wMm * r;
              hMm = hMm * r;
            }
            doc.addImage(dataUrl, format, margin, y, wMm, hMm);
            y += hMm + sectionGap;
          } catch (_) {
            doc.setFontSize(9);
            doc.text(`[Image ${i + 1} could not be embedded]`, margin, y);
            y += lineHeight + 4;
          }
        }
      }
    }

    return doc.output("blob");
  };

  const handlePublicationTypeOpen = () => {
    setPublicationTypeModal({ open: true });
  };

  const handlePublicationTypeClose = () => {
    setPublicationTypeModal({ open: false });
  };

  const handlePublicationTypeSelect = (pubType) => {
    setPublicationTypeModal({ open: false });
    setPublicationForm({
      name: "",
      title: "",
      pubType,
      file: null,
      others: "",
      author_first_name: "",
      author_last_name: "",
      publication_date: "",
      url: "",
      article_title: "",
      journal_name: "",
      volume: "",
      issue: "",
      pages: "",
      doi: "",
      year: "",
      book_title: "",
      publisher: "",
      edition: "",
      page_number: "",
      organization: "",
      report_title: "",
      creator: "",
      video_title: "",
      platform: "",
      newspaper_name: "",
      website_name: "",
      page_title: ""
    });
    setPublicationModal({ open: true, status: "idle", error: "" });
  };

  const handlePublicationOpen = () => {
    handlePublicationTypeOpen();
  };

  const handlePublicationClose = () => {
    setPublicationModal({ open: false, status: "idle", error: "" });
  };

  const handlePublicationChange = (field) => (event) => {
    if (field === "file") {
      setPublicationForm((prev) => ({ ...prev, file: event.target.files?.[0] || null }));
      return;
    }
    setPublicationForm((prev) => ({ ...prev, [field]: event.target.value }));
  };

  const submitPublication = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const f = publicationForm;
    const pt = f.pubType;
    // Validate required fields per type
    let validationError = null;
    if (!f.name) validationError = "Please provide a label/name for this record.";
    else if (pt === "webpage" && (!f.author_first_name || !f.author_last_name || !f.page_title || !f.website_name || !f.url)) validationError = "Please fill all required fields.";
    else if (pt === "journal_article" && (!f.author_first_name || !f.author_last_name || !f.article_title || !f.journal_name || !f.year)) validationError = "Please fill all required fields.";
    else if (pt === "book" && (!f.author_first_name || !f.author_last_name || !f.book_title || !f.publisher || !f.year)) validationError = "Please fill all required fields.";
    else if (pt === "report" && (!f.organization || !f.report_title || !f.year || !f.publisher)) validationError = "Please fill all required fields.";
    else if (pt === "video" && (!f.creator || !f.video_title || !f.platform || !f.publication_date || !f.url)) validationError = "Please fill all required fields.";
    else if (pt === "online_newspaper" && (!f.author_first_name || !f.author_last_name || !f.article_title || !f.newspaper_name || !f.publication_date || !f.url)) validationError = "Please fill all required fields.";
    if (validationError) {
      setPublicationModal({ open: true, status: "error", error: validationError });
      return;
    }
    setPublicationModal({ open: true, status: "loading", error: "" });
    try {
      const formData = new FormData();
      formData.append("name", f.name);
      formData.append("title", f.title || f.name);
      formData.append("pub_type", pt);
      if (f.others) formData.append("others", f.others);
      if (f.file) formData.append("file", f.file);
      const derivedAuthor = [f.author_first_name, f.author_last_name].map((v) => (v || "").trim()).filter(Boolean).join(" ");
      if (derivedAuthor) formData.append("author", derivedAuthor);
      // Append all optional fields if present
      const optionals = ["author_first_name","author_last_name","publication_date","url","article_title","journal_name","volume","issue","pages","doi","year","book_title","publisher","edition","page_number","organization","report_title","creator","video_title","platform","newspaper_name","website_name","page_title"];
      optionals.forEach((key) => {
        if (f[key]) formData.append(key, f[key]);
      });
      const res = await apiFetch(`${apiBaseUrl}/publications`, {
        method: "POST",
        body: formData
      });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        const message = data?.detail || "Unable to submit publication.";
        throw new Error(message);
      }
      setStatus({ type: "success", message: "Publication submitted." });
      handlePublicationClose();
      loadPublications();
    } catch (err) {
      setPublicationModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to submit publication."
      });
    }
  };

  const handleCloseEvent = async (eventItem) => {
    if (!eventItem?.id) return;
    try {
      const res = await apiFetch(`${apiBaseUrl}/events/${eventItem.id}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: "closed" })
      });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        const message = data?.detail || "Unable to close event.";
        throw new Error(message);
      }
      loadEvents();
    } catch (err) {
      setStatus({ type: "error", message: err?.message || "Unable to close event." });
    }
  };

  const handleViewReport = (eventItem) => {
    if (eventItem?.report_web_view_link) {
      window.open(eventItem.report_web_view_link, "_blank", "noopener,noreferrer");
      return;
    }
    setStatus({ type: "error", message: "Report link unavailable." });
  };

  const handleInviteFieldChange = (field) => (event) => {
    setInviteForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const submitReport = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const required = [
      { key: "executiveSummary", label: "Executive summary" },
      { key: "attendance", label: "Attendance" },
      { key: "programAgenda", label: "Program / agenda" },
      { key: "outcomesLearnings", label: "Outcomes and learnings" }
    ];
    const missing = required.find((r) => !reportForm[r.key] || !String(reportForm[r.key]).trim());
    if (missing) {
      setReportModal((prev) => ({
        ...prev,
        status: "error",
        error: `Please fill in: ${missing.label}`
      }));
      return;
    }

    const sel = reportIqacSelection;
    const iqacComplete = Boolean(sel.criterionId && sel.subFolderId && sel.itemId);
    if ((sel.criterionId || sel.subFolderId || sel.itemId) && !iqacComplete) {
      setReportModal((prev) => ({
        ...prev,
        status: "error",
        error: "Select IQAC criterion, sub-criterion, and evidence item, or clear the IQAC dropdown to skip."
      }));
      return;
    }

    setReportModal((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      const appendixImages = [];
      for (const file of reportAppendixPhotos) {
        const dataUrl = await new Promise((resolve, reject) => {
          const r = new FileReader();
          r.onload = () => resolve(r.result);
          r.onerror = reject;
          r.readAsDataURL(file);
        });
        const { width, height } = await new Promise((resolve, reject) => {
          const img = new Image();
          img.onload = () => resolve({ width: img.naturalWidth, height: img.naturalHeight });
          img.onerror = reject;
          img.src = dataUrl;
        });
        appendixImages.push({ dataUrl, width, height });
      }
      const blob = buildReportPdf(
        {
          eventName: reportModal.eventName,
          startDate: reportModal.startDate,
          eventVenue: reportModal.eventVenue,
          eventFacilitator: reportModal.eventFacilitator,
          appendixImages
        },
        reportForm
      );
      const expectedName = getExpectedReportFilename(reportModal.eventName, reportModal.startDate);
      const file = new File([blob], expectedName, { type: "application/pdf" });
      const formData = new FormData();
      formData.append("file", file);
      if (iqacComplete) {
        formData.append("iqac_criterion", String(sel.criterionId));
        formData.append("iqac_sub_folder", sel.subFolderId);
        formData.append("iqac_item", sel.itemId);
        if (sel.description.trim()) {
          formData.append("iqac_description", sel.description.trim());
        }
      }
      const res = await apiFetch(`${apiBaseUrl}/events/${reportModal.eventId}/report`, {
        method: "POST",
        body: formData
      });

      if (!res.ok) {
        const data = await res.json().catch(() => null);
        const message = data?.detail || "Unable to upload report.";
        throw new Error(message);
      }

      handleReportClose();
      loadEvents();
    } catch (err) {
      setReportModal((prev) => ({
        ...prev,
        status: "error",
        error: err?.message || "Unable to upload report."
      }));
    }
  };

  const formatStatusLabel = (value) => {
    if (!value) {
      return "";
    }
    return value
      .split("_")
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join(" ");
  };
  const getEventStatusInfo = (event) => {
    const statusValue = event.status || "";
    const explicitStatus = statusValue ? formatStatusLabel(statusValue) : null;
    const hasApprovalData =
      event.approval_status ||
      event.facility_status ||
      event.transport_status ||
      event.marketing_status ||
      event.it_status;
    let derivedStatus = "Approved";
    if (hasApprovalData) {
      const statuses = [
        event.approval_status,
        event.facility_status,
        event.transport_status,
        event.marketing_status,
        event.it_status
      ];
      if (statuses.includes("rejected")) {
        derivedStatus = "Rejected";
      } else if (statuses.every((status) => status === "approved")) {
        derivedStatus = "Approved";
      } else {
        derivedStatus = "Pending";
      }
    }
    const statusLabel =
      event.approval_status === "approved"
        ? "Approved"
        : explicitStatus || derivedStatus;
    const statusClass = (statusValue || statusLabel).toLowerCase().replace(/\s+/g, "-");
    return { statusLabel, statusClass };
  };

  const getNormalizedEventStatus = (event) => {
    const { statusLabel } = getEventStatusInfo(event);
    return (statusLabel || "").toLowerCase();
  };

  /** True if event start date/time is in the past (event has started); no actions allowed once started. */
  const isEventStarted = (event) => {
    if (!event || !event.start_date) return false;
    const startStr = `${event.start_date}T${normalizeTimeToHHMMSS(event.start_time)}`;
    const start = new Date(startStr);
    return !Number.isNaN(start.getTime()) && start <= new Date();
  };

  /** True if event end is in the past (uses end_date/end_time, or start_date if end_date missing). */
  const isEventEnded = (event) => {
    if (!event) return false;
    const dateStr = (event.end_date || event.start_date || "").trim();
    if (!dateStr) return false;
    const endStr = `${dateStr}T${normalizeTimeToHHMMSS(event.end_time ?? event.start_time)}`;
    const end = new Date(endStr);
    return !Number.isNaN(end.getTime()) && end <= new Date();
  };

  const isBudgetBreakdownPdf = (file) => {
    if (!file) return false;
    const name = (file.name || "").toLowerCase();
    const type = (file.type || "").toLowerCase();
    return type === "application/pdf" || name.endsWith(".pdf");
  };

  const submitEvent = async (formEvent, override) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const completedWithReportPendingCount = eventsState.items.filter((event) => {
      const isApprovalItem = String(event.id || "").startsWith("approval-");
      if (isApprovalItem) return false;
      if ((event.status || "").toLowerCase() !== "completed") return false;
      return !event.report_file_id;
    }).length;
    if (completedWithReportPendingCount >= 5) {
      setEventFormStatus({
        status: "error",
        error: "Upload reports for at least some completed events (5 or more have report pending) before creating a new one."
      });
      return;
    }
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setEventFormStatus({ status: "error", error: "Please sign in again." });
      return;
    }

    if (!budgetBreakdownFile || !isBudgetBreakdownPdf(budgetBreakdownFile)) {
      setEventFormStatus({
        status: "error",
        error: "Budget breakdown PDF is required. Choose a PDF file before continuing."
      });
      return;
    }

    setEventFormStatus({ status: "loading", error: "" });

    try {
      const parsedStart = timePartsTo24(eventTimeParts.start_time);
      const parsedEnd = timePartsTo24(eventTimeParts.end_time);
      if (!parsedStart || !parsedEnd) {
        setEventFormStatus({
          status: "error",
          error: "Select hour, minute and AM/PM for start and end time."
        });
        return;
      }
      const budgetVal = eventForm.budget && !isNaN(parseFloat(eventForm.budget)) && parseFloat(eventForm.budget) >= 0
        ? parseFloat(eventForm.budget) : null;
      const payload = override
        ? { ...eventForm, start_time: parsedStart, end_time: parsedEnd, override_conflict: true, budget: budgetVal }
        : { ...eventForm, start_time: parsedStart, end_time: parsedEnd, budget: budgetVal };
      const idemKey = generateIdempotencyKey();
      const res = await apiFetch(`${apiBaseUrl}/events`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(idemKey && { "Idempotency-Key": idemKey })
        },
        body: JSON.stringify(payload)
      });

      if (res.status === 409) {
        const data = await res.json();
        setConflictState({
          open: true,
          items: data?.conflicts || []
        });
        setEventFormStatus({ status: "idle", error: "" });
        return;
      }

      if (!res.ok) {
        const message = res.status === 400 ? "Check your date/time inputs." : "Unable to create event.";
        throw new Error(message);
      }

      const data = await res.json();
      try {
        await uploadBudgetBreakdown(data?.approval_request?.id, budgetBreakdownFile);
      } catch (uploadErr) {
        setEventFormStatus({
          status: "error",
          error:
            uploadErr?.message ||
            "Budget breakdown upload failed. Your request was created—open your pending request and try uploading again, or contact support."
        });
        loadEvents();
        return;
      }

      setEventForm({
        start_date: "",
        end_date: "",
        start_time: "",
        end_time: "",
        name: "",
        facilitator: defaultFacilitator,
        venue_name: "",
        intendedAudience: "",
        description: "",
        budget: ""
      });
      setBudgetBreakdownFile(null);
      if (budgetBreakdownInputRef.current) {
        budgetBreakdownInputRef.current.value = "";
      }
      setEventTimeParts({
        start_time: { hour: "", minute: "", period: "AM" },
        end_time: { hour: "", minute: "", period: "AM" }
      });
      setIsEventModalOpen(false);
      setConflictState({ open: false, items: [] });
      loadEvents();
    } catch (err) {
      setEventFormStatus({
        status: "error",
        error: err?.message || "Unable to create event."
      });
    }
  };

  const submitApprovalRequest = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setApprovalModal({
        open: true,
        status: "error",
        error: "Please sign in again."
      });
      return;
    }

    if (!budgetBreakdownFile || !isBudgetBreakdownPdf(budgetBreakdownFile)) {
      setApprovalModal({
        open: true,
        status: "error",
        error: "Budget breakdown PDF is required. Choose a PDF file before continuing."
      });
      return;
    }

    setApprovalModal((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      // Registrar receives only event details. Requirements go to Facility Manager after approval.
      const budgetVal = eventForm.budget && !isNaN(parseFloat(eventForm.budget)) && parseFloat(eventForm.budget) >= 0
        ? parseFloat(eventForm.budget) : null;
      const payload = {
        ...eventForm,
        budget: budgetVal,
        requirements: [],
        other_notes: "",
        override_conflict: overrideConflict
      };

      const idemKey = generateIdempotencyKey();
      const res = await apiFetch(`${apiBaseUrl}/events`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(idemKey && { "Idempotency-Key": idemKey })
        },
        body: JSON.stringify(payload)
      });

      if (res.status === 409) {
        const data = await res.json().catch(() => ({}));
        setApprovalModal({
          open: true,
          status: "error",
          error: "Schedule conflict detected. Try rescheduling or choose Override in the conflict dialog."
        });
        return;
      }

      if (!res.ok) {
        throw new Error("Unable to send approval request.");
      }

      const data = await res.json();
      try {
        await uploadBudgetBreakdown(data?.approval_request?.id, budgetBreakdownFile);
      } catch (uploadErr) {
        setApprovalModal({
          open: true,
          status: "error",
          error:
            uploadErr?.message ||
            "Budget breakdown upload failed. Your request was created—try sending the PDF again from your pending list or contact support."
        });
        loadEvents();
        return;
      }

      setApprovalModal({ open: false, status: "idle", error: "" });
      setOverrideConflict(false);
      resetEventFormState();
      setIsEventModalOpen(false);
      setConflictState({ open: false, items: [] });
      loadEvents();
      setStatus({ type: "success", message: "Event sent to registrar for approval." });
    } catch (err) {
      setApprovalModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send approval request."
      });
    }
  };

  const submitFacilityRequest = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setFacilityModal({
        open: true,
        status: "error",
        error: "Please sign in again."
      });
      return;
    }

    setFacilityModal((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      const eventPayload = pendingEvent || eventForm;
      const payload = {
        requested_to: facilityForm.to || undefined,
        event_id: eventPayload?.event_id || eventPayload?.id || "",
        event_name: eventPayload?.name || "",
        start_date: eventPayload?.start_date || "",
        start_time: eventPayload?.start_time || "",
        end_date: eventPayload?.end_date || "",
        end_time: eventPayload?.end_time || "",
        venue_required: facilityForm.venue_required,
        refreshments: facilityForm.refreshments,
        other_notes: facilityForm.other_notes || ""
      };

      const res = await apiFetch(`${apiBaseUrl}/facility/requests`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        throw new Error("Unable to send facility manager request.");
      }

      setFacilityModal({ open: false, status: "idle", error: "" });
      setRequirementsModal((prev) => (prev.open ? { ...prev, open: false, event: null } : prev));
      setStatus({ type: "success", message: "Facility manager request submitted." });
      loadEvents();
      const queue = requirementsFlowQueueRef.current;
      if (queue[0] === "facility") {
        requirementsFlowQueueRef.current = queue.slice(1);
        const next = requirementsFlowQueueRef.current[0];
        if (next === "it") handleItModalOpen();
        else if (next === "marketing") handleMarketingModalOpen();
        else if (next === "transport") handleTransportModalOpen();
      }
    } catch (err) {
      setFacilityModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send facility manager request."
      });
    }
  };

  const submitTransportRequest = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setTransportModal({
        open: true,
        status: "error",
        error: "Please sign in again."
      });
      return;
    }

    const eventPayload = pendingEvent || eventForm;
    const wantsGuest = Boolean(transportForm.include_guest_cab);
    const wantsStudents = Boolean(transportForm.include_students);
    if (!wantsGuest && !wantsStudents) {
      setTransportModal({
        open: true,
        status: "error",
        error: "Select at least one: cab for guest and/or students (off-campus)."
      });
      return;
    }
    if (wantsGuest) {
      const missing = [
        transportForm.guest_pickup_location,
        transportForm.guest_pickup_date,
        transportForm.guest_pickup_time,
        transportForm.guest_dropoff_location,
        transportForm.guest_dropoff_time
      ].some((v) => !(v || "").trim());
      if (missing) {
        setTransportModal({
          open: true,
          status: "error",
          error: "Fill guest cab: pickup location, pickup date & time, drop-off location, and drop-off time."
        });
        return;
      }
    }
    if (wantsStudents) {
      const n = parseInt(String(transportForm.student_count || "").trim(), 10);
      const missingStudents =
        !Number.isFinite(n) ||
        n < 1 ||
        !(transportForm.student_transport_kind || "").trim() ||
        !(transportForm.student_date || "").trim() ||
        !(transportForm.student_time || "").trim() ||
        !(transportForm.student_pickup_point || "").trim();
      if (missingStudents) {
        setTransportModal({
          open: true,
          status: "error",
          error: "Fill student transport: number of students, kind, date, time, and pickup point."
        });
        return;
      }
    }
    const transport_type =
      wantsGuest && wantsStudents ? "both" : wantsGuest ? "guest_cab" : "students_off_campus";

    setTransportModal((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      const studentCountParsed = parseInt(String(transportForm.student_count || "").trim(), 10);
      const payload = {
        requested_to: transportForm.to || undefined,
        event_id: eventPayload?.event_id || eventPayload?.id || "",
        event_name: eventPayload?.name || "",
        start_date: eventPayload?.start_date || "",
        start_time: eventPayload?.start_time || "",
        end_date: eventPayload?.end_date || "",
        end_time: eventPayload?.end_time || "",
        transport_type,
        guest_pickup_location: wantsGuest ? transportForm.guest_pickup_location || undefined : undefined,
        guest_pickup_date: wantsGuest ? transportForm.guest_pickup_date || undefined : undefined,
        guest_pickup_time: wantsGuest ? transportForm.guest_pickup_time || undefined : undefined,
        guest_dropoff_location: wantsGuest ? transportForm.guest_dropoff_location || undefined : undefined,
        guest_dropoff_date: wantsGuest ? transportForm.guest_dropoff_date || undefined : undefined,
        guest_dropoff_time: wantsGuest ? transportForm.guest_dropoff_time || undefined : undefined,
        student_count:
          wantsStudents && Number.isFinite(studentCountParsed) ? studentCountParsed : undefined,
        student_transport_kind: wantsStudents ? transportForm.student_transport_kind || undefined : undefined,
        student_date: wantsStudents ? transportForm.student_date || undefined : undefined,
        student_time: wantsStudents ? transportForm.student_time || undefined : undefined,
        student_pickup_point: wantsStudents ? transportForm.student_pickup_point || undefined : undefined,
        other_notes: transportForm.other_notes || ""
      };

      const res = await apiFetch(`${apiBaseUrl}/transport/requests`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        const detail = errData?.detail;
        const msg =
          typeof detail === "string"
            ? detail
            : Array.isArray(detail)
              ? detail.map((d) => d.msg || JSON.stringify(d)).join(" ")
              : "Unable to send transport request.";
        throw new Error(msg);
      }

      setTransportModal({ open: false, status: "idle", error: "" });
      setRequirementsModal((prev) => (prev.open ? { ...prev, open: false, event: null } : prev));
      setStatus({ type: "success", message: "Transport request submitted." });
      loadEvents();
      const queue = requirementsFlowQueueRef.current;
      if (queue[0] === "transport") {
        requirementsFlowQueueRef.current = queue.slice(1);
      }
    } catch (err) {
      setTransportModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send transport request."
      });
    }
  };

  const submitMarketingRequest = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setMarketingModal({
        open: true,
        status: "error",
        error: "Please sign in again."
      });
      return;
    }

    setMarketingModal((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      const eventPayload = pendingEvent || eventForm;
      const payload = {
        requested_to: marketingForm.to,
        event_id: eventPayload?.event_id || eventPayload?.id || "",
        event_name: eventPayload?.name || "",
        start_date: eventPayload?.start_date || "",
        start_time: eventPayload?.start_time || "",
        end_date: eventPayload?.end_date || "",
        end_time: eventPayload?.end_time || "",
        marketing_requirements: marketingForm.marketing_requirements,
        other_notes: marketingForm.other_notes
      };

      const res = await apiFetch(`${apiBaseUrl}/marketing/requests`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        throw new Error("Unable to send marketing request.");
      }

      setMarketingModal({ open: false, status: "idle", error: "" });
      setStatus({ type: "success", message: "Marketing request submitted." });
      loadEvents();
      const queue = requirementsFlowQueueRef.current;
      if (queue[0] === "marketing") {
        requirementsFlowQueueRef.current = queue.slice(1);
        const next = requirementsFlowQueueRef.current[0];
        if (next === "transport") handleTransportModalOpen();
      } else {
        requirementsFlowQueueRef.current = [];
      }
    } catch (err) {
      setMarketingModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send marketing request."
      });
    }
  };

  const submitItRequest = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setItModal({
        open: true,
        status: "error",
        error: "Please sign in again."
      });
      return;
    }

    setItModal((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      const eventPayload = pendingEvent || eventForm;
      const payload = {
        requested_to: itForm.to,
        event_id: eventPayload?.event_id || eventPayload?.id || "",
        event_name: eventPayload?.name || "",
        start_date: eventPayload?.start_date || "",
        start_time: eventPayload?.start_time || "",
        end_date: eventPayload?.end_date || "",
        end_time: eventPayload?.end_time || "",
        event_mode: itForm.event_mode || "offline",
        pa_system: itForm.pa_system,
        projection: itForm.projection,
        other_notes: itForm.other_notes
      };

      const res = await apiFetch(`${apiBaseUrl}/it/requests`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        throw new Error("Unable to send IT request.");
      }

      setItModal({ open: false, status: "idle", error: "" });
      setStatus({ type: "success", message: "IT request submitted." });
      loadEvents();
      const queue = requirementsFlowQueueRef.current;
      if (queue[0] === "it") {
        requirementsFlowQueueRef.current = queue.slice(1);
        const next = requirementsFlowQueueRef.current[0];
        if (next === "marketing") handleMarketingModalOpen();
      }
    } catch (err) {
      setItModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send IT request."
      });
    }
  };

  const submitInvite = async (formEvent) => {
    if (formEvent) {
      formEvent.preventDefault();
    }

    if (!inviteForm.to.trim()) {
      setInviteModal({ open: true, status: "error", error: "Recipient email is required." });
      return;
    }

    const token = localStorage.getItem("auth_token");
    if (!token) {
      setInviteModal({ open: true, status: "error", error: "Please sign in again." });
      return;
    }

    if (!inviteContext.eventId) {
      setInviteModal({ open: true, status: "error", error: "Event is missing." });
      return;
    }

    setInviteModal({ open: true, status: "loading", error: "" });

    try {
      const res = await apiFetch(`${apiBaseUrl}/invites`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          event_id: inviteContext.eventId,
          to_email: inviteForm.to,
          subject: inviteForm.subject,
          body: inviteForm.description
        })
      });

      if (res.status === 403) {
        throw new Error("Connect Google to send invites.");
      }

      if (!res.ok) {
        throw new Error("Unable to send invite.");
      }

      setInviteModal({ open: false, status: "idle", error: "" });
      setInviteForm({ to: "", subject: "", description: "" });
      setInviteContext({ eventId: "", eventName: "", startDate: "", startTime: "" });
      loadEvents();
    } catch (err) {
      setInviteModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send invite."
      });
    }
  };

  const handleEventSubmit = async (event) => {
    if (event) {
      event.preventDefault();
    }

    const token = localStorage.getItem("auth_token");
    if (!token) {
      setEventFormStatus({ status: "error", error: "Please sign in again." });
      return;
    }

    if (!budgetBreakdownFile || !isBudgetBreakdownPdf(budgetBreakdownFile)) {
      setEventFormStatus({
        status: "error",
        error: "Budget breakdown PDF is required. Choose a PDF file before continuing."
      });
      return;
    }

    setEventFormStatus({ status: "loading", error: "" });

    try {
      const parsedStart = timePartsTo24(eventTimeParts.start_time);
      const parsedEnd = timePartsTo24(eventTimeParts.end_time);
      if (!parsedStart || !parsedEnd) {
        setEventFormStatus({
          status: "error",
          error: "Select hour, minute and AM/PM for start and end time."
        });
        return;
      }
      const normalizedEventForm = {
        ...eventForm,
        start_time: parsedStart,
        end_time: parsedEnd
      };
      const res = await apiFetch(`${apiBaseUrl}/events/conflicts`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(normalizedEventForm)
      });

      if (!res.ok) {
        const message = res.status === 400 ? "Check your date/time inputs." : "Unable to check conflicts.";
        throw new Error(message);
      }

      const data = await res.json();
      if (data?.conflicts?.length) {
        setConflictState({ open: true, items: data.conflicts });
        setEventFormStatus({ status: "idle", error: "" });
        return;
      }

      setIsEventModalOpen(false);
      setEventFormStatus({ status: "idle", error: "" });
      setEventForm(normalizedEventForm);
      handleApprovalModalOpen();
    } catch (err) {
      setEventFormStatus({
        status: "error",
        error: err?.message || "Unable to check conflicts."
      });
    }
  };

  const handleConflictReschedule = () => {
    setOverrideConflict(false);
    setConflictState({ open: false, items: [] });
  };

  const handleConflictApprovalRequest = () => {
    if (!budgetBreakdownFile || !isBudgetBreakdownPdf(budgetBreakdownFile)) {
      setConflictState({ open: false, items: [] });
      setEventFormStatus({
        status: "error",
        error: "Budget breakdown PDF is required. Choose a PDF file before continuing."
      });
      return;
    }
    setOverrideConflict(true);
    setConflictState({ open: false, items: [] });
    setIsEventModalOpen(false);
    handleApprovalModalOpen();
  };

  const handleConflictCancel = () => {
    setOverrideConflict(false);
    setIsEventModalOpen(false);
    setConflictState({ open: false, items: [] });
  };

  const handleEventFieldChange = (field) => (event) => {
    setEventForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const handleEventTimePartChange = (field, key) => (event) => {
    const value = event.target.value;
    setEventTimeParts((prev) => {
      const nextField = { ...prev[field], [key]: value };
      const parsed = timePartsTo24(nextField);
      setEventForm((current) => ({
        ...current,
        [field]: parsed || ""
      }));
      return { ...prev, [field]: nextField };
    });
  };

  const handleApprovalFieldChange = (field) => (event) => {
    setApprovalForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const handleApprovalRequirementChange = (field) => (event) => {
    setApprovalForm((prev) => ({
      ...prev,
      requirements: {
        ...prev.requirements,
        [field]: event.target.checked
      }
    }));
  };

  const handleFacilityFieldChange = (field) => (event) => {
    setFacilityForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const handleFacilityToggle = (field) => (event) => {
    setFacilityForm((prev) => ({
      ...prev,
      [field]: event.target.checked
    }));
  };

  const handleTransportFieldChange = (field) => (event) => {
    setTransportForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const handleMarketingFieldChange = (field) => (event) => {
    setMarketingForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const handleMarketingToggle = (group, field) => (event) => {
    setMarketingForm((prev) => ({
      ...prev,
      marketing_requirements: {
        ...prev.marketing_requirements,
        [group]: {
          ...(prev.marketing_requirements?.[group] || {}),
          [field]: event.target.checked
        }
      }
    }));
  };

  const handleItFieldChange = (field) => (event) => {
    setItForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const handleItToggle = (field) => (event) => {
    setItForm((prev) => ({
      ...prev,
      [field]: event.target.checked
    }));
  };

  const handleCalendarConnect = async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setCalendarState({
        status: "needs_auth",
        events: [],
        error: "Missing auth token."
      });
      return;
    }

    try {
      const res = await apiFetch(`${apiBaseUrl}/calendar/connect-url`);

      if (!res.ok) {
        throw new Error("Unable to start Google Calendar auth.");
      }

      const data = await res.json();
      if (data?.url) {
        setGoogleScopeModal({ open: false, missing: [] });
        window.open(data.url, "_blank", "noopener,noreferrer");
      }
    } catch (err) {
      setCalendarState({
        status: "error",
        events: [],
        error: err?.message || "Unable to start Google Calendar auth."
      });
    }
  };

  if (user) {
    const profileName = user?.name || "Annisa Thalia";
    const profileRole = (user?.role || "Event Manager").toUpperCase();
    const normalizedSearch = searchQuery.trim().toLowerCase();
    const eventMatchesSearch = (event) => {
      if (!normalizedSearch) {
        return true;
      }
      const searchable = [
        event?.name,
        event?.description,
        event?.facilitator,
        event?.venue_name,
        event?.status,
        event?.start_date,
        event?.start_time
      ].filter(Boolean).join(" ").toLowerCase();
      return searchable.includes(normalizedSearch);
    };
    const getEventImageUrl = (event) => {
      const seedSource = String(event?.id || event?.name || "event-card");
      const seed = encodeURIComponent(`event-${seedSource}`);
      return `https://picsum.photos/seed/${seed}/640/360`;
    };
    const applySearch = () => {
      setSearchQuery(searchInput.trim());
    };
    const isMyEvents = activeView === "my-events";
    const isReportsView = activeView === "event-reports";
    const isCalendar = activeView === "calendar";
    const isApprovals = activeView === "approvals";
    const isRequirements = activeView === "requirements";
    const showApprovalsOrRequirementsContent =
      (isApprovals && canAccessApprovals) || (isRequirements && canAccessRequirements);
    const isPublications = activeView === "publications";
    const isAdminView = activeView === "admin";
    const isIqacData = activeView === "iqac-data";
    const visibleMenuItems = menuItems.filter((item) => {
      if (item.id === "admin" && !canAccessAdminConsole) {
        return false;
      }
      if (item.id === "event-reports" && !isAdmin && !isRegistrar) {
        return false;
      }
      if (item.id === "approvals" && !canAccessApprovals) {
        return false;
      }
      if (item.id === "requirements" && !canAccessRequirements) {
        return false;
      }
      if (item.id === "iqac-data" && !canAccessIqac) {
        return false;
      }
      return true;
    });

    const openWorkflowActionModal = (channel, requestId, status, actionLabel) => {
      setWorkflowActionModal({
        open: true,
        channel,
        requestId,
        status,
        actionLabel,
        comment: "",
        error: "",
        submitting: false
      });
    };

    const closeWorkflowActionModal = () => {
      setWorkflowActionModal({
        open: false,
        channel: null,
        requestId: null,
        status: null,
        actionLabel: "",
        comment: "",
        error: "",
        submitting: false
      });
    };

    const submitWorkflowActionModal = async () => {
      const token = localStorage.getItem("auth_token");
      const m = workflowActionModal;
      const comment = (m.comment || "").trim();
      const commentRequired =
        m.channel !== "approval" || String(m.status || "").toLowerCase() !== "approved";
      if (commentRequired && !comment) {
        setWorkflowActionModal((prev) => ({ ...prev, error: "Comment is required." }));
        return;
      }
      if (!token || !m.channel || !m.requestId || !m.status) {
        setWorkflowActionModal((prev) => ({ ...prev, error: "Missing action context." }));
        return;
      }

      setWorkflowActionModal((prev) => ({ ...prev, submitting: true, error: "" }));

      const body = JSON.stringify({ status: m.status, comment: comment || null });
      const headers = { "Content-Type": "application/json" };
      let url;
      try {
        if (m.channel === "approval") {
          const idemKey = generateIdempotencyKey();
          if (idemKey) headers["Idempotency-Key"] = idemKey;
          url = `${apiBaseUrl}/approvals/${m.requestId}`;
        } else if (m.channel === "facility") {
          url = `${apiBaseUrl}/facility/requests/${m.requestId}`;
        } else if (m.channel === "marketing") {
          url = `${apiBaseUrl}/marketing/requests/${m.requestId}`;
        } else if (m.channel === "it") {
          url = `${apiBaseUrl}/it/requests/${m.requestId}`;
        } else if (m.channel === "transport") {
          url = `${apiBaseUrl}/transport/requests/${m.requestId}`;
        } else {
          throw new Error("Unknown action channel.");
        }

        const res = await apiFetch(url, { method: "PATCH", headers, body });

        if (m.channel === "approval" && res.status === 409) {
          throw new Error("Schedule conflict detected. Ask the requester to reschedule.");
        }
        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          throw new Error(data?.detail || "Unable to submit action.");
        }

        closeWorkflowActionModal();
        if (m.channel === "approval") loadApprovalsInbox();
        else if (m.channel === "facility") loadFacilityInbox();
        else if (m.channel === "marketing") loadMarketingInbox();
        else if (m.channel === "it") loadItInbox();
        else if (m.channel === "transport") loadTransportInbox();
      } catch (err) {
        const msg = err?.message || "Unable to submit action.";
        setWorkflowActionModal((prev) => ({ ...prev, submitting: false, error: msg }));
      }
    };

    const renderPrimaryContent = () => {
      if (isAdminView) {
        if (!canAccessAdminConsole) {
          return (
            <div className="admin-empty">
              <p>Admin access required.</p>
            </div>
          );
        }

        const overview = adminOverview.data || {};
        return (
          <div className="primary-column admin-console">
            <div className="admin-hero">
              <div>
                <p className="admin-eyebrow">System Control</p>
                <h2>Administration Center</h2>
                <p className="admin-note">
                  Manage users, venues, and requests across the entire platform.
                </p>
              </div>
              <div className="admin-overview">
                <div className="admin-card">
                  <p>Users</p>
                  <h3>{overview.users ?? "--"}</h3>
                </div>
                <div className="admin-card">
                  <p>Venues</p>
                  <h3>{overview.venues ?? "--"}</h3>
                </div>
                <div className="admin-card">
                  <p>Events</p>
                  <h3>{overview.events ?? "--"}</h3>
                </div>
                <div className="admin-card">
                  <p>Approvals</p>
                  <h3>{overview.approvals ?? "--"}</h3>
                </div>
                <div className="admin-card">
                  <p>Transport</p>
                  <h3>{overview.transport ?? "--"}</h3>
                </div>
              </div>
              <button type="button" className="secondary-action" onClick={loadAdminOverview}>
                Refresh Overview
              </button>
            </div>

            <div className="admin-tabs">
              <button
                type="button"
                className={`tab-button ${adminTab === "users" ? "active" : ""}`}
                onClick={() => setAdminTab("users")}
              >
                Users
              </button>
              <button
                type="button"
                className={`tab-button ${adminTab === "venues" ? "active" : ""}`}
                onClick={() => setAdminTab("venues")}
              >
                Venues
              </button>
              <button
                type="button"
                className={`tab-button ${adminTab === "events" ? "active" : ""}`}
                onClick={() => setAdminTab("events")}
              >
                Events
              </button>
              <button
                type="button"
                className={`tab-button ${adminTab === "requests" ? "active" : ""}`}
                onClick={() => setAdminTab("requests")}
              >
                Requests
              </button>
              <button
                type="button"
                className={`tab-button ${adminTab === "invites" ? "active" : ""}`}
                onClick={() => setAdminTab("invites")}
              >
                Invites
              </button>
              <button
                type="button"
                className={`tab-button ${adminTab === "publications" ? "active" : ""}`}
                onClick={() => setAdminTab("publications")}
              >
                Publications
              </button>
            </div>

            {adminTab === "users" ? (
              <div className="admin-panel">
                <div className="admin-panel-header">
                  <h3>User Management</h3>
                  <div>
                    <button type="button" className="primary-action" onClick={handleAddUserModalOpen}>
                      Add User
                    </button>
                    <button type="button" className="secondary-action" onClick={loadAdminUsers}>
                      Refresh
                    </button>
                  </div>
                </div>
                {adminUsersState.status === "loading" ? <p className="table-message">Loading users...</p> : null}
                {adminUsersState.status === "error" ? (
                  <p className="table-message">{adminUsersState.error}</p>
                ) : null}
                <div className="admin-table">
                  <div className="admin-row header">
                    <span>User</span>
                    <span>Role</span>
                    <span>Actions</span>
                  </div>
                  {adminUsersState.items.map((item) => {
                    const initial = (item.name || item.email || "?").trim().charAt(0).toUpperCase();
                    return (
                      <div className="admin-row" key={item.id}>
                        <div className="admin-cell">
                          <div className="admin-user">
                            <span className="admin-avatar" aria-hidden="true">{initial}</span>
                            <div>
                              <p className="admin-name">{item.name || "Unnamed"}</p>
                              <p className="admin-email">{item.email}</p>
                            </div>
                          </div>
                        </div>
                        <div className="admin-cell">
                          <select
                            value={item.role || "faculty"}
                            onChange={(event) => handleAdminRoleChange(item.id, event.target.value)}
                          >
                            <option value="admin">Admin</option>
                            <option value="faculty">Faculty</option>
                            <option value="registrar">Registrar</option>
                            <option value="facility_manager">Facility Manager</option>
                            <option value="marketing">Marketing</option>
                            <option value="it">IT</option>
                            <option value="transport">Transport</option>
                            <option value="iqac">IQAC</option>
                          </select>
                        </div>
                        <div className="admin-cell">
                          <button
                            type="button"
                            className="details-button reject"
                            onClick={() => handleAdminDeleteUser(item.id)}
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    );
                  })}
                  {adminUsersState.items.length === 0 && adminUsersState.status === "ready" ? (
                    <p className="table-message">No users found.</p>
                  ) : null}
                </div>
              </div>
            ) : null}

            {adminTab === "venues" ? (
              <div className="admin-panel">
                <div className="admin-panel-header">
                  <h3>Venue Management</h3>
                  <button type="button" className="secondary-action" onClick={loadAdminVenues}>
                    Refresh
                  </button>
                </div>
                <form
                  className="admin-form"
                  onSubmit={(event) => {
                    event.preventDefault();
                    handleAdminCreateVenue(adminVenueName);
                  }}
                >
                  <input
                    type="text"
                    placeholder="Add a new venue"
                    value={adminVenueName}
                    onChange={(event) => setAdminVenueName(event.target.value)}
                  />
                  <button type="submit" className="primary-action">
                    Add Venue
                  </button>
                </form>
                {adminVenuesState.status === "loading" ? <p className="table-message">Loading venues...</p> : null}
                {adminVenuesState.error ? <p className="table-message">{adminVenuesState.error}</p> : null}
                <div className="admin-venue-list">
                  {adminVenuesState.items.map((venue) => (
                    <div key={venue.id} className="admin-venue-item">
                      <span>{venue.name}</span>
                      <button
                        type="button"
                        className="details-button reject"
                        onClick={() => handleAdminDeleteVenue(venue.id)}
                      >
                        Delete
                      </button>
                    </div>
                  ))}
                  {adminVenuesState.items.length === 0 && adminVenuesState.status === "ready" ? (
                    <p className="table-message">No venues yet.</p>
                  ) : null}
                </div>
              </div>
            ) : null}

            {adminTab === "events" ? (
              <div className="admin-panel">
                <div className="admin-panel-header">
                  <h3>All Events</h3>
                  <button type="button" className="secondary-action" onClick={loadAdminEvents}>
                    Refresh
                  </button>
                </div>
                {adminEventsState.status === "loading" ? <p className="table-message">Loading events...</p> : null}
                {adminEventsState.status === "error" ? (
                  <p className="table-message">{adminEventsState.error}</p>
                ) : null}
                <div className="admin-table">
                  <div className="admin-row header events">
                    <span>Event</span>
                    <span>Venue</span>
                    <span>Status</span>
                    <span>Action</span>
                  </div>
                  {adminEventsState.items.map((event) => {
                    const { statusLabel, statusClass } = getEventStatusInfo(event);
                    return (
                      <div className="admin-row events" key={event.id}>
                        <div className="admin-cell">
                          <p className="admin-name">{event.name}</p>
                          <p className="admin-email">
                            {event.start_date} ? {formatISTTime(event.start_time)}
                          </p>
                        </div>
                        <div className="admin-cell">{event.venue_name}</div>
                        <div className="admin-cell">
                          <span className={`status-pill ${statusClass}`}>{statusLabel}</span>
                        </div>
                        <div className="admin-cell">
                          <button
                            type="button"
                            className="details-button reject"
                            onClick={() => handleAdminDeleteEvent(event.id)}
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    );
                  })}
                  {adminEventsState.items.length === 0 && adminEventsState.status === "ready" ? (
                    <p className="table-message">No events found.</p>
                  ) : null}
                </div>
              </div>
            ) : null}

            {adminTab === "invites" ? (
              <div className="admin-panel">
                <div className="admin-panel-header">
                  <h3>Invites</h3>
                  <button type="button" className="secondary-action" onClick={loadAdminInvites}>
                    Refresh
                  </button>
                </div>
                {adminInvitesState.status === "loading" ? <p className="table-message">Loading invites...</p> : null}
                {adminInvitesState.status === "error" ? (
                  <p className="table-message">{adminInvitesState.error}</p>
                ) : null}
                <div className="admin-table">
                  <div className="admin-row header events">
                    <span>To</span>
                    <span>Subject</span>
                    <span>Status</span>
                    <span>Action</span>
                  </div>
                  {adminInvitesState.items.map((invite) => (
                    <div className="admin-row events" key={invite.id}>
                      <div className="admin-cell">
                        <p className="admin-name">{invite.to_email}</p>
                        <p className="admin-email">{invite.created_at?.slice(0, 10)}</p>
                      </div>
                      <div className="admin-cell">{invite.subject}</div>
                      <div className="admin-cell">
                        <span className={`status-pill ${invite.status}`}>{invite.status}</span>
                      </div>
                      <div className="admin-cell">
                        <button
                          type="button"
                          className="details-button reject"
                          onClick={() => handleAdminDeleteInvite(invite.id)}
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                  ))}
                  {adminInvitesState.items.length === 0 && adminInvitesState.status === "ready" ? (
                    <p className="table-message">No invites found.</p>
                  ) : null}
                </div>
              </div>
            ) : null}

            {adminTab === "publications" ? (
              <div className="admin-panel">
                <div className="admin-panel-header">
                  <h3>Publications</h3>
                  <button type="button" className="secondary-action" onClick={loadAdminPublications}>
                    Refresh
                  </button>
                </div>
                {adminPublicationsState.status === "loading" ? (
                  <p className="table-message">Loading publications...</p>
                ) : null}
                {adminPublicationsState.status === "error" ? (
                  <p className="table-message">{adminPublicationsState.error}</p>
                ) : null}
                <div className="admin-table">
                  <div className="admin-row header events">
                    <span>Name</span>
                    <span>Title</span>
                    <span>Uploaded</span>
                    <span>Action</span>
                  </div>
                  {adminPublicationsState.items.map((pub) => {
                    const pubTypeAdminLabels = { webpage: "Webpage", journal_article: "Journal Article", book: "Book", report: "Report", video: "Video", online_newspaper: "Online Newspaper" };
                    return (
                    <div className="admin-row events" key={pub.id}>
                      <div className="admin-cell">
                        <p className="admin-name">{pub.name}</p>
                        <p className="admin-email">{pub.file_name || pub.url || "—"}</p>
                      </div>
                      <div className="admin-cell">
                        <span className={`pub-type-badge pub-type-${pub.pub_type || "unknown"}`}>{pubTypeAdminLabels[pub.pub_type] || pub.pub_type || "—"}</span>
                      </div>
                      <div className="admin-cell">{pub.uploaded_at ? pub.uploaded_at.slice(0, 10) : pub.created_at?.slice(0, 10) || "—"}</div>
                      <div className="admin-cell">
                        <button
                          type="button"
                          className="details-button reject"
                          onClick={() => handleAdminDeletePublication(pub.id)}
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                    );
                  })}
                  {adminPublicationsState.items.length === 0 && adminPublicationsState.status === "ready" ? (
                    <p className="table-message">No publications found.</p>
                  ) : null}

                </div>
              </div>
            ) : null}

            {adminTab === "requests" ? (
              <div className="admin-panel">
                <div className="admin-panel-header">
                  <h3>Requests Overview</h3>
                  <button type="button" className="secondary-action" onClick={() => {
                    loadAdminApprovals();
                    loadAdminMarketing();
                    loadAdminIt();
                    loadAdminTransport();
                  }}>
                    Refresh
                  </button>
                </div>
                <div className="admin-requests-grid">
                  <div className="admin-request-block">
                    <h4>Approvals</h4>
                    {adminApprovalsState.status === "loading" ? (
                      <p className="table-message">Loading approvals...</p>
                    ) : null}
                    {adminApprovalsState.items.slice(0, 6).map((item) => (
                      <div key={item.id} className="admin-request-item">
                        <div>
                          <p className="admin-name">{item.event_name}</p>
                          <p className="admin-email">{item.requester_email}</p>
                        </div>
                        <div className="admin-request-actions">
                          <span className={`status-pill ${item.status}`}>{item.status}</span>
                          <button
                            type="button"
                            className="details-button reject"
                            onClick={() => handleAdminDeleteApproval(item.id)}
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="admin-request-block">
                    <h4>Marketing</h4>
                    {adminMarketingState.status === "loading" ? (
                      <p className="table-message">Loading marketing...</p>
                    ) : null}
                    {adminMarketingState.items.slice(0, 6).map((item) => (
                      <div key={item.id} className="admin-request-item">
                        <div>
                          <p className="admin-name">{item.event_name}</p>
                          <p className="admin-email">{item.requester_email}</p>
                        </div>
                        <div className="admin-request-actions">
                          <span className={`status-pill ${item.status}`}>{item.status}</span>
                          <button
                            type="button"
                            className="details-button reject"
                            onClick={() => handleAdminDeleteMarketing(item.id)}
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="admin-request-block">
                    <h4>IT</h4>
                    {adminItState.status === "loading" ? (
                      <p className="table-message">Loading IT...</p>
                    ) : null}
                    {adminItState.items.slice(0, 6).map((item) => (
                      <div key={item.id} className="admin-request-item">
                        <div>
                          <p className="admin-name">{item.event_name}</p>
                          <p className="admin-email">{item.requester_email}</p>
                        </div>
                        <div className="admin-request-actions">
                          <span className={`status-pill ${item.status}`}>{item.status}</span>
                          <button
                            type="button"
                            className="details-button reject"
                            onClick={() => handleAdminDeleteIt(item.id)}
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                  <div className="admin-request-block">
                    <h4>Transport</h4>
                    {adminTransportState.status === "loading" ? (
                      <p className="table-message">Loading transport...</p>
                    ) : null}
                    {adminTransportState.items.slice(0, 6).map((item) => (
                      <div key={item.id} className="admin-request-item">
                        <div>
                          <p className="admin-name">{item.event_name}</p>
                          <p className="admin-email">{item.requester_email}</p>
                        </div>
                        <div className="admin-request-actions">
                          <span className={`status-pill ${item.status}`}>{item.status}</span>
                          <button
                            type="button"
                            className="details-button reject"
                            onClick={() => handleAdminDeleteTransport(item.id)}
                          >
                            Delete
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            ) : null}
          </div>
        );
      }

      if (isMyEvents || isReportsView) {
        const isReportsTab = myEventsTab === "closed";
        const getNormalizedStatus = (event) => getNormalizedEventStatus(event);
        /** Backend lifecycle status (upcoming, ongoing, completed, closed) for tab filtering. Approval items have no lifecycle. */
        const getLifecycleStatus = (event) => {
          if (String(event.id || "").startsWith("approval-")) return null;
          return (event.status || "").toLowerCase();
        };
        const filteredEvents = eventsState.items.filter((event) => {
          const lifecycle = getLifecycleStatus(event);
          const statusMatches = isReportsView
            ? lifecycle === "closed"
            : myEventsTab === "all"
              ? true
              : myEventsTab === "pending"
                ? getNormalizedStatus(event) === "pending"
                : myEventsTab === "upcoming"
                  ? lifecycle === "upcoming"
                  : myEventsTab === "ongoing"
                  ? lifecycle === "ongoing"
                  : myEventsTab === "completed"
                      ? lifecycle === "completed"
                      : lifecycle === "closed";
          return statusMatches && eventMatchesSearch(event);
        });
        const completedWithReportPendingCount = eventsState.items.filter((event) => {
          const isApprovalItem = String(event.id || "").startsWith("approval-");
          if (isApprovalItem) return false;
          if (getLifecycleStatus(event) !== "completed") return false;
          return !event.report_file_id;
        }).length;
        const limitReached = completedWithReportPendingCount >= 5;
        const warnThresholdReached = completedWithReportPendingCount >= 3 && completedWithReportPendingCount < 5;
        const createTooltip = limitReached
          ? "Submit reports of completed events before creating a new one."
          : warnThresholdReached
            ? "Submit report of completed events to avoid creation block."
            : "";
        return (
          <div className="primary-column">
            <div className="my-events-page-header">
              <div className="my-events-title-group">
                <h2 className="my-events-title">{isReportsView ? "Event Reports" : "My Events"}</h2>
                <span className="my-events-count-badge">{filteredEvents.length}</span>
              </div>
              <div className="my-events-header-actions">
                {!isReportsView && (
                  <span title={createTooltip} className="action-tooltip">
                    <button
                      type="button"
                      className="primary-action my-events-new-btn"
                      onClick={() => {
                        if (limitReached) {
                          setStatus({
                            type: "error",
                            message: "Submit reports of completed events before creating a new one."
                          });
                          return;
                        }
                        if (warnThresholdReached) {
                          setStatus({
                            type: "info",
                            message: "Submit report of completed events to avoid creation block."
                          });
                        }
                        handleEventModalOpen();
                      }}
                      disabled={limitReached}
                    >
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                      New Event
                    </button>
                  </span>
                )}
                <button type="button" className="secondary-action my-events-refresh-btn" onClick={loadEvents}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg>
                  Refresh
                </button>
              </div>
            </div>

            <div className="events-table-card">
              {isReportsView ? null : (
                <div className="my-events-tabs">
                  <button type="button" className={`my-events-tab ${myEventsTab === "all" ? "active" : ""}`} onClick={() => setMyEventsTab("all")}>All</button>
                  <button type="button" className={`my-events-tab ${myEventsTab === "pending" ? "active" : ""}`} onClick={() => setMyEventsTab("pending")}>Pending</button>
                  <button type="button" className={`my-events-tab ${myEventsTab === "upcoming" ? "active" : ""}`} onClick={() => setMyEventsTab("upcoming")}>Upcoming</button>
                  <button type="button" className={`my-events-tab ${myEventsTab === "ongoing" ? "active" : ""}`} onClick={() => setMyEventsTab("ongoing")}>Ongoing</button>
                  <button type="button" className={`my-events-tab ${myEventsTab === "completed" ? "active" : ""}`} onClick={() => setMyEventsTab("completed")}>Completed</button>
                  <button type="button" className={`my-events-tab ${myEventsTab === "closed" ? "active" : ""}`} onClick={() => setMyEventsTab("closed")}>Closed</button>
                </div>
              )}
              <div className="events-table">
                <div className={`events-table-row header ${isReportsTab ? "reports" : ""}`}>
                  <span>Events</span>
                  {isReportsTab ? null : <span>Date</span>}
                  {isReportsTab ? null : <span>Time</span>}
                  <span>Status</span>
                  <span>Action</span>
                </div>
                {eventsState.status === "loading" ? (
                  Array.from({ length: 5 }).map((_, i) => (
                    <div key={i} className={`events-table-row my-events-skeleton-row ${isReportsTab ? "reports" : ""}`}>
                      <span className="skeleton-line" style={{ height: "16px", width: "65%", display: "block" }} />
                      {isReportsTab ? null : <span className="skeleton-line" style={{ height: "16px", width: "55%", display: "block" }} />}
                      {isReportsTab ? null : <span className="skeleton-line" style={{ height: "16px", width: "45%", display: "block" }} />}
                      <span className="skeleton-line" style={{ height: "26px", width: "72px", borderRadius: "999px", display: "block" }} />
                      <span className="skeleton-line" style={{ height: "30px", width: "80px", borderRadius: "10px", display: "block" }} />
                    </div>
                  ))
                ) : null}
                {eventsState.status === "error" ? (
                  <p className="table-message">{eventsState.error}</p>
                ) : null}
                {eventsState.status === "ready" && filteredEvents.length === 0 ? (
                  <div className="my-events-empty-state">
                    <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="#c4c9d4" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                    <p className="my-events-empty-title">
                      {isReportsTab ? "No closed events yet." : myEventsTab === "completed" ? "No completed events yet." : myEventsTab === "upcoming" ? "No upcoming events." : myEventsTab === "ongoing" ? "No ongoing events." : myEventsTab === "pending" ? "No pending events." : "No events found."}
                    </p>
                    {myEventsTab === "all" && !isReportsTab ? (
                      <span className="my-events-empty-sub">Create your first event to get started.</span>
                    ) : null}
                  </div>
                ) : null}
                {eventsState.status === "ready"
                  ? filteredEvents.map((event) => {
                      const statusValue = event.status || "";
                      const explicitStatus = statusValue ? formatStatusLabel(statusValue) : null;
                      const hasApprovalData =
                        event.approval_status ||
                        event.facility_status ||
                        event.transport_status ||
                        event.marketing_status ||
                        event.it_status;
                      let derivedStatus = "Approved";
                      if (hasApprovalData) {
                        const statuses = [
                          event.approval_status,
                          event.facility_status,
                          event.transport_status,
                          event.marketing_status,
                          event.it_status
                        ];
                        if (statuses.includes("rejected")) {
                          derivedStatus = "Rejected";
                        } else if (statuses.every((status) => status === "approved")) {
                          derivedStatus = "Approved";
                        } else {
                          derivedStatus = "Pending";
                        }
                      }

                      const statusLabel =
                        event.approval_status === "approved"
                          ? "Approved"
                          : explicitStatus || derivedStatus;
                      const statusClass = (statusValue || statusLabel)
                        .toLowerCase()
                        .replace(/\s+/g, "-");
                      const inviteSent = event.invite_status === "sent";
                      const isUpcomingEvent = (statusValue || "").toLowerCase() === "upcoming";
                      const eventHasStarted = isEventStarted(event);
                      const canInvite =
                        !eventHasStarted &&
                        isUpcomingEvent &&
                        ((!event.approval_status &&
                          !event.facility_status &&
                          !event.transport_status &&
                          !event.marketing_status &&
                          !event.it_status) ||
                          (event.approval_status === "approved" &&
                            event.facility_status === "approved" &&
                            event.transport_status === "approved" &&
                            event.marketing_status === "approved" &&
                            event.it_status === "approved")) &&
                        !inviteSent;
                      const isApprovalItem = String(event.id || "").startsWith("approval-");
                      const canSendSupportForms =
                        !eventHasStarted &&
                        !isApprovalItem &&
                        event.approval_status === "approved";
                      const canSendFacilityRequest =
                        canSendSupportForms &&
                        event.facility_status !== "approved" &&
                        event.facility_status !== "pending";
                      const canSendMarketingRequest =
                        canSendSupportForms &&
                        event.marketing_status !== "approved" &&
                        event.marketing_status !== "pending";
                      const canSendItRequest =
                        canSendSupportForms &&
                        event.it_status !== "approved" &&
                        event.it_status !== "pending";
                      const canSendTransportRequest =
                        canSendSupportForms &&
                        event.transport_status !== "approved" &&
                        event.transport_status !== "pending";
                      const canUploadReport = !isApprovalItem && statusValue === "completed";
                      const canCloseEvent =
                        !isApprovalItem &&
                        statusValue === "completed" &&
                        Boolean(event.report_file_id);
                      if (isReportsTab) {
                        return (
                          <div key={event.id} className="events-table-row reports my-events-row">
                            <span className="my-events-row-name">{event.name}</span>
                            <span className={`status-pill ${statusClass}`}>{statusLabel}</span>
                            <div className="event-actions">
                              <button
                                type="button"
                                className="ev-action-btn ev-action-details"
                                onClick={() => handleViewReport(event)}
                              >
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                                View Report
                              </button>
                            </div>
                          </div>
                        );
                      }
                      return (
                        <div key={event.id} className="events-table-row my-events-row">
                          <span className="my-events-row-name">{event.name}</span>
                          <span>{event.start_date}</span>
                          <span>{formatISTTime(event.start_time)}</span>
                          <div className="status-cell">
                            {canCloseEvent ? (
                              <button
                                type="button"
                                className="details-button reject status-close"
                                onClick={() => handleCloseEvent(event)}
                              >
                                Close
                              </button>
                            ) : (
                              <span className={`status-pill ${statusClass}`}>{statusLabel}</span>
                            )}
                          </div>
                          <div className="event-actions">
                            <button type="button" className="ev-action-btn ev-action-details" onClick={() => handleEventDetailsOpen(event)}>
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                              Details
                            </button>
                            {inviteSent ? (
                              <button type="button" className="ev-action-btn ev-action-sent" disabled>
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                                Sent
                              </button>
                            ) : null}
                            {canInvite ? (
                              <button
                                type="button"
                                className="ev-action-btn ev-action-invite"
                                onClick={() => handleInviteOpen(event)}
                              >
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/></svg>
                                Send Invite
                              </button>
                            ) : null}
                            {canUploadReport ? (
                              <button
                                type="button"
                                className="ev-action-btn ev-action-upload"
                                onClick={() => handleReportOpen(event)}
                              >
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
                                {event.report_file_id ? "Replace Report" : "Upload Report"}
                              </button>
                            ) : null}
                            {canSendSupportForms &&
                            (canSendFacilityRequest ||
                              canSendTransportRequest ||
                              canSendMarketingRequest ||
                              canSendItRequest) ? (
                              <button
                                type="button"
                                className="ev-action-btn ev-action-requirements"
                                onClick={() => handleSendRequirements(event)}
                              >
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>
                                Send your requirements
                              </button>
                            ) : null}
                            {event.report_file_id && event.status === "closed" ? (
                              <button
                                type="button"
                                className="ev-action-btn ev-action-details"
                                onClick={() => handleViewReport(event)}
                              >
                                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                                View Report
                              </button>
                            ) : null}
                          </div>
                        </div>
                      );
                    })
                  : null}
              </div>
            </div>

            {isEventModalOpen ? (
              <div className="modal-overlay premium-modal-overlay" role="dialog" aria-modal="true" onClick={(e) => { if (e.target === e.currentTarget) handleEventModalClose(); }}>
                <div className="modal-card premium-modal-card">
                  <div className="modal-header premium-modal-header">
                    <div className="premium-modal-title-row">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="var(--accent-blue, #4285f4)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" /><line x1="16" y1="2" x2="16" y2="6" /><line x1="8" y1="2" x2="8" y2="6" /><line x1="3" y1="10" x2="21" y2="10" /></svg>
                      <h3>Create Event</h3>
                    </div>
                    <button type="button" className="modal-close premium-modal-close" onClick={handleEventModalClose} aria-label="Close">
                      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" /></svg>
                    </button>
                  </div>
                  <form className="event-form premium-event-form" onSubmit={handleEventSubmit}>
                    <div className="premium-form-body">
                    {/* Date & Time Section */}
                    <div className="premium-section">
                      <div className="premium-section-label">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" /><line x1="16" y1="2" x2="16" y2="6" /><line x1="8" y1="2" x2="8" y2="6" /><line x1="3" y1="10" x2="21" y2="10" /></svg>
                        <span>Date &amp; Time</span>
                      </div>
                      <div className="premium-datetime-grid">
                        <div className="premium-datetime-row">
                          <span className="premium-datetime-label">Start</span>
                          <PremiumDatePicker
                            value={eventForm.start_date}
                            onChange={handleEventFieldChange("start_date")}
                            required
                          />
                          <PremiumTimePicker
                            timeParts={eventTimeParts.start_time}
                            onPartChange={(key) => handleEventTimePartChange("start_time", key)}
                            required
                          />
                        </div>
                        <div className="premium-datetime-row">
                          <span className="premium-datetime-label">End</span>
                          <PremiumDatePicker
                            value={eventForm.end_date}
                            onChange={handleEventFieldChange("end_date")}
                            required
                          />
                          <PremiumTimePicker
                            timeParts={eventTimeParts.end_time}
                            onPartChange={(key) => handleEventTimePartChange("end_time", key)}
                            required
                          />
                        </div>
                      </div>
                    </div>

                    {/* Event Details Section */}
                    <div className="premium-section">
                      <div className="premium-section-label">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7" /><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z" /></svg>
                        <span>Event Details</span>
                      </div>
                      <label className="form-field premium-form-field">
                        <span>Event name</span>
                        <input
                          type="text"
                          placeholder="e.g. Annual Tech Conference 2026"
                          value={eventForm.name}
                          onChange={handleEventFieldChange("name")}
                          required
                          className="premium-input"
                        />
                      </label>
                      <label className="form-field premium-form-field">
                        <span>Facilitator</span>
                        <input
                          type="text"
                          placeholder="e.g. Dr. Sharma"
                          value={eventForm.facilitator}
                          onChange={handleEventFieldChange("facilitator")}
                          required
                          className="premium-input"
                        />
                      </label>
                    </div>

                    {/* Venue & Audience Section */}
                    <div className="premium-section">
                      <div className="premium-section-label">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z" /><circle cx="12" cy="10" r="3" /></svg>
                        <span>Venue &amp; Audience</span>
                      </div>
                      <div className="premium-two-col">
                        <div className="form-field premium-form-field">
                          <SearchableSelect
                            label="Venue"
                            value={eventForm.venue_name}
                            onChange={handleEventFieldChange("venue_name")}
                            options={venuesState.items.map((v) => ({ value: v.name, label: v.name }))}
                            placeholder="Select a venue"
                            required
                            emptyMessage="No venues found"
                          />
                          {venuesState.status === "error" ? (
                            <span className="form-error">{venuesState.error}</span>
                          ) : null}
                        </div>
                        <div className="form-field premium-form-field">
                          <SearchableSelect
                            label="Intended Audience"
                            value={eventForm.intendedAudience}
                            onChange={handleEventFieldChange("intendedAudience")}
                            options={[
                              { value: "Students", label: "Students" },
                              { value: "Faculty", label: "Faculty" },
                              { value: "PhD Scholars", label: "PhD Scholars" },
                              { value: "Staffs", label: "Staffs" },
                              { value: "Everyone at VU", label: "Everyone at VU" }
                            ]}
                            placeholder="Select intended audience"
                            required
                          />
                        </div>
                      </div>
                    </div>

                    {/* Description & Budget Section */}
                    <div className="premium-section">
                      <div className="premium-section-label">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="17" y1="10" x2="3" y2="10" /><line x1="21" y1="6" x2="3" y2="6" /><line x1="21" y1="14" x2="3" y2="14" /><line x1="17" y1="18" x2="3" y2="18" /></svg>
                        <span>Description &amp; Budget</span>
                      </div>
                      <label className="form-field premium-form-field">
                        <span>Description</span>
                        <div className="premium-textarea-wrap">
                          <textarea
                            rows="4"
                            placeholder="Add a short overview of the event..."
                            value={eventForm.description}
                            onChange={(e) => {
                              handleEventFieldChange("description")(e);
                              e.target.style.height = "auto";
                              e.target.style.height = e.target.scrollHeight + "px";
                            }}
                            className="premium-textarea"
                            maxLength={2000}
                          />
                          <div className="premium-char-counter">
                            <span className="premium-char-count">{(eventForm.description || "").length} / 2000</span>
                          </div>
                        </div>
                      </label>
                      <div className="premium-budget-grid">
                        <label className="form-field premium-form-field">
                          <span>Budget (Rs)</span>
                          <div className="premium-input-icon-wrap">
                            <span className="premium-input-prefix">₹</span>
                            <input
                              type="number"
                              min="0"
                              step="1"
                              placeholder="e.g. 50000"
                              value={eventForm.budget}
                              onChange={handleEventFieldChange("budget")}
                              className="premium-input premium-input--with-prefix"
                            />
                          </div>
                        </label>
                        <div className="form-field premium-form-field">
                          <span>
                            Budget breakdown PDF <em>(required)</em>
                          </span>
                          <p className="premium-upload-hint">
                            Upload a PDF with your budget breakdown. You can upload it with any file name. It will be stored automatically using the event name and date.
                          </p>
                          <label className="premium-file-upload">
                            <input
                              ref={budgetBreakdownInputRef}
                              name="budget_breakdown_pdf"
                              type="file"
                              accept="application/pdf,.pdf"
                              className="premium-file-input"
                              required
                              onChange={(e) => {
                                const f = e.target.files?.[0];
                                setBudgetBreakdownFile(f || null);
                              }}
                            />
                            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4" /><polyline points="17 8 12 3 7 8" /><line x1="12" y1="3" x2="12" y2="15" /></svg>
                            <span>{budgetBreakdownFile ? budgetBreakdownFile.name : "Choose PDF file"}</span>
                          </label>
                          {budgetBreakdownFile ? (
                            <span className="premium-file-name">{budgetBreakdownFile.name}</span>
                          ) : null}
                        </div>
                      </div>
                    </div>

                    {eventFormStatus.status === "error" ? (
                      <div className="premium-form-error">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10" /><line x1="15" y1="9" x2="9" y2="15" /><line x1="9" y1="9" x2="15" y2="15" /></svg>
                        <span>{eventFormStatus.error}</span>
                      </div>
                    ) : null}
                    </div>{/* end premium-form-body */}
                    <div className="modal-actions premium-modal-actions">
                      <button type="button" className="secondary-action premium-cancel-btn" onClick={handleEventModalClose}>
                        Cancel
                      </button>
                      <button
                        type="submit"
                        className="primary-action premium-submit-btn"
                        disabled={
                          eventFormStatus.status === "loading" ||
                          !budgetBreakdownFile ||
                          !isBudgetBreakdownPdf(budgetBreakdownFile)
                        }
                        title={
                          !budgetBreakdownFile || !isBudgetBreakdownPdf(budgetBreakdownFile)
                            ? "Select a budget breakdown PDF to continue"
                            : undefined
                        }
                      >
                        {eventFormStatus.status === "loading" ? (
                          <>
                            <span className="premium-spinner" />
                            Creating...
                          </>
                        ) : (
                          <>
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" /></svg>
                            Create Event
                          </>
                        )}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}


            {conflictState.open ? (
              <div className="conflict-overlay" role="dialog" aria-modal="true">
                <div className="conflict-card">
                  <div className="conflict-header">
                    <span className="conflict-icon" aria-hidden="true">
                      !
                    </span>
                    <div>
                      <h3>Schedule Conflict</h3>
                      <p>The following event(s) are already scheduled at the selected time:</p>
                    </div>
                  </div>
                  <div className="conflict-table">
                    <div className="conflict-row header">
                      <span>All Events</span>
                      <span>Date</span>
                      <span>Time</span>
                      <span>Venue</span>
                    </div>
                    {conflictState.items.map((conflict) => (
                      <div key={conflict.id} className="conflict-row">
                        <span>{conflict.name}</span>
                        <span>{conflict.start_date}</span>
                        <span>{formatISTTime(conflict.start_time)}</span>
                        <span>{conflict.venue_name}</span>
                      </div>
                    ))}
                  </div>
                  <p className="conflict-footnote">
                    Would you like to reschedule your event or override this conflict?
                  </p>
                  <div className="conflict-actions">
                    <button type="button" className="conflict-button reschedule" onClick={handleConflictReschedule}>
                      Reschedule
                    </button>
                    <button type="button" className="conflict-button cancel" onClick={handleConflictCancel}>
                      Cancel
                    </button>
                    <button
                      type="button"
                      className="conflict-button override"
                      onClick={handleConflictApprovalRequest}
                    >
                      Override
                    </button>
                  </div>
                </div>
              </div>
            ) : null}

            {approvalModal.open ? (
              <div className="approval-overlay" role="dialog" aria-modal="true">
                <div className="approval-card">
                  <div className="approval-header">
                    <h3>REGISTRAR APPROVAL</h3>
                    <button type="button" className="modal-close" onClick={handleApprovalModalClose}>
                      &times;
                    </button>
                  </div>
                  <form className="approval-form" onSubmit={submitApprovalRequest}>
                    <div className="approval-grid">
                      <label className="approval-field">
                        <span>From</span>
                        <input type="email" value={user?.email || ""} readOnly />
                      </label>
                      <label className="approval-field">
                        <span>To</span>
                        <input type="text" value={registrarEmail || "Registrar email"} readOnly />
                      </label>
                    </div>

                    <div className="approval-summary">
                      <p>
                        <strong>Event:</strong> {pendingEvent?.name || eventForm.name || "Untitled event"}
                      </p>
                      <p>
                        <strong>Date:</strong>{" "}
                        {pendingEvent?.start_date || eventForm.start_date || "--"}{" "}
                        {pendingEvent?.end_date
                          ? `to ${pendingEvent.end_date}`
                          : eventForm.end_date
                            ? `to ${eventForm.end_date}`
                            : ""}
                      </p>
                      <p>
                        <strong>Time:</strong>{" "}
                        {formatISTTime(pendingEvent?.start_time || eventForm.start_time) || "--"}{" "}
                        {pendingEvent?.end_time
                          ? `to ${formatISTTime(pendingEvent.end_time)}`
                          : eventForm.end_time
                            ? `to ${formatISTTime(eventForm.end_time)}`
                            : ""}
                      </p>
                    </div>

                    <p className="approval-note">
                      Registrar will approve or reject this event. After approval, you can send requirements to Facility,
                      IT, Marketing, and Transport.
                    </p>

                    {approvalModal.status === "error" ? (
                      <p className="form-error">{approvalModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleApprovalModalClose}>
                        Cancel
                      </button>
                      <button
                        type="submit"
                        className="primary-action"
                        disabled={
                          approvalModal.status === "loading" ||
                          !budgetBreakdownFile ||
                          !isBudgetBreakdownPdf(budgetBreakdownFile)
                        }
                        title={
                          !budgetBreakdownFile || !isBudgetBreakdownPdf(budgetBreakdownFile)
                            ? "Select a budget breakdown PDF in the create event form first"
                            : undefined
                        }
                      >
                        {approvalModal.status === "loading" ? "Sending..." : "Send"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}

            {facilityModal.open ? (
              <div className="approval-overlay" role="dialog" aria-modal="true">
                <div className="marketing-card">
                  <div className="approval-header">
                    <h3>FACILITY MANAGER REQUEST</h3>
                    <button type="button" className="modal-close" onClick={handleFacilityModalClose}>
                      &times;
                    </button>
                  </div>
                  <form className="approval-form" onSubmit={submitFacilityRequest}>
                    <div className="approval-grid">
                      <label className="approval-field">
                        <span>From</span>
                        <input type="email" value={user?.email || ""} readOnly />
                      </label>
                      <label className="approval-field">
                        <span>To</span>
                        <input
                          type="email"
                          placeholder="facilitymanager@campus.edu"
                          value={facilityForm.to}
                          onChange={handleFacilityFieldChange("to")}
                        />
                      </label>
                    </div>

                    <div className="approval-summary">
                      <p>
                        <strong>Event:</strong> {pendingEvent?.name || eventForm.name || "Untitled event"}
                      </p>
                      <p>
                        <strong>Date:</strong>{" "}
                        {pendingEvent?.start_date || eventForm.start_date || "--"}{" "}
                        {pendingEvent?.end_date
                          ? `to ${pendingEvent.end_date}`
                          : eventForm.end_date
                            ? `to ${eventForm.end_date}`
                            : ""}
                      </p>
                      <p>
                        <strong>Time:</strong>{" "}
                        {formatISTTime(pendingEvent?.start_time || eventForm.start_time) || "--"}{" "}
                        {pendingEvent?.end_time
                          ? `to ${formatISTTime(pendingEvent.end_time)}`
                          : eventForm.end_time
                            ? `to ${formatISTTime(eventForm.end_time)}`
                            : ""}
                      </p>
                    </div>

                    <div className="approval-requirements">
                      <p>Requirements:</p>
                      <label>
                        <input
                          type="checkbox"
                          checked={facilityForm.venue_required}
                          onChange={handleFacilityToggle("venue_required")}
                        />
                        Venue setup
                      </label>
                      <label>
                        <input
                          type="checkbox"
                          checked={facilityForm.refreshments}
                          onChange={handleFacilityToggle("refreshments")}
                        />
                        Refreshments
                      </label>
                    </div>

                    <label className="approval-field">
                      <span>Others</span>
                      <textarea
                        rows="4"
                        placeholder="Add additional notes for the facility manager."
                        value={facilityForm.other_notes}
                        onChange={handleFacilityFieldChange("other_notes")}
                      />
                    </label>

                    {facilityModal.status === "error" ? (
                      <p className="form-error">{facilityModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleFacilitySkip}>
                        Skip
                      </button>
                      <button type="button" className="secondary-action" onClick={handleFacilityModalClose}>
                        Cancel
                      </button>
                      <button
                        type="submit"
                        className="primary-action"
                        disabled={facilityModal.status === "loading"}
                      >
                        {facilityModal.status === "loading" ? "Sending..." : "Send"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}

            {transportModal.open ? (
              <div className="approval-overlay" role="dialog" aria-modal="true">
                <div className="marketing-card marketing-card--scrollable">
                  <div className="approval-header">
                    <h3>TRANSPORT REQUEST</h3>
                    <button type="button" className="modal-close" onClick={handleTransportModalClose}>
                      &times;
                    </button>
                  </div>
                  <form className="approval-form requirements-scroll-form" onSubmit={submitTransportRequest}>
                    <div className="requirements-form-scroll">
                    <div className="approval-grid">
                      <label className="approval-field">
                        <span>From</span>
                        <input type="email" value={user?.email || ""} readOnly />
                      </label>
                      <label className="approval-field">
                        <span>To</span>
                        <input
                          type="email"
                          placeholder="transport@campus.edu"
                          value={transportForm.to}
                          onChange={handleTransportFieldChange("to")}
                        />
                      </label>
                    </div>

                    <div className="approval-summary">
                      <p>
                        <strong>Event:</strong> {pendingEvent?.name || eventForm.name || "Untitled event"}
                      </p>
                      <p>
                        <strong>Date:</strong>{" "}
                        {pendingEvent?.start_date || eventForm.start_date || "--"}{" "}
                        {pendingEvent?.end_date
                          ? `to ${pendingEvent.end_date}`
                          : eventForm.end_date
                            ? `to ${eventForm.end_date}`
                            : ""}
                      </p>
                      <p>
                        <strong>Time:</strong>{" "}
                        {formatISTTime(pendingEvent?.start_time || eventForm.start_time) || "--"}{" "}
                        {pendingEvent?.end_time
                          ? `to ${formatISTTime(pendingEvent.end_time)}`
                          : eventForm.end_time
                            ? `to ${formatISTTime(eventForm.end_time)}`
                            : ""}
                      </p>
                    </div>

                    <div className="approval-requirements">
                      <p>Transport arrangement (you can select both)</p>
                      <label>
                        <input
                          type="checkbox"
                          checked={transportForm.include_guest_cab}
                          onChange={(e) =>
                            setTransportForm((prev) => ({
                              ...prev,
                              include_guest_cab: e.target.checked
                            }))
                          }
                        />
                        Cab for guest
                      </label>
                      <label>
                        <input
                          type="checkbox"
                          checked={transportForm.include_students}
                          onChange={(e) =>
                            setTransportForm((prev) => ({
                              ...prev,
                              include_students: e.target.checked
                            }))
                          }
                        />
                        Students (off-campus event)
                      </label>
                    </div>

                    {transportForm.include_guest_cab ? (
                      <div className="form-grid" style={{ marginTop: "0.75rem" }}>
                        <p className="details-sublabel" style={{ gridColumn: "1 / -1", margin: 0 }}>
                          Guest cab
                        </p>
                        <label className="approval-field">
                          <span>Pick up location</span>
                          <input
                            type="text"
                            value={transportForm.guest_pickup_location}
                            onChange={handleTransportFieldChange("guest_pickup_location")}
                            placeholder="Address or landmark"
                          />
                        </label>
                        <label className="approval-field">
                          <span>Pick up date</span>
                          <input
                            type="date"
                            value={transportForm.guest_pickup_date}
                            onChange={handleTransportFieldChange("guest_pickup_date")}
                          />
                        </label>
                        <label className="approval-field">
                          <span>Pick up time</span>
                          <input
                            type="time"
                            value={transportForm.guest_pickup_time}
                            onChange={handleTransportFieldChange("guest_pickup_time")}
                          />
                        </label>
                        <label className="approval-field">
                          <span>Drop off location</span>
                          <input
                            type="text"
                            value={transportForm.guest_dropoff_location}
                            onChange={handleTransportFieldChange("guest_dropoff_location")}
                            placeholder="Address or landmark"
                          />
                        </label>
                        <label className="approval-field">
                          <span>Drop off date (optional)</span>
                          <input
                            type="date"
                            value={transportForm.guest_dropoff_date}
                            onChange={handleTransportFieldChange("guest_dropoff_date")}
                          />
                        </label>
                        <label className="approval-field">
                          <span>Drop off time</span>
                          <input
                            type="time"
                            value={transportForm.guest_dropoff_time}
                            onChange={handleTransportFieldChange("guest_dropoff_time")}
                          />
                        </label>
                      </div>
                    ) : null}

                    {transportForm.include_students ? (
                      <div className="form-grid" style={{ marginTop: "0.75rem" }}>
                        <p className="details-sublabel" style={{ gridColumn: "1 / -1", margin: 0 }}>
                          Student transport
                        </p>
                        <label className="approval-field">
                          <span>Number of students</span>
                          <input
                            type="number"
                            min="1"
                            step="1"
                            value={transportForm.student_count}
                            onChange={handleTransportFieldChange("student_count")}
                          />
                        </label>
                        <label className="approval-field">
                          <span>Kind of transport</span>
                          <input
                            type="text"
                            value={transportForm.student_transport_kind}
                            onChange={handleTransportFieldChange("student_transport_kind")}
                            placeholder="e.g. bus, van"
                          />
                        </label>
                        <label className="approval-field">
                          <span>Date</span>
                          <input
                            type="date"
                            value={transportForm.student_date}
                            onChange={handleTransportFieldChange("student_date")}
                          />
                        </label>
                        <label className="approval-field">
                          <span>Time</span>
                          <input
                            type="time"
                            value={transportForm.student_time}
                            onChange={handleTransportFieldChange("student_time")}
                          />
                        </label>
                        <label className="approval-field" style={{ gridColumn: "1 / -1" }}>
                          <span>Pick up point</span>
                          <input
                            type="text"
                            value={transportForm.student_pickup_point}
                            onChange={handleTransportFieldChange("student_pickup_point")}
                            placeholder="Meeting point for students"
                          />
                        </label>
                      </div>
                    ) : null}

                    <label className="approval-field">
                      <span>Additional notes</span>
                      <textarea
                        rows="3"
                        placeholder="Any other details for transport."
                        value={transportForm.other_notes}
                        onChange={handleTransportFieldChange("other_notes")}
                      />
                    </label>

                    {transportModal.status === "error" ? (
                      <p className="form-error">{transportModal.error}</p>
                    ) : null}
                    </div>

                    <div className="modal-actions requirements-modal-actions">
                      <button type="button" className="secondary-action" onClick={handleTransportSkip}>
                        Skip
                      </button>
                      <button type="button" className="secondary-action" onClick={handleTransportModalClose}>
                        Cancel
                      </button>
                      <button
                        type="submit"
                        className="primary-action"
                        disabled={transportModal.status === "loading"}
                      >
                        {transportModal.status === "loading" ? "Sending..." : "Send"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}

            {inviteModal.open ? (
              <div className="approval-overlay" role="dialog" aria-modal="true">
                <div className="invite-card">
                  <div className="approval-header">
                    <h3>Send Invite</h3>
                    <button type="button" className="modal-close" onClick={handleInviteClose}>
                      &times;
                    </button>
                  </div>
                  <form className="approval-form" onSubmit={submitInvite}>
                    <label className="approval-field">
                      <span>From</span>
                      <input type="email" value={user?.email || ""} readOnly />
                    </label>
                    <label className="approval-field">
                      <span>To</span>
                      <input
                        type="email"
                        placeholder="recipient@campus.edu"
                        value={inviteForm.to}
                        onChange={handleInviteFieldChange("to")}
                        required
                      />
                    </label>
                    <label className="approval-field">
                      <span>Subject</span>
                      <input
                        type="text"
                        value={inviteForm.subject}
                        onChange={handleInviteFieldChange("subject")}
                      />
                    </label>
                    <label className="approval-field">
                      <span>Description</span>
                      <textarea
                        placeholder="Add a short invitation message."
                        value={inviteForm.description}
                        onChange={handleInviteFieldChange("description")}
                      />
                    </label>
                    {inviteModal.status === "error" ? (
                      <div className="form-error">
                        <p>{inviteModal.error}</p>
                        {inviteModal.error === "Connect Google to send invites." ? (
                          <button type="button" className="secondary-action" onClick={handleCalendarConnect}>
                            Connect Google
                          </button>
                        ) : null}
                      </div>
                    ) : null}
                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleInviteClose}>
                        Cancel
                      </button>
                      <button type="submit" className="primary-action" disabled={inviteModal.status === "loading"}>
                        {inviteModal.status === "loading" ? "Sending..." : "Send Invite"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}

            {marketingModal.open ? (
              <div className="marketing-overlay" role="dialog" aria-modal="true">
                <div className="marketing-card">
                  <div className="approval-header">
                    <h3>MARKETING REQUEST</h3>
                    <button type="button" className="modal-close" onClick={handleMarketingModalClose}>
                      &times;
                    </button>
                  </div>
                  <form className="approval-form" onSubmit={submitMarketingRequest}>
                    <div className="approval-grid">
                      <label className="approval-field">
                        <span>From</span>
                        <input type="email" value={user?.email || ""} readOnly />
                      </label>
                      <label className="approval-field">
                        <span>To</span>
                        <input
                          type="email"
                          placeholder="marketing@campus.edu"
                          value={marketingForm.to}
                          onChange={handleMarketingFieldChange("to")}
                        />
                      </label>
                    </div>

                    <div className="approval-summary">
                      <p>
                        <strong>Event:</strong> {pendingEvent?.name || eventForm.name || "Untitled event"}
                      </p>
                      <p>
                        <strong>Date:</strong>{" "}
                        {pendingEvent?.start_date || eventForm.start_date || "--"}{" "}
                        {pendingEvent?.end_date
                          ? `to ${pendingEvent.end_date}`
                          : eventForm.end_date
                            ? `to ${eventForm.end_date}`
                            : ""}
                      </p>
                      <p>
                        <strong>Time:</strong>{" "}
                        {formatISTTime(pendingEvent?.start_time || eventForm.start_time) || "--"}{" "}
                        {pendingEvent?.end_time
                          ? `to ${formatISTTime(pendingEvent.end_time)}`
                          : eventForm.end_time
                            ? `to ${formatISTTime(eventForm.end_time)}`
                            : ""}
                      </p>
                    </div>

                    <div className="marketing-requirements">
                      <p>Requirements:</p>
                      {MARKETING_REQUIREMENT_GROUPS.map((group) => (
                        <div key={group.key} className="marketing-group">
                          <p className="form-hint">{group.title}</p>
                          <div className="marketing-grid">
                            {group.fields.map((field) => (
                              <label key={`${group.key}-${field.key}`}>
                                <input
                                  type="checkbox"
                                  checked={Boolean(marketingForm.marketing_requirements?.[group.key]?.[field.key])}
                                  onChange={handleMarketingToggle(group.key, field.key)}
                                />
                                {field.label}
                              </label>
                            ))}
                          </div>
                        </div>
                      ))}
                    </div>

                    <label className="approval-field">
                      <span>Others</span>
                      <textarea
                        rows="4"
                        placeholder="Add additional notes for the marketing team."
                        value={marketingForm.other_notes}
                        onChange={handleMarketingFieldChange("other_notes")}
                      />
                    </label>

                    {marketingModal.status === "error" ? (
                      <p className="form-error">{marketingModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleMarketingSkip}>
                        Skip
                      </button>
                      <button type="button" className="secondary-action" onClick={handleMarketingModalClose}>
                        Cancel
                      </button>
                      <button
                        type="submit"
                        className="primary-action"
                        disabled={marketingModal.status === "loading"}
                      >
                        {marketingModal.status === "loading" ? "Sending..." : "Send"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}

            {itModal.open ? (
              <div className="marketing-overlay" role="dialog" aria-modal="true">
                <div className="marketing-card">
                  <div className="approval-header">
                    <h3>IT SUPPORT REQUEST</h3>
                    <button type="button" className="modal-close" onClick={handleItModalClose}>
                      &times;
                    </button>
                  </div>
                  <form className="approval-form" onSubmit={submitItRequest}>
                    <div className="approval-grid">
                      <label className="approval-field">
                        <span>From</span>
                        <input type="email" value={user?.email || ""} readOnly />
                      </label>
                      <label className="approval-field">
                        <span>To</span>
                        <input
                          type="email"
                          placeholder="it@campus.edu"
                          value={itForm.to}
                          onChange={handleItFieldChange("to")}
                        />
                      </label>
                    </div>

                    <div className="approval-summary">
                      <p>
                        <strong>Event:</strong> {pendingEvent?.name || eventForm.name || "Untitled event"}
                      </p>
                      <p>
                        <strong>Date:</strong>{" "}
                        {pendingEvent?.start_date || eventForm.start_date || "--"}{" "}
                        {pendingEvent?.end_date
                          ? `to ${pendingEvent.end_date}`
                          : eventForm.end_date
                            ? `to ${eventForm.end_date}`
                            : ""}
                      </p>
                      <p>
                        <strong>Time:</strong>{" "}
                        {formatISTTime(pendingEvent?.start_time || eventForm.start_time) || "--"}{" "}
                        {pendingEvent?.end_time
                          ? `to ${formatISTTime(pendingEvent.end_time)}`
                          : eventForm.end_time
                            ? `to ${formatISTTime(eventForm.end_time)}`
                            : ""}
                      </p>
                    </div>

                    <div className="marketing-requirements">
                      <p>Event mode</p>
                      <div className="marketing-grid">
                        <label>
                          <input
                            type="radio"
                            name="it_event_mode"
                            value="online"
                            checked={itForm.event_mode === "online"}
                            onChange={() => setItForm((prev) => ({ ...prev, event_mode: "online" }))}
                          />
                          Online
                        </label>
                        <label>
                          <input
                            type="radio"
                            name="it_event_mode"
                            value="offline"
                            checked={itForm.event_mode === "offline"}
                            onChange={() => setItForm((prev) => ({ ...prev, event_mode: "offline" }))}
                          />
                          Offline
                        </label>
                      </div>
                    </div>

                    <div className="marketing-requirements">
                      <p>Requirements:</p>
                      <div className="marketing-grid">
                        <label>
                          <input
                            type="checkbox"
                            checked={itForm.pa_system}
                            onChange={handleItToggle("pa_system")}
                          />
                          PA System
                        </label>
                        <label>
                          <input
                            type="checkbox"
                            checked={itForm.projection}
                            onChange={handleItToggle("projection")}
                          />
                          Projection
                        </label>
                      </div>
                    </div>

                    <label className="approval-field">
                      <span>Others</span>
                      <textarea
                        rows="4"
                        placeholder="Add additional notes for IT."
                        value={itForm.other_notes}
                        onChange={handleItFieldChange("other_notes")}
                      />
                    </label>

                    {itModal.status === "error" ? (
                      <p className="form-error">{itModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleItSkip}>
                        Skip
                      </button>
                      <button type="button" className="secondary-action" onClick={handleItModalClose}>
                        Cancel
                      </button>
                      <button type="submit" className="primary-action" disabled={itModal.status === "loading"}>
                        {itModal.status === "loading" ? "Sending..." : "Send"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}

            {reportModal.open ? (
              <div className="modal-overlay" role="dialog" aria-modal="true">
                <div className="modal-card modal-card--report">
                  <div className="modal-header">
                    <h3>{reportModal.hasReport ? "Replace Report" : "Submit Event Report"}</h3>
                    <button type="button" className="modal-close" onClick={handleReportClose}>
                      &times;
                    </button>
                  </div>
                  <form className="event-form report-form" onSubmit={submitReport}>
                    <div className="form-field report-cover-info">
                      <span>Event (cover details)</span>
                      <p className="form-hint">
                        {reportModal.eventName || "Event"} · {reportModal.startDate || "—"} · {reportModal.eventVenue || "—"} · {reportModal.eventFacilitator || "—"}
                      </p>
                    </div>
                    <label className="form-field">
                      <span>Executive summary <em>(required)</em></span>
                      <p className="form-hint">Brief overview, goal, and main outcome</p>
                      <textarea
                        value={reportForm.executiveSummary}
                        onChange={handleReportFormChange("executiveSummary")}
                        placeholder="e.g. The workshop aimed to… and achieved…"
                        rows={3}
                      />
                    </label>
                    <label className="form-field">
                      <span>Attendance <em>(required)</em></span>
                      <p className="form-hint">Total attendees and breakdown if relevant</p>
                      <textarea
                        value={reportForm.attendance}
                        onChange={handleReportFormChange("attendance")}
                        placeholder="e.g. 45 participants (30 staff, 15 external)"
                        rows={2}
                      />
                    </label>
                    <label className="form-field">
                      <span>Program / agenda <em>(required)</em></span>
                      <p className="form-hint">Sessions or activities with times</p>
                      <textarea
                        value={reportForm.programAgenda}
                        onChange={handleReportFormChange("programAgenda")}
                        placeholder="e.g. 10:00–10:30 Intro, 10:30–12:00 Session 1…"
                        rows={4}
                      />
                    </label>
                    <label className="form-field">
                      <span>Outcomes and learnings <em>(required)</em></span>
                      <p className="form-hint">Key takeaways and feedback highlights</p>
                      <textarea
                        value={reportForm.outcomesLearnings}
                        onChange={handleReportFormChange("outcomesLearnings")}
                        placeholder="e.g. Participants reported… Next steps include…"
                        rows={4}
                      />
                    </label>
                    <label className="form-field">
                      <span>Follow-up <em>(optional)</em></span>
                      <p className="form-hint">Action items or next steps</p>
                      <textarea
                        value={reportForm.followUp}
                        onChange={handleReportFormChange("followUp")}
                        placeholder="e.g. Send follow-up survey by…"
                        rows={2}
                      />
                    </label>
                    <div className="form-field">
                      <span>Appendix <em>(optional)</em></span>
                      <p className="form-hint">Any additional notes, photos summary, or supporting material</p>
                      <textarea
                        value={reportForm.appendix}
                        onChange={handleReportFormChange("appendix")}
                        placeholder="e.g. Key photos uploaded separately; feedback quotes…"
                        rows={2}
                      />
                      <p className="form-hint" style={{ marginTop: "8px" }}>Upload photos to include in the report PDF</p>
                      <input
                        type="file"
                        accept="image/jpeg,image/png,image/webp,image/gif"
                        multiple
                        onChange={handleAppendixPhotosChange}
                        className="report-appendix-file-input"
                      />
                      {reportAppendixPhotos.length > 0 ? (
                        <ul className="report-appendix-photos">
                          {reportAppendixPhotos.map((file, index) => (
                            <li key={index}>
                              <span className="report-appendix-photo-name">{file.name}</span>
                              <button
                                type="button"
                                className="report-appendix-photo-remove"
                                onClick={() => removeAppendixPhoto(index)}
                                aria-label={`Remove ${file.name}`}
                              >
                                ×
                              </button>
                            </li>
                          ))}
                        </ul>
                      ) : null}
                    </div>
                    {canAccessIqac ? (
                      <div className="form-field report-iqac-section">
                        <span>IQAC Data Collection (optional)</span>
                        <p className="form-hint">
                          Choose criterion, then sub-criterion, then evidence item to store a copy of this report in IQAC Data Collection.
                        </p>
                        {reportIqacCriteria.status === "loading" ? (
                          <p className="form-hint">Loading IQAC structure…</p>
                        ) : null}
                        {reportIqacCriteria.status === "error" ? (
                          <p className="form-error">{reportIqacCriteria.error}</p>
                        ) : null}
                        {reportIqacCriteria.status === "ready" ? (
                          <>
                            <label className="form-field report-iqac-row">
                              <span>Criterion</span>
                              <select value={reportIqacSelection.criterionId} onChange={handleReportIqacCriterionChange}>
                                <option value="">— Do not file to IQAC —</option>
                                {reportIqacCriteria.items.map((c) => (
                                  <option key={c.id} value={String(c.id)}>
                                    {c.id}. {c.title}
                                  </option>
                                ))}
                              </select>
                            </label>
                            {reportIqacSelection.criterionId ? (
                              <label className="form-field report-iqac-row">
                                <span>Sub-criterion</span>
                                <select value={reportIqacSelection.subFolderId} onChange={handleReportIqacSubChange}>
                                  <option value="">— Select —</option>
                                  {(reportIqacCriteria.items.find((c) => String(c.id) === reportIqacSelection.criterionId)?.subFolders || []).map((s) => (
                                    <option key={s.id} value={s.id}>
                                      {s.id} {s.title}
                                    </option>
                                  ))}
                                </select>
                              </label>
                            ) : null}
                            {reportIqacSelection.criterionId && reportIqacSelection.subFolderId ? (
                              <label className="form-field report-iqac-row">
                                <span>Evidence item</span>
                                <select value={reportIqacSelection.itemId} onChange={handleReportIqacItemChange}>
                                  <option value="">— Select —</option>
                                  {(
                                    reportIqacCriteria.items
                                      .find((c) => String(c.id) === reportIqacSelection.criterionId)
                                      ?.subFolders?.find((s) => s.id === reportIqacSelection.subFolderId)?.items || []
                                  ).map((it) => (
                                    <option key={it.id} value={it.id}>
                                      {it.id} {it.title}
                                    </option>
                                  ))}
                                </select>
                              </label>
                            ) : null}
                            {reportIqacSelection.criterionId && reportIqacSelection.subFolderId && reportIqacSelection.itemId ? (
                              <label className="form-field report-iqac-row">
                                <span>IQAC note (optional)</span>
                                <input
                                  type="text"
                                  value={reportIqacSelection.description}
                                  onChange={handleReportIqacDescChange}
                                  placeholder="Additional note stored with the file in IQAC"
                                />
                              </label>
                            ) : null}
                          </>
                        ) : null}
                      </div>
                    ) : null}
                    <p className="form-hint report-save-hint">
                      Report will be saved as PDF: <strong>{getExpectedReportFilename(reportModal.eventName, reportModal.startDate)}</strong>
                    </p>
                    {reportModal.status === "error" ? (
                      <p className="form-error">{reportModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleReportClose}>
                        Cancel
                      </button>
                      <button type="submit" className="primary-action" disabled={reportModal.status === "loading"}>
                        {reportModal.status === "loading" ? "Generating & uploading…" : "Generate PDF & upload"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}
          </div>
        );
      }

      if (isIqacData) {
        if (!canAccessIqac) {
          return (
            <div className="admin-empty">
              <p>IQAC access required.</p>
            </div>
          );
        }
        return <IqacDataPage canDeleteIqacFiles={canDeleteIqacFiles} />;
      }

      if (isPublications) {
        /** Format a single publication as MLA-style citation. Uses *asterisks* for italicized container titles. */
        const formatPublicationMLA = (item) => {
          const pt = item.pub_type;
          const author =
            item.author_last_name && item.author_first_name
              ? `${item.author_last_name} ${item.author_first_name}`.trim()
              : item.author?.trim();
          const addPeriod = (s) => (s && !/\.$/.test(s) ? `${s}.` : s || "");

          if (pt === "webpage") {
            const pageTitle = item.page_title?.trim();
            const site = item.website_name?.trim();
            const date = item.publication_date?.trim();
            const url = item.url?.trim();
            const parts = [];
            if (author) parts.push(addPeriod(author));
            if (pageTitle) parts.push(`"${addPeriod(pageTitle).replace(/\.$/, "")}"`);
            if (site) parts.push(`*${addPeriod(site).replace(/\.$/, "")}*`);
            if (date) parts.push(date);
            if (url) parts.push(url);
            return parts.join(", ");
          }
          if (pt === "journal_article") {
            const artTitle = item.article_title?.trim();
            const journal = item.journal_name?.trim();
            const vol = item.volume?.trim();
            const no = item.issue?.trim();
            const year = item.year?.trim();
            const pp = item.pages?.trim();
            const doi = item.doi?.trim();
            const parts = [];
            if (author) parts.push(addPeriod(author));
            if (artTitle) parts.push(`"${addPeriod(artTitle).replace(/\.$/, "")}"`);
            if (journal) parts.push(`*${addPeriod(journal).replace(/\.$/, "")}*`);
            const volNo = [vol && `vol. ${vol}`, no && `no. ${no}`].filter(Boolean).join(", ");
            if (volNo) parts.push(volNo);
            if (year) parts.push(year);
            if (pp) parts.push(`pp. ${pp}`);
            if (doi) parts.push(`https://doi.org/${doi.replace(/^https?:\/\/doi\.org\/?/i, "")}`);
            return parts.join(", ");
          }
          if (pt === "book") {
            const title = item.book_title?.trim();
            const pub = item.publisher?.trim();
            const year = item.year?.trim();
            const ed = item.edition?.trim();
            const parts = [];
            if (author) parts.push(addPeriod(author));
            if (title) parts.push(`*${addPeriod(title).replace(/\.$/, "")}*`);
            if (ed) parts.push(`${ed} ed.`);
            if (pub) parts.push(pub);
            if (year) parts.push(year);
            return parts.join(", ");
          }
          if (pt === "report") {
            const org = item.organization?.trim();
            const title = item.report_title?.trim();
            const pub = item.publisher?.trim();
            const year = item.year?.trim();
            const parts = [];
            if (org) parts.push(addPeriod(org));
            if (title) parts.push(`*${addPeriod(title).replace(/\.$/, "")}*`);
            if (pub) parts.push(pub);
            if (year) parts.push(year);
            return parts.join(", ");
          }
          if (pt === "video") {
            const creator = item.creator?.trim();
            const title = item.video_title?.trim();
            const platform = item.platform?.trim();
            const date = item.publication_date?.trim();
            const url = item.url?.trim();
            const parts = [];
            if (creator) parts.push(addPeriod(creator));
            if (title) parts.push(`"${addPeriod(title).replace(/\.$/, "")}"`);
            if (platform) parts.push(`*${addPeriod(platform).replace(/\.$/, "")}*`);
            if (date) parts.push(date);
            if (url) parts.push(url);
            return parts.join(", ");
          }
          if (pt === "online_newspaper") {
            const artTitle = item.article_title?.trim() || item.title?.trim();
            const paper = item.newspaper_name?.trim();
            const date = item.publication_date?.trim();
            const url = item.url?.trim();
            const parts = [];
            if (author) parts.push(addPeriod(author));
            if (artTitle) parts.push(`"${addPeriod(artTitle).replace(/\.$/, "")}"`);
            if (paper) parts.push(`*${addPeriod(paper).replace(/\.$/, "")}*`);
            if (date) parts.push(date);
            if (url) parts.push(url);
            return parts.join(", ");
          }
          return item.title || item.name || "Untitled";
        };

        const renderMlaCitation = (citation) => {
          if (!citation) return null;
          return citation.split(/(\*[^*]+\*)/g).map((seg, i) =>
            seg.startsWith("*") && seg.endsWith("*") ? (
              <em key={i} className="mla-italic">{seg.slice(1, -1)}</em>
            ) : (
              <span key={i}>{seg}</span>
            )
          );
        };

        const pubTypeIcons = {
          webpage: (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20"/></svg>
          ),
          journal_article: (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>
          ),
          book: (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 19.5A2.5 2.5 0 016.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z"/></svg>
          ),
          report: (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="18" y1="12" x2="6" y2="12"/><line x1="18" y1="16" x2="6" y2="16"/><polyline points="10 6 9 6 8 6"/></svg>
          ),
          video: (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>
          ),
          online_newspaper: (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 22h16a2 2 0 002-2V4a2 2 0 00-2-2H8a2 2 0 00-2 2v16a4 4 0 01-4-4V6"/><line x1="12" y1="10" x2="18" y2="10"/><line x1="12" y1="14" x2="18" y2="14"/><rect x="8" y="10" width="2" height="4"/></svg>
          ),
        };

        const allPubItems = Array.isArray(publicationsState.items) ? publicationsState.items : [];
        const filteredPubItems = !publicationTypeFilter
          ? allPubItems
          : allPubItems.filter((item) => (item.pub_type || "") === publicationTypeFilter);

        return (
          <div className="primary-column">
            <div className="pub-page-header">
              <div className="pub-page-title-group">
                <h2 className="pub-page-title">Publications</h2>
                {publicationsState.status === "ready" && (
                  <span className="pub-page-count">{filteredPubItems.length}</span>
                )}
              </div>
              <div className="pub-page-header-actions">
                <button type="button" className="primary-action pub-new-btn" onClick={handlePublicationOpen}>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
                  New Publication
                </button>
                <div className="pub-filter-group">
                  <div className="pub-select-wrapper">
                    <svg className="pub-select-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20"/></svg>
                    <select
                      value={publicationTypeFilter}
                      onChange={(e) => setPublicationTypeFilter(e.target.value)}
                      className="pub-styled-select"
                      aria-label="Filter by publication type"
                    >
                      <option value="">All types</option>
                      {Object.entries(PUB_META).map(([key, { label }]) => (
                        <option key={key} value={key}>{label}</option>
                      ))}
                    </select>
                    <svg className="pub-select-caret" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
                  </div>
                  <div className="pub-select-wrapper">
                    <svg className="pub-select-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
                    <select
                      value={publicationSort}
                      onChange={(e) => setPublicationSort(e.target.value)}
                      className="pub-styled-select"
                      aria-label="Sort publications"
                    >
                      <option value="date_desc">Newest first</option>
                      <option value="date_asc">Oldest first</option>
                      <option value="title_asc">Title (A–Z)</option>
                      <option value="title_desc">Title (Z–A)</option>
                    </select>
                    <svg className="pub-select-caret" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
                  </div>
                </div>
              </div>
            </div>

            {/* ── Publications list (MLA style) ── */}
            {publicationsState.status === "loading" ? (
              <ul className="pub-mla-list" aria-label="Loading publications">
                {Array.from({ length: 4 }).map((_, i) => (
                  <li key={i} className="pub-mla-list-item pub-skeleton-item">
                    <div className="skeleton-line" style={{ height: "14px", width: "85%", display: "block" }} />
                    <div className="skeleton-line" style={{ height: "14px", width: "60%", display: "block", marginTop: "6px" }} />
                    <div style={{ display: "flex", gap: "8px", marginTop: "8px" }}>
                      <div className="skeleton-line" style={{ height: "22px", width: "80px", borderRadius: "999px", display: "block" }} />
                      <div className="skeleton-line" style={{ height: "22px", width: "90px", borderRadius: "8px", display: "block" }} />
                    </div>
                  </li>
                ))}
              </ul>
            ) : publicationsState.status === "error" ? (
              <div className="pub-list-empty"><p className="form-error">{publicationsState.error}</p></div>
            ) : publicationsState.status === "ready" && allPubItems.length === 0 ? (
              <div className="pub-list-empty">
                <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="#c4c9d4" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><path d="M4 19.5A2.5 2.5 0 016.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z"/></svg>
                <p className="pub-empty-title">No publications yet</p>
                <p className="pub-empty-sub">Click <strong>+ New Publication</strong> to add your first one.</p>
              </div>
            ) : filteredPubItems.length === 0 && allPubItems.length > 0 ? (
              <div className="pub-list-empty">
                <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="#c4c9d4" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
                <p className="pub-empty-title">No publications of this type</p>
                <p className="pub-empty-sub">Try selecting "All types" or another type.</p>
              </div>
            ) : (
              <ul className="pub-mla-list" aria-label="Publications">
                {filteredPubItems.map((item) => {
                  const meta = PUB_META[item.pub_type] || { icon: "📋", label: item.pub_type || "Unknown", color: "#666" };
                  const citation = formatPublicationMLA(item);
                  const linkUrl = item.web_view_link || item.url;
                  const isFile = Boolean(item.web_view_link);
                  const linkLabel = item.web_view_link ? "View file" : item.url ? "Visit URL" : null;
                  return (
                    <li key={item.id} className="pub-mla-list-item">
                      <div className="pub-mla-citation">
                        {renderMlaCitation(citation)}
                      </div>
                      {item.others?.trim() && (
                        <p className="pub-mla-notes">{item.others}</p>
                      )}
                      <div className="pub-mla-meta">
                        <span className={`pub-type-badge pub-type-${item.pub_type || "unknown"}`}>
                          <span className="pub-badge-icon">{pubTypeIcons[item.pub_type] || null}</span>
                          {meta.label}
                        </span>
                        {linkLabel && (
                          <button
                            type="button"
                            className={`pub-action-btn ${isFile ? "pub-action-file" : "pub-action-url"}`}
                            onClick={() => window.open(linkUrl, "_blank", "noopener,noreferrer")}
                          >
                            {isFile ? (
                              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                            ) : (
                              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>
                            )}
                            {linkLabel}
                          </button>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}


            {/* ── Publication type-selection modal ── */}
            {publicationTypeModal.open ? (
              <div className="modal-overlay pub-type-overlay" role="dialog" aria-modal="true">
                <div className="modal-card pub-type-modal-card">
                  <div className="modal-header">
                    <div>
                      <h3>Add New Publication</h3>
                      <p className="pub-type-subtitle">Select the type of publication you want to add</p>
                    </div>
                    <button type="button" className="modal-close" onClick={handlePublicationTypeClose}>
                      &times;
                    </button>
                  </div>
                  <div className="pub-type-grid">
                    {[
                      {
                        key: "webpage",
                        icon: <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20"/></svg>,
                        label: "Webpage",
                        desc: "Information from a specific page on a website",
                        color: "#2c7a7b"
                      },
                      {
                        key: "journal_article",
                        icon: <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/></svg>,
                        label: "Journal Article",
                        desc: "Peer-reviewed academic or scholarly journal articles",
                        color: "#553c9a"
                      },
                      {
                        key: "book",
                        icon: <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M4 19.5A2.5 2.5 0 016.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z"/></svg>,
                        label: "Book",
                        desc: "Printed book or e-book with publisher info",
                        color: "#c05621"
                      },
                      {
                        key: "report",
                        icon: <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/><line x1="2" y1="20" x2="22" y2="20"/></svg>,
                        label: "Report",
                        desc: "Research, policy or statistical reports by organizations",
                        color: "#2b6cb0"
                      },
                      {
                        key: "video",
                        icon: <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>,
                        label: "Video",
                        desc: "Online videos from YouTube, Vimeo or platforms",
                        color: "#c53030"
                      },
                      {
                        key: "online_newspaper",
                        icon: <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d="M4 22h16a2 2 0 002-2V4a2 2 0 00-2-2H8a2 2 0 00-2 2v16a4 4 0 01-4-4V6"/><line x1="12" y1="10" x2="18" y2="10"/><line x1="12" y1="14" x2="18" y2="14"/><rect x="8" y="10" width="2" height="4"/></svg>,
                        label: "Online Newspaper",
                        desc: "Articles published in online news websites",
                        color: "#276749"
                      }
                    ].map((type) => (
                      <button
                        key={type.key}
                        type="button"
                        className="pub-type-card"
                        style={{ "--pub-card-color": type.color }}
                        onClick={() => handlePublicationTypeSelect(type.key)}
                      >
                        <span className="pub-type-icon" aria-hidden="true" style={{ color: type.color }}>{type.icon}</span>
                        <span className="pub-type-card-label">{type.label}</span>
                        <span className="pub-type-card-desc">{type.desc}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            ) : null}

            {/* ── Publication form modal (type-specific) ── */}
            {publicationModal.open ? (
              <div className="modal-overlay" role="dialog" aria-modal="true">
                <div className="modal-card pub-form-card">
                  <div className="modal-header">
                    <div>
                      <h3 className="pub-form-modal-title">
                        {{
                          webpage: <><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#2c7a7b" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20"/></svg> Webpage Citation</>,
                          journal_article: <><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#553c9a" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/></svg> Journal Article Citation</>,
                          book: <><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#c05621" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 19.5A2.5 2.5 0 016.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z"/></svg> Book Citation</>,
                          report: <><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#2b6cb0" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/><line x1="2" y1="20" x2="22" y2="20"/></svg> Report Citation</>,
                          video: <><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#c53030" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg> Video Citation</>,
                          online_newspaper: <><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#276749" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M4 22h16a2 2 0 002-2V4a2 2 0 00-2-2H8a2 2 0 00-2 2v16a4 4 0 01-4-4V6"/><line x1="12" y1="10" x2="18" y2="10"/><line x1="12" y1="14" x2="18" y2="14"/></svg> Online Newspaper Citation</>
                        }[publicationForm.pubType] || "New Publication"}
                      </h3>
                    </div>
                    <button type="button" className="modal-close" onClick={handlePublicationClose}>
                      &times;
                    </button>
                  </div>
                  <form className="pub-form" onSubmit={submitPublication}>
                    {/* Common: Label */}
                    <label className="form-field">
                      <span>Record Label <span className="req">*</span></span>
                      <input
                        type="text"
                        placeholder="Short identifier, e.g. Smith2024"
                        value={publicationForm.name}
                        onChange={handlePublicationChange("name")}
                        required
                      />
                    </label>

                    {/* ── WEBPAGE ── */}
                    {publicationForm.pubType === "webpage" ? (
                      <>
                        <div className="pub-form-row">
                          <label className="form-field">
                            <span>Author First Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. John" value={publicationForm.author_first_name} onChange={handlePublicationChange("author_first_name")} />
                          </label>
                          <label className="form-field">
                            <span>Author Last Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. Smith" value={publicationForm.author_last_name} onChange={handlePublicationChange("author_last_name")} />
                          </label>
                        </div>
                        <label className="form-field">
                          <span>Page Title <span className="req">*</span></span>
                          <input type="text" placeholder="Title of the specific page" value={publicationForm.page_title} onChange={handlePublicationChange("page_title")} />
                        </label>
                        <label className="form-field">
                          <span>Website Name <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. Wikipedia" value={publicationForm.website_name} onChange={handlePublicationChange("website_name")} />
                        </label>
                        <label className="form-field">
                          <span>URL <span className="req">*</span></span>
                          <input type="url" placeholder="https://..." value={publicationForm.url} onChange={handlePublicationChange("url")} />
                        </label>
                        <label className="form-field">
                          <span>Publication Date</span>
                          <input type="text" placeholder="e.g. 15 Jan 2024" value={publicationForm.publication_date} onChange={handlePublicationChange("publication_date")} />
                        </label>
                      </>
                    ) : null}

                    {/* ── JOURNAL ARTICLE ── */}
                    {publicationForm.pubType === "journal_article" ? (
                      <>
                        <div className="pub-form-row">
                          <label className="form-field">
                            <span>Author First Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. John" value={publicationForm.author_first_name} onChange={handlePublicationChange("author_first_name")} />
                          </label>
                          <label className="form-field">
                            <span>Author Last Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. Smith" value={publicationForm.author_last_name} onChange={handlePublicationChange("author_last_name")} />
                          </label>
                        </div>
                        <label className="form-field">
                          <span>Article Title <span className="req">*</span></span>
                          <input type="text" placeholder="Full title of the article" value={publicationForm.article_title} onChange={handlePublicationChange("article_title")} />
                        </label>
                        <label className="form-field">
                          <span>Journal Name <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. Nature" value={publicationForm.journal_name} onChange={handlePublicationChange("journal_name")} />
                        </label>
                        <label className="form-field">
                          <span>Year <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. 2024" value={publicationForm.year} onChange={handlePublicationChange("year")} />
                        </label>
                        <div className="pub-form-row">
                          <label className="form-field">
                            <span>Volume</span>
                            <input type="text" placeholder="e.g. 12" value={publicationForm.volume} onChange={handlePublicationChange("volume")} />
                          </label>
                          <label className="form-field">
                            <span>Issue</span>
                            <input type="text" placeholder="e.g. 3" value={publicationForm.issue} onChange={handlePublicationChange("issue")} />
                          </label>
                          <label className="form-field">
                            <span>Pages</span>
                            <input type="text" placeholder="e.g. 45–60" value={publicationForm.pages} onChange={handlePublicationChange("pages")} />
                          </label>
                        </div>
                        <label className="form-field">
                          <span>DOI</span>
                          <input type="text" placeholder="e.g. 10.1000/xyz123" value={publicationForm.doi} onChange={handlePublicationChange("doi")} />
                        </label>
                        <label className="form-field">
                          <span>PDF File (optional, max 10 MB)</span>
                          <input type="file" accept=".pdf,application/pdf" onChange={handlePublicationChange("file")} />
                        </label>
                      </>
                    ) : null}

                    {/* ── BOOK ── */}
                    {publicationForm.pubType === "book" ? (
                      <>
                        <div className="pub-form-row">
                          <label className="form-field">
                            <span>Author First Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. John" value={publicationForm.author_first_name} onChange={handlePublicationChange("author_first_name")} />
                          </label>
                          <label className="form-field">
                            <span>Author Last Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. Smith" value={publicationForm.author_last_name} onChange={handlePublicationChange("author_last_name")} />
                          </label>
                        </div>
                        <label className="form-field">
                          <span>Book Title <span className="req">*</span></span>
                          <input type="text" placeholder="Full title of the book" value={publicationForm.book_title} onChange={handlePublicationChange("book_title")} />
                        </label>
                        <label className="form-field">
                          <span>Publisher <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. Oxford University Press" value={publicationForm.publisher} onChange={handlePublicationChange("publisher")} />
                        </label>
                        <label className="form-field">
                          <span>Year <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. 2022" value={publicationForm.year} onChange={handlePublicationChange("year")} />
                        </label>
                        <div className="pub-form-row">
                          <label className="form-field">
                            <span>Edition</span>
                            <input type="text" placeholder="e.g. 3rd" value={publicationForm.edition} onChange={handlePublicationChange("edition")} />
                          </label>
                          <label className="form-field">
                            <span>Page Number</span>
                            <input type="text" placeholder="e.g. 142" value={publicationForm.page_number} onChange={handlePublicationChange("page_number")} />
                          </label>
                        </div>
                        <label className="form-field">
                          <span>PDF File (optional, max 10 MB)</span>
                          <input type="file" accept=".pdf,application/pdf" onChange={handlePublicationChange("file")} />
                        </label>
                      </>
                    ) : null}

                    {/* ── REPORT ── */}
                    {publicationForm.pubType === "report" ? (
                      <>
                        <label className="form-field">
                          <span>Organization <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. WHO, UNESCO" value={publicationForm.organization} onChange={handlePublicationChange("organization")} />
                        </label>
                        <label className="form-field">
                          <span>Report Title <span className="req">*</span></span>
                          <input type="text" placeholder="Full title of the report" value={publicationForm.report_title} onChange={handlePublicationChange("report_title")} />
                        </label>
                        <label className="form-field">
                          <span>Publisher <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. World Health Organization" value={publicationForm.publisher} onChange={handlePublicationChange("publisher")} />
                        </label>
                        <label className="form-field">
                          <span>Year <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. 2023" value={publicationForm.year} onChange={handlePublicationChange("year")} />
                        </label>
                        <label className="form-field">
                          <span>PDF File (optional, max 10 MB)</span>
                          <input type="file" accept=".pdf,application/pdf" onChange={handlePublicationChange("file")} />
                        </label>
                      </>
                    ) : null}

                    {/* ── VIDEO ── */}
                    {publicationForm.pubType === "video" ? (
                      <>
                        <label className="form-field">
                          <span>Creator / Uploader <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. Khan Academy" value={publicationForm.creator} onChange={handlePublicationChange("creator")} />
                        </label>
                        <label className="form-field">
                          <span>Video Title <span className="req">*</span></span>
                          <input type="text" placeholder="Full title of the video" value={publicationForm.video_title} onChange={handlePublicationChange("video_title")} />
                        </label>
                        <label className="form-field">
                          <span>Platform <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. YouTube, Vimeo" value={publicationForm.platform} onChange={handlePublicationChange("platform")} />
                        </label>
                        <label className="form-field">
                          <span>Date <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. 5 March 2024" value={publicationForm.publication_date} onChange={handlePublicationChange("publication_date")} />
                        </label>
                        <label className="form-field">
                          <span>URL <span className="req">*</span></span>
                          <input type="url" placeholder="https://..." value={publicationForm.url} onChange={handlePublicationChange("url")} />
                        </label>
                      </>
                    ) : null}

                    {/* ── ONLINE NEWSPAPER ── */}
                    {publicationForm.pubType === "online_newspaper" ? (
                      <>
                        <div className="pub-form-row">
                          <label className="form-field">
                            <span>Author First Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. Jane" value={publicationForm.author_first_name} onChange={handlePublicationChange("author_first_name")} />
                          </label>
                          <label className="form-field">
                            <span>Author Last Name <span className="req">*</span></span>
                            <input type="text" placeholder="e.g. Doe" value={publicationForm.author_last_name} onChange={handlePublicationChange("author_last_name")} />
                          </label>
                        </div>
                        <label className="form-field">
                          <span>Article Title <span className="req">*</span></span>
                          <input type="text" placeholder="Full title of the article" value={publicationForm.article_title} onChange={handlePublicationChange("article_title")} />
                        </label>
                        <label className="form-field">
                          <span>Newspaper Name <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. The Guardian" value={publicationForm.newspaper_name} onChange={handlePublicationChange("newspaper_name")} />
                        </label>
                        <label className="form-field">
                          <span>Publication Date <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. 10 Feb 2024" value={publicationForm.publication_date} onChange={handlePublicationChange("publication_date")} />
                        </label>
                        <label className="form-field">
                          <span>URL <span className="req">*</span></span>
                          <input type="url" placeholder="https://..." value={publicationForm.url} onChange={handlePublicationChange("url")} />
                        </label>
                      </>
                    ) : null}

                    {/* Common: Notes */}
                    <label className="form-field">
                      <span>Additional Notes</span>
                      <textarea
                        rows="2"
                        placeholder="Any extra details..."
                        value={publicationForm.others}
                        onChange={handlePublicationChange("others")}
                      />
                    </label>

                    {publicationModal.status === "error" ? (
                      <p className="form-error">{publicationModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={() => { handlePublicationClose(); handlePublicationTypeOpen(); }}>
                        ← Back
                      </button>
                      <button type="button" className="secondary-action" onClick={handlePublicationClose}>
                        Cancel
                      </button>
                      <button type="submit" className="primary-action" disabled={publicationModal.status === "loading"}>
                        {publicationModal.status === "loading" ? "Submitting..." : "Submit"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}
          </div>
        );
      }


      if (isCalendar) {
        const calendarInitialView = window.innerWidth < 768 ? "timeGridDay" : window.innerWidth < 1024 ? "timeGridWeek" : "dayGridMonth";
        return (
          <div className="primary-column">
            <div className="calendar-card">
              <div className="calendar-toolbar">
                <div>
                  <h3>Calendar</h3>
                  <p className="calendar-subtitle">All approved events</p>
                </div>
                <div className="calendar-actions">
                  <button type="button" className="secondary-action" onClick={() => fetchCalendarEvents()}>
                    Refresh
                  </button>
                  <button type="button" className="primary-action" onClick={handleCalendarConnect}>
                    Connect Google Calendar
                  </button>
                </div>
              </div>

              {calendarState.status === "loading" ? (
                <p className="calendar-message">Loading events...</p>
              ) : null}

              {calendarState.status === "needs_auth" ? (
                <p className="calendar-message">{calendarState.error}</p>
              ) : null}

              {calendarState.status === "error" ? (
                <p className="calendar-message">{calendarState.error}</p>
              ) : null}

              <div className="calendar-shell">
                <FullCalendar
                  plugins={[dayGridPlugin, timeGridPlugin, interactionPlugin]}
                  initialView={calendarInitialView}
                  timeZone="Asia/Kolkata"
                  eventTimeFormat={{ hour: "numeric", minute: "2-digit", meridiem: "short" }}
                  headerToolbar={{
                    left: "prev,next today",
                    center: "title",
                    right: "dayGridMonth,timeGridWeek,timeGridDay"
                  }}
                  height="auto"
                  editable
                  eventResizableFromStart
                  events={calendarState.events}
                  datesSet={(info) => fetchCalendarEvents({ start: info.start, end: info.end })}
                  eventClick={(info) => {
                    info.jsEvent.preventDefault();
                    const evt = info.event;
                    setCalendarDetailModal({
                      open: true,
                      event: {
                        title: evt.title,
                        start: evt.start,
                        end: evt.end,
                        location: evt.extendedProps?.location || "",
                        url: evt.url || ""
                      }
                    });
                  }}
                  eventDidMount={(info) => {
                    const evt = info.event;
                    const loc = evt.extendedProps?.location;
                    const startStr = evt.start
                      ? evt.start.toLocaleString("en-IN", { timeZone: "Asia/Kolkata", dateStyle: "medium", timeStyle: "short" })
                      : "";
                    const endStr = evt.end
                      ? evt.end.toLocaleString("en-IN", { timeZone: "Asia/Kolkata", timeStyle: "short" })
                      : "";
                    const tooltipHtml = `<strong>${evt.title}</strong>${startStr ? `<br/>${startStr}${endStr ? " – " + endStr : ""}` : ""}${loc ? `<br/>📍 ${loc}` : ""}`;
                    tippy(info.el, {
                      content: tooltipHtml,
                      allowHTML: true,
                      placement: "top",
                      theme: "calendar-tooltip",
                      delay: [200, 0],
                      animation: "shift-away",
                      arrow: true
                    });

                    const title = (evt.title || "").toLowerCase();
                    let color = "var(--accent-blue)";
                    if (title.includes("workshop")) color = "#6366f1";
                    else if (title.includes("seminar")) color = "#0891b2";
                    else if (title.includes("meeting")) color = "#059669";
                    else if (title.includes("cultural") || title.includes("fest")) color = "#d946ef";
                    else if (title.includes("exam") || title.includes("test")) color = "#dc2626";
                    else if (title.includes("holiday") || title.includes("break")) color = "#f59e0b";
                    else if (title.includes("sports") || title.includes("athletic")) color = "#10b981";
                    info.el.style.backgroundColor = color;
                    info.el.style.borderColor = color;
                  }}
                />
              </div>
            </div>

            {calendarDetailModal.open && calendarDetailModal.event ? (
              <Modal
                title="Event Details"
                onClose={() => setCalendarDetailModal({ open: false, event: null })}
                className="calendar-detail-modal"
                actions={
                  calendarDetailModal.event.url ? (
                    <a
                      href={calendarDetailModal.event.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="primary-action"
                    >
                      Open in Google Calendar
                    </a>
                  ) : null
                }
              >
                <div className="modal-body calendar-detail-body">
                  <div className="cal-detail-row">
                    <span className="cal-detail-label">Title</span>
                    <span className="cal-detail-value">{calendarDetailModal.event.title}</span>
                  </div>
                  {calendarDetailModal.event.start ? (
                    <div className="cal-detail-row">
                      <span className="cal-detail-label">Start</span>
                      <span className="cal-detail-value">
                        {calendarDetailModal.event.start.toLocaleString("en-IN", {
                          timeZone: "Asia/Kolkata",
                          dateStyle: "full",
                          timeStyle: "short"
                        })}
                      </span>
                    </div>
                  ) : null}
                  {calendarDetailModal.event.end ? (
                    <div className="cal-detail-row">
                      <span className="cal-detail-label">End</span>
                      <span className="cal-detail-value">
                        {calendarDetailModal.event.end.toLocaleString("en-IN", {
                          timeZone: "Asia/Kolkata",
                          dateStyle: "full",
                          timeStyle: "short"
                        })}
                      </span>
                    </div>
                  ) : null}
                  {calendarDetailModal.event.location ? (
                    <div className="cal-detail-row">
                      <span className="cal-detail-label">Venue</span>
                      <span className="cal-detail-value">{calendarDetailModal.event.location}</span>
                    </div>
                  ) : null}
                </div>
              </Modal>
            ) : null}
          </div>
        );
      }

      if (isApprovals || isRequirements) {
        return (
          <div className="primary-column">
            {!showApprovalsOrRequirementsContent ? (
              <div className="events-table-card">
                <p className="table-message">
                  {isApprovals ? "You do not have access to approvals." : "You do not have access to requirements."}
                </p>
              </div>
            ) : null}
            {showApprovalsOrRequirementsContent ? (
            <>
            <div className="approvals-tabs">
              {isApproverRole ? (
                <button
                  type="button"
                  className={`tab-button ${approvalsTab === "approval-requests" ? "active" : ""}`}
                  onClick={() => setApprovalsTab("approval-requests")}
                >
                  Approval Requests
                  {approvalsState.status === "ready" && workflowInboxAttentionCount(approvalsState.items) > 0 ? (
                    <span className="tab-badge">{workflowInboxAttentionCount(approvalsState.items)}</span>
                  ) : null}
                </button>
              ) : null}
              {isFacilityManagerRole ? (
                <button
                  type="button"
                  className={`tab-button ${approvalsTab === "facility" ? "active" : ""}`}
                  onClick={() => setApprovalsTab("facility")}
                >
                  Facility Manager
                  {facilityState.status === "ready" && workflowInboxAttentionCount(facilityState.items) > 0 ? (
                    <span className="tab-badge">{workflowInboxAttentionCount(facilityState.items)}</span>
                  ) : null}
                </button>
              ) : null}
              {isMarketingRole ? (
                <button
                  type="button"
                  className={`tab-button ${approvalsTab === "marketing" ? "active" : ""}`}
                  onClick={() => setApprovalsTab("marketing")}
                >
                  Marketing
                  {marketingState.status === "ready" && workflowInboxAttentionCount(marketingState.items) > 0 ? (
                    <span className="tab-badge">{workflowInboxAttentionCount(marketingState.items)}</span>
                  ) : null}
                </button>
              ) : null}
              {isItRole ? (
                <button
                  type="button"
                  className={`tab-button ${approvalsTab === "it" ? "active" : ""}`}
                  onClick={() => setApprovalsTab("it")}
                >
                  IT
                  {itState.status === "ready" && workflowInboxAttentionCount(itState.items) > 0 ? (
                    <span className="tab-badge">{workflowInboxAttentionCount(itState.items)}</span>
                  ) : null}
                </button>
              ) : null}
              {isTransportRole ? (
                <button
                  type="button"
                  className={`tab-button ${approvalsTab === "transport" ? "active" : ""}`}
                  onClick={() => setApprovalsTab("transport")}
                >
                  Transport
                  {transportState.status === "ready" && workflowInboxAttentionCount(transportState.items) > 0 ? (
                    <span className="tab-badge">{workflowInboxAttentionCount(transportState.items)}</span>
                  ) : null}
                </button>
              ) : null}
            </div>
            {isApproverRole && approvalsTab === "approval-requests" ? (
            <div className="events-table-card">
              <div className="table-header table-header--toolbar">
                <h3>Approval Requests</h3>
                <button type="button" className="refresh-toolbar-btn" onClick={loadApprovalsInbox}>
                  Refresh
                </button>
              </div>
              <div className="events-table">
                <div className="events-table-row header approvals">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Status</span>
                  <span>Actions</span>
                </div>
                {approvalsState.status === "loading" ? (
                  <p className="table-message">Loading approvals...</p>
                ) : null}
                {approvalsState.status === "error" ? (
                  <p className="table-message">{approvalsState.error}</p>
                ) : null}
                {approvalsState.status === "ready" && approvalsState.items.length === 0 ? (
                  <p className="table-message">No approval requests yet.</p>
                ) : null}
                {approvalsState.status === "ready"
                    ? approvalsState.items.map((item) => {
                        const statusLabel = formatInboxDecisionStatusLabel(item.status);
                        const eventHasStarted = isEventStarted(item);
                        const rowAttention = canActOnWorkflowRow(item.status);
                        return (
                          <div
                            key={item.id}
                            className={`events-table-row approvals${rowAttention ? " approvals-row--pending" : ""}`}
                          >
                            <span className="approvals-col-event">{item.event_name}</span>
                            <span className="approvals-col-requester">{item.requester_email}</span>
                            <div className="req-inbox-status-with-details">
                              <span className={`status-pill registrar-status-pill ${item.status}`}>{statusLabel}</span>
                              <button
                                type="button"
                                className="details-button details-button--primary"
                                onClick={() => handleApprovalDetailsOpen(item)}
                              >
                                Details
                              </button>
                            </div>
                            <div className="approval-actions registrar-approval-actions req-inbox-actions">
                              {rowAttention && !eventHasStarted ? (
                                <select
                                  className="workflow-action-select"
                                  aria-label="Choose approval action"
                                  defaultValue=""
                                  onChange={(e) => {
                                    const v = e.target.value;
                                    e.target.value = "";
                                    if (v === "approved") openWorkflowActionModal("approval", item.id, "approved", "Approve");
                                    else if (v === "rejected") openWorkflowActionModal("approval", item.id, "rejected", "Reject");
                                    else if (v === "clarification_requested") {
                                      openWorkflowActionModal(
                                        "approval",
                                        item.id,
                                        "clarification_requested",
                                        "Need clarification"
                                      );
                                    }
                                  }}
                                >
                                  <option value="">Action</option>
                                  <option value="approved">Approve</option>
                                  <option value="rejected">Reject</option>
                                  <option value="clarification_requested">Need clarification</option>
                                </select>
                              ) : (
                                <span className="req-inbox-actions-placeholder" aria-hidden>
                                  —
                                </span>
                              )}
                            </div>
                          </div>
                        );
                    })
                    : null}
              </div>
            </div>
            ) : null}

            {isFacilityManagerRole && approvalsTab === "facility" ? (
            <div className="events-table-card">
              <div className="table-header table-header--toolbar">
                <h3>Facility Manager Requests</h3>
                <button type="button" className="refresh-toolbar-btn" onClick={loadFacilityInbox}>
                  Refresh
                </button>
              </div>
              <div className="events-table">
                <div className="events-table-row header inbox-req-row">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Status</span>
                  <span>Actions</span>
                </div>
                {facilityState.status === "loading" ? (
                  <p className="table-message">Loading facility requests...</p>
                ) : null}
                {facilityState.status === "error" ? (
                  <p className="table-message">{facilityState.error}</p>
                ) : null}
                {facilityState.status === "ready" && facilityState.items.length === 0 ? (
                  <p className="table-message">No facility requests yet.</p>
                ) : null}
                {facilityState.status === "ready"
                  ? facilityState.items.map((item) => {
                      const statusLabel = formatInboxDecisionStatusLabel(item.status);
                      const eventHasStarted = isEventStarted(item);
                      const rowAttention = canActOnWorkflowRow(item.status);
                      return (
                        <div
                          key={item.id}
                          className={`events-table-row inbox-req-row${rowAttention ? " inbox-req-row--pending" : ""}`}
                        >
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <div className="req-inbox-status-with-details">
                            <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                            <button
                              type="button"
                              className="details-button details-button--primary"
                              onClick={() => item.event_id && handleEventDetailsOpen({ id: item.event_id })}
                              title={item.event_id ? "View event details" : "Event details available after approval"}
                              disabled={!item.event_id}
                            >
                              Details
                            </button>
                          </div>
                          <div className="req-inbox-actions">
                            {rowAttention && !eventHasStarted ? (
                              <select
                                className="workflow-action-select"
                                aria-label="Choose facility action"
                                defaultValue=""
                                onChange={(e) => {
                                  const v = e.target.value;
                                  e.target.value = "";
                                  if (v === "approved") openWorkflowActionModal("facility", item.id, "approved", "Approve");
                                  else if (v === "rejected") openWorkflowActionModal("facility", item.id, "rejected", "Reject");
                                  else if (v === "clarification_requested") {
                                    openWorkflowActionModal(
                                      "facility",
                                      item.id,
                                      "clarification_requested",
                                      "Need clarification"
                                    );
                                  }
                                }}
                              >
                                <option value="">Action</option>
                                <option value="approved">Approve</option>
                                <option value="rejected">Reject</option>
                                <option value="clarification_requested">Need clarification</option>
                              </select>
                            ) : (
                              <span className="req-inbox-actions-placeholder">—</span>
                            )}
                          </div>
                        </div>
                      );
                    })
                  : null}
              </div>
            </div>
            ) : null}

            {isMarketingRole && approvalsTab === "marketing" ? (
            <div className="events-table-card">
              <div className="table-header table-header--toolbar">
                <h3>Marketing Requests</h3>
                <button type="button" className="refresh-toolbar-btn" onClick={loadMarketingInbox}>
                  Refresh
                </button>
              </div>
              <div className="events-table">
                <div className="events-table-row header inbox-req-row">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Status</span>
                  <span>Actions</span>
                </div>
                {marketingState.status === "loading" ? (
                  <p className="table-message">Loading marketing requests...</p>
                ) : null}
                {marketingState.status === "error" ? (
                  <p className="table-message">{marketingState.error}</p>
                ) : null}
                {marketingState.status === "ready" && marketingState.items.length === 0 ? (
                  <p className="table-message">No marketing requests yet.</p>
                ) : null}
                {marketingState.status === "ready"
                  ? marketingState.items.map((item) => {
                      const statusLabel = formatInboxDecisionStatusLabel(item.status);
                      const eventHasStarted = isEventStarted(item);
                      const rowAttention = canActOnWorkflowRow(item.status);
                      const marketingHasFileUploads = REQUIREMENT_OPTIONS.some(
                        (opt) => getMarketingDeliverableUploadFlags(item)[opt.key]
                      );
                      return (
                        <div
                          key={item.id}
                          className={`events-table-row inbox-req-row${rowAttention ? " inbox-req-row--pending" : ""}`}
                        >
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <div className="req-inbox-status-with-details">
                            <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                            <button
                              type="button"
                              className="details-button details-button--primary"
                              onClick={() => item.event_id && handleEventDetailsOpen({ id: item.event_id })}
                              title={item.event_id ? "View event details" : "Event details available after approval"}
                              disabled={!item.event_id}
                            >
                              Details
                            </button>
                          </div>
                          <div className="req-inbox-actions">
                            <button
                              type="button"
                              className="details-button upload"
                              disabled={!marketingHasFileUploads}
                              title={
                                marketingHasFileUploads
                                  ? ""
                                  : "No file uploads for this request (during-event videoshoot / photoshoot only)."
                              }
                              onClick={() => openMarketingDeliverableModal(item)}
                            >
                              Upload
                            </button>
                            {rowAttention && !eventHasStarted ? (
                              <select
                                className="workflow-action-select"
                                aria-label="Choose marketing action"
                                defaultValue=""
                                onChange={(e) => {
                                  const v = e.target.value;
                                  e.target.value = "";
                                  if (v === "approved") openWorkflowActionModal("marketing", item.id, "approved", "Approve");
                                  else if (v === "rejected") openWorkflowActionModal("marketing", item.id, "rejected", "Reject");
                                  else if (v === "clarification_requested") {
                                    openWorkflowActionModal(
                                      "marketing",
                                      item.id,
                                      "clarification_requested",
                                      "Need clarification"
                                    );
                                  }
                                }}
                              >
                                <option value="">Action</option>
                                <option value="approved">Approve</option>
                                <option value="rejected">Reject</option>
                                <option value="clarification_requested">Need clarification</option>
                              </select>
                            ) : (
                              <span className="req-inbox-actions-placeholder">—</span>
                            )}
                          </div>
                        </div>
                      );
                    })
                  : null}
              </div>
            </div>
            ) : null}

            {isTransportRole && approvalsTab === "transport" ? (
            <div className="events-table-card">
              <div className="table-header table-header--toolbar">
                <h3>Transport Requests</h3>
                <button type="button" className="refresh-toolbar-btn" onClick={loadTransportInbox}>
                  Refresh
                </button>
              </div>
              <div className="events-table">
                <div className="events-table-row header inbox-req-row">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Status</span>
                  <span>Actions</span>
                </div>
                {transportState.status === "loading" ? (
                  <p className="table-message">Loading transport requests...</p>
                ) : null}
                {transportState.status === "error" ? (
                  <p className="table-message">{transportState.error}</p>
                ) : null}
                {transportState.status === "ready" && transportState.items.length === 0 ? (
                  <p className="table-message">No transport requests yet.</p>
                ) : null}
                {transportState.status === "ready"
                  ? transportState.items.map((item) => {
                      const statusLabel = formatInboxDecisionStatusLabel(item.status);
                      const eventHasStarted = isEventStarted(item);
                      const rowAttention = canActOnWorkflowRow(item.status);
                      return (
                        <div
                          key={item.id}
                          className={`events-table-row inbox-req-row${rowAttention ? " inbox-req-row--pending" : ""}`}
                        >
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <div className="req-inbox-status-with-details">
                            <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                            <button
                              type="button"
                              className="details-button details-button--primary"
                              onClick={() => item.event_id && handleEventDetailsOpen({ id: item.event_id })}
                              title={item.event_id ? "View event details" : "Event details available after approval"}
                              disabled={!item.event_id}
                            >
                              Details
                            </button>
                          </div>
                          <div className="req-inbox-actions">
                            {rowAttention && !eventHasStarted ? (
                              <select
                                className="workflow-action-select"
                                aria-label="Choose transport action"
                                defaultValue=""
                                onChange={(e) => {
                                  const v = e.target.value;
                                  e.target.value = "";
                                  if (v === "approved") openWorkflowActionModal("transport", item.id, "approved", "Approve");
                                  else if (v === "rejected") openWorkflowActionModal("transport", item.id, "rejected", "Reject");
                                  else if (v === "clarification_requested") {
                                    openWorkflowActionModal(
                                      "transport",
                                      item.id,
                                      "clarification_requested",
                                      "Need clarification"
                                    );
                                  }
                                }}
                              >
                                <option value="">Action</option>
                                <option value="approved">Approve</option>
                                <option value="rejected">Reject</option>
                                <option value="clarification_requested">Need clarification</option>
                              </select>
                            ) : (
                              <span className="req-inbox-actions-placeholder">—</span>
                            )}
                          </div>
                        </div>
                      );
                    })
                  : null}
              </div>
            </div>
            ) : null}

            {isItRole && approvalsTab === "it" ? (
            <div className="events-table-card">
              <div className="table-header table-header--toolbar">
                <h3>IT Requests</h3>
                <button type="button" className="refresh-toolbar-btn" onClick={loadItInbox}>
                  Refresh
                </button>
              </div>
              <div className="events-table">
                <div className="events-table-row header inbox-req-row">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Status</span>
                  <span>Actions</span>
                </div>
                {itState.status === "loading" ? (
                  <p className="table-message">Loading IT requests...</p>
                ) : null}
                {itState.status === "error" ? (
                  <p className="table-message">{itState.error}</p>
                ) : null}
                {itState.status === "ready" && itState.items.length === 0 ? (
                  <p className="table-message">No IT requests yet.</p>
                ) : null}
                {itState.status === "ready"
                  ? itState.items.map((item) => {
                      const statusLabel = formatInboxDecisionStatusLabel(item.status);
                      const eventHasStarted = isEventStarted(item);
                      const rowAttention = canActOnWorkflowRow(item.status);
                      return (
                        <div
                          key={item.id}
                          className={`events-table-row inbox-req-row${rowAttention ? " inbox-req-row--pending" : ""}`}
                        >
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <div className="req-inbox-status-with-details">
                            <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                            <button
                              type="button"
                              className="details-button details-button--primary"
                              onClick={() => item.event_id && handleEventDetailsOpen({ id: item.event_id })}
                              title={item.event_id ? "View event details" : "Event details available after approval"}
                              disabled={!item.event_id}
                            >
                              Details
                            </button>
                          </div>
                          <div className="req-inbox-actions">
                            {rowAttention && !eventHasStarted ? (
                              <select
                                className="workflow-action-select"
                                aria-label="Choose IT action"
                                defaultValue=""
                                onChange={(e) => {
                                  const v = e.target.value;
                                  e.target.value = "";
                                  if (v === "approved") openWorkflowActionModal("it", item.id, "approved", "Approve");
                                  else if (v === "rejected") openWorkflowActionModal("it", item.id, "rejected", "Reject");
                                  else if (v === "clarification_requested") {
                                    openWorkflowActionModal(
                                      "it",
                                      item.id,
                                      "clarification_requested",
                                      "Need clarification"
                                    );
                                  }
                                }}
                              >
                                <option value="">Action</option>
                                <option value="approved">Approve</option>
                                <option value="rejected">Reject</option>
                                <option value="clarification_requested">Need clarification</option>
                              </select>
                            ) : (
                              <span className="req-inbox-actions-placeholder">—</span>
                            )}
                          </div>
                        </div>
                      );
                    })
                  : null}
              </div>
            </div>
            ) : null}
            </>
            ) : null}
          </div>
        );
      }

      return (
        <div className="primary-column">
          <div className="events-card">
            <div className="events-header">
              <p>Your Events</p>
              <div className="events-nav">
                <button type="button" className="nav-button">
                  <SimpleIcon path="M15 6 9 12l6 6" />
                </button>
                <button type="button" className="nav-button">
                  <SimpleIcon path="M9 6l6 6-6 6" />
                </button>
              </div>
            </div>
            <div className="events-grid">
              {eventsState.status === "loading" ? (
                <p className="table-message">Loading events...</p>
              ) : null}
              {eventsState.status === "error" ? (
                <p className="table-message">{eventsState.error}</p>
              ) : null}
              {eventsState.status === "ready" && eventsState.items.length === 0 ? (
                <p className="table-message">No events yet. Create your first event.</p>
              ) : null}
              {eventsState.status === "ready" && eventsState.items.length > 0 ? (() => {
                const approvedOnly = eventsState.items.filter((e) => !String(e.id || "").startsWith("approval-") && e.approval_status === "approved");
                const matching = approvedOnly.filter(eventMatchesSearch);
                if (matching.length === 0) {
                  return (
                    <p className="table-message">
                      {approvedOnly.length === 0 ? "No events approved by registrar yet." : "No events match your search."}
                    </p>
                  );
                }
                return null;
              })() : null}
              {eventsState.status === "ready"
                ? eventsState.items
                    .filter((e) => !String(e.id || "").startsWith("approval-") && e.approval_status === "approved")
                    .filter(eventMatchesSearch)
                    .map((event) => {
                    const { statusLabel, statusClass } = getEventStatusInfo(event);
                    return (
                      <article key={event.id} className="event-card">
                        <div className={`event-status ${statusClass}`}>{statusLabel}</div>
                        <div
                          className="event-image"
                          style={{
                            backgroundImage: `linear-gradient(180deg, rgba(13,14,20,0.08) 0%, rgba(13,14,20,0.28) 100%), url(${getEventImageUrl(event)})`
                          }}
                        />
                        <p className="event-title">{event.name}</p>
                        <p className="event-meta">
                          <span className="event-date">{event.start_date}</span>
                          <span className="event-dot">•</span>
                          <span className="event-time">{formatISTTime(event.start_time)}</span>
                        </p>
                      </article>
                    );
                  })
                : null}
            </div>
          </div>
        </div>
      );
    };

    return (
      <MessengerProvider user={user}>
      <div className={`dashboard-page ${mobileMenuOpen ? "mobile-menu-open" : ""}`}>
        {googleScopeModal.open ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card">
              <div className="modal-header">
                <h3>Connect Google</h3>
                <button
                  type="button"
                  className="modal-close"
                  onClick={() => setGoogleScopeModal({ open: false, missing: [] })}
                >
                  &times;
                </button>
              </div>
              <div className="approval-summary">
                <p>
                  Your Google connection is missing permissions needed for calendar,
                  invites, or report uploads. Please connect Google to continue.
                </p>
                {googleScopeModal.missing.length ? (
                  <p>
                    <strong>Missing scopes:</strong> {googleScopeModal.missing.join(", ")}
                  </p>
                ) : null}
              </div>
              <div className="modal-actions">
                <button
                  type="button"
                  className="secondary-action"
                  onClick={() => setGoogleScopeModal({ open: false, missing: [] })}
                >
                  Later
                </button>
                <button type="button" className="primary-action" onClick={handleCalendarConnect}>
                  Connect Google
                </button>
              </div>
            </div>
          </div>
        ) : null}
        {addUserModal.open ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card">
              <div className="modal-header">
                <h3>Add User</h3>
                <button type="button" className="modal-close" onClick={handleAddUserModalClose}>
                  &times;
                </button>
              </div>
              <form className="event-form" onSubmit={handleAddUserSubmit}>
                <label className="form-field">
                  <span>Email</span>
                  <input
                    type="email"
                    placeholder="user@example.edu"
                    value={addUserModal.email}
                    onChange={(e) => setAddUserModal((prev) => ({ ...prev, email: e.target.value }))}
                    required
                  />
                </label>
                <label className="form-field">
                  <span>Role</span>
                  <select
                    value={addUserModal.role}
                    onChange={(e) => setAddUserModal((prev) => ({ ...prev, role: e.target.value }))}
                  >
                    <option value="registrar">Registrar</option>
                    <option value="facility_manager">Facility Manager</option>
                    <option value="marketing">Marketing</option>
                    <option value="it">IT</option>
                    <option value="transport">Transport</option>
                    <option value="iqac">IQAC</option>
                  </select>
                </label>
                {addUserModal.error ? (
                  <p className="form-error">{addUserModal.error}</p>
                ) : null}
                <div className="modal-actions">
                  <button type="button" className="secondary-action" onClick={handleAddUserModalClose}>
                    Cancel
                  </button>
                  <button type="submit" className="primary-action" disabled={addUserModal.status === "loading"}>
                    {addUserModal.status === "loading" ? "Adding..." : "Add User"}
                  </button>
                </div>
              </form>
            </div>
          </div>
        ) : null}


        {eventDetailsModal.open ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card details-card event-details-modal">
              <div className="modal-header">
                <h3>Event Details</h3>
                <button type="button" className="modal-close" onClick={handleEventDetailsClose}>
                  &times;
                </button>
              </div>
              {eventDetailsModal.status === "loading" ? (
                <p className="table-message">Loading event details...</p>
              ) : eventDetailsModal.status === "error" ? (
                <p className="form-error">{eventDetailsModal.error}</p>
              ) : eventDetailsModal.details ? (
                <EventDetailsModalBody
                  details={eventDetailsModal.details}
                  fallbackEventName={eventDetailsModal.event?.name}
                  formatISTTime={formatISTTime}
                  normalizeMarketingRequirements={normalizeMarketingRequirements}
                  getMarketingDeliverableLabel={getMarketingDeliverableLabel}
                  viewerRole={normalizedUserRole}
                  transportRequestTypeLabel={transportRequestTypeLabel}
                  isMarketingViewer={isMarketingRole}
                  getMarketingDeliverableUploadFlags={getMarketingDeliverableUploadFlags}
                  onMarketingUpload={(req) => {
                    handleEventDetailsClose();
                    openMarketingDeliverableModal(req);
                  }}
                />
              ) : (
                <p className="table-message">Event details not available.</p>
              )}
              <div className="modal-actions">
                <button type="button" className="secondary-action" onClick={handleEventDetailsClose}>
                  Close
                </button>
              </div>
            </div>
          </div>
        ) : null}
        {approvalDetailsModal.open ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card details-card event-details-modal approval-details-modal">
              <div className="modal-header">
                <h3>Approval request</h3>
                <button type="button" className="modal-close" onClick={handleApprovalDetailsClose}>
                  &times;
                </button>
              </div>
              {approvalDetailsModal.request ? (
                <ConnectedApprovalDetailsModalBody
                  request={approvalDetailsModal.request}
                  eventDetails={approvalDetailsModal.eventDetails}
                  detailsStatus={approvalDetailsModal.detailsStatus}
                  detailsError={approvalDetailsModal.detailsError}
                  formatISTTime={formatISTTime}
                  normalizeMarketingRequirements={normalizeMarketingRequirements}
                  getMarketingDeliverableLabel={getMarketingDeliverableLabel}
                  transportRequestTypeLabel={transportRequestTypeLabel}
                  onRefreshApprovalDetails={refreshApprovalDetails}
                  approvalDiscussionCanReply={approvalDiscussionCanReply}
                  currentUserId={user?.id}
                  viewerRole={
                    String(user?.id) === String(approvalDetailsModal.request?.requester_id) && !isRegistrar
                      ? "faculty"
                      : normalizedUserRole
                  }
                />
              ) : (
                <p className="table-message">Approval request details not available.</p>
              )}
              <div className="modal-actions">
                <button type="button" className="secondary-action" onClick={handleApprovalDetailsClose}>
                  Close
                </button>
              </div>
            </div>
          </div>
        ) : null}

        {workflowActionModal.open ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card modal-card-narrow workflow-action-modal-card">
              <div className="modal-header">
                <h3>Submit action</h3>
                <button type="button" className="modal-close" onClick={closeWorkflowActionModal}>
                  &times;
                </button>
              </div>
              <p className="workflow-action-modal-type">
                <span className="details-label">Action</span>
                <span className="workflow-action-modal-type-value">{workflowActionModal.actionLabel || "—"}</span>
              </p>
              <label className="form-field workflow-action-comment-field">
                <span>
                  Comment{" "}
                  {workflowActionModal.channel === "approval" &&
                  String(workflowActionModal.status || "").toLowerCase() === "approved"
                    ? "(optional)"
                    : "(required)"}
                </span>
                <textarea
                  className="workflow-action-textarea"
                  rows={4}
                  value={workflowActionModal.comment}
                  onChange={(e) =>
                    setWorkflowActionModal((prev) => ({ ...prev, comment: e.target.value, error: "" }))
                  }
                  placeholder="Add your note, reason, or question for the requester."
                />
              </label>
              {workflowActionModal.error ? (
                <p className="form-error">{workflowActionModal.error}</p>
              ) : null}
              <div className="modal-actions">
                <button type="button" className="secondary-action" onClick={closeWorkflowActionModal}>
                  Cancel
                </button>
                <button
                  type="button"
                  className="primary-action"
                  disabled={workflowActionModal.submitting}
                  onClick={() => submitWorkflowActionModal()}
                >
                  {workflowActionModal.submitting ? "Submitting…" : "Submit"}
                </button>
              </div>
            </div>
          </div>
        ) : null}
        {marketingDeliverableModal.open && marketingDeliverableModal.request ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card modal-card-wide">
              <div className="modal-header">
                <h3>Upload Deliverables</h3>
                <button type="button" className="modal-close" onClick={closeMarketingDeliverableModal}>
                  &times;
                </button>
              </div>
              <p className="details-value" style={{ marginBottom: "1rem" }}>
                {marketingDeliverableModal.request.event_name || "Event"}
              </p>
              <p className="form-hint" style={{ marginBottom: "1rem" }}>
                Upload pre-event items (poster, pre-event social) before the event starts. Post-event items (video upload,
                post social, post-event photos) after the event ends. Videoshoot and on-site photoshoot are handled during
                the event and do not use this form. You can save in multiple visits (max 25MB per file).
              </p>
              <form className="event-form" onSubmit={submitMarketingDeliverable}>
                {REQUIREMENT_OPTIONS.filter((opt) =>
                  getMarketingDeliverableUploadFlags(marketingDeliverableModal.request || {})[opt.key]
                ).map((opt) => {
                  const r = marketingDeliverableModal.requirements?.[opt.type] || { na: false, file: null };
                  const rowLock = getMarketingDeliverableRowLock(opt.type, marketingDeliverableModal.request);
                  const rowDisabled = rowLock.locked;
                  return (
                    <div key={opt.type} className="form-field deliverable-row">
                      <span className="deliverable-label">{opt.label}</span>
                      {rowLock.hint ? (
                        <span className="form-hint" style={{ display: "block", marginBottom: "0.25rem" }}>
                          {rowLock.hint}
                        </span>
                      ) : null}
                      <label className="deliverable-na">
                        <input
                          type="checkbox"
                          checked={r.na}
                          disabled={rowDisabled}
                          onChange={(e) => {
                            setMarketingDeliverableModal((prev) => ({
                              ...prev,
                              requirements: {
                                ...prev.requirements,
                                [opt.type]: { na: e.target.checked, file: e.target.checked ? null : r.file }
                              }
                            }));
                          }}
                        />
                        NA
                      </label>
                      <label className="deliverable-file">
                        <input
                          key={`${opt.type}-${r.na}`}
                          type="file"
                          accept="*/*"
                          disabled={r.na || rowDisabled}
                          onChange={(e) => {
                            const f = e.target.files?.[0];
                            setMarketingDeliverableModal((prev) => ({
                              ...prev,
                              requirements: {
                                ...prev.requirements,
                                [opt.type]: { na: r.na, file: f || null }
                              }
                            }));
                          }}
                        />
                        {r.na ? "" : r.file ? r.file.name : "Choose file"}
                      </label>
                    </div>
                  );
                })}
                {marketingDeliverableModal.request?.deliverables?.length ? (
                  <div className="form-field" style={{ marginTop: "1rem", marginBottom: "1rem" }}>
                    <span>Already uploaded / marked</span>
                    <ul style={{ margin: 0, paddingLeft: "1.25rem" }}>
                      {marketingDeliverableModal.request.deliverables.map((d, i) => (
                        <li key={i}>
                          {d.is_na ? (
                            <span>{getMarketingDeliverableLabel(d.deliverable_type)}: N/A</span>
                          ) : d.web_view_link ? (
                            <a href={d.web_view_link} target="_blank" rel="noreferrer">
                              {d.file_name || getMarketingDeliverableLabel(d.deliverable_type)}
                            </a>
                          ) : (
                            <span>{d.file_name || getMarketingDeliverableLabel(d.deliverable_type)}</span>
                          )}
                          {!d.is_na ? ` (${getMarketingDeliverableLabel(d.deliverable_type)})` : null}
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : null}
                {marketingDeliverableModal.status === "error" ? (
                  <p className="form-error">
                    {marketingDeliverableModal.error}
                    {marketingDeliverableModal.error === "Google not connected" ? (
                      <>
                        {" "}
                        <button
                          type="button"
                          className="secondary-action"
                          onClick={handleCalendarConnect}
                          style={{ marginLeft: "0.5rem" }}
                        >
                          Connect Google
                        </button>
                      </>
                    ) : null}
                  </p>
                ) : null}
                <div className="modal-actions">
                  <button type="button" className="secondary-action" onClick={closeMarketingDeliverableModal}>
                    Cancel
                  </button>
                  <button
                    type="submit"
                    className="primary-action"
                    disabled={
                      marketingDeliverableModal.status === "loading" ||
                      !hasMarketingModalActionableChoice(
                        marketingDeliverableModal.request,
                        marketingDeliverableModal.requirements
                      )
                    }
                  >
                    {marketingDeliverableModal.status === "loading" ? "Saving..." : "Save"}
                  </button>
                </div>
              </form>
            </div>
          </div>
        ) : null}
        <Sidebar
          visibleMenuItems={visibleMenuItems}
          onLogout={handleLogout}
          className={mobileMenuOpen ? "mobile-open" : ""}
          onNavigate={() => setMobileMenuOpen(false)}
          user={user}
        />
        {mobileMenuOpen ? (
          <button
            type="button"
            className="mobile-nav-overlay"
            onClick={() => setMobileMenuOpen(false)}
            aria-label="Close navigation menu"
          />
        ) : null}

        <main className="dashboard-main">
          <header className="mobile-nav-header">
            <div className="mobile-nav-brand">
              <div className="brand-icon" aria-hidden="true">
                <SimpleIcon path="M6 12a6 6 0 1 1 6 6H6v-6Z" />
              </div>
              <span>{(user?.role || "Faculty").replace(/_/g, " ").toUpperCase()}</span>
            </div>
            <button
              type="button"
              className="mobile-nav-toggle"
              onClick={() => setMobileMenuOpen((prev) => !prev)}
              aria-label="Open navigation menu"
              aria-expanded={mobileMenuOpen}
            >
              <SimpleIcon path="M12 5a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm0 7a2 2 0 1 1 0 4 2 2 0 0 1 0-4Zm0 7a2 2 0 1 1 0 4 2 2 0 0 1 0-4Z" />
            </button>
          </header>
          <header className="dashboard-header">
            <div>
              <p className="dashboard-title">
                {isMyEvents
                  ? "My Events"
                  : isReportsView
                    ? "Event Reports"
                    : isPublications
                      ? "Publications"
                      : isIqacData
                        ? "IQAC Data Collection"
                        : isCalendar
                          ? "Calendar View"
                          : isApprovals
                            ? "Approvals"
                            : isRequirements
                              ? "Requirements"
                              : isAdminView
                                ? "Admin Console"
                                : "Dashboard Overview"}
              </p>
            </div>
            <div className="search-bar">
              <span className="search-icon">
                <SimpleIcon path="M15.5 15.5 20 20M17 10.5a6.5 6.5 0 1 1-13 0 6.5 6.5 0 0 1 13 0Z" />
              </span>
              <input
                type="search"
                placeholder="Events, Reports, Schedule, etc"
                value={searchInput}
                onChange={(event) => {
                  const value = event.target.value;
                  setSearchInput(value);
                  if (!value.trim()) {
                    setSearchQuery("");
                  }
                }}
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    applySearch();
                  }
                }}
              />
              <button
                type="button"
                className={`search-button ${searchInput.trim() ? "active" : ""}`}
                onClick={applySearch}
                aria-label="Apply search"
              >
                Search
              </button>
            </div>
            <div className="header-actions">
              <button type="button" className="icon-button">
                <SimpleIcon path="M12 3a6 6 0 0 1 6 6v4l2 3H4l2-3V9a6 6 0 0 1 6-6Zm0 18a2.5 2.5 0 0 0 2.45-2H9.55A2.5 2.5 0 0 0 12 21Z" />
              </button>
              <div className="profile">
                <div>
                  <p className="profile-name">{profileName}</p>
                  <p className="profile-role">{profileRole}</p>
                </div>
                <div className="profile-avatar" />
              </div>
            </div>
          </header>

          <section className="dashboard-content">
            {renderPrimaryContent()}
          </section>

          <FloatingMessenger />
        </main>
      </div>
      </MessengerProvider>
    );
  }

  return <LoginPage googleButtonRef={googleButtonRef} status={status} />;
}

