import { useState, useRef, useEffect, useCallback, useMemo } from "react";
import { useMessenger } from "./messenger/MessengerContext";
import SimpleIcon from "./icons/SimpleIcon";

/**
 * NotificationBell — lives in the dashboard header (inside MessengerProvider).
 * Shows unread chat/discussion count as a badge and a per-conversation dropdown.
 */
export default function NotificationBell() {
  const {
    totalUnread,
    conversations,
    openPanel,
    openConversation,
    openApprovalThread,
    formatChatTime,
  } = useMessenger();
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

  // Conversations with unread messages, sorted newest first
  const unreadConvs = useMemo(() => {
    return conversations
      .filter((c) => (c.unread_count || 0) > 0)
      .sort((a, b) => {
        const ta = new Date(a.last_message?.created_at || a.updated_at || 0).getTime();
        const tb = new Date(b.last_message?.created_at || b.updated_at || 0).getTime();
        return tb - ta;
      })
      .slice(0, 8);
  }, [conversations]);

  const handleOpenConv = useCallback(
    (conv) => {
      setOpen(false);
      openPanel();
      if (conv.thread_kind === "approval_thread") {
        openApprovalThread(conv.id);
      } else {
        openConversation(conv);
      }
    },
    [openPanel, openConversation, openApprovalThread]
  );

  const handleOpenAll = useCallback(() => {
    setOpen(false);
    openPanel();
  }, [openPanel]);

  const total = totalUnread;

  function convLabel(conv) {
    if (conv.thread_kind === "approval_thread") {
      return conv.event_title || conv.title || "Workflow Discussion";
    }
    if (conv.thread_kind === "event") {
      return conv.title || "Event Chat";
    }
    return conv.other_user?.name || conv.title || "Direct Message";
  }

  function convAvatar(conv) {
    const label = convLabel(conv);
    return label.trim().charAt(0).toUpperCase() || "?";
  }

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
            {unreadConvs.length > 0 ? (
              <>
                {unreadConvs.map((conv) => {
                  const name = convLabel(conv);
                  const avatar = convAvatar(conv);
                  const lm = conv.last_message;
                  const preview = lm?.text
                    ? `${lm.sender_name ? lm.sender_name + ": " : ""}${lm.text.slice(0, 60)}`
                    : "New message";
                  const time = lm?.created_at
                    ? formatChatTime(lm.created_at)
                    : conv.updated_at
                    ? formatChatTime(conv.updated_at)
                    : "";
                  const unread = conv.unread_count || 0;
                  return (
                    <button
                      key={conv.id}
                      type="button"
                      className="notif-item"
                      onClick={() => handleOpenConv(conv)}
                    >
                      <span className="notif-item-avatar" aria-hidden="true">
                        {avatar}
                      </span>
                      <div className="notif-item-body">
                        <p className="notif-item-label">{name}</p>
                        <p className="notif-item-meta">{preview}</p>
                        {time && <p className="notif-item-time">{time}</p>}
                      </div>
                      {unread > 0 && (
                        <span className="notif-item-count" aria-label={`${unread} unread`}>
                          {unread > 99 ? "99+" : unread}
                        </span>
                      )}
                    </button>
                  );
                })}
                {total > 0 && (
                  <button
                    type="button"
                    className="notif-see-all"
                    onClick={handleOpenAll}
                  >
                    Open messenger
                  </button>
                )}
              </>
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

