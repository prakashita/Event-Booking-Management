import { useCallback, useEffect, useMemo, useState } from "react";

import Modal from "./ui/Modal";
import {
  ACADEMIC_YEAR_OPTIONS,
  ACADEMIC_CATEGORY_OPTIONS,
  SEMESTER_TYPE_OPTIONS,
  SEMESTER_OPTIONS,
  getCurrentAcademicYear,
} from "../constants";

/* -- Static options ------------------------------------------------- */

const ENTRY_TYPE_OPTIONS = [
  { value: "", label: "All Types" },
  { value: "holiday", label: "Holiday" },
  { value: "academic", label: "Academic" },
];

const SYNC_STATUS_OPTIONS = [
  { value: "", label: "All Sync" },
  { value: "synced", label: "Synced" },
  { value: "pending", label: "Pending" },
  { value: "sync_failed", label: "Failed" },
  { value: "disabled", label: "Disabled" },
];

const ACTIVE_OPTIONS = [
  { value: "", label: "All" },
  { value: "true", label: "Active" },
  { value: "false", label: "Inactive" },
];

/* -- Form defaults -------------------------------------------------- */

const currentAY = getCurrentAcademicYear();

const HOLIDAY_DEFAULTS = {
  academic_year: currentAY,
  calendar_year: new Date().getFullYear(),
  date: "",
  holiday_name: "",
  description: "",
  color: "#f59e0b",
  visible_to_all: true,
  google_sync_enabled: false,
  is_active: true,
};

const ACADEMIC_DEFAULTS = {
  academic_year: currentAY,
  semester_type: "Odd Semester",
  semester: "Semester I",
  title: "",
  category: "Registration",
  start_date: "",
  end_date: "",
  all_day: true,
  description: "",
  color: "#2563eb",
  visible_to_all: true,
  google_sync_enabled: false,
  is_active: true,
};

/* -- Helpers -------------------------------------------------------- */

function toDayLabel(value) {
  if (!value) return "\u2014";
  const parsed = new Date(value + "T00:00:00");
  if (Number.isNaN(parsed.getTime())) return "\u2014";
  return parsed.toLocaleDateString("en-IN", { weekday: "long", timeZone: "Asia/Kolkata" });
}

function toSyncLabel(entry) {
  if (entry.sync_status === "synced") return "Synced";
  if (entry.sync_status === "sync_failed") return "Sync Failed";
  if (entry.sync_status === "pending") return "Pending";
  return "Disabled";
}

function buildMutationMessage(action, payload) {
  const sync = payload?.sync;
  if (sync?.success) return action + " saved and synced to Google Calendar.";
  if (sync?.sync_error) return action + " saved. Sync error: " + sync.sync_error;
  return action + " saved successfully.";
}

/** Parse FastAPI 422 detail into a user-friendly message. */
function parseValidationError(data) {
  if (!data) return "Request failed.";
  const parseErrors = (errors) => {
    if (!Array.isArray(errors)) return null;
    return errors
      .map((e) => {
        const field = Array.isArray(e.loc) ? e.loc.filter((p) => p !== "body").join(" \u2192 ") : "";
        const msg = e.msg || JSON.stringify(e);
        return field ? field + ": " + msg : msg;
      })
      .join("\n");
  };
  if (typeof data.detail === "string" && data.detail !== "Validation error") return data.detail;
  const detailed = parseErrors(data.errors || data.detail);
  if (detailed) return detailed;
  return typeof data.detail === "string" ? data.detail : "Validation error. Please check your input.";
}

/* -- Payload builders (critical for fixing 422) --------------------- */

function buildHolidayPayload(form) {
  return {
    entry_type: "holiday",
    academic_year: form.academic_year,
    calendar_year: form.calendar_year || null,
    date: form.date || null,
    holiday_name: form.holiday_name?.trim() || null,
    description: form.description?.trim() || null,
    color: form.color || null,
    visible_to_all: Boolean(form.visible_to_all),
    google_sync_enabled: Boolean(form.google_sync_enabled),
    is_active: Boolean(form.is_active),
  };
}

function buildAcademicPayload(form) {
  return {
    entry_type: "academic",
    academic_year: form.academic_year,
    calendar_year: null,
    semester_type: form.semester_type || null,
    semester: form.semester || null,
    title: form.title?.trim() || null,
    category: form.category || null,
    start_date: form.start_date || null,
    end_date: form.end_date || null,
    all_day: form.all_day !== false,
    description: form.description?.trim() || null,
    color: form.color || null,
    visible_to_all: Boolean(form.visible_to_all),
    google_sync_enabled: Boolean(form.google_sync_enabled),
    is_active: Boolean(form.is_active),
  };
}

function buildEditPayload(form) {
  if (form.entry_type === "holiday") {
    return {
      academic_year: form.academic_year || undefined,
      calendar_year: form.calendar_year || undefined,
      date: form.date || undefined,
      holiday_name: form.holiday_name || undefined,
      description: form.description || undefined,
      color: form.color || undefined,
      visible_to_all: form.visible_to_all,
      google_sync_enabled: form.google_sync_enabled,
      is_active: form.is_active,
    };
  }
  return {
    academic_year: form.academic_year || undefined,
    semester_type: form.semester_type || undefined,
    semester: form.semester || undefined,
    title: form.title || undefined,
    category: form.category || undefined,
    start_date: form.start_date || undefined,
    end_date: form.end_date || undefined,
    all_day: form.all_day,
    description: form.description || undefined,
    color: form.color || undefined,
    visible_to_all: form.visible_to_all,
    google_sync_enabled: form.google_sync_enabled,
    is_active: form.is_active,
  };
}

function buildEditDraft(entry) {
  if (entry.entry_type === "holiday") {
    return {
      id: entry.id,
      entry_type: "holiday",
      sync_status: entry.sync_status || "disabled",
      academic_year: entry.academic_year || currentAY,
      calendar_year: entry.calendar_year || new Date().getFullYear(),
      date: entry.date || entry.start_date || "",
      holiday_name: entry.holiday_name || entry.title || "",
      description: entry.description || "",
      color: entry.color || "#f59e0b",
      visible_to_all: Boolean(entry.visible_to_all),
      google_sync_enabled: Boolean(entry.google_sync_enabled),
      is_active: Boolean(entry.is_active),
    };
  }
  return {
    id: entry.id,
    entry_type: "academic",
    sync_status: entry.sync_status || "disabled",
    academic_year: entry.academic_year || currentAY,
    semester_type: entry.semester_type || "Odd Semester",
    semester: entry.semester || "Semester I",
    title: entry.title || "",
    category: entry.category || "Registration",
    start_date: entry.start_date || "",
    end_date: entry.end_date || "",
    all_day: entry.all_day !== false,
    description: entry.description || "",
    color: entry.color || "#2563eb",
    visible_to_all: Boolean(entry.visible_to_all),
    google_sync_enabled: Boolean(entry.google_sync_enabled),
    is_active: Boolean(entry.is_active),
  };
}

/* -- Frontend validation -------------------------------------------- */

function validateHolidayForm(form) {
  const errors = {};
  if (!form.academic_year) errors.academic_year = "Academic year is required.";
  if (!form.date) errors.date = "Holiday date is required.";
  if (!form.holiday_name?.trim()) errors.holiday_name = "Holiday name is required.";
  return errors;
}

function validateAcademicForm(form) {
  const errors = {};
  if (!form.academic_year) errors.academic_year = "Academic year is required.";
  if (!form.title?.trim()) errors.title = "Event title is required.";
  if (!form.category) errors.category = "Category is required.";
  if (!form.semester_type) errors.semester_type = "Semester type is required.";
  if (!form.start_date) errors.start_date = "Start date is required.";
  if (form.end_date && form.start_date && form.end_date < form.start_date) {
    errors.end_date = "End date cannot be before start date.";
  }
  return errors;
}

/* =================================================================
   Component
   ================================================================= */

export default function InstitutionCalendarAdmin({ apiBaseUrl, apiFetch, onCalendarMutated, standalonePage = false }) {
  const [entriesState, setEntriesState] = useState({ status: "idle", items: [], error: "" });
  const [filters, setFilters] = useState({ academic_year: "", semester: "", entry_type: "", category: "" });
  const [localSyncFilter, setLocalSyncFilter] = useState("");
  const [localActiveFilter, setLocalActiveFilter] = useState("");
  const [localSearch, setLocalSearch] = useState("");
  const [holidayForm, setHolidayForm] = useState(HOLIDAY_DEFAULTS);
  const [academicForm, setAcademicForm] = useState(ACADEMIC_DEFAULTS);
  const [fieldErrors, setFieldErrors] = useState({});
  const [editingEntry, setEditingEntry] = useState(null);
  const [editFieldErrors, setEditFieldErrors] = useState({});
  const [notice, setNotice] = useState({ type: "idle", message: "" });
  const [busyAction, setBusyAction] = useState({ id: "", action: "" });

  /* -- Derived data ------------------------------------------------- */
  const filteredEntries = useMemo(() => {
    let items = entriesState.items;
    if (localSyncFilter) items = items.filter((e) => e.sync_status === localSyncFilter);
    if (localActiveFilter === "true") items = items.filter((e) => e.is_active);
    if (localActiveFilter === "false") items = items.filter((e) => !e.is_active);
    if (localSearch.trim()) {
      const q = localSearch.toLowerCase();
      items = items.filter(
        (e) =>
          (e.title || "").toLowerCase().includes(q) ||
          (e.holiday_name || "").toLowerCase().includes(q) ||
          (e.description || "").toLowerCase().includes(q) ||
          (e.category || "").toLowerCase().includes(q)
      );
    }
    return items;
  }, [entriesState.items, localSyncFilter, localActiveFilter, localSearch]);

  /* -- API: load entries -------------------------------------------- */
  const loadEntries = useCallback(async (nextFilters = filters) => {
    setEntriesState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const params = new URLSearchParams();
      Object.entries(nextFilters).forEach(([key, value]) => { if (value) params.set(key, value); });
      const url = params.toString()
        ? apiBaseUrl + "/institution-calendar?" + params.toString()
        : apiBaseUrl + "/institution-calendar";
      const res = await apiFetch(url);
      if (!res.ok) throw new Error("Unable to load institution calendar entries.");
      const data = await res.json();
      setEntriesState({ status: "ready", items: Array.isArray(data) ? data : [], error: "" });
    } catch (err) {
      setEntriesState({ status: "error", items: [], error: err?.message || "Unable to load entries." });
    }
  }, [apiBaseUrl, apiFetch, filters]);

  const notifyCalendarMutation = useCallback(() => {
    if (typeof onCalendarMutated === "function") onCalendarMutated();
  }, [onCalendarMutated]);

  /* -- API: submit entry -------------------------------------------- */
  const submitEntry = useCallback(async (payload, options) => {
    const { method, url, successPrefix, reset } = options;
    setNotice({ type: "idle", message: "" });
    setBusyAction({ id: url, action: method });
    try {
      const res = await apiFetch(url, {
        method,
        body: payload,
        headers: { "Content-Type": "application/json" },
      });
      const data = await res.json().catch(() => null);
      if (!res.ok) {
        if (res.status === 422) {
          console.error("InstitutionCalendarAdmin submit payload:", payload, "response:", data);
        }
        throw new Error(parseValidationError(data));
      }
      setNotice({ type: "success", message: buildMutationMessage(successPrefix, data) });
      if (typeof reset === "function") reset();
      setEditingEntry(null);
      setFieldErrors({});
      setEditFieldErrors({});
      await loadEntries();
      notifyCalendarMutation();
    } catch (err) {
      setNotice({ type: "error", message: err?.message || "Unable to save entry." });
    } finally {
      setBusyAction({ id: "", action: "" });
    }
  }, [apiFetch, loadEntries, notifyCalendarMutation]);

  /* -- API: delete -------------------------------------------------- */
  const handleDelete = useCallback(async (entry) => {
    const displayName = entry.title || entry.holiday_name || "this entry";
    if (!window.confirm('Delete "' + displayName + '" from the institution calendar?')) return;
    setBusyAction({ id: entry.id, action: "delete" });
    setNotice({ type: "idle", message: "" });
    try {
      const res = await apiFetch(apiBaseUrl + "/institution-calendar/" + entry.id, { method: "DELETE" });
      if (!res.ok) {
        const data = await res.json().catch(() => null);
        throw new Error(data?.detail || "Unable to delete entry.");
      }
      setNotice({ type: "success", message: "Entry deleted." });
      await loadEntries();
      notifyCalendarMutation();
    } catch (err) {
      setNotice({ type: "error", message: err?.message || "Unable to delete entry." });
    } finally {
      setBusyAction({ id: "", action: "" });
    }
  }, [apiBaseUrl, apiFetch, loadEntries, notifyCalendarMutation]);

  /* -- API: sync/unsync --------------------------------------------- */
  const handleSyncToggle = useCallback(async (entry, shouldSync) => {
    const action = shouldSync ? "sync" : "unsync";
    setBusyAction({ id: entry.id, action });
    setNotice({ type: "idle", message: "" });
    try {
      const res = await apiFetch(
        shouldSync
          ? apiBaseUrl + "/institution-calendar/" + entry.id + "/sync-google"
          : apiBaseUrl + "/institution-calendar/" + entry.id + "/unsync-google",
        { method: shouldSync ? "POST" : "DELETE" }
      );
      const data = await res.json().catch(() => null);
      if (!res.ok) throw new Error(data?.detail || "Unable to " + action + " entry.");
      setNotice({ type: data?.sync?.success ? "success" : "error", message: buildMutationMessage("Sync", data) });
      await loadEntries();
      notifyCalendarMutation();
    } catch (err) {
      setNotice({ type: "error", message: err?.message || "Unable to " + action + " entry." });
    } finally {
      setBusyAction({ id: "", action: "" });
    }
  }, [apiBaseUrl, apiFetch, loadEntries, notifyCalendarMutation]);

  /* -- Form handlers ------------------------------------------------ */
  const handleHolidaySubmit = useCallback((e) => {
    if (e && e.preventDefault) e.preventDefault();
    const errors = validateHolidayForm(holidayForm);
    setFieldErrors(errors);
    if (Object.keys(errors).length > 0) return;
    submitEntry(buildHolidayPayload(holidayForm), {
      method: "POST",
      url: apiBaseUrl + "/institution-calendar",
      successPrefix: "Holiday",
      reset: () => { setHolidayForm(HOLIDAY_DEFAULTS); setAddHolidayModalOpen(false); },
    });
  }, [holidayForm, apiBaseUrl, submitEntry]);

  const handleAcademicSubmit = useCallback((e) => {
    if (e && e.preventDefault) e.preventDefault();
    const errors = validateAcademicForm(academicForm);
    setFieldErrors(errors);
    if (Object.keys(errors).length > 0) return;
    submitEntry(buildAcademicPayload(academicForm), {
      method: "POST",
      url: apiBaseUrl + "/institution-calendar",
      successPrefix: "Academic entry",
      reset: () => { setAcademicForm(ACADEMIC_DEFAULTS); setAddAcademicModalOpen(false); },
    });
  }, [academicForm, apiBaseUrl, submitEntry]);

  const handleEditSubmit = useCallback(() => {
    if (!editingEntry) return;
    const validate = editingEntry.entry_type === "holiday" ? validateHolidayForm : validateAcademicForm;
    const errors = validate(editingEntry);
    setEditFieldErrors(errors);
    if (Object.keys(errors).length > 0) return;
    submitEntry(buildEditPayload(editingEntry), {
      method: "PATCH",
      url: apiBaseUrl + "/institution-calendar/" + editingEntry.id,
      successPrefix: "Entry",
    });
  }, [editingEntry, apiBaseUrl, submitEntry]);

  const updateHolidayDate = useCallback((dateStr) => {
    setHolidayForm((prev) => {
      const next = { ...prev, date: dateStr };
      if (dateStr) {
        const parsed = new Date(dateStr + "T00:00:00");
        if (!Number.isNaN(parsed.getTime())) next.calendar_year = parsed.getFullYear();
      }
      return next;
    });
  }, []);

  useEffect(() => { loadEntries(filters); }, [filters, loadEntries]); // eslint-disable-line react-hooks/exhaustive-deps

  const isSubmitting = busyAction.action === "POST";

  const FieldError = ({ name, errors: errs }) => {
    if (!errs?.[name]) return null;
    return <span className="institution-field-error">{errs[name]}</span>;
  };

  const [addHolidayModalOpen, setAddHolidayModalOpen] = useState(false);
  const [addAcademicModalOpen, setAddAcademicModalOpen] = useState(false);

  /* ================================================================
     RENDER
     ================================================================ */
  return (
    <div className={standalonePage ? "cal-updates-page" : "admin-panel institution-calendar-panel"}>
      {/* -- Header -------------------------------------------------- */}
      {standalonePage ? (
        <div className="cal-updates-page-header">
          <div>
            <h2>Calendar Updates</h2>
            <p className="admin-note">Manage institution holidays and academic calendar entries visible on the shared calendar.</p>
          </div>
          <div className="cal-updates-header-actions">
            <button type="button" className="cal-add-entry-btn cal-add-holiday" onClick={() => { setAddHolidayModalOpen(true); setFieldErrors({}); }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
              Add Holiday
            </button>
            <button type="button" className="cal-add-entry-btn cal-add-academic" onClick={() => { setAddAcademicModalOpen(true); setFieldErrors({}); }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
              Add Academic Entry
            </button>
            <button type="button" className="secondary-action" onClick={() => loadEntries(filters)}>Refresh</button>
          </div>
        </div>
      ) : (
        <div className="admin-panel-header">
          <div>
            <h3>Calendar Updates</h3>
            <p className="admin-note">Manage institution holidays and academic calendar entries visible on the shared calendar.</p>
          </div>
          <div className="cal-updates-header-actions">
            <button type="button" className="cal-add-entry-btn cal-add-holiday" onClick={() => { setAddHolidayModalOpen(true); setFieldErrors({}); }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
              Add Holiday
            </button>
            <button type="button" className="cal-add-entry-btn cal-add-academic" onClick={() => { setAddAcademicModalOpen(true); setFieldErrors({}); }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
              Add Academic Entry
            </button>
            <button type="button" className="secondary-action" onClick={() => loadEntries(filters)}>Refresh</button>
          </div>
        </div>
      )}

      {/* -- Notice -------------------------------------------------- */}
      {notice.message ? (
        <p className={"institution-notice " + (notice.type === "error" ? "error" : "success")} style={{ whiteSpace: "pre-line" }}>{notice.message}</p>
      ) : null}

      {/* -- Manage current entries (primary section) ---------------- */}
      <div className="institution-calendar-card">
        <div className="institution-card-header">
          <div>
            <h4>Manage Current Entries</h4>
            <p>Search, filter, edit, delete, and sync institution calendar records.</p>
          </div>
        </div>
        <div className="institution-filter-grid">
          <label className="institution-field">
            <span>Entry Type</span>
            <select value={filters.entry_type} onChange={(e) => setFilters((prev) => ({ ...prev, entry_type: e.target.value }))}>
              {ENTRY_TYPE_OPTIONS.map((opt) => <option key={opt.label} value={opt.value}>{opt.label}</option>)}
            </select>
          </label>
          <label className="institution-field">
            <span>Academic Year</span>
            <select value={filters.academic_year} onChange={(e) => setFilters((prev) => ({ ...prev, academic_year: e.target.value }))}>
              <option value="">All Years</option>
              {ACADEMIC_YEAR_OPTIONS.map((yr) => <option key={yr} value={yr}>{yr}</option>)}
            </select>
          </label>
          <label className="institution-field">
            <span>Semester</span>
            <select value={filters.semester} onChange={(e) => setFilters((prev) => ({ ...prev, semester: e.target.value }))}>
              <option value="">All Semesters</option>
              {SEMESTER_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
            </select>
          </label>
          <label className="institution-field">
            <span>Category</span>
            <select value={filters.category} onChange={(e) => setFilters((prev) => ({ ...prev, category: e.target.value }))}>
              <option value="">All Categories</option>
              <option value="Holiday">Holiday</option>
              {ACADEMIC_CATEGORY_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
            </select>
          </label>
          <label className="institution-field">
            <span>Sync Status</span>
            <select value={localSyncFilter} onChange={(e) => setLocalSyncFilter(e.target.value)}>
              {SYNC_STATUS_OPTIONS.map((opt) => <option key={opt.label} value={opt.value}>{opt.label}</option>)}
            </select>
          </label>
          <label className="institution-field">
            <span>Active</span>
            <select value={localActiveFilter} onChange={(e) => setLocalActiveFilter(e.target.value)}>
              {ACTIVE_OPTIONS.map((opt) => <option key={opt.label} value={opt.value}>{opt.label}</option>)}
            </select>
          </label>
          <label className="institution-field">
            <span>Search</span>
            <input type="text" value={localSearch} onChange={(e) => setLocalSearch(e.target.value)} placeholder="Search title, category, description..." />
          </label>
          <div className="institution-filter-actions">
            <button type="button" className="secondary-action institution-filter-clear-btn" onClick={() => {
              const reset = { academic_year: "", semester: "", entry_type: "", category: "" };
              setFilters(reset);
              setLocalSyncFilter("");
              setLocalActiveFilter("");
              setLocalSearch("");
            }}>Clear Filters</button>
          </div>
        </div>

        {entriesState.status === "loading" && <p className="table-message">Loading institution calendar entries...</p>}
        {entriesState.error && <p className="table-message">{entriesState.error}</p>}

        <div className="institution-calendar-table">
          <div className="institution-calendar-row institution-calendar-row--header">
            <span>Title</span>
            <span>Type</span>
            <span>Category</span>
            <span>Academic Year</span>
            <span>Semester</span>
            <span>Start</span>
            <span>End</span>
            <span>Status</span>
            <span>Sync</span>
            <span>Actions</span>
          </div>
          {filteredEntries.map((entry) => (
            <div className="institution-calendar-row" key={entry.id}>
              <div>
                <p className="admin-name">{entry.title}</p>
                <p className="admin-email">{entry.description || entry.day_label || "\u2014"}</p>
              </div>
              <span>
                <span className={"institution-type-badge " + entry.entry_type}>
                  {entry.entry_type === "holiday" ? "Holiday" : "Academic"}
                </span>
              </span>
              <span>{entry.category}</span>
              <span>{entry.academic_year}</span>
              <span>{entry.entry_type === "holiday" ? "NA" : (entry.semester || entry.semester_type || "\u2014")}</span>
              <span>{entry.start_date}</span>
              <span>{entry.end_date}</span>
              <span>
                <span className={"institution-type-badge " + (entry.is_active ? "active" : "inactive")}>
                  {entry.is_active ? "Active" : "Inactive"}
                </span>
              </span>
              <div>
                <span className={"institution-status-pill " + entry.sync_status}>{toSyncLabel(entry)}</span>
                {entry.google_sync_error ? <p className="admin-email" style={{ fontSize: "0.72rem" }}>{entry.google_sync_error}</p> : null}
              </div>
              <div className="institution-row-actions">
                <button type="button" className="details-button" onClick={() => { setEditingEntry(buildEditDraft(entry)); setEditFieldErrors({}); }}>Edit</button>
              </div>
            </div>
          ))}
          {entriesState.status === "ready" && filteredEntries.length === 0 && (
            <p className="table-message">No entries match the current filters.</p>
          )}
        </div>
      </div>

      {/* -- Add Holiday modal --------------------------------------- */}
      {addHolidayModalOpen ? (
        <Modal
          title="Add Holiday"
          onClose={() => setAddHolidayModalOpen(false)}
          className="institution-calendar-modal"
          actions={<>
            <button type="button" className="secondary-action" onClick={() => { setHolidayForm(HOLIDAY_DEFAULTS); setFieldErrors({}); }}>Reset</button>
            <button type="button" className="primary-action" disabled={isSubmitting} onClick={handleHolidaySubmit}>{isSubmitting ? "Adding..." : "Add Holiday"}</button>
          </>}
        >
          <div className="modal-body institution-calendar-modal-body">
            <form onSubmit={handleHolidaySubmit} id="holiday-form">
              <div className="institution-calendar-form-grid">
                <label className="institution-field">
                  <span>Academic Year *</span>
                  <select value={holidayForm.academic_year} onChange={(e) => setHolidayForm((prev) => ({ ...prev, academic_year: e.target.value }))} required>
                    <option value="">Select academic year</option>
                    {ACADEMIC_YEAR_OPTIONS.map((yr) => <option key={yr} value={yr}>{yr}</option>)}
                  </select>
                  <FieldError name="academic_year" errors={fieldErrors} />
                </label>
                <label className="institution-field">
                  <span>Calendar Year</span>
                  <input type="number" value={holidayForm.calendar_year} onChange={(e) => setHolidayForm((prev) => ({ ...prev, calendar_year: Number(e.target.value) || new Date().getFullYear() }))} min="1900" max="3000" />
                </label>
                <label className="institution-field">
                  <span>Date *</span>
                  <input type="date" value={holidayForm.date} onChange={(e) => updateHolidayDate(e.target.value)} required />
                  <FieldError name="date" errors={fieldErrors} />
                </label>
                <div className="institution-field institution-field--readonly">
                  <span>Day</span>
                  <strong>{toDayLabel(holidayForm.date)}</strong>
                </div>
                <label className="institution-field institution-field--wide">
                  <span>Holiday Name *</span>
                  <input type="text" value={holidayForm.holiday_name} onChange={(e) => setHolidayForm((prev) => ({ ...prev, holiday_name: e.target.value }))} placeholder="e.g. Republic Day" required />
                  <FieldError name="holiday_name" errors={fieldErrors} />
                </label>
                <label className="institution-field institution-field--wide">
                  <span>Description / Notes</span>
                  <textarea rows={3} value={holidayForm.description} onChange={(e) => setHolidayForm((prev) => ({ ...prev, description: e.target.value }))} placeholder="Mirror holiday circular notes here." />
                </label>
                <label className="institution-field">
                  <span>Display Color</span>
                  <input type="color" value={holidayForm.color} onChange={(e) => setHolidayForm((prev) => ({ ...prev, color: e.target.value }))} />
                </label>
                <label className="institution-toggle"><input type="checkbox" checked={holidayForm.visible_to_all} onChange={(e) => setHolidayForm((prev) => ({ ...prev, visible_to_all: e.target.checked }))} /><span>Visible to All</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={holidayForm.google_sync_enabled} onChange={(e) => setHolidayForm((prev) => ({ ...prev, google_sync_enabled: e.target.checked }))} /><span>Google Sync</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={holidayForm.is_active} onChange={(e) => setHolidayForm((prev) => ({ ...prev, is_active: e.target.checked }))} /><span>Active</span></label>
              </div>
            </form>
          </div>
        </Modal>
      ) : null}

      {/* -- Add Academic modal -------------------------------------- */}
      {addAcademicModalOpen ? (
        <Modal
          title="Add Academic Entry"
          onClose={() => setAddAcademicModalOpen(false)}
          className="institution-calendar-modal"
          actions={<>
            <button type="button" className="secondary-action" onClick={() => { setAcademicForm(ACADEMIC_DEFAULTS); setFieldErrors({}); }}>Reset</button>
            <button type="button" className="primary-action" disabled={isSubmitting} onClick={handleAcademicSubmit}>{isSubmitting ? "Adding..." : "Add Academic Entry"}</button>
          </>}
        >
          <div className="modal-body institution-calendar-modal-body">
            <form onSubmit={handleAcademicSubmit} id="academic-form">
              <div className="institution-calendar-form-grid">
                <label className="institution-field">
                  <span>Academic Year *</span>
                  <select value={academicForm.academic_year} onChange={(e) => setAcademicForm((prev) => ({ ...prev, academic_year: e.target.value }))} required>
                    <option value="">Select academic year</option>
                    {ACADEMIC_YEAR_OPTIONS.map((yr) => <option key={yr} value={yr}>{yr}</option>)}
                  </select>
                  <FieldError name="academic_year" errors={fieldErrors} />
                </label>
                <label className="institution-field">
                  <span>Semester Type *</span>
                  <select value={academicForm.semester_type} onChange={(e) => setAcademicForm((prev) => ({ ...prev, semester_type: e.target.value }))} required>
                    {SEMESTER_TYPE_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
                  </select>
                  <FieldError name="semester_type" errors={fieldErrors} />
                </label>
                <label className="institution-field">
                  <span>Semester</span>
                  <select value={academicForm.semester} onChange={(e) => setAcademicForm((prev) => ({ ...prev, semester: e.target.value }))}>
                    <option value="">None</option>
                    {SEMESTER_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
                  </select>
                </label>
                <label className="institution-field institution-field--wide">
                  <span>Academic Event Title *</span>
                  <input type="text" value={academicForm.title} onChange={(e) => setAcademicForm((prev) => ({ ...prev, title: e.target.value }))} placeholder="e.g. First Day of Instruction" required />
                  <FieldError name="title" errors={fieldErrors} />
                </label>
                <label className="institution-field">
                  <span>Event Category *</span>
                  <select value={academicForm.category} onChange={(e) => setAcademicForm((prev) => ({ ...prev, category: e.target.value }))} required>
                    {ACADEMIC_CATEGORY_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
                  </select>
                  <FieldError name="category" errors={fieldErrors} />
                </label>
                <label className="institution-field">
                  <span>Start Date *</span>
                  <input type="date" value={academicForm.start_date} onChange={(e) => setAcademicForm((prev) => ({ ...prev, start_date: e.target.value }))} required />
                  <FieldError name="start_date" errors={fieldErrors} />
                </label>
                <label className="institution-field">
                  <span>End Date</span>
                  <input type="date" value={academicForm.end_date} onChange={(e) => setAcademicForm((prev) => ({ ...prev, end_date: e.target.value }))} min={academicForm.start_date || undefined} />
                  <FieldError name="end_date" errors={fieldErrors} />
                </label>
                <label className="institution-toggle"><input type="checkbox" checked={academicForm.all_day} onChange={(e) => setAcademicForm((prev) => ({ ...prev, all_day: e.target.checked }))} /><span>All Day</span></label>
                <label className="institution-field institution-field--wide">
                  <span>Description / Notes</span>
                  <textarea rows={3} value={academicForm.description} onChange={(e) => setAcademicForm((prev) => ({ ...prev, description: e.target.value }))} placeholder="Commencement, examinations, results, meetings, and notes." />
                </label>
                <label className="institution-field">
                  <span>Display Color</span>
                  <input type="color" value={academicForm.color} onChange={(e) => setAcademicForm((prev) => ({ ...prev, color: e.target.value }))} />
                </label>
                <label className="institution-toggle"><input type="checkbox" checked={academicForm.visible_to_all} onChange={(e) => setAcademicForm((prev) => ({ ...prev, visible_to_all: e.target.checked }))} /><span>Visible to All</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={academicForm.google_sync_enabled} onChange={(e) => setAcademicForm((prev) => ({ ...prev, google_sync_enabled: e.target.checked }))} /><span>Google Sync</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={academicForm.is_active} onChange={(e) => setAcademicForm((prev) => ({ ...prev, is_active: e.target.checked }))} /><span>Active</span></label>
              </div>
            </form>
          </div>
        </Modal>
      ) : null}

      {/* -- Edit modal ---------------------------------------------- */}
      {editingEntry ? (
        <Modal
          title={editingEntry.entry_type === "holiday" ? "Edit Holiday Entry" : "Edit Academic Calendar Entry"}
          onClose={() => setEditingEntry(null)}
          className="institution-calendar-modal"
          actions={<>
            <div className="institution-edit-danger-actions">
              {editingEntry.sync_status === "synced" ? (
                <button type="button" className="secondary-action" disabled={busyAction.id === editingEntry.id} onClick={() => { setEditingEntry(null); handleSyncToggle(editingEntry, false); }}>Unsync</button>
              ) : null}
              <button type="button" className="details-button reject" disabled={busyAction.id === editingEntry.id && busyAction.action === "delete"} onClick={() => { setEditingEntry(null); handleDelete(editingEntry); }}>Delete</button>
            </div>
            <button type="button" className="secondary-action" onClick={() => setEditingEntry(null)}>Cancel</button>
            <button type="button" className="primary-action" onClick={handleEditSubmit}>Save Changes</button>
          </>}
        >
          <div className="modal-body institution-calendar-modal-body">
            {editingEntry.entry_type === "holiday" ? (
              <div className="institution-calendar-form-grid">
                <label className="institution-field"><span>Academic Year *</span>
                  <select value={editingEntry.academic_year} onChange={(e) => setEditingEntry((prev) => ({ ...prev, academic_year: e.target.value }))}>
                    <option value="">Select</option>
                    {ACADEMIC_YEAR_OPTIONS.map((yr) => <option key={yr} value={yr}>{yr}</option>)}
                  </select>
                  <FieldError name="academic_year" errors={editFieldErrors} />
                </label>
                <label className="institution-field"><span>Calendar Year</span>
                  <input type="number" value={editingEntry.calendar_year} onChange={(e) => setEditingEntry((prev) => ({ ...prev, calendar_year: Number(e.target.value) || new Date().getFullYear() }))} min="1900" max="3000" />
                </label>
                <label className="institution-field"><span>Date *</span>
                  <input type="date" value={editingEntry.date} onChange={(e) => { const v = e.target.value; setEditingEntry((prev) => { const next = { ...prev, date: v }; if (v) { const p = new Date(v + "T00:00:00"); if (!Number.isNaN(p.getTime())) next.calendar_year = p.getFullYear(); } return next; }); }} />
                  <FieldError name="date" errors={editFieldErrors} />
                </label>
                <div className="institution-field institution-field--readonly"><span>Day</span><strong>{toDayLabel(editingEntry.date)}</strong></div>
                <label className="institution-field institution-field--wide"><span>Holiday Name *</span>
                  <input type="text" value={editingEntry.holiday_name} onChange={(e) => setEditingEntry((prev) => ({ ...prev, holiday_name: e.target.value }))} />
                  <FieldError name="holiday_name" errors={editFieldErrors} />
                </label>
                <label className="institution-field institution-field--wide"><span>Description / Notes</span>
                  <textarea rows={3} value={editingEntry.description} onChange={(e) => setEditingEntry((prev) => ({ ...prev, description: e.target.value }))} />
                </label>
                <label className="institution-field"><span>Display Color</span><input type="color" value={editingEntry.color} onChange={(e) => setEditingEntry((prev) => ({ ...prev, color: e.target.value }))} /></label>
                <label className="institution-toggle"><input type="checkbox" checked={editingEntry.visible_to_all} onChange={(e) => setEditingEntry((prev) => ({ ...prev, visible_to_all: e.target.checked }))} /><span>Visible to All</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={editingEntry.google_sync_enabled} onChange={(e) => setEditingEntry((prev) => ({ ...prev, google_sync_enabled: e.target.checked }))} /><span>Google Sync</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={editingEntry.is_active} onChange={(e) => setEditingEntry((prev) => ({ ...prev, is_active: e.target.checked }))} /><span>Active</span></label>
              </div>
            ) : (
              <div className="institution-calendar-form-grid">
                <label className="institution-field"><span>Academic Year *</span>
                  <select value={editingEntry.academic_year} onChange={(e) => setEditingEntry((prev) => ({ ...prev, academic_year: e.target.value }))}>
                    <option value="">Select</option>
                    {ACADEMIC_YEAR_OPTIONS.map((yr) => <option key={yr} value={yr}>{yr}</option>)}
                  </select>
                  <FieldError name="academic_year" errors={editFieldErrors} />
                </label>
                <label className="institution-field"><span>Semester Type *</span>
                  <select value={editingEntry.semester_type} onChange={(e) => setEditingEntry((prev) => ({ ...prev, semester_type: e.target.value }))}>
                    {SEMESTER_TYPE_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
                  </select>
                  <FieldError name="semester_type" errors={editFieldErrors} />
                </label>
                <label className="institution-field"><span>Semester</span>
                  <select value={editingEntry.semester} onChange={(e) => setEditingEntry((prev) => ({ ...prev, semester: e.target.value }))}>
                    <option value="">None</option>
                    {SEMESTER_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
                  </select>
                </label>
                <label className="institution-field institution-field--wide"><span>Title *</span>
                  <input type="text" value={editingEntry.title} onChange={(e) => setEditingEntry((prev) => ({ ...prev, title: e.target.value }))} />
                  <FieldError name="title" errors={editFieldErrors} />
                </label>
                <label className="institution-field"><span>Category *</span>
                  <select value={editingEntry.category} onChange={(e) => setEditingEntry((prev) => ({ ...prev, category: e.target.value }))}>
                    {ACADEMIC_CATEGORY_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
                  </select>
                  <FieldError name="category" errors={editFieldErrors} />
                </label>
                <label className="institution-field"><span>Start Date *</span>
                  <input type="date" value={editingEntry.start_date} onChange={(e) => setEditingEntry((prev) => ({ ...prev, start_date: e.target.value }))} />
                  <FieldError name="start_date" errors={editFieldErrors} />
                </label>
                <label className="institution-field"><span>End Date</span>
                  <input type="date" value={editingEntry.end_date} onChange={(e) => setEditingEntry((prev) => ({ ...prev, end_date: e.target.value }))} min={editingEntry.start_date || undefined} />
                  <FieldError name="end_date" errors={editFieldErrors} />
                </label>
                <label className="institution-toggle"><input type="checkbox" checked={editingEntry.all_day} onChange={(e) => setEditingEntry((prev) => ({ ...prev, all_day: e.target.checked }))} /><span>All Day</span></label>
                <label className="institution-field institution-field--wide"><span>Description / Notes</span>
                  <textarea rows={3} value={editingEntry.description} onChange={(e) => setEditingEntry((prev) => ({ ...prev, description: e.target.value }))} />
                </label>
                <label className="institution-field"><span>Display Color</span><input type="color" value={editingEntry.color} onChange={(e) => setEditingEntry((prev) => ({ ...prev, color: e.target.value }))} /></label>
                <label className="institution-toggle"><input type="checkbox" checked={editingEntry.visible_to_all} onChange={(e) => setEditingEntry((prev) => ({ ...prev, visible_to_all: e.target.checked }))} /><span>Visible to All</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={editingEntry.google_sync_enabled} onChange={(e) => setEditingEntry((prev) => ({ ...prev, google_sync_enabled: e.target.checked }))} /><span>Google Sync</span></label>
                <label className="institution-toggle"><input type="checkbox" checked={editingEntry.is_active} onChange={(e) => setEditingEntry((prev) => ({ ...prev, is_active: e.target.checked }))} /><span>Active</span></label>
              </div>
            )}
          </div>
        </Modal>
      ) : null}
    </div>
  );
}