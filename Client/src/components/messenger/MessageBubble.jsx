import React, { useState, useRef, useEffect } from "react";

const MessageBubble = React.memo(function MessageBubble({
  message,
  isOwn,
  isRead,
  formatTime,
  resolveAttachmentUrl,
  onDeleteForMe,
  onRequestDeleteForEveryone,
  onStartEdit,
  isEditing,
  editDraft,
  onEditDraftChange,
  onSaveEdit,
  onCancelEdit,
  onStartReply,
}) {
  const [dropdownOpen, setDropdownOpen] = useState(false);
  const menuRef = useRef(null);

  const isDeleted = message.deleted_for_everyone;
  const canEdit = isOwn && !isDeleted && (message.content || "").trim().length > 0;
  const hasActions =
    onDeleteForMe ||
    (isOwn && onRequestDeleteForEveryone && !isDeleted) ||
    (canEdit && onStartEdit) ||
    (onStartReply && !isDeleted);

  useEffect(() => {
    if (!dropdownOpen) return;
    const close = (e) => {
      if (menuRef.current && !menuRef.current.contains(e.target)) {
        setDropdownOpen(false);
      }
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [dropdownOpen]);

  return (
    <div
      className={`msger-msg${isOwn ? " own" : ""}${isDeleted ? " deleted" : ""}`}
      data-message-id={message.id}
    >
      <div className="msger-bubble">
        <div className="msger-msg-meta">
          <span className="msger-msg-author">{message.sender_name}</span>
          <span>{formatTime(message.created_at)}</span>
          {message.edited ? (
            <span className="msger-msg-edited" title="Edited">
              (edited)
            </span>
          ) : null}
          {hasActions && !isEditing ? (
            <div className="msger-msg-menu-wrap" ref={menuRef}>
              <button
                type="button"
                className="msger-msg-menu-trigger"
                aria-expanded={dropdownOpen}
                aria-haspopup="true"
                aria-label="Message actions"
                onClick={() => setDropdownOpen((v) => !v)}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                  <circle cx="12" cy="5" r="2" />
                  <circle cx="12" cy="12" r="2" />
                  <circle cx="12" cy="19" r="2" />
                </svg>
              </button>
              {dropdownOpen ? (
                <div className="msger-msg-menu" role="menu">
                  {onStartReply && !isDeleted ? (
                    <button
                      type="button"
                      role="menuitem"
                      className="msger-msg-menu-item"
                      onClick={() => {
                        setDropdownOpen(false);
                        onStartReply(message);
                      }}
                    >
                      Reply
                    </button>
                  ) : null}
                  {canEdit && onStartEdit ? (
                    <button
                      type="button"
                      role="menuitem"
                      className="msger-msg-menu-item"
                      onClick={() => {
                        setDropdownOpen(false);
                        onStartEdit(message);
                      }}
                    >
                      Edit
                    </button>
                  ) : null}
                  {onDeleteForMe ? (
                    <button
                      type="button"
                      role="menuitem"
                      className="msger-msg-menu-item"
                      onClick={() => {
                        setDropdownOpen(false);
                        onDeleteForMe(message.id);
                      }}
                    >
                      Delete for me
                    </button>
                  ) : null}
                  {isOwn && onRequestDeleteForEveryone && !isDeleted ? (
                    <button
                      type="button"
                      role="menuitem"
                      className="msger-msg-menu-item danger"
                      onClick={() => {
                        setDropdownOpen(false);
                        onRequestDeleteForEveryone(message.id);
                      }}
                    >
                      Delete for everyone
                    </button>
                  ) : null}
                </div>
              ) : null}
            </div>
          ) : null}
        </div>
        {isDeleted ? (
          <p className="msger-msg-text msger-msg-deleted">
            <em>{message.content}</em>
          </p>
        ) : isEditing ? (
          <div className="msger-msg-edit">
            <textarea
              className="msger-msg-edit-input"
              value={editDraft}
              onChange={(e) => onEditDraftChange(e.target.value)}
              rows={3}
              autoFocus
            />
            <div className="msger-msg-edit-actions">
              <button type="button" className="msger-msg-edit-cancel" onClick={onCancelEdit}>
                Cancel
              </button>
              <button type="button" className="msger-msg-edit-save" onClick={onSaveEdit}>
                Save
              </button>
            </div>
          </div>
        ) : (
          <>
            {message.reply_to_snapshot ? (
              <div className="msger-reply-quote">
                <span className="msger-reply-quote-author">
                  {message.reply_to_snapshot.sender_name}
                </span>
                <p className="msger-reply-quote-preview">
                  {message.reply_to_snapshot.content_preview}
                </p>
              </div>
            ) : null}
            {message.content ? (
              <p className="msger-msg-text">{message.content}</p>
            ) : null}
            {message.attachments?.length > 0 ? (
              <div className="msger-attachments">
                {message.attachments.map((att) => {
                  const url = resolveAttachmentUrl(att.url);
                  const isImage = att.content_type?.startsWith("image/");
                  const isVideo = att.content_type?.startsWith("video/");
                  return (
                    <div key={`${message.id}-${att.url}`} className="msger-attachment">
                      {isImage ? (
                        <img src={url} alt={att.name} />
                      ) : isVideo ? (
                        <video src={url} controls playsInline className="msger-attachment-video" />
                      ) : (
                        <a href={url} target="_blank" rel="noreferrer">
                          {att.name}
                        </a>
                      )}
                    </div>
                  );
                })}
              </div>
            ) : null}
          </>
        )}
        {isOwn && !isEditing ? (
          <div className="msger-read">{isRead ? "✓✓" : "✓"}</div>
        ) : null}
      </div>
    </div>
  );
});

export default MessageBubble;
