import { useState, useRef, useEffect, useCallback, useMemo, memo } from "react";
import { createPortal } from "react-dom";

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December"
];
const DAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

function daysInMonth(year, month) {
  return new Date(year, month + 1, 0).getDate();
}

function PremiumDatePicker({ value, onChange, required, label }) {
  const [open, setOpen] = useState(false);
  const wrapperRef = useRef(null);
  const triggerRef = useRef(null);
  const dropdownRef = useRef(null);
  const rafRef = useRef(null);
  const [dropPos, setDropPos] = useState({ top: 0, left: 0, width: 320 });

  const parsed = useMemo(() => (value ? new Date(value + "T00:00:00") : null), [value]);
  const [viewYear, setViewYear] = useState(parsed ? parsed.getFullYear() : new Date().getFullYear());
  const [viewMonth, setViewMonth] = useState(parsed ? parsed.getMonth() : new Date().getMonth());

  const calcDropPos = useCallback(() => {
    if (!triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    // Close if trigger has scrolled completely out of viewport
    if (rect.bottom < 0 || rect.top > window.innerHeight) {
      setOpen(false);
      return;
    }
    const dropH = 304;
    const spaceBelow = window.innerHeight - rect.bottom;
    const viewportPadding = window.innerWidth < 420 ? 12 : 16;
    const preferredWidth = window.innerWidth < 420
      ? Math.min(340, window.innerWidth - viewportPadding * 2)
      : Math.min(360, Math.max(320, rect.width));
    const maxLeft = Math.max(viewportPadding, window.innerWidth - preferredWidth - viewportPadding);
    setDropPos({
      top: spaceBelow >= dropH + 8 ? rect.bottom + 6 : Math.max(viewportPadding, rect.top - dropH - 6),
      left: Math.max(viewportPadding, Math.min(rect.left, maxLeft)),
      width: preferredWidth,
    });
  }, []);

  useEffect(() => {
    if (!open) return;
    const p = value ? new Date(value + "T00:00:00") : new Date();
    setViewYear(p.getFullYear());
    setViewMonth(p.getMonth());
    calcDropPos();
    rafRef.current = requestAnimationFrame(calcDropPos);

    const handleMouseDown = (e) => {
      if (triggerRef.current?.contains(e.target)) return;
      if (dropdownRef.current?.contains(e.target)) return;
      setOpen(false);
    };
    const handleScroll = () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      rafRef.current = requestAnimationFrame(calcDropPos);
    };
    const handleResize = () => {
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      rafRef.current = requestAnimationFrame(calcDropPos);
    };
    document.addEventListener("mousedown", handleMouseDown);
    document.addEventListener("scroll", handleScroll, true);
    window.addEventListener("resize", handleResize);
    return () => {
      document.removeEventListener("mousedown", handleMouseDown);
      document.removeEventListener("scroll", handleScroll, true);
      window.removeEventListener("resize", handleResize);
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, [open, value, calcDropPos]);

  const handleKeyDown = useCallback((e) => {
    if (e.key === "Escape") setOpen(false);
  }, []);

  const toggleOpen = useCallback(() => {
    setOpen((current) => !current);
  }, []);

  const prevMonth = useCallback(() => {
    if (viewMonth === 0) { setViewMonth(11); setViewYear((y) => y - 1); }
    else setViewMonth((m) => m - 1);
  }, [viewMonth]);
  const nextMonth = useCallback(() => {
    if (viewMonth === 11) { setViewMonth(0); setViewYear((y) => y + 1); }
    else setViewMonth((m) => m + 1);
  }, [viewMonth]);

  const selectDay = useCallback((day) => {
    const mm = String(viewMonth + 1).padStart(2, "0");
    const dd = String(day).padStart(2, "0");
    const syntheticEvent = { target: { value: `${viewYear}-${mm}-${dd}` } };
    onChange(syntheticEvent);
    setOpen(false);
  }, [onChange, viewMonth, viewYear]);

  const handleDayClick = useCallback((event) => {
    const day = Number(event.currentTarget.dataset.day);
    if (day) selectDay(day);
  }, [selectDay]);

  const grid = useMemo(() => {
    const totalDays = daysInMonth(viewYear, viewMonth);
    const firstDay = new Date(viewYear, viewMonth, 1).getDay();
    const days = [];
    for (let i = 0; i < firstDay; i++) days.push(null);
    for (let d = 1; d <= totalDays; d++) days.push(d);
    return days;
  }, [viewMonth, viewYear]);

  const selectedDay = useMemo(
    () => parsed && parsed.getFullYear() === viewYear && parsed.getMonth() === viewMonth ? parsed.getDate() : null,
    [parsed, viewMonth, viewYear]
  );

  const today = useMemo(() => new Date(), []);
  const isToday = useCallback(
    (d) => d && today.getFullYear() === viewYear && today.getMonth() === viewMonth && today.getDate() === d,
    [today, viewMonth, viewYear]
  );

  const displayText = useMemo(
    () => parsed ? parsed.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" }) : "",
    [parsed]
  );

  return (
    <div className="pdp-wrapper" ref={wrapperRef} onKeyDown={handleKeyDown}>
      {label && <span className="pdp-label">{label}</span>}
      <button
        ref={triggerRef}
        type="button"
        className={`pdp-trigger ${open ? "pdp-trigger--open" : ""}`}
        onClick={toggleOpen}
        aria-haspopup="dialog"
        aria-expanded={open}
      >
        <svg className="pdp-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="3" y="4" width="18" height="18" rx="2" /><line x1="16" y1="2" x2="16" y2="6" /><line x1="8" y1="2" x2="8" y2="6" /><line x1="3" y1="10" x2="21" y2="10" />
        </svg>
        <span className={displayText ? "" : "pdp-placeholder"}>{displayText || "Select date"}</span>
        <svg className="pdp-chevron" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.293l3.71-4.06a.75.75 0 111.08 1.04l-4.25 4.65a.75.75 0 01-1.08 0L5.21 8.27a.75.75 0 01.02-1.06z" /></svg>
      </button>
      {/* Hidden native input for form validation */}
      <input type="date" value={value} required={required} tabIndex={-1} className="pdp-hidden-input" onChange={onChange} aria-hidden="true" />
      {open && createPortal(
        <div
          ref={dropdownRef}
          className="pdp-dropdown"
          style={{ position: "fixed", top: dropPos.top, left: dropPos.left, width: dropPos.width, zIndex: 99999 }}
          role="dialog"
          aria-label="Date picker"
        >
          <div className="pdp-nav">
            <button type="button" className="pdp-nav-btn" onClick={prevMonth} aria-label="Previous month">
              <svg viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M12.79 14.77a.75.75 0 01-1.06-.02L8.02 10.7a.75.75 0 010-1.04l3.71-4.06a.75.75 0 111.08 1.04L9.56 10.2l3.25 3.54a.75.75 0 01-.02 1.06z" /></svg>
            </button>
            <span className="pdp-title">{MONTHS[viewMonth]} {viewYear}</span>
            <button type="button" className="pdp-nav-btn" onClick={nextMonth} aria-label="Next month">
              <svg viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M7.21 14.77a.75.75 0 01-.02-1.06L10.44 10.2 7.19 6.66a.75.75 0 111.08-1.04l3.71 4.06a.75.75 0 010 1.04l-3.71 4.06a.75.75 0 01-1.06.02z" /></svg>
            </button>
          </div>
          <div className="pdp-days-header">
            {DAYS.map((d) => <span key={d} className="pdp-day-label">{d}</span>)}
          </div>
          <div className="pdp-grid">
            {grid.map((day, i) => (
              <button
                key={i}
                type="button"
                disabled={!day}
                className={[
                  "pdp-cell",
                  day === selectedDay ? "pdp-cell--selected" : "",
                  isToday(day) ? "pdp-cell--today" : ""
                ].join(" ")}
                data-day={day || ""}
                onClick={handleDayClick}
                aria-label={day ? `${MONTHS[viewMonth]} ${day}` : undefined}
              >
                {day || ""}
              </button>
            ))}
          </div>
        </div>,
        document.body
      )}
    </div>
  );
}

export default memo(PremiumDatePicker);
