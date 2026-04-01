import React from "react";

const ConversationItem = React.memo(function ConversationItem({
  name,
  avatarLabel,
  isActive,
  isEvent,
  unread,
  meta,
  online,
  onClick,
}) {
  return (
    <button
      type="button"
      className={`msger-conv-item${isActive ? " active" : ""}${isEvent ? " event" : ""}`}
      onClick={onClick}
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
          {unread > 0 && <span className="msger-unread">{unread}</span>}
        </p>
        {meta && <p className="msger-conv-meta">{meta}</p>}
      </div>
    </button>
  );
});

export default ConversationItem;
