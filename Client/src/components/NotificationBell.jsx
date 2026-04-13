import { useState, useRef, useEffect, useCallback } from "react";
import { useMessenger } from "./messenger/MessengerContext";
import SimpleIcon from "./icons/SimpleIcon";

/**
 * NotificationBell — lives in the dashboard header (inside MessengerProvider).
 * Shows unread chat/discussion count as a badge and a dropdown panel.
 */
export default function NotificationBell() {
  const { totalUnread, openPanel } = useMessenger();
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  useEffect(() => {
    if (!open) return;
    function handleOutside(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    }
    document.addEventListener("mousedown", handleOutside);
    return () => document.removeEventListener("mousedown", handleOutside);
  }, [open]);

  const handleOpenMessages = useCallback(() => {
    setOpen(false);
    openPanel();
  }, [openPanel]);

  const total = totalUnread;

  return (
    <div className="notif-root" ref={ref}>
      <button
        type="button"
        className={`icon-button notif-trigger${open ? " notif-trigger--open" : ""}`}
        onClick={() => setOpen((v) => !v)}
        aria-label={`Notifications${total > 0 ? ` (${total} unread)` : ""}`}
        aria-expanded={open}
        aria-haspopup="true"
        style={{ position: "relative" }}
      >
        <SimpleIcon path="M12 3a6 6 0 0 1 6 6v4l2 3H4l2-3V9a6 6 0 0 1 6-6Zm0 18a2.5 2.5 0 0 0 2.45-2H9.55A2.5 2.5 0 0 0 12 21Z" />
        {total > 0 && (
          <span className="notif-badge" aria-hidden="true">
            {total > 99 ? "99+" : total}
          </span>
        )}
      </button>

      {open && (
        <div className="notif-dropdown" role="dialog" aria-label="Notifications">
            <div className="notif-header">
              <p className="notif-header-title">Notifications</p>
              {total > 0 && (
                <span className="notif-header-count">{total} unread</span>
              )}
            </div>

            <div className="notif-body">
              {total > 0 ? (
                <button
                  type="button"
                  className="notif-item"
                  onClick={handleOpenMessages}
                >
                  <span className="notif-item-icon">
                    <SimpleIcon path="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z" />
                  </span>
                  <div className="notif-item-body">
                    <p className="notif-item-label">Unread Messages</p>
                    <p className="notif-item-meta">
                      {total} unread in chats &amp; discussions
                    </p>
                  </div>
                  <span className="notif-item-count">{total > 99 ? "99+" : total}</span>
                </button>
              ) : (
                <div className="notif-empty">
                  <svg
                    width="32"
                    height="32"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    aria-hidden="true"
                    className="notif-empty-icon"
                  >
                    <path d="M12 3a6 6 0 0 1 6 6v4l2 3H4l2-3V9a6 6 0 0 1 6-6Z" />
                    <path d="M12 21a2.5 2.5 0 0 0 2.45-2H9.55A2.5 2.5 0 0 0 12 21Z" />
                  </svg>
                  <p>You&apos;re all caught up</p>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
  );
}
