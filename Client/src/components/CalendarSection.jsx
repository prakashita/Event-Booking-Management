/**
 * CalendarSection — lazy-loaded wrapper for FullCalendar + tippy.
 *
 * This module is code-split from the main bundle. It is only loaded when
 * the user opens the calendar route. This means FullCalendar (~300 KB),
 * dayGridPlugin, timeGridPlugin, interactionPlugin, and tippy.js are NOT
 * on the critical path for any other route.
 *
 * Props mirror the calendar-related state/handlers from App.jsx:
 *   calendarState, calendarFilter, setCalendarFilter,
 *   filteredCalendarEvents, fetchCalendarEvents, handleCalendarConnect,
 *   calendarDetailModal, setCalendarDetailModal
 */
import FullCalendar from "@fullcalendar/react";
import dayGridPlugin from "@fullcalendar/daygrid";
import timeGridPlugin from "@fullcalendar/timegrid";
import interactionPlugin from "@fullcalendar/interaction";
import tippy from "tippy.js";
import "tippy.js/dist/tippy.css";
import { memo } from "react";
import { Modal } from "./ui";

function formatCalendarDateRange(start, end, allDay = false) {
  if (!start) return "—";
  const options = allDay
    ? { timeZone: "Asia/Kolkata", dateStyle: "full" }
    : { timeZone: "Asia/Kolkata", dateStyle: "full", timeStyle: "short" };
  const startLabel = start.toLocaleString("en-IN", options);
  if (!end) return startLabel;
  const endLabel = end.toLocaleString("en-IN", options);
  return `${startLabel} – ${endLabel}`;
}

const CalendarSection = memo(function CalendarSection({
  calendarState,
  calendarFilter,
  setCalendarFilter,
  filteredCalendarEvents,
  fetchCalendarEvents,
  handleCalendarConnect,
  calendarDetailModal,
  setCalendarDetailModal
}) {
  const calendarInitialView =
    window.innerWidth < 768
      ? "timeGridDay"
      : window.innerWidth < 1024
      ? "timeGridWeek"
      : "dayGridMonth";

  return (
    <div className="primary-column">
      <div className="calendar-card">
        <div className="calendar-toolbar">
          <div>
            <h3>Calendar</h3>
            <p className="calendar-subtitle">
              Approved events plus visible institution holidays and academic updates
            </p>
          </div>
          <div className="calendar-actions">
            <div className="calendar-filter-control">
              <button
                type="button"
                className={`cal-filter-btn${calendarFilter === "all" ? " active" : ""}`}
                onClick={() => setCalendarFilter("all")}
              >
                All
              </button>
              <button
                type="button"
                className={`cal-filter-btn${calendarFilter === "events" ? " active" : ""}`}
                onClick={() => setCalendarFilter("events")}
              >
                Events
              </button>
              <button
                type="button"
                className={`cal-filter-btn${calendarFilter === "holidays" ? " active" : ""}`}
                onClick={() => setCalendarFilter("holidays")}
              >
                Holidays
              </button>
              <button
                type="button"
                className={`cal-filter-btn${calendarFilter === "academic" ? " active" : ""}`}
                onClick={() => setCalendarFilter("academic")}
              >
                Academic
              </button>
            </div>
            <button
              type="button"
              className="secondary-action"
              onClick={() => fetchCalendarEvents()}
            >
              Refresh
            </button>
            <button
              type="button"
              className="primary-action"
              onClick={handleCalendarConnect}
            >
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
            eventTimeFormat={{
              hour: "numeric",
              minute: "2-digit",
              meridiem: "short"
            }}
            headerToolbar={{
              left: "prev,next today",
              center: "title",
              right: "dayGridMonth,timeGridWeek,timeGridDay"
            }}
            height="auto"
            editable
            eventResizableFromStart
            events={filteredCalendarEvents}
            datesSet={(info) =>
              fetchCalendarEvents({ start: info.start, end: info.end })
            }
            eventClick={(info) => {
              info.jsEvent.preventDefault();
              const evt = info.event;
              setCalendarDetailModal({
                open: true,
                event: {
                  title: evt.title,
                  start: evt.start,
                  end: evt.end,
                  allDay: evt.allDay,
                  location: evt.extendedProps?.location || "",
                  url: evt.url || "",
                  category: evt.extendedProps?.category || "",
                  entryType: evt.extendedProps?.entryType || "event",
                  sourceType: evt.extendedProps?.sourceType || "event_booking",
                  academicYear: evt.extendedProps?.academicYear || "",
                  semesterType: evt.extendedProps?.semesterType || "",
                  semester: evt.extendedProps?.semester || "",
                  description: evt.extendedProps?.description || "",
                  dayLabel: evt.extendedProps?.dayLabel || "",
                  dateRangeLabel: evt.extendedProps?.dateRangeLabel || ""
                }
              });
            }}
            eventDidMount={(info) => {
              const evt = info.event;
              const loc = evt.extendedProps?.location;
              const category = evt.extendedProps?.category;
              const academicYear = evt.extendedProps?.academicYear;
              const semesterType = evt.extendedProps?.semesterType;
              const semester = evt.extendedProps?.semester;
              const description = evt.extendedProps?.description;
              const dayLabel = evt.extendedProps?.dayLabel;
              const sourceType = evt.extendedProps?.sourceType;
              const entryType = evt.extendedProps?.entryType;
              const dateLabel =
                evt.extendedProps?.dateRangeLabel ||
                formatCalendarDateRange(evt.start, evt.end, evt.allDay);
              const sourceTag =
                sourceType === "institution_calendar"
                  ? entryType === "holiday"
                    ? `<span style="display:inline-block;padding:2px 8px;border-radius:99px;font-size:0.7rem;font-weight:700;background:rgba(245,158,11,0.15);color:#92400e;margin-bottom:4px">Holiday</span><br/>`
                    : `<span style="display:inline-block;padding:2px 8px;border-radius:99px;font-size:0.7rem;font-weight:700;background:rgba(37,99,235,0.12);color:#1e40af;margin-bottom:4px">Academic</span><br/>`
                  : "";
              const tooltipBits = [
                sourceTag,
                `<strong>${evt.title}</strong>`,
                category ? `<br/>${category}` : "",
                academicYear ? `<br/>AY: ${academicYear}` : "",
                semesterType
                  ? `<br/>${semesterType}${semester ? ` | ${semester}` : ""}`
                  : semester
                  ? `<br/>${semester}`
                  : "",
                dayLabel ? `<br/>📅 ${dayLabel}` : "",
                dateLabel ? `<br/>${dateLabel}` : "",
                loc ? `<br/>📍 ${loc}` : "",
                description ? `<br/><em>${description}</em>` : ""
              ];
              tippy(info.el, {
                content: tooltipBits.join(""),
                allowHTML: true,
                placement: "top",
                theme: "calendar-tooltip",
                delay: [200, 0],
                animation: "shift-away",
                arrow: true
              });

              const color =
                evt.backgroundColor || evt.borderColor || "var(--accent-blue)";
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
              <span className="cal-detail-value">
                {calendarDetailModal.event.title}
              </span>
            </div>
            <div className="cal-detail-row">
              <span className="cal-detail-label">Type</span>
              <span className="cal-detail-value">
                {calendarDetailModal.event.sourceType === "institution_calendar"
                  ? calendarDetailModal.event.entryType === "holiday"
                    ? "Institution Holiday"
                    : "Institution Academic"
                  : "Event Booking"}
              </span>
            </div>
            {calendarDetailModal.event.category ? (
              <div className="cal-detail-row">
                <span className="cal-detail-label">Category</span>
                <span className="cal-detail-value">
                  {calendarDetailModal.event.category}
                </span>
              </div>
            ) : null}
            {calendarDetailModal.event.academicYear ? (
              <div className="cal-detail-row">
                <span className="cal-detail-label">Academic Year</span>
                <span className="cal-detail-value">
                  {calendarDetailModal.event.academicYear}
                </span>
              </div>
            ) : null}
            {calendarDetailModal.event.semesterType ||
            calendarDetailModal.event.semester ? (
              <div className="cal-detail-row">
                <span className="cal-detail-label">Semester</span>
                <span className="cal-detail-value">
                  {[
                    calendarDetailModal.event.semesterType,
                    calendarDetailModal.event.semester
                  ]
                    .filter(Boolean)
                    .join(" | ")}
                </span>
              </div>
            ) : null}
            {calendarDetailModal.event.start ? (
              <div className="cal-detail-row">
                <span className="cal-detail-label">Schedule</span>
                <span className="cal-detail-value">
                  {formatCalendarDateRange(
                    calendarDetailModal.event.start,
                    calendarDetailModal.event.end,
                    calendarDetailModal.event.allDay
                  )}
                </span>
              </div>
            ) : null}
            {calendarDetailModal.event.dayLabel ? (
              <div className="cal-detail-row">
                <span className="cal-detail-label">Day</span>
                <span className="cal-detail-value">
                  {calendarDetailModal.event.dayLabel}
                </span>
              </div>
            ) : null}
            {calendarDetailModal.event.location ? (
              <div className="cal-detail-row">
                <span className="cal-detail-label">Venue</span>
                <span className="cal-detail-value">
                  {calendarDetailModal.event.location}
                </span>
              </div>
            ) : null}
            {calendarDetailModal.event.description ? (
              <div className="cal-detail-row">
                <span className="cal-detail-label">Notes</span>
                <span className="cal-detail-value">
                  {calendarDetailModal.event.description}
                </span>
              </div>
            ) : null}
          </div>
        </Modal>
      ) : null}
    </div>
  );
});

export default CalendarSection;
