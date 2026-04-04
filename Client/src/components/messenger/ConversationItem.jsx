import React, { useState, useRef, useEffect } from "react";

const ConversationItem = React.memo(function ConversationItem({
  name,
  avatarLabel,
  isActive,
  isEvent,
  unread,
  meta,
  time,
  online,
  memberCountLabel,
  participantNamesTitle,
  onClick,
  onClearChat,
  onPurgeChat,
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef(null);

  const showConvMenu = Boolean(onClearChat || onPurgeChat);

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
    <button
      type="button"
      className={`msger-conv-item${isActive ? " active" : ""}${isEvent ? " event" : ""}`}
      onClick={onClick}
      title={participantNamesTitle || undefined}
    >
      <span
        className={`msger-avatar${isEvent ? " msger-avatar-event" : ""}`}
        aria-hidden="true"
      >
        {avatarLabel}
        {!isEvent && (
          <span className={`msger-presence${online ? " online" : ""}`} />
        )}
      </span>
      <div className="msger-conv-text">
        <p className="msger-conv-name">
          {name}
          {unread > 0 ? <span className="msger-unread">{unread}</span> : null}
        </p>
        {memberCountLabel ? (
          <p className="msger-conv-members">{memberCountLabel}</p>
        ) : null}
        {meta ? <p className="msger-conv-meta">{meta}</p> : null}
      </div>
      <div className="msger-conv-right">
        {time ? <span className="msger-conv-time">{time}</span> : null}
        {showConvMenu ? (
          <div className="msger-conv-menu-wrap" ref={menuRef}>
            <button
              type="button"
              className="msger-conv-menu-trigger"
              aria-label={`Chat options for ${name}`}
              aria-expanded={menuOpen}
              onClick={(e) => {
                e.stopPropagation();
                setMenuOpen((v) => !v);
              }}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                <circle cx="12" cy="5" r="2" />
                <circle cx="12" cy="12" r="2" />
                <circle cx="12" cy="19" r="2" />
              </svg>
            </button>
            {menuOpen ? (
              <div className="msger-conv-menu" role="menu">
                {onClearChat ? (
                  <button
                    type="button"
                    role="menuitem"
                    className="msger-conv-menu-item"
                    onClick={(e) => {
                      e.stopPropagation();
                      setMenuOpen(false);
                      onClearChat();
                    }}
                  >
                    Clear chat
                  </button>
                ) : null}
                {onPurgeChat ? (
                  <button
                    type="button"
                    role="menuitem"
                    className="msger-conv-menu-item danger"
                    onClick={(e) => {
                      e.stopPropagation();
                      setMenuOpen(false);
                      onPurgeChat();
                    }}
                  >
                    Delete chat
                  </button>
                ) : null}
              </div>
            ) : null}
          </div>
        ) : null}
      </div>
    </button>
  );
});

export default ConversationItem;
