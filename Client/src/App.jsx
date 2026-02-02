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
  { id: "calendar", label: "Calendar View" },
  { id: "approvals", label: "Approvals" },
  { id: "venue", label: "Booking Venue" },
  { id: "messages", label: "Messages" }
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
  const [activeView, setActiveView] = useState("dashboard");
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
  const [reportFile, setReportFile] = useState(null);
  const [calendarState, setCalendarState] = useState({
    status: "idle",
    events: [],
    error: ""
  });
  const [googleScopeModal, setGoogleScopeModal] = useState({
    open: false,
    missing: []
  });
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
  const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || "http://localhost:8000";
  const googleClientId =
    import.meta.env.VITE_GOOGLE_CLIENT_ID ||
    "947113013769-dsal8c7k52irs6eokfnvl6o1a6v2rvea.apps.googleusercontent.com";

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
    if (!user || (activeView !== "my-events" && activeView !== "dashboard")) {
      return;
    }
    loadEvents();
    if (activeView === "my-events") {
      loadVenues();
    }
  }, [activeView, loadEvents, loadVenues, user]);

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

  const handleLogout = () => {
    localStorage.removeItem("auth_token");
    localStorage.removeItem("auth_user");
    setUser(null);
    setStatus({ type: "idle", message: "" });
  };

  const handleEventModalOpen = () => {
    setIsEventModalOpen(true);
    setEventFormStatus({ status: "idle", error: "" });
  };

  const handleEventModalClose = () => {
    setIsEventModalOpen(false);
    setConflictState({ open: false, items: [] });
  };

  const handleApprovalModalOpen = () => {
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

  const handleInviteOpen = (item) => {
    const eventId = item?.id || item?.event_id || "";
    const eventName = item?.event_name || item?.name || "";
    const startDate = item?.start_date || "";
    const startTime = item?.start_time || "";
    setInviteContext({ eventId, eventName, startDate, startTime });
    setInviteForm({
      to: "",
      subject: eventName ? `Event Invitation: ${eventName}` : "Event Invitation",
      description: eventName
        ? `You are invited to ${eventName} on ${startDate} at ${startTime}.`
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

  const handleReportClose = () => {
    setReportFile(null);
    setReportModal({ open: false, status: "idle", error: "", eventId: "", eventName: "", hasReport: false });
  };

  const handleReportFileChange = (event) => {
    setReportFile(event.target.files?.[0] || null);
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
  const submitEvent = async (formEvent, override) => {
    if (formEvent) {
      formEvent.preventDefault();
    }
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setEventFormStatus({ status: "error", error: "Please sign in again." });
      return;
    }

    setEventFormStatus({ status: "loading", error: "" });

    try {
      const payload = override
        ? { ...eventForm, override_conflict: true }
        : eventForm;
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
        facilitator: "",
        venue_name: "",
        description: ""
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
      setPendingEvent(null);
      setEventForm({
        start_date: "",
        end_date: "",
        start_time: "",
        end_time: "",
        name: "",
        facilitator: "",
        venue_name: "",
        description: ""
      });
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
      const res = await apiFetch(`${apiBaseUrl}/events/conflicts`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify(eventForm)
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
      handleApprovalModalOpen();
    } catch (err) {
      setEventFormStatus({
        status: "error",
        error: err?.message || "Unable to check conflicts."
      });
    }
  };

  const handleConflictReschedule = () => {
    setConflictState({ open: false, items: [] });
  };

  const handleConflictApprovalRequest = () => {
    setConflictState({ open: false, items: [] });
    setIsEventModalOpen(false);
    handleApprovalModalOpen();
  };

  const handleConflictCancel = () => {
    setIsEventModalOpen(false);
    setConflictState({ open: false, items: [] });
  };

  const handleEventFieldChange = (field) => (event) => {
    setEventForm((prev) => ({
      ...prev,
      [field]: event.target.value
    }));
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
    const profileRole = user?.role || "Event Manager";
    const isMyEvents = activeView === "my-events";
    const isCalendar = activeView === "calendar";
    const isApprovals = activeView === "approvals";

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
      if (isMyEvents) {
        return (
          <div className="primary-column">
            <div className="events-actions">
              <button type="button" className="primary-action" onClick={handleEventModalOpen}>
                + New Event
              </button>
              <button type="button" className="secondary-action" onClick={loadEvents}>
                Refresh
              </button>
            </div>

            <div className="events-table-card">
              <div className="table-header">
                <h3>My Events</h3>
                <div className="table-tabs">
                  <button type="button" className="tab-button active">
                    All Events
                  </button>
                  <button type="button" className="tab-button">
                    Upcoming
                  </button>
                  <button type="button" className="tab-button">
                    In Progress
                  </button>
                </div>
              </div>
              <div className="events-table">
                <div className="events-table-row header">
                  <span>Events</span>
                  <span>Date</span>
                  <span>Time</span>
                  <span>Status</span>
                  <span>Action</span>
                </div>
                {eventsState.status === "loading" ? (
                  <p className="table-message">Loading events...</p>
                ) : null}
                {eventsState.status === "error" ? (
                  <p className="table-message">{eventsState.error}</p>
                ) : null}
                {eventsState.status === "ready" && eventsState.items.length === 0 ? (
                  <p className="table-message">No events yet. Create your first event.</p>
                ) : null}
                {eventsState.status === "ready"
                  ? eventsState.items.map((event) => {
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
                      const canInvite =
                        event.approval_status === "approved" &&
                        event.marketing_status === "approved" &&
                        event.it_status === "approved" &&
                        !inviteSent;
                      const isApprovalItem = String(event.id || "").startsWith("approval-");
                      const canUploadReport = !isApprovalItem && statusValue === "completed";
                      return (
                        <div key={event.id} className="events-table-row">
                          <span>{event.name}</span>
                          <span>{event.start_date}</span>
                          <span>{event.start_time}</span>
                          <span className={`status-pill ${statusClass}`}>{statusLabel}</span>
                          <div className="event-actions">
                            <button type="button" className="details-button">
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
                        <input
                          type="time"
                          value={eventForm.start_time}
                          onChange={handleEventFieldChange("start_time")}
                          required
                        />
                      </label>
                      <label className="form-field">
                        <span>End time</span>
                        <input
                          type="time"
                          value={eventForm.end_time}
                          onChange={handleEventFieldChange("end_time")}
                          required
                        />
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
                        <span>{conflict.start_time}</span>
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
                        {pendingEvent?.start_time || eventForm.start_time || "--"}{" "}
                        {pendingEvent?.end_time
                          ? `to ${pendingEvent.end_time}`
                          : eventForm.end_time
                            ? `to ${eventForm.end_time}`
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
                        {eventForm.start_time || "--"} {eventForm.end_time ? `to ${eventForm.end_time}` : ""}
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
                        {pendingEvent?.start_time || eventForm.start_time || "--"}{" "}
                        {pendingEvent?.end_time
                          ? `to ${pendingEvent.end_time}`
                          : eventForm.end_time
                            ? `to ${eventForm.end_time}`
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
                          <span>{item.start_time}</span>
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
                          <span>{item.start_time}</span>
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
                          <span>{item.start_time}</span>
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
          <button type="button" className="request-button">
            Request Approval
          </button>

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
              {eventsState.status === "ready"
                ? eventsState.items.map((event) => {
                    const { statusLabel, statusClass } = getEventStatusInfo(event);
                    return (
                      <article key={event.id} className="event-card">
                        <div className={`event-status ${statusClass}`}>{statusLabel}</div>
                        <div className="event-image" />
                        <p className="event-title">{event.name}</p>
                        <p className="event-meta">
                          <span className="event-date">{event.start_date}</span>
                          <span className="event-dot">•</span>
                          <span className="event-time">{event.start_time}</span>
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
              {menuItems.map((item, index) => (
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
                  : isCalendar
                    ? "Calendar View"
                    : isApprovals
                      ? "Approvals"
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
              />
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

            <aside className="inbox-card">
              <div className="inbox-header">
                <div>
                  <p className="inbox-title">Inbox</p>
                  <p className="inbox-subtitle">Handle Questions</p>
                </div>
                <button type="button" className="icon-button">
                  <SimpleIcon path="M5 12a2 2 0 1 1 0 0Zm7 0a2 2 0 1 1 0 0Zm7 0a2 2 0 1 1 0 0Z" />
                </button>
              </div>
              <div className="inbox-list">
                {inboxItems.map((item, index) => (
                  <div key={`${item.name}-${index}`} className="inbox-item">
                    <div className="inbox-avatar" />
                    <div className="inbox-body">
                      <p className="inbox-name">
                        {item.name}
                        <span>{item.time}</span>
                      </p>
                      <p className="inbox-message">{item.message}</p>
                      <div className="inbox-actions">
                        <button type="button" className="ghost-button">
                          Archive
                        </button>
                        <button type="button" className="primary-button">
                          Reply
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </aside>
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
              New here? <span>Create an account</span>
            </p>
          </div>
        </section>
      </div>
    </div>
  );
}

