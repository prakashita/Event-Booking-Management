import { useCallback, useEffect, useRef, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import interactionPlugin from "@fullcalendar/interaction";
import { menuItems, preferenceItems, inboxItems, eventsTable, PUB_META, PATH_TO_VIEW, ROUTES } from "./constants";
import { formatISTTime, normalizeTimeToHHMMSS, parse24ToTimeParts, timePartsTo24 } from "./utils/format";
import { GoogleIcon, SimpleIcon, PlaceholderCard } from "./components/icons";
import { LoginPage, Sidebar } from "./components/layout";
import { Modal, StatusMessage } from "./components/ui";
import api from "./services/api";

export default function App() {
  const location = useLocation();
  const navigate = useNavigate();
  const activeView = PATH_TO_VIEW[location.pathname] ?? "dashboard";

  const googleButtonRef = useRef(null);
  const [status, setStatus] = useState({ type: "idle", message: "" });
  const [searchInput, setSearchInput] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [myEventsTab, setMyEventsTab] = useState("all");
  const [isEventModalOpen, setIsEventModalOpen] = useState(false);
  const [venuesState, setVenuesState] = useState({ status: "idle", items: [], error: "" });
  const [eventsState, setEventsState] = useState({ status: "idle", items: [], error: "" });
  const [approvalsState, setApprovalsState] = useState({ status: "idle", items: [], error: "" });
  const [marketingState, setMarketingState] = useState({ status: "idle", items: [], error: "" });
  const [itState, setItState] = useState({ status: "idle", items: [], error: "" });
  const [facilityState, setFacilityState] = useState({ status: "idle", items: [], error: "" });
  const [eventForm, setEventForm] = useState({
    start_date: "",
    end_date: "",
    start_time: "",
    end_time: "",
    name: "",
    facilitator: "",
    venue_name: "",
    description: "",
    budget: ""
  });
  const [eventTimeParts, setEventTimeParts] = useState({
    start_time: { hour: "", minute: "", period: "AM" },
    end_time: { hour: "", minute: "", period: "AM" }
  });
  const [eventFormStatus, setEventFormStatus] = useState({ status: "idle", error: "" });
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
  const [marketingForm, setMarketingForm] = useState({
    to: "",
    poster_required: true,
    poster_dimension: "",
    video_required: false,
    video_dimension: "",
    linkedin_post: false,
    photography: false,
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
  const [requirementsModal, setRequirementsModal] = useState({ open: false, event: null });
  const [approvalsTab, setApprovalsTab] = useState("approval-requests");
  const [reportModal, setReportModal] = useState({
    open: false,
    status: "idle",
    error: "",
    eventId: "",
    eventName: "",
    hasReport: false
  });
  const REQUIREMENT_OPTIONS = [
    { key: "poster_required", type: "poster", label: "Poster" },
    { key: "video_required", type: "video", label: "Video" },
    { key: "linkedin_post", type: "linkedin", label: "LinkedIn" },
    { key: "photography", type: "photography", label: "Photography" }
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
  const [approvalDetailsModal, setApprovalDetailsModal] = useState({ open: false, request: null });
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
    author: "",
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

  const [reportFile, setReportFile] = useState(null);
  const [calendarState, setCalendarState] = useState({
    status: "idle",
    events: [],
    error: ""
  });
  const [publicationsState, setPublicationsState] = useState({
    status: "idle",
    items: [],
    error: ""
  });
  const [publicationSort, setPublicationSort] = useState("date_desc");

  const [adminTab, setAdminTab] = useState("users");
  const [adminOverview, setAdminOverview] = useState({ status: "idle", data: null, error: "" });
  const [adminUsersState, setAdminUsersState] = useState({ status: "idle", items: [], error: "" });
  const [adminVenuesState, setAdminVenuesState] = useState({ status: "idle", items: [], error: "" });
  const [adminEventsState, setAdminEventsState] = useState({ status: "idle", items: [], error: "" });
  const [adminApprovalsState, setAdminApprovalsState] = useState({ status: "idle", items: [], error: "" });
  const [adminMarketingState, setAdminMarketingState] = useState({ status: "idle", items: [], error: "" });
  const [adminItState, setAdminItState] = useState({ status: "idle", items: [], error: "" });
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
  const [chatUsers, setChatUsers] = useState([]);
  const [chatActiveUser, setChatActiveUser] = useState(null);
  const [chatConversationId, setChatConversationId] = useState("");
  const [chatMessages, setChatMessages] = useState([]);
  const [chatStatus, setChatStatus] = useState({ status: "idle", error: "" });
  const [chatInput, setChatInput] = useState("");
  const [chatFiles, setChatFiles] = useState([]);
  const [chatTypingUser, setChatTypingUser] = useState(null);
  const [chatUnreadByUser, setChatUnreadByUser] = useState({});
  const [chatHasMore, setChatHasMore] = useState(true);
  const [chatLoadingMore, setChatLoadingMore] = useState(false);
  const chatWsRef = useRef(null);
  const chatListRef = useRef(null);
  const chatTypingTimeoutRef = useRef(null);
  const chatActiveConversationRef = useRef("");
  const chatActiveUserRef = useRef(null);
  const loadConversationMessagesRef = useRef(null);
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
  const canAccessAdminConsole = isAdmin || isRegistrar;
  const canAccessApprovals = isRegistrar;
  const canAccessRequirements = isFacilityManagerRole || isMarketingRole || isItRole;
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
      setPublicationsState({ status: "ready", items: data, error: "" });
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
      setAdminUsersState({ status: "ready", items: data, error: "" });
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
      setAdminVenuesState({ status: "ready", items: data, error: "" });
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
      setAdminEventsState({ status: "ready", items: data, error: "" });
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
      setAdminApprovalsState({ status: "ready", items: data, error: "" });
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
      setAdminMarketingState({ status: "ready", items: data, error: "" });
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
      setAdminItState({ status: "ready", items: data, error: "" });
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
      setAdminInvitesState({ status: "ready", items: data, error: "" });
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
      setAdminPublicationsState({ status: "ready", items: data, error: "" });
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

  const formatChatTime = useCallback((value) => {
    if (!value) {
      return "";
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "";
    }
    return date
      .toLocaleTimeString("en-IN", {
        timeZone: "Asia/Kolkata",
        hour: "numeric",
        minute: "2-digit",
        hour12: true
      })
      .toUpperCase();
  }, []);

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

  const resolveAttachmentUrl = useCallback(
    (url) => {
      if (!url) {
        return "";
      }
      if (url.startsWith("http://") || url.startsWith("https://")) {
        return url;
      }
      return `${apiBaseUrl}${url}`;
    },
    [apiBaseUrl]
  );

  const loadChatUsers = useCallback(async () => {
    if (!user) {
      return;
    }
    try {
      const res = await apiFetch(`${apiBaseUrl}/chat/users`);
      if (!res.ok) {
        throw new Error("Unable to load users.");
      }
      const data = await res.json();
      setChatUsers((prev) => {
        const unreadMap = chatUnreadByUser;
        return data.map((item) => ({
          ...item,
          unread: unreadMap[item.id] || 0
        }));
      });
      setChatStatus({ status: "ready", error: "" });
    } catch (err) {
      setChatStatus((prev) => ({
        status: "error",
        error: err?.message || "Unable to load users."
      }));
    }
  }, [apiBaseUrl, apiFetch, chatUnreadByUser, user]);

  const loadConversationMessages = useCallback(
    async (conversationId, before) => {
      if (!conversationId) {
        return;
      }
      if (before) {
        setChatLoadingMore(true);
      } else {
        setChatStatus({ status: "loading", error: "" });
      }
      try {
        const params = new URLSearchParams({ limit: "50" });
        if (before) {
          params.set("before", before);
        }
        const res = await apiFetch(
          `${apiBaseUrl}/chat/conversations/${conversationId}/messages?${params.toString()}`
        );
        if (!res.ok) {
          throw new Error("Unable to load messages.");
        }
        const data = await res.json();
        setChatMessages((prev) => (before ? [...data, ...prev] : data));
        if (data.length < 50) {
          setChatHasMore(false);
        } else if (!before) {
          setChatHasMore(true);
        }
        setChatStatus({ status: "ready", error: "" });
      } catch (err) {
        setChatStatus({ status: "error", error: err?.message || "Unable to load messages." });
      } finally {
        setChatLoadingMore(false);
      }
    },
    [apiBaseUrl, apiFetch]
  );

  const startConversation = useCallback(
    async (targetUser) => {
      if (!targetUser) {
        return;
      }
      setChatActiveUser(targetUser);
      setChatTypingUser(null);
      setChatMessages([]);
      setChatHasMore(true);
      setChatLoadingMore(false);
      setChatStatus({ status: "loading", error: "" });
      try {
        const res = await apiFetch(`${apiBaseUrl}/chat/conversations`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ user_id: targetUser.id })
        });
        if (!res.ok) {
          throw new Error("Unable to start conversation.");
        }
        const data = await res.json();
        setChatConversationId(data.id);
        await loadConversationMessages(data.id);
        setChatUnreadByUser((prev) => ({ ...prev, [targetUser.id]: 0 }));
        setChatUsers((prev) =>
          prev.map((item) => (item.id === targetUser.id ? { ...item, unread: 0 } : item))
        );
      } catch (err) {
        setChatStatus({ status: "error", error: err?.message || "Unable to start conversation." });
      }
    },
    [apiBaseUrl, apiFetch, loadConversationMessages]
  );

  const uploadChatAttachment = useCallback(
    async (file) => {
      const formData = new FormData();
      formData.append("file", file);
      const res = await apiFetch(`${apiBaseUrl}/chat/upload`, {
        method: "POST",
        body: formData
      });
      if (!res.ok) {
        throw new Error("Unable to upload attachment.");
      }
      const data = await res.json();
      return data.attachment;
    },
    [apiBaseUrl, apiFetch]
  );

  const sendReadReceipts = useCallback(
    async (messageIds) => {
      if (!messageIds?.length) {
        return;
      }
      const ws = chatWsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "read", message_ids: messageIds }));
        return;
      }
      await apiFetch(`${apiBaseUrl}/chat/read`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message_ids: messageIds })
      });
    },
    [apiBaseUrl, apiFetch]
  );

  const sendChatMessage = useCallback(
    async () => {
      const trimmed = chatInput.trim();
      if (!trimmed && chatFiles.length === 0) {
        return;
      }
      if (!chatConversationId) {
        setChatStatus({ status: "error", error: "Select a user to start chatting." });
        return;
      }
      const clientId =
        typeof crypto !== "undefined" && crypto.randomUUID
          ? crypto.randomUUID()
          : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
      try {
        const attachments =
          chatFiles.length > 0 ? await Promise.all(chatFiles.map(uploadChatAttachment)) : [];
        const optimisticMessage = {
          id: `client-${clientId}`,
          client_id: clientId,
          conversation_id: chatConversationId,
          sender_id: user.id,
          sender_name: user.name,
          sender_email: user.email,
          content: trimmed,
          attachments,
          read_by: [user.id],
          created_at: new Date().toISOString()
        };
        setChatMessages((prev) => [...prev, optimisticMessage]);
        const payload = {
          type: "message",
          text: trimmed,
          attachments,
          conversation_id: chatConversationId,
          client_id: clientId
        };
        const ws = chatWsRef.current;
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(payload));
        } else {
          await apiFetch(`${apiBaseUrl}/chat/messages`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              conversation_id: chatConversationId,
              content: trimmed,
              attachments
            })
          });
        }
        setChatInput("");
        setChatFiles([]);
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: "typing", is_typing: false, conversation_id: chatConversationId }));
        }
      } catch (err) {
        setChatStatus({ status: "error", error: err?.message || "Unable to send message." });
      }
    },
    [apiBaseUrl, apiFetch, chatConversationId, chatFiles, chatInput, uploadChatAttachment, user]
  );

  const handleChatInputChange = useCallback(
    (event) => {
      const value = event.target.value;
      setChatInput(value);
      const ws = chatWsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN && chatConversationId) {
        ws.send(JSON.stringify({ type: "typing", is_typing: true, conversation_id: chatConversationId }));
      }
      if (chatTypingTimeoutRef.current) {
        clearTimeout(chatTypingTimeoutRef.current);
      }
      chatTypingTimeoutRef.current = setTimeout(() => {
        const activeWs = chatWsRef.current;
        if (activeWs && activeWs.readyState === WebSocket.OPEN && chatConversationId) {
          activeWs.send(JSON.stringify({ type: "typing", is_typing: false, conversation_id: chatConversationId }));
        }
      }, 1500);
    },
    [chatConversationId]
  );

  const handleChatFiles = useCallback((event) => {
    const nextFiles = Array.from(event.target.files || []);
    if (nextFiles.length) {
      setChatFiles((prev) => [...prev, ...nextFiles]);
    }
    event.target.value = "";
  }, []);

  const removeChatFile = useCallback((index) => {
    setChatFiles((prev) => prev.filter((_, idx) => idx !== index));
  }, []);

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
      setVenuesState({ status: "ready", items: data, error: "" });
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
        setEventsState({ status: "ready", items: reportsData, error: "" });
        return;
      }

      const [eventsRes, approvalsRes, facilityRes, marketingRes, itRes, invitesRes] = await Promise.all([
        apiFetch(`${apiBaseUrl}/events`),
        apiFetch(`${apiBaseUrl}/approvals/me`),
        apiFetch(`${apiBaseUrl}/facility/requests/me`),
        apiFetch(`${apiBaseUrl}/marketing/requests/me`),
        apiFetch(`${apiBaseUrl}/it/requests/me`),
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
      const invitesData = invitesRes.ok ? await invitesRes.json() : [];
      const approvalByEventId = new Map();
      const facilityByEventId = new Map();
      const marketingByEventId = new Map();
      const itByEventId = new Map();
      const inviteByEventId = new Map();
      const approvalByEventKey = new Map();
      const facilityByEventKey = new Map();
      const marketingByEventKey = new Map();
      const itByEventKey = new Map();

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
      setApprovalsState({ status: "ready", items: data, error: "" });
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
    } else {
      setRegistrarEmail("");
      setFacilityManagerEmail("");
      setMarketingEmail("");
      setItEmail("");
    }
  }, [user, loadRegistrarEmail, loadFacilityManagerEmail, loadMarketingEmail, loadItEmail]);

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
    chatActiveConversationRef.current = chatConversationId;
  }, [chatConversationId]);

  useEffect(() => {
    chatActiveUserRef.current = chatActiveUser?.id || null;
  }, [chatActiveUser]);

  useEffect(() => {
    loadConversationMessagesRef.current = loadConversationMessages;
  }, [loadConversationMessages]);

  useEffect(() => {
    loadEventsRef.current = loadEvents;
  }, [loadEvents]);

  useEffect(() => {
    if (!user) {
      if (chatWsRef.current) {
        chatWsRef.current.close();
        chatWsRef.current = null;
      }
      setChatUsers([]);
      setChatMessages([]);
      setChatActiveUser(null);
      setChatConversationId("");
      setChatStatus({ status: "idle", error: "" });
      setChatTypingUser(null);
      setChatUnreadByUser({});
      return;
    }

    loadChatUsers();

    const token = localStorage.getItem("auth_token");
    if (!token) {
      return;
    }

    const wsBase = apiBaseUrl.replace(/^http/, "ws");
    const ws = new WebSocket(`${wsBase}/chat/ws?token=${token}`);
    chatWsRef.current = ws;

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === "message" && data.message) {
          const incoming = data.message;
          const activeConversation = chatActiveConversationRef.current;
          const activeUserId = chatActiveUserRef.current;
          if (incoming.conversation_id === activeConversation) {
            if (incoming.client_id) {
              setChatMessages((prev) => {
                const replaced = prev.map((message) =>
                  message.client_id === incoming.client_id ? incoming : message
                );
                const hasMatch = prev.some((message) => message.client_id === incoming.client_id);
                return hasMatch ? replaced : [...prev, incoming];
              });
            } else {
              setChatMessages((prev) => [...prev, incoming]);
            }
          } else if (activeUserId && incoming.sender_id === activeUserId) {
            setChatConversationId(incoming.conversation_id);
            setChatMessages((prev) => [...prev, incoming]);
            if (loadConversationMessagesRef.current) {
              loadConversationMessagesRef.current(incoming.conversation_id);
            }
          } else if (incoming.sender_id) {
            setChatUnreadByUser((prev) => ({
              ...prev,
              [incoming.sender_id]: (prev[incoming.sender_id] || 0) + 1
            }));
            setChatUsers((prev) =>
              prev.map((item) =>
                item.id === incoming.sender_id
                  ? { ...item, unread: (item.unread || 0) + 1 }
                  : item
              )
            );
          }
          return;
        }
        if (data.type === "typing") {
          if (data.conversation_id !== chatActiveConversationRef.current) {
            return;
          }
          if (data.is_typing) {
            setChatTypingUser({ id: data.user_id, name: data.user_name });
          } else {
            setChatTypingUser(null);
          }
          return;
        }
        if (data.type === "read" && data.message_ids) {
          setChatMessages((prev) =>
            prev.map((message) => {
              if (!data.message_ids.includes(message.id)) {
                return message;
              }
              if (message.read_by.includes(data.user_id)) {
                return message;
              }
              return { ...message, read_by: [...message.read_by, data.user_id] };
            })
          );
          return;
        }
        if (data.type === "presence") {
          setChatUsers((prev) =>
            prev.map((item) =>
              item.id === data.user_id
                ? { ...item, online: data.online, last_seen: data.last_seen }
                : item
            )
          );
          setChatActiveUser((prev) =>
            prev && prev.id === data.user_id
              ? { ...prev, online: data.online, last_seen: data.last_seen }
              : prev
          );
        }
      } catch (err) {
        // Ignore malformed payloads
      }
    };

    return () => {
      ws.close();
    };
  }, [apiBaseUrl, loadChatUsers, user]);

  useEffect(() => {
    if (!chatListRef.current) {
      return;
    }
    chatListRef.current.scrollTop = chatListRef.current.scrollHeight;
  }, [chatMessages.length]);

  useEffect(() => {
    if (!chatActiveUser) {
      return;
    }
    const updated = chatUsers.find((item) => item.id === chatActiveUser.id);
    if (updated) {
      setChatActiveUser(updated);
    }
  }, [chatUsers, chatActiveUser]);

  useEffect(() => {
    if (!user || chatMessages.length === 0 || !chatConversationId) {
      return;
    }
    const unread = chatMessages
      .filter((message) => message.sender_id !== user.id && !message.read_by.includes(user.id))
      .map((message) => message.id);
    if (unread.length) {
      sendReadReceipts(unread);
    }
  }, [chatMessages, chatConversationId, sendReadReceipts, user]);

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
  }, [
    activeView,
    approvalsState.status,
    facilityState.status,
    isApproverRole,
    isFacilityManagerRole,
    isItRole,
    isMarketingRole,
    loadApprovalsInbox,
    loadFacilityInbox,
    loadItInbox,
    loadMarketingInbox,
    itState.status,
    marketingState.status,
    user
  ]);

  useEffect(() => {
    if (
      (activeView === "approvals" && !canAccessApprovals) ||
      (activeView === "requirements" && !canAccessRequirements) ||
      (activeView === "event-reports" && !isAdmin && !isRegistrar)
    ) {
      navigate(ROUTES.DASHBOARD);
    }
  }, [activeView, canAccessApprovals, canAccessRequirements, isAdmin, isRegistrar, navigate]);

  useEffect(() => {
    const showApprovalsOrRequirements =
      (activeView === "approvals" && canAccessApprovals) || (activeView === "requirements" && canAccessRequirements);
    if (showApprovalsOrRequirements) {
      if (isApproverRole) setApprovalsTab("approval-requests");
      else if (isFacilityManagerRole) setApprovalsTab("facility");
      else if (isMarketingRole) setApprovalsTab("marketing");
      else if (isItRole) setApprovalsTab("it");
    }
  }, [activeView, canAccessApprovals, canAccessRequirements, isApproverRole, isFacilityManagerRole, isMarketingRole, isItRole]);

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
    loadAdminInvites();
    loadAdminPublications();
  }, [
    activeView,
    canAccessAdminConsole,
    loadAdminApprovals,
    loadAdminEvents,
    loadAdminIt,
    loadAdminMarketing,
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
    setEventForm((prev) => ({
      ...prev,
      facilitator: prev.facilitator || defaultFacilitator
    }));
    setIsEventModalOpen(true);
    setEventFormStatus({ status: "idle", error: "" });
  };

  const handleEventModalClose = () => {
    setIsEventModalOpen(false);
    setConflictState({ open: false, items: [] });
  };

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
      poster_required: true,
      poster_dimension: "",
      video_required: false,
      video_dimension: "",
      linkedin_post: false,
      photography: false,
      other_notes: ""
    });
    setMarketingModal({ open: true, status: "idle", error: "" });
  };

  const handleMarketingModalClose = () => {
    requirementsFlowQueueRef.current = [];
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
      description: "",
      budget: ""
    });
  };

  const handleMarketingSkip = () => {
    handleMarketingModalClose();
  };

  const handleItSkip = () => {
    setItModal({ open: false, status: "idle", error: "" });
    const queue = requirementsFlowQueueRef.current;
    if (queue[0] === "it") {
      requirementsFlowQueueRef.current = queue.slice(1);
      const next = requirementsFlowQueueRef.current[0];
      if (next === "marketing") handleMarketingModalOpen();
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
    requirementsFlowQueueRef.current = queue;
    if (queue[0] === "facility") handleFacilityModalOpen();
    else if (queue[0] === "it") handleItModalOpen();
    else if (queue[0] === "marketing") handleMarketingModalOpen();
  };

  const handleReportOpen = (eventItem) => {
    setReportFile(null);
    setReportModal({
      open: true,
      status: "idle",
      error: "",
      eventId: eventItem.id,
      eventName: eventItem.name,
      hasReport: Boolean(eventItem.report_file_id)
    });
  };

  const handleEventDetailsOpen = async (eventItem) => {
    if (!eventItem?.id) return;
    if (String(eventItem.id).startsWith("approval-")) {
      setApprovalDetailsModal({ open: true, request: eventItem });
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

  const handleApprovalDetailsOpen = (requestItem) => {
    setApprovalDetailsModal({ open: true, request: requestItem });
  };

    const handleApprovalDetailsClose = () => {
      setApprovalDetailsModal({ open: false, request: null });
    };

  const openMarketingDeliverableModal = (request) => {
    if (isEventStarted(request)) return;
    const requirements = {};
    REQUIREMENT_OPTIONS.forEach(({ key, type }) => {
      if (request[key]) {
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
    const hasAnyChoice = Object.values(requirements || {}).some((r) => r.na || r.file);
    if (!request?.id || !hasAnyChoice) {
      setMarketingDeliverableModal((prev) => ({
        ...prev,
        status: "error",
        error: "For each requirement, select NA or upload a file."
      }));
      return;
    }
    setMarketingDeliverableModal((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const formData = new FormData();
      REQUIREMENT_OPTIONS.forEach(({ type }) => {
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
    setReportFile(null);
    setReportModal({ open: false, status: "idle", error: "", eventId: "", eventName: "", hasReport: false });
  };

  const handleReportFileChange = (event) => {
    setReportFile(event.target.files?.[0] || null);
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
      author: "",
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
    else if (pt === "webpage" && (!f.author || !f.page_title || !f.website_name || !f.url)) validationError = "Please fill all required fields.";
    else if (pt === "journal_article" && (!f.author || !f.article_title || !f.journal_name || !f.year)) validationError = "Please fill all required fields.";
    else if (pt === "book" && (!f.author || !f.book_title || !f.publisher || !f.year)) validationError = "Please fill all required fields.";
    else if (pt === "report" && (!f.organization || !f.report_title || !f.year || !f.publisher)) validationError = "Please fill all required fields.";
    else if (pt === "video" && (!f.creator || !f.video_title || !f.platform || !f.publication_date || !f.url)) validationError = "Please fill all required fields.";
    else if (pt === "online_newspaper" && (!f.author || !f.article_title || !f.newspaper_name || !f.publication_date || !f.url)) validationError = "Please fill all required fields.";
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
      // Append all optional fields if present
      const optionals = ["author","publication_date","url","article_title","journal_name","volume","issue","pages","doi","year","book_title","publisher","edition","page_number","organization","report_title","creator","video_title","platform","newspaper_name","website_name","page_title"];
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
    if (!reportFile) {
      setReportModal((prev) => ({
        ...prev,
        status: "error",
        error: "Please select a PDF report."
      }));
      return;
    }

    setReportModal((prev) => ({ ...prev, status: "loading", error: "" }));

    try {
      const formData = new FormData();
      formData.append("file", reportFile);
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
      event.approval_status || event.marketing_status || event.it_status;
    let derivedStatus = "Approved";
    if (hasApprovalData) {
      const statuses = [event.approval_status, event.marketing_status, event.it_status];
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

      setEventForm({
        start_date: "",
        end_date: "",
        start_time: "",
        end_time: "",
        name: "",
        facilitator: defaultFacilitator,
        venue_name: "",
        description: "",
        budget: ""
      });
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

      setApprovalModal({ open: false, status: "idle", error: "" });
      setOverrideConflict(false);
      resetEventFormState();
      setIsEventModalOpen(false);
      setConflictState({ open: false, items: [] });
      setStatus({ type: "success", message: "Event sent to registrar for approval." });
      loadEvents();
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
      }
    } catch (err) {
      setFacilityModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send facility manager request."
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
        poster_required: marketingForm.poster_required,
        poster_dimension: marketingForm.poster_dimension,
        video_required: marketingForm.video_required,
        video_dimension: marketingForm.video_dimension,
        linkedin_post: marketingForm.linkedin_post,
        photography: marketingForm.photography,
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
      requirementsFlowQueueRef.current = [];
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

  const handleMarketingFieldChange = (field) => (event) => {
    setMarketingForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
  };

  const handleMarketingToggle = (field) => (event) => {
    setMarketingForm((prev) => ({
      ...prev,
      [field]: event.target.checked
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
      return true;
    });
    const typingName = chatTypingUser?.name || "";

    const handleApprovalDecision = async (requestId, decision) => {
      const token = localStorage.getItem("auth_token");
      if (!token) {
        setApprovalsState({ status: "error", items: [], error: "Missing auth token." });
        return;
      }

      try {
        const idemKey = generateIdempotencyKey();
        const res = await apiFetch(`${apiBaseUrl}/approvals/${requestId}`, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            ...(idemKey && { "Idempotency-Key": idemKey })
          },
          body: JSON.stringify({ status: decision })
        });

        if (res.status === 409) {
          throw new Error("Schedule conflict detected. Ask the requester to reschedule.");
        }
        if (!res.ok) {
          throw new Error("Unable to update approval.");
        }

        loadApprovalsInbox();
      } catch (err) {
        setApprovalsState({
          status: "error",
          items: [],
          error: err?.message || "Unable to update approval."
        });
      }
    };

    const handleFacilityDecision = async (requestId, decision) => {
      const token = localStorage.getItem("auth_token");
      if (!token) {
        setFacilityState({ status: "error", items: [], error: "Missing auth token." });
        return;
      }

      try {
        const res = await apiFetch(`${apiBaseUrl}/facility/requests/${requestId}`, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ status: decision })
        });

        if (!res.ok) {
          throw new Error("Unable to update facility request.");
        }

        loadFacilityInbox();
      } catch (err) {
        setFacilityState({
          status: "error",
          items: [],
          error: err?.message || "Unable to update facility request."
        });
      }
    };

    const handleMarketingDecision = async (requestId, decision) => {
      const token = localStorage.getItem("auth_token");
      if (!token) {
        setMarketingState({ status: "error", items: [], error: "Missing auth token." });
        return;
      }

      try {
        const res = await apiFetch(`${apiBaseUrl}/marketing/requests/${requestId}`, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ status: decision })
        });

        if (!res.ok) {
          throw new Error("Unable to update marketing request.");
        }

        loadMarketingInbox();
      } catch (err) {
        setMarketingState({
          status: "error",
          items: [],
          error: err?.message || "Unable to update marketing request."
        });
      }
    };

    const handleItDecision = async (requestId, decision) => {
      const token = localStorage.getItem("auth_token");
      if (!token) {
        setItState({ status: "error", items: [], error: "Missing auth token." });
        return;
      }

      try {
        const res = await apiFetch(`${apiBaseUrl}/it/requests/${requestId}`, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json"
          },
          body: JSON.stringify({ status: decision })
        });

        if (!res.ok) {
          throw new Error("Unable to update IT request.");
        }

        loadItInbox();
      } catch (err) {
        setItState({
          status: "error",
          items: [],
          error: err?.message || "Unable to update IT request."
        });
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
            <div className="events-actions">
              <span title={createTooltip} className="action-tooltip">
                <button
                  type="button"
                  className="primary-action"
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
                  + New Event
                </button>
              </span>
              <button type="button" className="secondary-action" onClick={loadEvents}>
                Refresh
              </button>
            </div>

            <div className="events-table-card">
              <div className="table-header">
                <h3>{isReportsView ? "Event Reports" : "My Events"}</h3>
                {isReportsView ? null : (
                  <div className="table-tabs">
                  <button
                    type="button"
                    className={`tab-button ${myEventsTab === "all" ? "active" : ""}`}
                    onClick={() => setMyEventsTab("all")}
                  >
                    All
                  </button>
                  <button
                    type="button"
                    className={`tab-button ${myEventsTab === "pending" ? "active" : ""}`}
                    onClick={() => setMyEventsTab("pending")}
                  >
                    Pending
                  </button>
                  <button
                    type="button"
                    className={`tab-button ${myEventsTab === "upcoming" ? "active" : ""}`}
                    onClick={() => setMyEventsTab("upcoming")}
                  >
                    Upcoming
                  </button>
                  <button
                    type="button"
                    className={`tab-button ${myEventsTab === "ongoing" ? "active" : ""}`}
                    onClick={() => setMyEventsTab("ongoing")}
                  >
                    Ongoing
                  </button>
                  <button
                    type="button"
                    className={`tab-button ${myEventsTab === "completed" ? "active" : ""}`}
                    onClick={() => setMyEventsTab("completed")}
                  >
                    Completed
                  </button>
                  <button
                    type="button"
                    className={`tab-button ${myEventsTab === "closed" ? "active" : ""}`}
                    onClick={() => setMyEventsTab("closed")}
                  >
                    Closed
                  </button>
                </div>
                )}
              </div>
              <div className="events-table">
                <div className={`events-table-row header ${isReportsTab ? "reports" : ""}`}>
                  <span>Events</span>
                  {isReportsTab ? null : <span>Date</span>}
                  {isReportsTab ? null : <span>Time</span>}
                  <span>Status</span>
                  <span>Action</span>
                </div>
                {eventsState.status === "loading" ? (
                  <p className="table-message">Loading events...</p>
                ) : null}
                {eventsState.status === "error" ? (
                  <p className="table-message">{eventsState.error}</p>
                ) : null}
                {eventsState.status === "ready" && filteredEvents.length === 0 ? (
                  <p className="table-message">
                    {isReportsTab
                      ? "No closed events yet."
                      : myEventsTab === "completed"
                        ? "No completed events yet."
                        : myEventsTab === "upcoming"
                          ? "No upcoming events."
                          : myEventsTab === "ongoing"
                            ? "No ongoing events."
                            : myEventsTab === "closed"
                              ? "No closed events yet."
                              : myEventsTab === "pending"
                                ? "No pending events."
                                : "No events yet. Create your first event."}
                  </p>
                ) : null}
                {eventsState.status === "ready"
                  ? filteredEvents.map((event) => {
                      const statusValue = event.status || "";
                      const explicitStatus = statusValue ? formatStatusLabel(statusValue) : null;
                      const hasApprovalData =
                        event.approval_status || event.facility_status || event.marketing_status || event.it_status;
                      let derivedStatus = "Approved";
                      if (hasApprovalData) {
                        const statuses = [
                          event.approval_status,
                          event.facility_status,
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
                        ((!event.approval_status && !event.facility_status && !event.marketing_status && !event.it_status) ||
                          (event.approval_status === "approved" &&
                            event.facility_status === "approved" &&
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
                      const canUploadReport = !isApprovalItem && statusValue === "completed";
                      const canCloseEvent =
                        !isApprovalItem &&
                        statusValue === "completed" &&
                        Boolean(event.report_file_id);
                      if (isReportsTab) {
                        return (
                          <div key={event.id} className="events-table-row reports">
                            <span>{event.name}</span>
                            <span className={`status-pill ${statusClass}`}>{statusLabel}</span>
                            <div className="event-actions">
                              <button
                                type="button"
                                className="details-button invite"
                                onClick={() => handleViewReport(event)}
                              >
                                View Report
                              </button>
                            </div>
                          </div>
                        );
                      }
                      return (
                        <div key={event.id} className="events-table-row">
                          <span>{event.name}</span>
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
                            <button type="button" className="details-button" onClick={() => handleEventDetailsOpen(event)}>
                              Details
                            </button>
                            {inviteSent ? (
                              <button type="button" className="details-button invite" disabled>
                                Sent
                              </button>
                            ) : null}
                            {canInvite ? (
                              <button
                                type="button"
                                className="details-button invite"
                                onClick={() => handleInviteOpen(event)}
                              >
                                Send Invite
                              </button>
                            ) : null}
                            {canUploadReport ? (
                              <button
                                type="button"
                                className="details-button invite"
                                onClick={() => handleReportOpen(event)}
                              >
                                {event.report_file_id ? "Replace Report" : "Upload Report"}
                              </button>
                            ) : null}
                            {canSendSupportForms &&
                            (canSendFacilityRequest || canSendMarketingRequest || canSendItRequest) ? (
                              <button
                                type="button"
                                className="details-button invite"
                                onClick={() => handleSendRequirements(event)}
                              >
                                Send your requirements
                              </button>
                            ) : null}
                            {event.report_file_id && event.status === "closed" ? (
                              <button
                                type="button"
                                className="details-button invite"
                                onClick={() => handleViewReport(event)}
                              >
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
              <div className="modal-overlay" role="dialog" aria-modal="true">
                <div className="modal-card">
                  <div className="modal-header">
                    <h3>Create Event</h3>
                    <button type="button" className="modal-close" onClick={handleEventModalClose}>
                      &times;
                    </button>
                  </div>
                  <form className="event-form" onSubmit={handleEventSubmit}>
                    <div className="form-grid">
                      <label className="form-field">
                        <span>Start date</span>
                        <input
                          type="date"
                          value={eventForm.start_date}
                          onChange={handleEventFieldChange("start_date")}
                          required
                        />
                      </label>
                      <label className="form-field">
                        <span>End date</span>
                        <input
                          type="date"
                          value={eventForm.end_date}
                          onChange={handleEventFieldChange("end_date")}
                          required
                        />
                      </label>
                      <label className="form-field">
                        <span>Start time</span>
                        <div className="time-picker">
                          <select
                            value={eventTimeParts.start_time.hour}
                            onChange={handleEventTimePartChange("start_time", "hour")}
                            required
                          >
                            <option value="">Hour</option>
                            {Array.from({ length: 12 }, (_, i) => String(i + 1)).map((hour) => (
                              <option key={`start-hour-${hour}`} value={hour}>
                                {hour}
                              </option>
                            ))}
                          </select>
                          <select
                            value={eventTimeParts.start_time.minute}
                            onChange={handleEventTimePartChange("start_time", "minute")}
                            required
                          >
                            <option value="">Minute</option>
                            {Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0")).map((minute) => (
                              <option key={`start-minute-${minute}`} value={minute}>
                                {minute}
                              </option>
                            ))}
                          </select>
                          <select
                            value={eventTimeParts.start_time.period}
                            onChange={handleEventTimePartChange("start_time", "period")}
                            required
                          >
                            <option value="AM">AM</option>
                            <option value="PM">PM</option>
                          </select>
                        </div>
                      </label>
                      <label className="form-field">
                        <span>End time</span>
                        <div className="time-picker">
                          <select
                            value={eventTimeParts.end_time.hour}
                            onChange={handleEventTimePartChange("end_time", "hour")}
                            required
                          >
                            <option value="">Hour</option>
                            {Array.from({ length: 12 }, (_, i) => String(i + 1)).map((hour) => (
                              <option key={`end-hour-${hour}`} value={hour}>
                                {hour}
                              </option>
                            ))}
                          </select>
                          <select
                            value={eventTimeParts.end_time.minute}
                            onChange={handleEventTimePartChange("end_time", "minute")}
                            required
                          >
                            <option value="">Minute</option>
                            {Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0")).map((minute) => (
                              <option key={`end-minute-${minute}`} value={minute}>
                                {minute}
                              </option>
                            ))}
                          </select>
                          <select
                            value={eventTimeParts.end_time.period}
                            onChange={handleEventTimePartChange("end_time", "period")}
                            required
                          >
                            <option value="AM">AM</option>
                            <option value="PM">PM</option>
                          </select>
                        </div>
                      </label>
                    </div>
                    <label className="form-field">
                      <span>Event name</span>
                      <input
                        type="text"
                        placeholder="Business Conference 2025"
                        value={eventForm.name}
                        onChange={handleEventFieldChange("name")}
                        required
                      />
                    </label>
                    <label className="form-field">
                      <span>Facilitator</span>
                      <input
                        type="text"
                        placeholder="James"
                        value={eventForm.facilitator}
                        onChange={handleEventFieldChange("facilitator")}
                        required
                      />
                    </label>
                    <label className="form-field">
                      <span>Venue</span>
                      <select
                        value={eventForm.venue_name}
                        onChange={handleEventFieldChange("venue_name")}
                        required
                      >
                        <option value="">Select a venue</option>
                        {venuesState.items.map((venue) => (
                          <option key={venue.id} value={venue.name}>
                            {venue.name}
                          </option>
                        ))}
                      </select>
                      {venuesState.status === "error" ? (
                        <span className="form-error">{venuesState.error}</span>
                      ) : null}
                    </label>
                    <label className="form-field">
                      <span>Description</span>
                      <textarea
                        rows="3"
                        placeholder="Add a short overview of the event."
                        value={eventForm.description}
                        onChange={handleEventFieldChange("description")}
                      />
                    </label>
                    <label className="form-field">
                      <span>Budget (Rs)</span>
                      <input
                        type="number"
                        min="0"
                        step="1"
                        placeholder="e.g. 50000"
                        value={eventForm.budget}
                        onChange={handleEventFieldChange("budget")}
                      />
                    </label>
                    {eventFormStatus.status === "error" ? (
                      <p className="form-error">{eventFormStatus.error}</p>
                    ) : null}
                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleEventModalClose}>
                        Cancel
                      </button>
                      <button type="submit" className="primary-action" disabled={eventFormStatus.status === "loading"}>
                        {eventFormStatus.status === "loading" ? "Creating..." : "Create Event"}
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
                      Registrar will approve or reject this event. After approval, you can send requirements to Facility Manager, IT, and Marketing.
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
                        disabled={approvalModal.status === "loading"}
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
                      <div className="marketing-grid">
                        <label>
                          <input
                            type="checkbox"
                            checked={marketingForm.poster_required}
                            onChange={handleMarketingToggle("poster_required")}
                          />
                          Poster
                          <select
                            value={marketingForm.poster_dimension}
                            onChange={handleMarketingFieldChange("poster_dimension")}
                          >
                            <option value="">Dimension</option>
                            <option value="A4">A4</option>
                            <option value="A3">A3</option>
                            <option value="1080x1080">1080x1080</option>
                          </select>
                        </label>
                        <label>
                          <input
                            type="checkbox"
                            checked={marketingForm.video_required}
                            onChange={handleMarketingToggle("video_required")}
                          />
                          Video
                          <select
                            value={marketingForm.video_dimension}
                            onChange={handleMarketingFieldChange("video_dimension")}
                          >
                            <option value="">Dimension</option>
                            <option value="1920x1080">1920x1080</option>
                            <option value="1080x1920">1080x1920</option>
                            <option value="1280x720">1280x720</option>
                          </select>
                        </label>
                        <label>
                          <input
                            type="checkbox"
                            checked={marketingForm.linkedin_post}
                            onChange={handleMarketingToggle("linkedin_post")}
                          />
                          Linkedin Post
                        </label>
                        <label>
                          <input
                            type="checkbox"
                            checked={marketingForm.photography}
                            onChange={handleMarketingToggle("photography")}
                          />
                          Photography
                        </label>
                      </div>
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
                <div className="modal-card">
                  <div className="modal-header">
                    <h3>{reportModal.hasReport ? "Replace Report" : "Upload Report"}</h3>
                    <button type="button" className="modal-close" onClick={handleReportClose}>
                      &times;
                    </button>
                  </div>
                  <form className="event-form" onSubmit={submitReport}>
                    <label className="form-field">
                      <span>Event</span>
                      <input type="text" value={reportModal.eventName || "Event"} readOnly />
                    </label>
                    <label className="form-field">
                      <span>Report (PDF, max 10MB)</span>
                      <input type="file" accept=".pdf,application/pdf" onChange={handleReportFileChange} />
                    </label>

                    {reportModal.status === "error" ? (
                      <p className="form-error">{reportModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleReportClose}>
                        Cancel
                      </button>
                      <button type="submit" className="primary-action" disabled={reportModal.status === "loading"}>
                        {reportModal.status === "loading" ? "Uploading..." : "Upload"}
                      </button>
                    </div>
                  </form>
                </div>
              </div>
            ) : null}
          </div>
        );
      }

      if (isPublications) {
        const getPubDetails = (item) => {
          const pt = item.pub_type;
          if (pt === "webpage") return [
            item.author && `Author: ${item.author}`,
            item.website_name && `Site: ${item.website_name}`,
            item.publication_date && `Date: ${item.publication_date}`,
          ].filter(Boolean);
          if (pt === "journal_article") return [
            item.author && `Author: ${item.author}`,
            item.journal_name && `Journal: ${item.journal_name}`,
            [item.volume && `Vol. ${item.volume}`, item.issue && `No. ${item.issue}`, item.pages && `pp. ${item.pages}`].filter(Boolean).join(", "),
            item.year && `Year: ${item.year}`,
            item.doi && `DOI: ${item.doi}`,
          ].filter(Boolean);
          if (pt === "book") return [
            item.author && `Author: ${item.author}`,
            item.publisher && `Publisher: ${item.publisher}`,
            [item.edition && `${item.edition} Ed.`, item.year].filter(Boolean).join(", "),
          ].filter(Boolean);
          if (pt === "report") return [
            item.organization && `Org: ${item.organization}`,
            item.publisher && `Publisher: ${item.publisher}`,
            item.year && `Year: ${item.year}`,
          ].filter(Boolean);
          if (pt === "video") return [
            item.creator && `Creator: ${item.creator}`,
            item.platform && `Platform: ${item.platform}`,
            item.publication_date && `Date: ${item.publication_date}`,
          ].filter(Boolean);
          if (pt === "online_newspaper") return [
            item.author && `Author: ${item.author}`,
            item.newspaper_name && `Source: ${item.newspaper_name}`,
            item.publication_date && `Date: ${item.publication_date}`,
          ].filter(Boolean);
          return [];
        };

        const getSubjectTitle = (item) =>
          item.article_title || item.book_title || item.report_title ||
          item.video_title || item.page_title || item.title || "Untitled";

        return (
          <div className="primary-column">
            <div className="events-actions">
              <button type="button" className="primary-action" onClick={handlePublicationOpen}>
                + New Publication
              </button>
              <label className="publication-sort-label">
                Sort:
                <select
                  value={publicationSort}
                  onChange={(e) => setPublicationSort(e.target.value)}
                  className="publication-sort-select"
                  aria-label="Sort publications"
                >
                  <option value="date_desc">Date added (newest first)</option>
                  <option value="date_asc">Date added (oldest first)</option>
                  <option value="title_asc">Title (A–Z)</option>
                  <option value="title_desc">Title (Z–A)</option>
                </select>
              </label>
            </div>

            {/* ── Publications card grid ── */}
            {publicationsState.status === "loading" ? (
              <div className="pub-list-empty"><p>Loading publications…</p></div>
            ) : publicationsState.status === "error" ? (
              <div className="pub-list-empty"><p className="form-error">{publicationsState.error}</p></div>
            ) : publicationsState.status === "ready" && publicationsState.items.length === 0 ? (
              <div className="pub-list-empty">
                <span className="pub-empty-icon">📭</span>
                <p className="pub-empty-title">No publications yet</p>
                <p className="pub-empty-sub">Click <strong>+ New Publication</strong> to add your first one.</p>
              </div>
            ) : (
              <div className="pub-card-grid">
                {publicationsState.items.map((item) => {
                  const meta = PUB_META[item.pub_type] || { icon: "📋", label: item.pub_type || "Unknown", color: "#666" };
                  const details = getPubDetails(item);
                  const subject = getSubjectTitle(item);
                  const linkUrl = item.web_view_link || item.url;
                  const linkLabel = item.web_view_link ? "View File" : item.url ? "Visit URL" : null;
                  return (
                    <div key={item.id} className="pub-card">
                      <div className="pub-card-top">
                        <span className="pub-card-icon" style={{ color: meta.color }}>{meta.icon}</span>
                        <span className={`pub-type-badge pub-type-${item.pub_type || "unknown"}`}>{meta.label}</span>
                      </div>
                      <div className="pub-card-body">
                        <p className="pub-card-label">{item.name}</p>
                        <h4 className="pub-card-title">{subject}</h4>
                        {details.length > 0 && (
                          <ul className="pub-card-meta">
                            {details.map((d, i) => d && <li key={i}>{d}</li>)}
                          </ul>
                        )}
                        {item.others && (
                          <p className="pub-card-notes">{item.others}</p>
                        )}
                      </div>
                      <div className="pub-card-footer">
                        <span className="pub-card-date">{item.created_at ? new Date(item.created_at).toLocaleDateString("en-IN", { day: "numeric", month: "short", year: "numeric" }) : ""}</span>
                        {linkLabel ? (
                          <button
                            type="button"
                            className="pub-card-action"
                            onClick={() => window.open(linkUrl, "_blank", "noopener,noreferrer")}
                          >
                            {linkLabel} →
                          </button>
                        ) : (
                          <span className="no-link-text">No link</span>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
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
                      { key: "webpage", icon: "🌐", label: "Webpage", desc: "Information from a specific page on a website" },
                      { key: "journal_article", icon: "📄", label: "Journal Article", desc: "Peer-reviewed academic or scholarly journal articles" },
                      { key: "book", icon: "📚", label: "Book", desc: "Printed book or e-book with publisher info" },
                      { key: "report", icon: "📊", label: "Report", desc: "Research, policy or statistical reports by organizations" },
                      { key: "video", icon: "🎬", label: "Video", desc: "Online videos from YouTube, Vimeo or platforms" },
                      { key: "online_newspaper", icon: "📰", label: "Online Newspaper", desc: "Articles published in online news websites" }
                    ].map((type) => (
                      <button
                        key={type.key}
                        type="button"
                        className="pub-type-card"
                        onClick={() => handlePublicationTypeSelect(type.key)}
                      >
                        <span className="pub-type-icon" aria-hidden="true">{type.icon}</span>
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
                      <h3>
                        {{
                          webpage: "🌐 Webpage Citation",
                          journal_article: "📄 Journal Article Citation",
                          book: "📚 Book Citation",
                          report: "📊 Report Citation",
                          video: "🎬 Video Citation",
                          online_newspaper: "📰 Online Newspaper Citation"
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
                        <label className="form-field">
                          <span>Author <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. John Smith" value={publicationForm.author} onChange={handlePublicationChange("author")} />
                        </label>
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
                        <label className="form-field">
                          <span>Author(s) <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. Smith, J." value={publicationForm.author} onChange={handlePublicationChange("author")} />
                        </label>
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
                        <label className="form-field">
                          <span>Author(s) <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. Smith, J." value={publicationForm.author} onChange={handlePublicationChange("author")} />
                        </label>
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
                        <label className="form-field">
                          <span>Author <span className="req">*</span></span>
                          <input type="text" placeholder="e.g. Jane Doe" value={publicationForm.author} onChange={handlePublicationChange("author")} />
                        </label>
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
                  initialView="dayGridMonth"
                  timeZone="Asia/Kolkata"
                  eventTimeFormat={{ hour: "numeric", minute: "2-digit", meridiem: "short" }}
                  headerToolbar={{
                    left: "prev,next today",
                    center: "title",
                    right: "dayGridMonth,timeGridWeek,timeGridDay"
                  }}
                  height="auto"
                  events={calendarState.events}
                  datesSet={(info) => fetchCalendarEvents({ start: info.start, end: info.end })}
                />
              </div>
            </div>
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
                  {approvalsState.status === "ready" && approvalsState.items.filter((i) => i.status === "pending").length > 0 ? (
                    <span className="tab-badge">{approvalsState.items.filter((i) => i.status === "pending").length}</span>
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
                  {facilityState.status === "ready" && facilityState.items.filter((i) => i.status === "pending").length > 0 ? (
                    <span className="tab-badge">{facilityState.items.filter((i) => i.status === "pending").length}</span>
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
                  {marketingState.status === "ready" && marketingState.items.filter((i) => i.status === "pending").length > 0 ? (
                    <span className="tab-badge">{marketingState.items.filter((i) => i.status === "pending").length}</span>
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
                  {itState.status === "ready" && itState.items.filter((i) => i.status === "pending").length > 0 ? (
                    <span className="tab-badge">{itState.items.filter((i) => i.status === "pending").length}</span>
                  ) : null}
                </button>
              ) : null}
            </div>
            {isApproverRole && approvalsTab === "approval-requests" ? (
            <div className="events-table-card">
              <div className="table-header">
                <h3>Approval Requests</h3>
                <button type="button" className="secondary-action" onClick={loadApprovalsInbox}>Refresh</button>
              </div>
              <div className="events-table">
                <div className="events-table-row header approvals">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Budget</span>
                  <span>Date</span>
                  <span>Time</span>
                  <span>Status</span>
                  <span>Action</span>
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
                        const statusLabel = `${item.status.charAt(0).toUpperCase()}${item.status.slice(1)}`;
                        const eventHasStarted = isEventStarted(item);
                        return (
                          <div key={item.id} className="events-table-row approvals">
                            <span>{item.event_name}</span>
                            <span>{item.requester_email}</span>
                            <span>{item.budget != null ? `Rs ${Number(item.budget).toLocaleString()}` : "—"}</span>
                            <span>{item.start_date}</span>
                          <span>{formatISTTime(item.start_time)}</span>
                          <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                          <div className="approval-actions">
                            <button
                              type="button"
                              className="details-button"
                              onClick={() => handleApprovalDetailsOpen(item)}
                            >
                              Details
                            </button>
                            {item.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  className="details-button"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleApprovalDecision(item.id, "approved")}
                                >
                                  Approve
                                </button>
                                <button
                                  type="button"
                                  className="details-button reject"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleApprovalDecision(item.id, "rejected")}
                                >
                                  Reject
                                </button>
                              </>
                            ) : null}
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
              <div className="table-header">
                <h3>Facility Manager Requests</h3>
                <button type="button" className="secondary-action" onClick={loadFacilityInbox}>Refresh</button>
              </div>
              <div className="events-table">
                <div className="events-table-row header facility">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Date</span>
                  <span>Time</span>
                  <span>Status</span>
                  <span>Needs</span>
                  <span>Action</span>
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
                      const needs = [];
                      if (item.venue_required) {
                        needs.push("Venue");
                      }
                      if (item.refreshments) {
                        needs.push("Refreshments");
                      }
                      const needsLabel = needs.length ? needs.join(", ") : "None";
                      const statusLabel = `${item.status.charAt(0).toUpperCase()}${item.status.slice(1)}`;
                      const eventHasStarted = isEventStarted(item);
                      return (
                        <div key={item.id} className="events-table-row facility">
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <span>{item.start_date}</span>
                          <span>{formatISTTime(item.start_time)}</span>
                          <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                          <span className="marketing-needs">{needsLabel}</span>
                          <div className="approval-actions">
                            <button
                              type="button"
                              className="details-button"
                              onClick={() => item.event_id && handleEventDetailsOpen({ id: item.event_id })}
                              title={item.event_id ? "View event details" : "Event details available after approval"}
                              disabled={!item.event_id}
                            >
                              Details
                            </button>
                            {item.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  className="details-button"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleFacilityDecision(item.id, "approved")}
                                >
                                  Accept
                                </button>
                                <button
                                  type="button"
                                  className="details-button reject"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleFacilityDecision(item.id, "rejected")}
                                >
                                  Reject
                                </button>
                              </>
                            ) : null}
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
              <div className="table-header">
                <h3>Marketing Requests</h3>
                <button type="button" className="secondary-action" onClick={loadMarketingInbox}>Refresh</button>
              </div>
              <div className="events-table">
                <div className="events-table-row header marketing">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Date</span>
                  <span>Time</span>
                  <span>Status</span>
                  <span>Needs</span>
                  <span>Action</span>
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
                      const needs = [];
                      if (item.poster_required) {
                        needs.push("Poster");
                      }
                      if (item.video_required) {
                        needs.push("Video");
                      }
                      if (item.linkedin_post) {
                        needs.push("LinkedIn");
                      }
                      if (item.photography) {
                        needs.push("Photography");
                      }
                      const needsLabel = needs.length ? needs.join(", ") : "None";
                      const statusLabel = `${item.status.charAt(0).toUpperCase()}${item.status.slice(1)}`;
                      const eventHasStarted = isEventStarted(item);
                      return (
                        <div key={item.id} className="events-table-row marketing">
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <span>{item.start_date}</span>
                          <span>{formatISTTime(item.start_time)}</span>
                          <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                          <span className="marketing-needs">{needsLabel}</span>
                          <div className="approval-actions">
                            <button
                              type="button"
                              className="details-button"
                              onClick={() => item.event_id && handleEventDetailsOpen({ id: item.event_id })}
                              title={item.event_id ? "View event details" : "Event details available after approval"}
                              disabled={!item.event_id}
                            >
                              Details
                            </button>
                            <button
                              type="button"
                              className="details-button upload"
                              disabled={eventHasStarted}
                              title={eventHasStarted ? "Event has already started" : ""}
                              onClick={() => openMarketingDeliverableModal(item)}
                            >
                              Upload
                            </button>
                            {item.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  className="details-button"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleMarketingDecision(item.id, "approved")}
                                >
                                  Accept
                                </button>
                                <button
                                  type="button"
                                  className="details-button reject"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleMarketingDecision(item.id, "rejected")}
                                >
                                  Reject
                                </button>
                              </>
                            ) : null}
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
              <div className="table-header">
                <h3>IT Requests</h3>
                <button type="button" className="secondary-action" onClick={loadItInbox}>Refresh</button>
              </div>
              <div className="events-table">
                <div className="events-table-row header it">
                  <span>Event</span>
                  <span>Requester</span>
                  <span>Date</span>
                  <span>Time</span>
                  <span>Status</span>
                  <span>Needs</span>
                  <span>Action</span>
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
                      const needs = [];
                      if (item.pa_system) {
                        needs.push("PA System");
                      }
                      if (item.projection) {
                        needs.push("Projection");
                      }
                      const needsLabel = needs.length ? needs.join(", ") : "None";
                      const statusLabel = `${item.status.charAt(0).toUpperCase()}${item.status.slice(1)}`;
                      const eventHasStarted = isEventStarted(item);
                      return (
                        <div key={item.id} className="events-table-row it">
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <span>{item.start_date}</span>
                          <span>{formatISTTime(item.start_time)}</span>
                          <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                          <span className="marketing-needs">{needsLabel}</span>
                          <div className="approval-actions">
                            <button
                              type="button"
                              className="details-button"
                              onClick={() => item.event_id && handleEventDetailsOpen({ id: item.event_id })}
                              title={item.event_id ? "View event details" : "Event details available after approval"}
                              disabled={!item.event_id}
                            >
                              Details
                            </button>
                            {item.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  className="details-button"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleItDecision(item.id, "approved")}
                                >
                                  Accept
                                </button>
                                <button
                                  type="button"
                                  className="details-button reject"
                                  disabled={eventHasStarted}
                                  title={eventHasStarted ? "Event has already started" : ""}
                                  onClick={() => handleItDecision(item.id, "rejected")}
                                >
                                  Reject
                                </button>
                              </>
                            ) : null}
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
      <div className="dashboard-page">
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
                <>
                  <div className="details-grid">
                    <div>
                      <p className="details-label">Event</p>
                      <p className="details-value">{eventDetailsModal.details.event?.name || eventDetailsModal.event?.name}</p>
                    </div>
                    <div>
                      <p className="details-label">Facilitator</p>
                      <p className="details-value">{eventDetailsModal.details.event?.facilitator}</p>
                    </div>
                    <div>
                      <p className="details-label">Venue</p>
                      <p className="details-value">{eventDetailsModal.details.event?.venue_name}</p>
                    </div>
                    <div>
                      <p className="details-label">Budget (Rs)</p>
                      <p className="details-value">
                        {eventDetailsModal.details.event?.budget != null
                          ? `Rs ${Number(eventDetailsModal.details.event.budget).toLocaleString()}`
                          : "—"}
                      </p>
                    </div>
                    <div>
                      <p className="details-label">Status</p>
                      <p className="details-value">{eventDetailsModal.details.event?.status}</p>
                    </div>
                    <div>
                      <p className="details-label">Start</p>
                      <p className="details-value">
                        {eventDetailsModal.details.event?.start_date && eventDetailsModal.details.event?.start_time
                          ? `${eventDetailsModal.details.event.start_date} ${formatISTTime(eventDetailsModal.details.event.start_time)}`
                          : "—"}
                      </p>
                    </div>
                    <div>
                      <p className="details-label">End</p>
                      <p className="details-value">
                        {eventDetailsModal.details.event?.end_date && eventDetailsModal.details.event?.end_time
                          ? `${eventDetailsModal.details.event.end_date} ${formatISTTime(eventDetailsModal.details.event.end_time)}`
                          : "—"}
                      </p>
                    </div>
                    <div className="details-wide">
                      <p className="details-label">Description</p>
                      <p className="details-value">{eventDetailsModal.details.event?.description || "—"}</p>
                    </div>
                  </div>

                  <div className="event-details-section">
                    <p className="details-label">Registrar approval</p>
                    {eventDetailsModal.details.approval_request ? (
                      <div className="details-subsection">
                        <p className="details-value">
                          Sent to: <strong>{eventDetailsModal.details.approval_request.requested_to || "—"}</strong>
                        </p>
                        <p className="details-value">
                          Status: <span className={`status-pill ${eventDetailsModal.details.approval_request.status}`}>
                            {eventDetailsModal.details.approval_request.status}
                          </span>
                        </p>
                        {eventDetailsModal.details.approval_request.status === "approved" && eventDetailsModal.details.approval_request.decided_by ? (
                          <p className="details-value">Approved by: <strong>{eventDetailsModal.details.approval_request.decided_by}</strong></p>
                        ) : eventDetailsModal.details.approval_request.status === "pending" ? (
                          <p className="details-value">Awaiting approval from registrar.</p>
                        ) : eventDetailsModal.details.approval_request.decided_by ? (
                          <p className="details-value">Decided by: <strong>{eventDetailsModal.details.approval_request.decided_by}</strong></p>
                        ) : null}
                      </div>
                    ) : (
                      <p className="details-value">No approval request sent for this event.</p>
                    )}
                  </div>

                  <div className="event-details-section">
                    <p className="details-label">Requirements sent</p>
                    {eventDetailsModal.details.facility_requests?.length > 0 ? (
                      <div className="details-subsection">
                        <p className="details-sublabel">Facility</p>
                        {eventDetailsModal.details.facility_requests.map((r, i) => (
                          <div key={r.id || i} className="details-row">
                            <span>To: {r.requested_to || "—"}</span>
                            <span className={`status-pill ${r.status}`}>{r.status}</span>
                            {r.decided_by ? <span>By: {r.decided_by}</span> : r.status === "pending" ? <span>Pending</span> : null}
                          </div>
                        ))}
                      </div>
                    ) : null}
                    {eventDetailsModal.details.marketing_requests?.length > 0 ? (
                      <div className="details-subsection">
                        <p className="details-sublabel">Marketing</p>
                        {eventDetailsModal.details.marketing_requests.map((r, i) => (
                          <div key={r.id || i} className="details-row">
                            <span>To: {r.requested_to || "—"}</span>
                            <span className={`status-pill ${r.status}`}>{r.status}</span>
                            {r.decided_by ? <span>By: {r.decided_by}</span> : r.status === "pending" ? <span>Pending</span> : null}
                          </div>
                        ))}
                      </div>
                    ) : null}
                    {eventDetailsModal.details.it_requests?.length > 0 ? (
                      <div className="details-subsection">
                        <p className="details-sublabel">IT</p>
                        {eventDetailsModal.details.it_requests.map((r, i) => (
                          <div key={r.id || i} className="details-row">
                            <span>To: {r.requested_to || "—"}</span>
                            <span className={`status-pill ${r.status}`}>{r.status}</span>
                            {r.decided_by ? <span>By: {r.decided_by}</span> : r.status === "pending" ? <span>Pending</span> : null}
                          </div>
                        ))}
                      </div>
                    ) : null}
                    {!(eventDetailsModal.details.facility_requests?.length || eventDetailsModal.details.marketing_requests?.length || eventDetailsModal.details.it_requests?.length) ? (
                      <p className="details-value">No facility, marketing, or IT requests sent yet.</p>
                    ) : null}
                  </div>

                  {eventDetailsModal.details.marketing_requests?.some((r) => r.deliverables?.length) ? (
                    <div className="event-details-section">
                      <p className="details-label">Files uploaded by marketing</p>
                      {eventDetailsModal.details.marketing_requests.map((req, i) =>
                        req.deliverables?.length ? (
                          <div key={req.id || i} className="details-subsection">
                            {eventDetailsModal.details.marketing_requests.length > 1 ? (
                              <p className="details-sublabel">Request to {req.requested_to || "marketing"}</p>
                            ) : null}
                            <ul className="details-list">
                              {req.deliverables.map((d, j) => (
                                <li key={j}>
                                  {d.is_na ? (
                                    <span>{d.deliverable_type}: N/A</span>
                                  ) : d.web_view_link ? (
                                    <a href={d.web_view_link} target="_blank" rel="noreferrer">{d.file_name || d.deliverable_type}</a>
                                  ) : (
                                    <span>{d.file_name || d.deliverable_type}</span>
                                  )}
                                  {!d.is_na ? ` (${d.deliverable_type})` : null}
                                </li>
                              ))}
                            </ul>
                          </div>
                        ) : null
                      )}
                    </div>
                  ) : null}

                </>
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
            <div className="modal-card details-card">
              <div className="modal-header">
                <h3>Approval Request Details</h3>
                <button type="button" className="modal-close" onClick={handleApprovalDetailsClose}>
                  &times;
                </button>
              </div>
              {approvalDetailsModal.request ? (
                <div className="details-grid">
                  <div>
                    <p className="details-label">Event</p>
                    <p className="details-value">{approvalDetailsModal.request.event_name || "-"}</p>
                  </div>
                  <div>
                    <p className="details-label">Requester</p>
                    <p className="details-value">{approvalDetailsModal.request.requester_email || "-"}</p>
                  </div>
                  <div>
                    <p className="details-label">Budget (Rs)</p>
                    <p className="details-value">
                      {approvalDetailsModal.request.budget != null &&
                      approvalDetailsModal.request.budget !== "" &&
                      !isNaN(Number(approvalDetailsModal.request.budget))
                        ? `Rs ${Number(approvalDetailsModal.request.budget).toLocaleString()}`
                        : "—"}
                    </p>
                  </div>
                  <div>
                    <p className="details-label">Requested To</p>
                    <p className="details-value">{approvalDetailsModal.request.requested_to || "-"}</p>
                  </div>
                  <div>
                    <p className="details-label">Status</p>
                    <p className="details-value">{approvalDetailsModal.request.status || "-"}</p>
                  </div>
                  <div>
                    <p className="details-label">Facilitator</p>
                    <p className="details-value">{approvalDetailsModal.request.facilitator || "-"}</p>
                  </div>
                  <div>
                    <p className="details-label">Venue</p>
                    <p className="details-value">{approvalDetailsModal.request.venue_name || "-"}</p>
                  </div>
                  <div>
                    <p className="details-label">Start</p>
                    <p className="details-value">
                      {approvalDetailsModal.request.start_date || "-"} ?{" "}
                      {approvalDetailsModal.request.start_time
                        ? formatISTTime(approvalDetailsModal.request.start_time)
                        : "-"}
                    </p>
                  </div>
                  <div>
                    <p className="details-label">End</p>
                    <p className="details-value">
                      {approvalDetailsModal.request.end_date || "-"} ?{" "}
                      {approvalDetailsModal.request.end_time
                        ? formatISTTime(approvalDetailsModal.request.end_time)
                        : "-"}
                    </p>
                  </div>
                  <div className="details-wide">
                    <p className="details-label">Requirements</p>
                    <p className="details-value">
                      {Array.isArray(approvalDetailsModal.request.requirements) &&
                      approvalDetailsModal.request.requirements.length
                        ? approvalDetailsModal.request.requirements.join(", ")
                        : "None"}
                    </p>
                  </div>
                  <div className="details-wide">
                    <p className="details-label">Other Notes</p>
                    <p className="details-value">{approvalDetailsModal.request.other_notes || "-"}</p>
                  </div>
                  <div className="details-wide">
                    <p className="details-label">Description</p>
                    <p className="details-value">{approvalDetailsModal.request.description || "-"}</p>
                  </div>
                </div>
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
                For each requirement, select NA or upload a file (max 25MB each).
              </p>
              <form className="event-form" onSubmit={submitMarketingDeliverable}>
                {REQUIREMENT_OPTIONS.filter((opt) => marketingDeliverableModal.request?.[opt.key]).map((opt) => {
                  const r = marketingDeliverableModal.requirements?.[opt.type] || { na: false, file: null };
                  return (
                    <div key={opt.type} className="form-field deliverable-row">
                      <span className="deliverable-label">{opt.label}</span>
                      <label className="deliverable-na">
                        <input
                          type="checkbox"
                          checked={r.na}
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
                          disabled={r.na}
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
                            <span>{d.deliverable_type}: N/A</span>
                          ) : d.web_view_link ? (
                            <a href={d.web_view_link} target="_blank" rel="noreferrer">
                              {d.file_name || d.deliverable_type}
                            </a>
                          ) : (
                            <span>{d.file_name || d.deliverable_type}</span>
                          )}
                          {!d.is_na ? ` (${d.deliverable_type})` : null}
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
                      !Object.values(marketingDeliverableModal.requirements || {}).some((r) => r.na || r.file)
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
        />

        <main className="dashboard-main">
          <header className="dashboard-header">
            <div>
              <p className="dashboard-title">
                {isMyEvents
                  ? "My Events"
                  : isReportsView
                    ? "Event Reports"
                    : isPublications
                      ? "Publications"
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

            <aside className="chat-panel">
              <div className="chat-header">
                <div>
                  <p className="chat-title">Messages</p>
                  <p className="chat-subtitle">Select a user to start chatting</p>
                </div>
                <button
                  type="button"
                  className="icon-button chat-refresh"
                  onClick={() => loadChatUsers()}
                  aria-label="Refresh users"
                >
                  <SimpleIcon path="M12 5a7 7 0 1 1-6.3 4H3l3-3 3 3H7.3A4.7 4.7 0 1 0 12 7v2l3-3-3-3v2Z" />
                </button>
              </div>
              <div className="chat-users">
                {chatUsers.map((chatUser) => {
                  const name = chatUser.name || "Unknown";
                  const avatarLabel = name.trim().charAt(0).toUpperCase() || "?";
                  return (
                    <button
                      key={chatUser.id}
                      type="button"
                      className={`chat-user ${chatActiveUser?.id === chatUser.id ? "active" : ""}`}
                      onClick={() => startConversation(chatUser)}
                    >
                      <span className="chat-avatar" aria-hidden="true">
                        {avatarLabel}
                        <span className={`chat-presence ${chatUser.online ? "online" : ""}`} />
                      </span>
                      <div className="chat-user-text">
                        <p className="chat-user-name">
                          {name}
                          {chatUser.unread ? <span className="chat-unread">{chatUser.unread}</span> : null}
                        </p>
                      </div>
                    </button>
                  );
                })}
                {chatUsers.length === 0 ? <p className="chat-note">No users found.</p> : null}
              </div>
            </aside>
            {chatActiveUser ? (
              <div className="chat-window" role="dialog" aria-label={`Chat with ${chatActiveUser.name}`}>
                <div className="chat-window-header">
                  <div>
                    <p className="chat-thread-name">{chatActiveUser.name}</p>
                    <p className="chat-thread-status">
                      {chatActiveUser.online
                        ? "Online"
                        : chatActiveUser.last_seen
                          ? `Last seen ${formatChatTime(chatActiveUser.last_seen)}`
                          : "Last seen unknown"}
                    </p>
                  </div>
                  <button
                    type="button"
                    className="chat-window-close"
                    onClick={() => {
                      setChatActiveUser(null);
                      setChatConversationId("");
                      setChatMessages([]);
                      setChatTypingUser(null);
                    }}
                    aria-label="Close chat window"
                  >
                    &times;
                  </button>
                </div>
                <div className="chat-body" ref={chatListRef}>
                  {chatHasMore && chatMessages.length ? (
                    <button
                      type="button"
                      className="chat-load"
                      onClick={() => loadConversationMessages(chatConversationId, chatMessages[0]?.created_at)}
                      disabled={chatLoadingMore}
                    >
                      {chatLoadingMore ? "Loading..." : "Load earlier"}
                    </button>
                  ) : null}
                  {chatStatus.status === "loading" ? <p className="chat-note">Loading chat...</p> : null}
                  {chatStatus.status === "error" ? <p className="chat-note">{chatStatus.error}</p> : null}
                  {chatMessages.map((message) => {
                    const isOwn = message.sender_id === user.id;
                    const isRead = chatActiveUser && message.read_by.includes(chatActiveUser.id);
                    return (
                      <div key={message.id} className={`chat-message ${isOwn ? "own" : ""}`}>
                        <div className="chat-bubble">
                          <div className="chat-meta">
                            <span className="chat-author">{message.sender_name}</span>
                            <span>{formatChatTime(message.created_at)}</span>
                          </div>
                          {message.content ? <p className="chat-text">{message.content}</p> : null}
                          {message.attachments?.length ? (
                            <div className="chat-attachments">
                              {message.attachments.map((attachment) => {
                                const url = resolveAttachmentUrl(attachment.url);
                                const isImage = attachment.content_type?.startsWith("image/");
                                return (
                                  <div key={`${message.id}-${attachment.url}`} className="chat-attachment">
                                    {isImage ? (
                                      <img src={url} alt={attachment.name} />
                                    ) : (
                                      <a href={url} target="_blank" rel="noreferrer">
                                        {attachment.name}
                                      </a>
                                    )}
                                  </div>
                                );
                              })}
                            </div>
                          ) : null}
                          {isOwn ? (
                            <div className="chat-read">{isRead ? "✓✓" : "✓"}</div>
                          ) : null}
                        </div>
                      </div>
                    );
                  })}
                </div>
                {typingName ? <div className="chat-typing">{typingName} typing...</div> : null}
                <div className="chat-composer compact">
                  {chatFiles.length ? (
                    <div className="chat-files">
                      {chatFiles.map((file, index) => (
                        <div key={`${file.name}-${index}`} className="chat-file">
                          <span>{file.name}</span>
                          <button
                            type="button"
                            className="chat-file-remove"
                            onClick={() => removeChatFile(index)}
                            aria-label={`Remove ${file.name}`}
                          >
                            &times;
                          </button>
                        </div>
                      ))}
                    </div>
                  ) : null}
                  <div className="chat-input-row">
                    <label className="chat-attach">
                      <input type="file" multiple onChange={handleChatFiles} disabled={!chatActiveUser} />
                      <span>+</span>
                    </label>
                    <textarea
                      value={chatInput}
                      onChange={handleChatInputChange}
                      placeholder="Type a message..."
                      rows={2}
                      onKeyDown={(event) => {
                        if (event.key === "Enter" && !event.shiftKey) {
                          event.preventDefault();
                          sendChatMessage();
                        }
                      }}
                    />
                    <button type="button" className="chat-send" onClick={sendChatMessage}>
                      Send
                    </button>
                  </div>
                </div>
              </div>
            ) : null}
          </section>
        </main>
      </div>
    );
  }

  return <LoginPage googleButtonRef={googleButtonRef} status={status} />;
}

