import { useEffect, useRef } from "react";

export default function MessengerConfirmDialog({
  open,
  title,
  message,
  confirmLabel = "Confirm",
  cancelLabel = "Cancel",
  danger,
  onConfirm,
  onCancel,
}) {
  const cancelRef = useRef(null);

  useEffect(() => {
    if (!open) return;
    cancelRef.current?.focus();
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e) => {
      if (e.key === "Escape") onCancel?.();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open, onCancel]);

  if (!open) return null;

  return (
    <div
      className="msger-confirm-backdrop"
      role="presentation"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onCancel?.();
      }}
    >
      <div
        className="msger-confirm-dialog"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="msger-confirm-title"
        aria-describedby="msger-confirm-desc"
      >
        <h3 id="msger-confirm-title" className="msger-confirm-title">
          {title}
        </h3>
        <p id="msger-confirm-desc" className="msger-confirm-message">
          {message}
        </p>
        <div className="msger-confirm-actions">
          <button
            ref={cancelRef}
            type="button"
            className="msger-confirm-btn msger-confirm-btn-secondary"
            onClick={onCancel}
          >
            {cancelLabel}
          </button>
          <button
            type="button"
            className={`msger-confirm-btn${danger ? " danger" : ""}`}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
