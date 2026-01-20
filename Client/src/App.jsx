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
  { id: "venue", label: "Booking Venue" },
  { id: "messages", label: "Messages" }
];

const preferenceItems = [
  { id: "users", label: "User Management" },
  { id: "settings", label: "Settings" }
];

const eventCards = [
  {
    title: "Business Conference 2025",
    date: "Jan 25",
    time: "09:30 AM",
    status: "In Progress"
  },
  {
    title: "Annual Fest",
    date: "Nov 27",
    time: "07:00 PM",
    status: "Ready"
  },
  {
    title: "Business Conference 2025",
    date: "Jan 25",
    time: "09:30 AM",
    status: "Pending"
  },
  {
    title: "Annual Meet",
    date: "Dec 03",
    time: "11:00 AM",
    status: "Pending"
  },
  {
    title: "Research Showcase",
    date: "Dec 14",
    time: "02:30 PM",
    status: "Ready"
  },
  {
    title: "Faculty Awards",
    date: "Dec 18",
    time: "05:15 PM",
    status: "Ready"
  }
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
  const [calendarState, setCalendarState] = useState({
    status: "idle",
    events: [],
    error: ""
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
      const res = await fetch(url, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      });

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
      const res = await fetch(`${apiBaseUrl}/events`, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      });
      if (!res.ok) {
        throw new Error("Unable to load events.");
      }
      const data = await res.json();
      setEventsState({ status: "ready", items: data, error: "" });
    } catch (err) {
      setEventsState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load events."
      });
    }
  }, [apiBaseUrl]);

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
    if (!user || activeView !== "my-events") {
      return;
    }
    if (venuesState.status === "idle") {
      loadVenues();
    }
    if (eventsState.status === "idle") {
      loadEvents();
    }
  }, [activeView, eventsState.status, loadEvents, loadVenues, user, venuesState.status]);

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
      const res = await fetch(`${apiBaseUrl}/events`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`
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

  const handleEventSubmit = (event) => {
    submitEvent(event, false);
  };

  const handleConflictReschedule = () => {
    setConflictState({ open: false, items: [] });
  };

  const handleConflictCancel = () => {
    setIsEventModalOpen(false);
    setConflictState({ open: false, items: [] });
  };

  const handleConflictOverride = () => {
    submitEvent(null, true);
  };

  const handleEventFieldChange = (field) => (event) => {
    setEventForm((prev) => ({
      ...prev,
      [field]: event.target.value
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
      const res = await fetch(`${apiBaseUrl}/calendar/connect-url`, {
        headers: {
          Authorization: `Bearer ${token}`
        }
      });

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

    const renderPrimaryContent = () => {
      if (isMyEvents) {
        return (
          <div className="primary-column">
            <div className="events-actions">
              <button type="button" className="primary-action" onClick={handleEventModalOpen}>
                + New Event
              </button>
              <button type="button" className="secondary-action">
                RSVP
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
                  ? eventsState.items.map((event) => (
                      <div key={event.id} className="events-table-row">
                        <span>{event.name}</span>
                        <span>{event.start_date}</span>
                        <span>{event.start_time}</span>
                        <span className="status-pill pending">Pending</span>
                        <button type="button" className="details-button">
                          Details
                        </button>
                      </div>
                    ))
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
                    <button type="button" className="conflict-button override" onClick={handleConflictOverride}>
                      Override
                    </button>
                  </div>
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
              {eventCards.map((event, index) => (
                <article key={`${event.title}-${index}`} className="event-card">
                  <div className={`event-status ${event.status.toLowerCase().replace(" ", "-")}`}>
                    {event.status}
                  </div>
                  <div className="event-image" />
                  <p className="event-title">{event.title}</p>
                  <p className="event-meta">
                    <span className="event-date">{event.date}</span>
                    <span className="event-dot">•</span>
                    <span className="event-time">{event.time}</span>
                  </p>
                </article>
              ))}
            </div>
          </div>
        </div>
      );
    };

    return (
      <div className="dashboard-page">
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
                {isMyEvents ? "My Events" : isCalendar ? "Calendar View" : "Dashboard Overview"}
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
