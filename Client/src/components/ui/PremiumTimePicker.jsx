import { useState, useRef, useEffect, useCallback, useMemo, memo } from "react";
import { createPortal } from "react-dom";

function generateTimeSlots() {
  const slots = [];
  for (let h = 1; h <= 12; h++) {
    for (let m = 0; m < 60; m += 5) {
      const hour = String(h);
      const minute = String(m).padStart(2, "0");
      slots.push({ hour, minute, period: "AM", label: `${h}:${minute} AM` });
      slots.push({ hour, minute, period: "PM", label: `${h}:${minute} PM` });
    }
  }
  slots.sort((a, b) => {
    const toNum = (s) => {
      let hh = parseInt(s.hour);
      if (s.period === "AM" && hh === 12) hh = 0;
      if (s.period === "PM" && hh !== 12) hh += 12;
      return hh * 60 + parseInt(s.minute);
    };
    return toNum(a) - toNum(b);
  });
  return slots;
}

const TIME_SLOTS = generateTimeSlots();

function parseValueToParts(value) {
  if (!value) return { hour: "", minute: "", period: "AM" };
  const [rawHour = "", rawMinute = ""] = String(value).split(":");
  const h24 = parseInt(rawHour, 10);
  if (Number.isNaN(h24)) return { hour: "", minute: "", period: "AM" };
  const period = h24 >= 12 ? "PM" : "AM";
  const hour12 = h24 % 12 || 12;
  return {
    hour: String(hour12),
    minute: String(rawMinute || "00").padStart(2, "0").slice(0, 2),
    period
  };
}

function slotToValue(slot) {
  let hour = parseInt(slot.hour, 10);
  if (slot.period === "AM" && hour === 12) hour = 0;
  if (slot.period === "PM" && hour !== 12) hour += 12;
  return `${String(hour).padStart(2, "0")}:${slot.minute}`;
}

function PremiumTimePicker({ timeParts, onPartChange, value, onChange, required, label }) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const wrapperRef = useRef(null);
  const triggerRef = useRef(null);
  const dropdownRef = useRef(null);
  const listRef = useRef(null);
  const rafRef = useRef(null);
  const [dropPos, setDropPos] = useState({ top: 0, left: 0, width: 200 });
  const effectiveParts = value !== undefined ? parseValueToParts(value) : timeParts;

  const currentLabel = useMemo(() => {
    if (!effectiveParts?.hour || !effectiveParts?.minute) return "";
    return `${effectiveParts.hour}:${effectiveParts.minute} ${effectiveParts.period}`;
  }, [effectiveParts?.hour, effectiveParts?.minute, effectiveParts?.period]);

  const filtered = useMemo(() => {
    if (!search) return TIME_SLOTS;
    return TIME_SLOTS.filter((s) => s.label.toLowerCase().includes(search.toLowerCase()));
  }, [search]);

  const calcDropPos = useCallback(() => {
    if (!triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > window.innerHeight) {
      setOpen(false);
      return;
    }
    const dropH = 300;
    const spaceBelow = window.innerHeight - rect.bottom;
    const isMobile = window.innerWidth < 560;
    if (isMobile) {
      setDropPos({ top: Math.max(8, window.innerHeight - dropH - 16), left: 8, width: window.innerWidth - 16 });
    } else {
      setDropPos({
        top: spaceBelow >= dropH + 10 ? rect.bottom + 6 : Math.max(8, rect.top - dropH - 6),
        left: Math.max(8, Math.min(rect.left, window.innerWidth - 212)),
        width: Math.max(200, rect.width),
      });
    }
  }, []);

  useEffect(() => {
    if (!open) return;
    setSearch("");
    calcDropPos();

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
  }, [open, calcDropPos]);

  useEffect(() => {
    if (!open || !listRef.current || !currentLabel) return;
    const active = listRef.current.querySelector(".ptp-slot--active");
    if (active) active.scrollIntoView({ block: "center" });
  }, [open, currentLabel]);

  const handleKeyDown = useCallback((e) => {
    if (e.key === "Escape") setOpen(false);
  }, []);

  const selectSlot = (slot) => {
    if (onChange) {
      onChange({ target: { value: slotToValue(slot) } });
    } else {
      onPartChange("hour")({ target: { value: slot.hour } });
      onPartChange("minute")({ target: { value: slot.minute } });
      onPartChange("period")({ target: { value: slot.period } });
    }
    setOpen(false);
  };
  const noop = () => {};

  return (
    <div className="ptp-wrapper" ref={wrapperRef} onKeyDown={handleKeyDown}>
      {label && <span className="ptp-label">{label}</span>}
      <button
        ref={triggerRef}
        type="button"
        className={`ptp-trigger ${open ? "ptp-trigger--open" : ""}`}
        onClick={() => setOpen(!open)}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <svg className="ptp-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" />
        </svg>
        <span className={currentLabel ? "" : "ptp-placeholder"}>{currentLabel || "Select time"}</span>
        <svg className="ptp-chevron" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.293l3.71-4.06a.75.75 0 111.08 1.04l-4.25 4.65a.75.75 0 01-1.08 0L5.21 8.27a.75.75 0 01.02-1.06z" /></svg>
      </button>
      {/* Hidden selects for form validation */}
      <select value={effectiveParts?.hour || ""} required={required} tabIndex={-1} className="ptp-hidden" onChange={onPartChange ? onPartChange("hour") : noop} aria-hidden="true">
        <option value="">Hour</option>
        {Array.from({ length: 12 }, (_, i) => String(i + 1)).map((h) => <option key={h} value={h}>{h}</option>)}
      </select>
      <select value={effectiveParts?.minute || ""} required={required} tabIndex={-1} className="ptp-hidden" onChange={onPartChange ? onPartChange("minute") : noop} aria-hidden="true">
        <option value="">Min</option>
        {Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0")).map((m) => <option key={m} value={m}>{m}</option>)}
      </select>
      {open && createPortal(
        <div
          ref={dropdownRef}
          className="ptp-dropdown"
          style={{ position: "fixed", top: dropPos.top, left: dropPos.left, width: dropPos.width, zIndex: 99999 }}
          role="listbox"
          aria-label="Time picker"
        >
          <div className="ptp-search-wrap">
            <input
              type="text"
              className="ptp-search"
              placeholder="Search time..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              autoFocus
            />
          </div>
          <div className="ptp-list" ref={listRef}>
            {filtered.length === 0 && <div className="ptp-empty">No matches</div>}
            {filtered.map((slot) => (
              <button
                key={slot.label}
                type="button"
                role="option"
                aria-selected={slot.label === currentLabel}
                className={`ptp-slot ${slot.label === currentLabel ? "ptp-slot--active" : ""}`}
                onClick={() => selectSlot(slot)}
              >
                {slot.label}
              </button>
            ))}
          </div>
        </div>,
        document.body
      )}
    </div>
  );
}

export default memo(PremiumTimePicker);
