import { useCallback, useEffect, useRef, useState } from "react";
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import interactionPlugin from "@fullcalendar/interaction";

const stats = [
  { label: "Active Events", value: "128+" },
  { label: "Attendees Managed", value: "24k" },
  { label: "Automated Reminders", value: "98%" }
];

const menuItems = [
  { id: "dashboard", label: "Dashboard" },
  { id: "my-events", label: "My Events" },
  { id: "event-reports", label: "Event Reports" },
  { id: "calendar", label: "Calendar View" },
  { id: "approvals", label: "Approvals" },
  { id: "publications", label: "Publications" },
  { id: "admin", label: "Admin Console" }
];

const preferenceItems = [
  { id: "users", label: "User Management" },
  { id: "settings", label: "Settings" }
];

const inboxItems = [
  {
    name: "Nur Azzahra",
    time: "2 hours ago",
    message: "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
  },
  {
    name: "Nur Azzahra",
    time: "2 hours ago",
    message: "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
  },
  {
    name: "Nur Azzahra",
    time: "2 hours ago",
    message: "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
  }
];

const eventsTable = [
  {
    name: "Event 1",
    date: "11 September 2025",
    time: "9 am",
    status: "In Progress"
  },
  {
    name: "Event 2",
    date: "12 September 2025",
    time: "1 pm",
    status: "Ready"
  },
  {
    name: "Event 3",
    date: "15 October 2025",
    time: "2 pm",
    status: "Pending"
  },
  {
    name: "Event 4",
    date: "18 September 2025",
    time: "9 am",
    status: "Ready"
  },
  {
    name: "Event 5",
    date: "22 September 2025",
    time: "1 pm",
    status: "Pending"
  },
  {
    name: "Event 6",
    date: "1 October 2025",
    time: "2 pm",
    status: "Pending"
  },
  {
    name: "Event 7",
    date: "18 September 2025",
    time: "9 am",
    status: "Ready"
  },
  {
    name: "Event 8",
    date: "22 September 2025",
    time: "1 pm",
    status: "Pending"
  },
  {
    name: "Event 9",
    date: "1 October 2025",
    time: "2 pm",
    status: "Pending"
  }
];

const GoogleIcon = () => (
  <svg viewBox="0 0 48 48" aria-hidden="true" focusable="false">
    <path
      fill="#EA4335"
      d="M24 9.5c3.3 0 6.1 1.1 8.3 3.1l6-6C34.7 3.4 29.8 1.5 24 1.5 14.6 1.5 6.6 6.9 3.2 14.7l7.2 5.6C12.2 14 17.7 9.5 24 9.5z"
    />
    <path
      fill="#FBBC05"
      d="M46.5 24.5c0-1.6-.1-2.7-.4-4H24v7.6h12.7c-.5 2.6-2 6.4-5.2 9l8 6.2c4.7-4.3 7-10.7 7-18.8z"
    />
    <path
      fill="#34A853"
      d="M10.4 28.3a13.9 13.9 0 0 1-.7-4.3c0-1.5.3-3 .7-4.3l-7.2-5.6A23.6 23.6 0 0 0 1.5 24c0 3.9.9 7.5 2.7 10.9l6.2-6.6z"
    />
    <path
      fill="#4285F4"
      d="M24 46.5c6.4 0 11.7-2.1 15.6-5.8l-8-6.2c-2.2 1.5-5.1 2.6-7.6 2.6-6.3 0-11.7-4.2-13.6-10l-6.2 6.6C7.6 41.8 15.2 46.5 24 46.5z"
    />
  </svg>
);

const PlaceholderCard = () => (
  <div className="image-card">
    <div className="image-glow" />
    <div className="image-placeholder">
      <div className="image-icon" aria-hidden="true" />
    </div>
  </div>
);

const SimpleIcon = ({ path }) => (
  <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
    <path d={path} />
  </svg>
);

export default function App() {
  const googleButtonRef = useRef(null);
  const [status, setStatus] = useState({ type: "idle", message: "" });
  const [searchInput, setSearchInput] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [activeView, setActiveView] = useState("dashboard");
  const [myEventsTab, setMyEventsTab] = useState("all");
  const [isEventModalOpen, setIsEventModalOpen] = useState(false);
  const [venuesState, setVenuesState] = useState({ status: "idle", items: [], error: "" });
  const [eventsState, setEventsState] = useState({ status: "idle", items: [], error: "" });
  const [approvalsState, setApprovalsState] = useState({ status: "idle", items: [], error: "" });
  const [marketingState, setMarketingState] = useState({ status: "idle", items: [], error: "" });
  const [itState, setItState] = useState({ status: "idle", items: [], error: "" });
  const [eventForm, setEventForm] = useState({
    start_date: "",
    end_date: "",
    start_time: "",
    end_time: "",
    name: "",
    facilitator: "",
    venue_name: "",
    description: ""
  });
  const [eventTimeParts, setEventTimeParts] = useState({
    start_time: { hour: "", minute: "", period: "AM" },
    end_time: { hour: "", minute: "", period: "AM" }
  });
  const [eventFormStatus, setEventFormStatus] = useState({ status: "idle", error: "" });
  const [conflictState, setConflictState] = useState({ open: false, items: [] });
  const [approvalModal, setApprovalModal] = useState({ open: false, status: "idle", error: "" });
  const [approvalForm, setApprovalForm] = useState({
    to: "",
    requirements: {
      venue: true,
      refreshments: false
    },
    other_notes: ""
  });
  const [skipApprovalFlow, setSkipApprovalFlow] = useState(false);
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
    recording: false,
    other_notes: ""
  });
  const [itModal, setItModal] = useState({ open: false, status: "idle", error: "" });
  const [itForm, setItForm] = useState({
    to: "",
    pa_system: true,
    projection: false,
    other_notes: ""
  });
  const [reportModal, setReportModal] = useState({
    open: false,
    status: "idle",
    error: "",
    eventId: "",
    eventName: "",
    hasReport: false
  });
  const [eventDetailsModal, setEventDetailsModal] = useState({ open: false, event: null });
  const [publicationModal, setPublicationModal] = useState({
    open: false,
    status: "idle",
    error: ""
  });
  const [publicationForm, setPublicationForm] = useState({
    name: "",
    title: "",
    file: null,
    others: ""
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
  const [googleScopeModal, setGoogleScopeModal] = useState({
    open: false,
    missing: []
  });
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
  const isAdmin = (user?.role || "").toLowerCase() === "admin";
  const defaultFacilitator = (user?.name || "").trim();

  const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";
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
    setActiveView("dashboard");
    setStatus({ type: "error", message: "Session expired. Please log in again." });
  }, []);

  const apiFetch = useCallback(
    async (input, init = {}) => {
      const token = localStorage.getItem("auth_token");
      if (!token) {
        handleSessionExpired();
        throw new Error("Missing auth token.");
      }

      const headers = {
        ...(init.headers || {}),
        Authorization: `Bearer ${token}`
      };

      const res = await fetch(input, { ...init, headers });
      if (res.status === 401) {
        handleSessionExpired();
      }
      return res;
    },
    [handleSessionExpired]
  );

  const loadPublications = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setPublicationsState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }
    setPublicationsState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await apiFetch(`${apiBaseUrl}/publications`);
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
  }, [apiBaseUrl, apiFetch]);

  const loadAdminOverview = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminUsers = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminVenues = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminEvents = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminApprovals = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminMarketing = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminIt = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminInvites = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);

  const loadAdminPublications = useCallback(async () => {
    if (!isAdmin) {
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
  }, [apiBaseUrl, apiFetch, isAdmin]);


  const handleAdminRoleChange = useCallback(
    async (targetUserId, role) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin, user]
  );

  const handleAdminDeleteUser = useCallback(
    async (targetUserId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminCreateVenue = useCallback(
    async (name) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminDeleteVenue = useCallback(
    async (venueId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminDeleteEvent = useCallback(
    async (eventId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminDeleteApproval = useCallback(
    async (requestId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminDeleteMarketing = useCallback(
    async (requestId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminDeleteIt = useCallback(
    async (requestId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminDeleteInvite = useCallback(
    async (inviteId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
  );

  const handleAdminDeletePublication = useCallback(
    async (publicationId) => {
      if (!isAdmin) {
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
    [apiBaseUrl, apiFetch, isAdmin]
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

  const formatISTTime = useCallback((value) => {
    if (!value) {
      return "";
    }
    const raw = String(value).trim();
    const timeMatch = raw.match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
    if (timeMatch) {
      const hours24 = Number(timeMatch[1]);
      const minutes = timeMatch[2];
      if (Number.isNaN(hours24) || hours24 > 23) {
        return raw;
      }
      const period = hours24 >= 12 ? "PM" : "AM";
      const hours12 = hours24 % 12 || 12;
      return `${hours12}:${minutes} ${period}`;
    }
    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) {
      return raw;
    }
    return parsed
      .toLocaleTimeString("en-IN", {
        timeZone: "Asia/Kolkata",
        hour: "numeric",
        minute: "2-digit",
        hour12: true
      })
      .toUpperCase();
  }, []);

  const parse24ToTimeParts = useCallback((value) => {
    const raw = String(value || "").trim();
    const match = raw.match(/^(\d{1,2}):(\d{2})(?::\d{2})?$/);
    if (!match) {
      return { hour: "", minute: "", period: "AM" };
    }
    const hours24 = Number(match[1]);
    if (Number.isNaN(hours24) || hours24 > 23) {
      return { hour: "", minute: "", period: "AM" };
    }
    const minute = match[2];
    const period = hours24 >= 12 ? "PM" : "AM";
    const hour12 = hours24 % 12 || 12;
    return { hour: String(hour12), minute, period };
  }, []);

  const timePartsTo24 = useCallback((parts) => {
    if (!parts?.hour || !parts?.minute || !parts?.period) {
      return "";
    }
    const hour12 = Number(parts.hour);
    if (Number.isNaN(hour12) || hour12 < 1 || hour12 > 12) {
      return "";
    }
    const minute = String(parts.minute).padStart(2, "0");
    if (!/^\d{2}$/.test(minute)) {
      return "";
    }
    const period = String(parts.period).toUpperCase();
    let hour24 = hour12 % 12;
    if (period === "PM") {
      hour24 += 12;
    }
    return `${String(hour24).padStart(2, "0")}:${minute}`;
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
        setActiveView("dashboard");
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
        ? `${apiBaseUrl}/calendar/events?${query}`
        : `${apiBaseUrl}/calendar/events`;
      const res = await apiFetch(url);

      if (res.status === 403) {
        setCalendarState({
          status: "needs_auth",
          events: [],
          error: "Connect your Google Calendar to load events."
        });
        return;
      }

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
      const [eventsRes, approvalsRes, marketingRes, itRes, invitesRes] = await Promise.all([
        apiFetch(`${apiBaseUrl}/events`),
        apiFetch(`${apiBaseUrl}/approvals/me`),
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

      const eventsData = await eventsRes.json();
      const approvalsData = await approvalsRes.json();
      const marketingData = marketingRes.ok ? await marketingRes.json() : [];
      const itData = itRes.ok ? await itRes.json() : [];
      const invitesData = invitesRes.ok ? await invitesRes.json() : [];
      const approvalByEventId = new Map();
      const marketingByEventId = new Map();
      const itByEventId = new Map();
      const inviteByEventId = new Map();
      const approvalByEventKey = new Map();
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
          marketing_status:
            marketingByEventId.get(event.id) || marketingByEventKey.get(eventKey),
          it_status: itByEventId.get(event.id) || itByEventKey.get(eventKey),
          invite_status: inviteByEventId.get(event.id)
        };
      });

      setEventsState({
        status: "ready",
        items: [...approvalItems, ...enrichedEvents],
        error: ""
      });
    } catch (err) {
      setEventsState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load events."
      });
    }
  }, [apiBaseUrl]);

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

  const checkGoogleScopes = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      return;
    }

    try {
      const res = await apiFetch(`${apiBaseUrl}/auth/google/status`);
      if (!res.ok) {
        return;
      }
      const data = await res.json();
      const missing = data?.missing_scopes || [];
      if (missing.length) {
        setGoogleScopeModal({ open: true, missing });
      } else {
        setGoogleScopeModal({ open: false, missing: [] });
      }
    } catch (err) {
      // Keep silent to avoid blocking the UI on a status check
    }
  }, [apiBaseUrl, apiFetch]);

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
    if (!user || (activeView !== "my-events" && activeView !== "dashboard")) {
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
    if (!user || activeView !== "approvals") {
      return;
    }
    if (approvalsState.status === "idle") {
      loadApprovalsInbox();
    }
    if (marketingState.status === "idle") {
      loadMarketingInbox();
    }
    if (itState.status === "idle") {
      loadItInbox();
    }
  }, [
    activeView,
    approvalsState.status,
    loadApprovalsInbox,
    loadItInbox,
    loadMarketingInbox,
    itState.status,
    marketingState.status,
    user
  ]);

  useEffect(() => {
    if (!user || !isAdmin || activeView !== "admin") {
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
    isAdmin,
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
    setSkipApprovalFlow(false);
    setApprovalForm({
      to: "",
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

  const handleApprovalSkip = async () => {
    setSkipApprovalFlow(true);
    setPendingEvent({ ...eventForm });
    handleApprovalModalClose();
    handleMarketingModalOpen();
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
      to: "",
      poster_required: true,
      poster_dimension: "",
      video_required: false,
      video_dimension: "",
      linkedin_post: false,
      photography: false,
      recording: false,
      other_notes: ""
    });
    setMarketingModal({ open: true, status: "idle", error: "" });
  };

  const handleMarketingModalClose = () => {
    setMarketingModal({ open: false, status: "idle", error: "" });
  };

  const handleItModalOpen = () => {
    setItForm({
      to: "",
      pa_system: true,
      projection: false,
      other_notes: ""
    });
    setItModal({ open: true, status: "idle", error: "" });
  };

  const handleItModalClose = () => {
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
      description: ""
    });
  };

  const createEventDirect = async () => {
    try {
      const parsedStart = timePartsTo24(eventTimeParts.start_time);
      const parsedEnd = timePartsTo24(eventTimeParts.end_time);
      if (!parsedStart || !parsedEnd) {
        throw new Error("Select hour, minute and AM/PM for start and end time.");
      }
      const normalizedEventForm = {
        ...eventForm,
        start_time: parsedStart,
        end_time: parsedEnd
      };
      const payload = overrideConflict
        ? { ...normalizedEventForm, override_conflict: true }
        : normalizedEventForm;
      const res = await apiFetch(`${apiBaseUrl}/events`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        const message = data?.detail || "Unable to create event.";
        throw new Error(message);
      }
      resetEventFormState();
      setSkipApprovalFlow(false);
      loadEvents();
    } catch (err) {
      setStatus({ type: "error", message: err?.message || "Unable to create event." });
    }
  };

  const handleMarketingSkip = () => {
    handleMarketingModalClose();
    handleItModalOpen();
  };

  const handleItSkip = async () => {
    handleItModalClose();
    if (skipApprovalFlow) {
      await createEventDirect();
    }
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

  const handleEventDetailsOpen = (eventItem) => {
    setEventDetailsModal({ open: true, event: eventItem });
  };

  const handleEventDetailsClose = () => {
    setEventDetailsModal({ open: false, event: null });
  };

  const handleReportClose = () => {
    setReportFile(null);
    setReportModal({ open: false, status: "idle", error: "", eventId: "", eventName: "", hasReport: false });
  };

  const handleReportFileChange = (event) => {
    setReportFile(event.target.files?.[0] || null);
  };

  const handlePublicationOpen = () => {
    setPublicationForm({
      name: "",
      title: "",
      file: null,
      others: ""
    });
    setPublicationModal({ open: true, status: "idle", error: "" });
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
    if (!publicationForm.name || !publicationForm.title || !publicationForm.file) {
      setPublicationModal({
        open: true,
        status: "error",
        error: "Please fill name, title, and attach a file."
      });
      return;
    }
    setPublicationModal({ open: true, status: "loading", error: "" });
    try {
      const formData = new FormData();
      formData.append("name", publicationForm.name);
      formData.append("title", publicationForm.title);
      formData.append("others", publicationForm.others || "");
      formData.append("file", publicationForm.file);
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
    if (!eventItem?.id) {
      return;
    }
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
    const statusLabel = explicitStatus || derivedStatus;
    const statusClass = (statusValue || statusLabel).toLowerCase().replace(/\s+/g, "-");
    return { statusLabel, statusClass };
  };

  const getNormalizedEventStatus = (event) => {
    const { statusLabel } = getEventStatusInfo(event);
    return (statusLabel || "").toLowerCase();
  };
  const submitEvent = async (formEvent, override) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const completedUnclosedCount = eventsState.items.filter((event) => {
      const isApprovalItem = String(event.id || "").startsWith("approval-");
      if (isApprovalItem) {
        return false;
      }
      return getNormalizedEventStatus(event) === "completed";
    }).length;
    if (completedUnclosedCount >= 5) {
      setEventFormStatus({
        status: "error",
        error: "Submit reports for completed events before creating a new one."
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
      const payload = override
        ? { ...eventForm, start_time: parsedStart, end_time: parsedEnd, override_conflict: true }
        : { ...eventForm, start_time: parsedStart, end_time: parsedEnd };
      const res = await apiFetch(`${apiBaseUrl}/events`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
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
        description: ""
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
      const requirements = [];
      if (approvalForm.requirements.venue) {
        requirements.push("Venue");
      }
      if (approvalForm.requirements.refreshments) {
        requirements.push("Refreshments");
      }

      const payload = {
        ...eventForm,
        submit_for_approval: true,
        approval_to: approvalForm.to,
        requirements,
        other_notes: approvalForm.other_notes
      };

      const res = await apiFetch(`${apiBaseUrl}/events`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        throw new Error("Unable to send approval request.");
      }

      setPendingEvent({ ...eventForm });
      setSkipApprovalFlow(false);
      setApprovalModal({ open: false, status: "idle", error: "" });
      handleMarketingModalOpen();
      setConflictState({ open: false, items: [] });
      loadEvents();
    } catch (err) {
      setApprovalModal({
        open: true,
        status: "error",
        error: err?.message || "Unable to send approval request."
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
        recording: marketingForm.recording,
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
      handleItModalOpen();
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
        event_name: eventPayload?.name || "",
        start_date: eventPayload?.start_date || "",
        start_time: eventPayload?.start_time || "",
        end_date: eventPayload?.end_date || "",
        end_time: eventPayload?.end_time || "",
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
      if (skipApprovalFlow) {
        await createEventDirect();
        return;
      }
      resetEventFormState();
      loadEvents();
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
    const isPublications = activeView === "publications";
    const isAdminView = activeView === "admin";
    const visibleMenuItems = isAdmin ? menuItems : menuItems.filter((item) => item.id !== "admin");
    const typingName = chatTypingUser?.name || "";

    const handleApprovalDecision = async (requestId, decision) => {
      const token = localStorage.getItem("auth_token");
      if (!token) {
        setApprovalsState({ status: "error", items: [], error: "Missing auth token." });
        return;
      }

      try {
        const res = await apiFetch(`${apiBaseUrl}/approvals/${requestId}`, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json"
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
        if (!isAdmin) {
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
                  <button type="button" className="secondary-action" onClick={loadAdminUsers}>
                    Refresh
                  </button>
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
                            <option value="approver">Approver</option>
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
                  {adminPublicationsState.items.map((pub) => (
                    <div className="admin-row events" key={pub.id}>
                      <div className="admin-cell">
                        <p className="admin-name">{pub.name}</p>
                        <p className="admin-email">{pub.file_name}</p>
                      </div>
                      <div className="admin-cell">{pub.title}</div>
                      <div className="admin-cell">{pub.uploaded_at?.slice(0, 10)}</div>
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
                  ))}
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
        const filteredEvents = eventsState.items.filter((event) => {
          const statusMatches = isReportsView
            ? getNormalizedStatus(event) === "closed"
            : myEventsTab === "all"
              ? true
              : myEventsTab === "pending"
                ? getNormalizedStatus(event) === "pending"
                : myEventsTab === "upcoming"
                  ? getNormalizedStatus(event) === "upcoming"
                  : myEventsTab === "ongoing"
                  ? getNormalizedStatus(event) === "ongoing"
                  : myEventsTab === "completed"
                      ? getNormalizedStatus(event) === "completed"
                      : getNormalizedStatus(event) === "closed"
          return statusMatches && eventMatchesSearch(event);
        });
        const completedUnclosedCount = eventsState.items.filter((event) => {
          const isApprovalItem = String(event.id || "").startsWith("approval-");
          if (isApprovalItem) {
            return false;
          }
          return getNormalizedStatus(event) === "completed";
        }).length;
        const limitReached = completedUnclosedCount >= 5;
        const warnThresholdReached = completedUnclosedCount >= 3 && completedUnclosedCount < 5;
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
                    {isReportsTab ? "No closed events yet." : "No events yet. Create your first event."}
                  </p>
                ) : null}
                {eventsState.status === "ready"
                  ? filteredEvents.map((event) => {
                      const statusValue = event.status || "";
                      const explicitStatus = statusValue ? formatStatusLabel(statusValue) : null;
                      const hasApprovalData =
                        event.approval_status || event.marketing_status || event.it_status;
                      let derivedStatus = "Approved";
                      if (hasApprovalData) {
                        const statuses = [
                          event.approval_status,
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

                      const statusLabel = explicitStatus || derivedStatus;
                      const statusClass = (statusValue || statusLabel)
                        .toLowerCase()
                        .replace(/\s+/g, "-");
                      const inviteSent = event.invite_status === "sent";
                      const isUpcomingEvent = getNormalizedEventStatus(event) === "upcoming";
                      const canInvite =
                        isUpcomingEvent &&
                        ((!event.approval_status && !event.marketing_status && !event.it_status) ||
                          (event.approval_status === "approved" &&
                            event.marketing_status === "approved" &&
                            event.it_status === "approved")) &&
                        !inviteSent;
                      const isApprovalItem = String(event.id || "").startsWith("approval-");
                      const canUploadReport = !isApprovalItem && statusValue === "completed";
                      const canCloseEvent =
                        !isApprovalItem && statusValue === "completed" && Boolean(event.report_file_id);
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
                    <h3>ADMIN</h3>
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
                        <input
                          type="email"
                          placeholder="admin@campus.edu"
                          value={approvalForm.to}
                          onChange={handleApprovalFieldChange("to")}
                          required
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
                          checked={approvalForm.requirements.venue}
                          onChange={handleApprovalRequirementChange("venue")}
                        />
                        Venue
                      </label>
                      <label>
                        <input
                          type="checkbox"
                          checked={approvalForm.requirements.refreshments}
                          onChange={handleApprovalRequirementChange("refreshments")}
                        />
                        Refreshments
                      </label>
                    </div>

                    <label className="approval-field">
                      <span>Others</span>
                      <textarea
                        rows="4"
                        placeholder="Add additional notes for the admin."
                        value={approvalForm.other_notes}
                        onChange={handleApprovalFieldChange("other_notes")}
                      />
                    </label>

                    {approvalModal.status === "error" ? (
                      <p className="form-error">{approvalModal.error}</p>
                    ) : null}

                    <div className="modal-actions">
                      <button type="button" className="secondary-action" onClick={handleApprovalSkip}>
                        Skip
                      </button>
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
                    <h3>MARKETING TEAM</h3>
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
                          required
                        />
                      </label>
                    </div>

                    <div className="approval-summary">
                      <p>
                        <strong>Event:</strong> {eventForm.name || "Untitled event"}
                      </p>
                      <p>
                        <strong>Date:</strong>{" "}
                        {eventForm.start_date || "--"} {eventForm.end_date ? `to ${eventForm.end_date}` : ""}
                      </p>
                      <p>
                        <strong>Time:</strong>{" "}
                        {formatISTTime(eventForm.start_time) || "--"}{" "}
                        {eventForm.end_time ? `to ${formatISTTime(eventForm.end_time)}` : ""}
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
                        <label>
                          <input
                            type="checkbox"
                            checked={marketingForm.recording}
                            onChange={handleMarketingToggle("recording")}
                          />
                          Recording
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
                    <h3>IT DEPARTMENT</h3>
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
                          required
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
        return (
          <div className="primary-column">
            <div className="events-actions">
              <button type="button" className="primary-action" onClick={handlePublicationOpen}>
                + New Publication
              </button>
            </div>
            <div className="events-table-card">
              <div className="table-header">
                <h3>Publications</h3>
              </div>
              <div className="events-table">
                <div className="events-table-row header reports">
                  <span>Name</span>
                  <span>Title</span>
                  <span>Action</span>
                </div>
                {publicationsState.status === "loading" ? (
                  <p className="table-message">Loading publications...</p>
                ) : null}
                {publicationsState.status === "error" ? (
                  <p className="table-message">{publicationsState.error}</p>
                ) : null}
                {publicationsState.status === "ready" && publicationsState.items.length === 0 ? (
                  <p className="table-message">No publications submitted yet.</p>
                ) : null}
                {publicationsState.status === "ready"
                  ? publicationsState.items.map((item) => (
                      <div key={item.id} className="events-table-row reports">
                        <span>{item.name}</span>
                        <span>{item.title}</span>
                        <div className="event-actions">
                          <button
                            type="button"
                            className="details-button invite"
                            onClick={() => {
                              if (item.web_view_link) {
                                window.open(item.web_view_link, "_blank", "noopener,noreferrer");
                              } else {
                                setStatus({ type: "error", message: "Publication link unavailable." });
                              }
                            }}
                          >
                            View File
                          </button>
                        </div>
                      </div>
                    ))
                  : null}
              </div>
            </div>
          </div>
        );
      }

      if (isCalendar) {
        return (
          <div className="primary-column">
            <div className="calendar-card">
              <div className="calendar-toolbar">
                <div>
                  <h3>Google Calendar</h3>
                  <p className="calendar-subtitle">Your upcoming events</p>
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

      if (isApprovals) {
        return (
          <div className="primary-column">
            <div className="events-table-card">
              <div className="table-header">
                <h3>Approval Requests</h3>
              </div>
              <div className="events-table">
                <div className="events-table-row header approvals">
                  <span>Event</span>
                  <span>Requester</span>
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
                        return (
                          <div key={item.id} className="events-table-row approvals">
                            <span>{item.event_name}</span>
                            <span>{item.requester_email}</span>
                          <span>{item.start_date}</span>
                          <span>{formatISTTime(item.start_time)}</span>
                          <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                          <div className="approval-actions">
                            {item.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  className="details-button"
                                  onClick={() => handleApprovalDecision(item.id, "approved")}
                                >
                                  Approve
                                </button>
                                <button
                                  type="button"
                                  className="details-button reject"
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

            <div className="events-table-card">
              <div className="table-header">
                <h3>Marketing Requests</h3>
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
                      if (item.recording) {
                        needs.push("Recording");
                      }
                      const needsLabel = needs.length ? needs.join(", ") : "None";
                      const statusLabel = `${item.status.charAt(0).toUpperCase()}${item.status.slice(1)}`;
                      return (
                        <div key={item.id} className="events-table-row marketing">
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <span>{item.start_date}</span>
                          <span>{formatISTTime(item.start_time)}</span>
                          <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                          <span className="marketing-needs">{needsLabel}</span>
                          <div className="approval-actions">
                            {item.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  className="details-button"
                                  onClick={() => handleMarketingDecision(item.id, "approved")}
                                >
                                  Approve
                                </button>
                                <button
                                  type="button"
                                  className="details-button reject"
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

            <div className="events-table-card">
              <div className="table-header">
                <h3>IT Requests</h3>
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
                      return (
                        <div key={item.id} className="events-table-row it">
                          <span>{item.event_name}</span>
                          <span>{item.requester_email}</span>
                          <span>{item.start_date}</span>
                          <span>{formatISTTime(item.start_time)}</span>
                          <span className={`status-pill ${item.status}`}>{statusLabel}</span>
                          <span className="marketing-needs">{needsLabel}</span>
                          <div className="approval-actions">
                            {item.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  className="details-button"
                                  onClick={() => handleItDecision(item.id, "approved")}
                                >
                                  Approve
                                </button>
                                <button
                                  type="button"
                                  className="details-button reject"
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
              {eventsState.status === "ready" && eventsState.items.length > 0 && !eventsState.items.some(eventMatchesSearch) ? (
                <p className="table-message">No events match your search.</p>
              ) : null}
              {eventsState.status === "ready"
                ? eventsState.items.filter(eventMatchesSearch).map((event) => {
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
        {publicationModal.open ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card">
              <div className="modal-header">
                <h3>New Publication</h3>
                <button type="button" className="modal-close" onClick={handlePublicationClose}>
                  &times;
                </button>
              </div>
              <form className="event-form" onSubmit={submitPublication}>
                <div className="form-grid">
                  <label className="form-field">
                    <span>Name</span>
                    <input
                      type="text"
                      value={publicationForm.name}
                      onChange={handlePublicationChange("name")}
                      required
                    />
                  </label>
                  <label className="form-field">
                    <span>Title</span>
                    <input
                      type="text"
                      value={publicationForm.title}
                      onChange={handlePublicationChange("title")}
                      required
                    />
                  </label>
                </div>
                <label className="form-field">
                  <span>File</span>
                  <input type="file" onChange={handlePublicationChange("file")} required />
                </label>
                <label className="form-field">
                  <span>Others</span>
                  <textarea
                    value={publicationForm.others}
                    onChange={handlePublicationChange("others")}
                    placeholder="Additional details"
                  />
                </label>
                {publicationModal.status === "error" ? (
                  <p className="form-error">{publicationModal.error}</p>
                ) : null}
                <div className="modal-actions">
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
        {eventDetailsModal.open ? (
          <div className="modal-overlay" role="dialog" aria-modal="true">
            <div className="modal-card details-card">
              <div className="modal-header">
                <h3>Event Details</h3>
                <button type="button" className="modal-close" onClick={handleEventDetailsClose}>
                  &times;
                </button>
              </div>
              {eventDetailsModal.event ? (
                <div className="details-grid">
                  <div>
                    <p className="details-label">Event</p>
                    <p className="details-value">{eventDetailsModal.event.name}</p>
                  </div>
                  <div>
                    <p className="details-label">Facilitator</p>
                    <p className="details-value">{eventDetailsModal.event.facilitator}</p>
                  </div>
                  <div>
                    <p className="details-label">Venue</p>
                    <p className="details-value">{eventDetailsModal.event.venue_name}</p>
                  </div>
                  <div>
                    <p className="details-label">Status</p>
                    <p className="details-value">{eventDetailsModal.event.status}</p>
                  </div>
                  <div>
                    <p className="details-label">Start</p>
                    <p className="details-value">
                      {eventDetailsModal.event.start_date} ? {formatISTTime(eventDetailsModal.event.start_time)}
                    </p>
                  </div>
                  <div>
                    <p className="details-label">End</p>
                    <p className="details-value">
                      {eventDetailsModal.event.end_date} ? {formatISTTime(eventDetailsModal.event.end_time)}
                    </p>
                  </div>
                  <div className="details-wide">
                    <p className="details-label">Description</p>
                    <p className="details-value">{eventDetailsModal.event.description || "?"}</p>
                  </div>
                </div>
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
        <aside className="sidebar">
          <div className="brand">
            <div className="brand-icon">
              <SimpleIcon path="M6 12a6 6 0 1 1 6 6H6v-6Z" />
            </div>
            <span>FACULTY</span>
          </div>

          <div className="menu-block">
            <p className="menu-title">Menu</p>
            <nav className="menu-list">
              {visibleMenuItems.map((item, index) => (
                <button
                  key={item.id}
                  type="button"
                  className={`menu-item ${activeView === item.id ? "active" : ""}`}
                  onClick={() => setActiveView(item.id)}
                >
                  <span className="menu-icon">
                    <SimpleIcon path="M3 10.5 12 3l9 7.5v9.5H3z" />
                  </span>
                  {item.label}
                </button>
              ))}
            </nav>
          </div>

          <div className="menu-block">
            <p className="menu-title">Preferences</p>
            <nav className="menu-list">
              {preferenceItems.map((item) => (
                <button key={item.id} type="button" className="menu-item">
                  <span className="menu-icon">
                    <SimpleIcon path="M12 2a6 6 0 1 1 0 12 6 6 0 0 1 0-12Zm0 14c4.4 0 8 2 8 4v2H4v-2c0-2 3.6-4 8-4Z" />
                  </span>
                  {item.label}
                </button>
              ))}
            </nav>
          </div>

          <button type="button" className="menu-item logout" onClick={handleLogout}>
            <span className="menu-icon">
              <SimpleIcon path="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l-4-4 4-4M6 13h12" />
            </span>
            Logout
          </button>
        </aside>

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

  return (
    <div className="page">
      <div className="orb orb-left" />
      <div className="orb orb-right" />
      <div className="container">
        <section className="hero">
          <PlaceholderCard />
          <div className="hero-text">
            <p className="eyebrow">Event Booking Management</p>
            <h1>Run smarter events, from invites to attendance.</h1>
            <p className="lead">
              Organize every stage with a centralized workspace, automated
              reminders, and real-time visibility that keeps teams aligned.
            </p>
            <div className="stats">
              {stats.map((item) => (
                <div key={item.label} className="stat">
                  <span className="stat-value">{item.value}</span>
                  <span className="stat-label">{item.label}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="login-panel">
          <div className="panel-card">
            <p className="panel-eyebrow">Welcome back</p>
            <h2>Login to your account</h2>
            <p className="panel-copy">
              Sign in to continue scheduling, tracking, and refining every
              event experience.
            </p>

            <div className="google-button google-render" ref={googleButtonRef}>
              <span className="google-fallback" aria-hidden="true">
                <span className="google-icon">
                  <GoogleIcon />
                </span>
                Continue with Google
              </span>
            </div>

            {status.message ? (
              <p className={`status ${status.type}`}>{status.message}</p>
            ) : null}

            <p className="panel-footnote">
              Use your institutional Google account to continue.
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}

