import { useState, useRef, useEffect, useCallback, useMemo, memo } from "react";

function SearchableSelect({ value, onChange, options, placeholder, required, label, emptyMessage }) {
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const ref = useRef(null);
  const listRef = useRef(null);

  const filtered = useMemo(() => {
    if (!search) return options;
    const q = search.toLowerCase();
    return options.filter((o) => o.label.toLowerCase().includes(q));
  }, [search, options]);

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
    if (!open || !listRef.current || !value) return;
    const active = listRef.current.querySelector(".ss-option--active");
    if (active) active.scrollIntoView({ block: "center" });
  }, [open, value]);

  const handleKeyDown = useCallback((e) => {
    if (e.key === "Escape") setOpen(false);
  }, []);

  const selectOption = (val) => {
    onChange({ target: { value: val } });
    setOpen(false);
  };

  const selectedLabel = options.find((o) => o.value === value)?.label || "";

  return (
    <div className="ss-wrapper" ref={ref} onKeyDown={handleKeyDown}>
      {label && <span className="ss-label">{label}</span>}
      <button
        type="button"
        className={`ss-trigger ${open ? "ss-trigger--open" : ""}`}
        onClick={() => setOpen(!open)}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <span className={selectedLabel ? "" : "ss-placeholder"}>{selectedLabel || placeholder || "Select..."}</span>
        <svg className="ss-chevron" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.293l3.71-4.06a.75.75 0 111.08 1.04l-4.25 4.65a.75.75 0 01-1.08 0L5.21 8.27a.75.75 0 01.02-1.06z" /></svg>
      </button>
      {/* Hidden native select for form validation */}
      <select value={value} required={required} tabIndex={-1} className="ss-hidden" onChange={onChange} aria-hidden="true">
        <option value="">{placeholder || "Select..."}</option>
        {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
      {open && (
        <div className="ss-dropdown" role="listbox" aria-label={label || placeholder}>
          <div className="ss-search-wrap">
            <svg className="ss-search-icon" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" /></svg>
            <input
              type="text"
              className="ss-search"
              placeholder="Search..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              autoFocus
            />
          </div>
          <div className="ss-list" ref={listRef}>
            {filtered.length === 0 && <div className="ss-empty">{emptyMessage || "No matches"}</div>}
            {filtered.map((o) => (
              <button
                key={o.value}
                type="button"
                role="option"
                aria-selected={o.value === value}
                className={`ss-option ${o.value === value ? "ss-option--active" : ""}`}
                onClick={() => selectOption(o.value)}
              >
                {o.label}
                {o.value === value && (
                  <svg className="ss-check" viewBox="0 0 20 20" fill="currentColor"><path fillRule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" /></svg>
                )}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default memo(SearchableSelect);
