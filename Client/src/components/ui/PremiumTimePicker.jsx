import { useState, useRef, useEffect, useCallback, useMemo, memo } from "react";

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

function PremiumTimePicker({ timeParts, onPartChange, required, label }) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const ref = useRef(null);
  const listRef = useRef(null);

  const currentLabel = useMemo(() => {
    if (!timeParts.hour || !timeParts.minute) return "";
    return `${timeParts.hour}:${timeParts.minute} ${timeParts.period}`;
  }, [timeParts.hour, timeParts.minute, timeParts.period]);

  const filtered = useMemo(() => {
    if (!search) return TIME_SLOTS;
    return TIME_SLOTS.filter((s) => s.label.toLowerCase().includes(search.toLowerCase()));
  }, [search]);

  useEffect(() => {
    if (!open) return;
    setSearch("");
    const handler = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  useEffect(() => {
    if (!open || !listRef.current || !currentLabel) return;
    const active = listRef.current.querySelector(".ptp-slot--active");
    if (active) active.scrollIntoView({ block: "center" });
  }, [open, currentLabel]);

  const handleKeyDown = useCallback((e) => {
    if (e.key === "Escape") setOpen(false);
  }, []);

  const selectSlot = (slot) => {
    onPartChange("hour")({ target: { value: slot.hour } });
    onPartChange("minute")({ target: { value: slot.minute } });
    onPartChange("period")({ target: { value: slot.period } });
    setOpen(false);
  };

  return (
    <div className="ptp-wrapper" ref={ref} onKeyDown={handleKeyDown}>
      {label && <span className="ptp-label">{label}</span>}
      <button
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
      <select value={timeParts.hour} required={required} tabIndex={-1} className="ptp-hidden" onChange={onPartChange("hour")} aria-hidden="true">
        <option value="">Hour</option>
        {Array.from({ length: 12 }, (_, i) => String(i + 1)).map((h) => <option key={h} value={h}>{h}</option>)}
      </select>
      <select value={timeParts.minute} required={required} tabIndex={-1} className="ptp-hidden" onChange={onPartChange("minute")} aria-hidden="true">
        <option value="">Min</option>
        {Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0")).map((m) => <option key={m} value={m}>{m}</option>)}
      </select>
      {open && (
        <div className="ptp-dropdown" role="listbox" aria-label="Time picker">
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
        </div>
      )}
    </div>
  );
}

export default memo(PremiumTimePicker);
