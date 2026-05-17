import React, { useState, useRef, useEffect } from "react";

const ConversationItem = React.memo(function ConversationItem({
  name,
  avatarLabel,
  isActive,
  isEvent,
  isWorkflow,
  isLocked,
  workflowLabel,
  unread,
  meta,
  time,
  online,
  memberCountLabel,
  participantNamesTitle,
  onClick,
  onDeleteForMe,
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);

  const showConvMenu = Boolean(onDeleteForMe);

  useEffect(() => {
    if (!menuOpen) return;
    const close = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setMenuOpen(false);
      }
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [menuOpen]);

  return (
    <div
      role="button"
      tabIndex={0}
      className={`msger-conv-item${isActive ? " active" : ""}${isEvent ? " event" : ""}${isWorkflow ? " workflow" : ""}${isLocked ? " locked" : ""}`}
      onClick={onClick}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onClick?.();
        }
      }}
      title={participantNamesTitle || undefined}
    >
      <span
        className={`msger-avatar${isEvent ? " msger-avatar-event" : ""}${isWorkflow ? " msger-avatar-workflow" : ""}`}
        aria-hidden="true"
      >
        {isWorkflow && isLocked ? (
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
        ) : (
          avatarLabel
        )}
        {!isEvent && !isWorkflow && (
          <span className={`msger-presence${online ? " online" : ""}`} />
        )}
      </span>
      <div className="msger-conv-text">
        <p className="msger-conv-name">
          {name}
          {unread > 0 ? <span className="msger-unread">{unread}</span> : null}
        </p>
        {workflowLabel ? (
          <p className="msger-conv-workflow-label">{workflowLabel}</p>
        ) : null}
        {isWorkflow && participantNamesTitle ? (
          <p className="msger-conv-workflow-participants">{participantNamesTitle}</p>
        ) : null}
        {memberCountLabel ? (
          <p className="msger-conv-members">{memberCountLabel}</p>
        ) : null}
        {meta ? <p className="msger-conv-meta">{meta}</p> : null}
      </div>
      <div className="msger-conv-right">
        {time ? <span className="msger-conv-time">{time}</span> : null}
        {showConvMenu && (
          <div className="msger-conv-menu-wrap" ref={menuRef}>
            <button
              type="button"
              className="msger-conv-menu-trigger"
              aria-label="Conversation options"
              aria-expanded={menuOpen}
              onClick={(e) => { e.stopPropagation(); setMenuOpen((v) => !v); }}
            >
              ···
            </button>
            {menuOpen && (
              <div className="msger-conv-menu" role="menu">
                {onDeleteForMe && (
                  <button
                    type="button"
                    className="msger-conv-menu-item danger"
                    role="menuitem"
                    onClick={(e) => { e.stopPropagation(); onDeleteForMe(); setMenuOpen(false); }}
                  >
                    Delete chat for me
                  </button>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
});

export default ConversationItem;
