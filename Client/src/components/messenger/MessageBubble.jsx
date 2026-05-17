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
  // Edit window: 10 minutes from message creation (must match backend enforcement)
  const withinEditWindow =
    !message.created_at ||
    Date.now() - new Date(message.created_at).getTime() < 10 * 60 * 1000;
  const canEdit = isOwn && !isDeleted && (message.content || "").trim().length > 0 && withinEditWindow;
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
                aria-label="Message actions"
                aria-expanded={dropdownOpen}
                onClick={(e) => { e.stopPropagation(); setDropdownOpen((v) => !v); }}
              >
                ···
              </button>
              {dropdownOpen && (
                <div className="msger-msg-menu" role="menu">
                  {onStartReply && !isDeleted && (
                    <button
                      type="button"
                      className="msger-msg-menu-item"
                      role="menuitem"
                      onClick={() => { onStartReply(message); setDropdownOpen(false); }}
                    >
                      ↩ Reply
                    </button>
                  )}
                  {canEdit && onStartEdit && (
                    <button
                      type="button"
                      className="msger-msg-menu-item"
                      role="menuitem"
                      onClick={() => { onStartEdit(message); setDropdownOpen(false); }}
                    >
                      ✎ Edit
                    </button>
                  )}
                  {onDeleteForMe && (
                    <button
                      type="button"
                      className="msger-msg-menu-item"
                      role="menuitem"
                      onClick={() => { onDeleteForMe(message.id); setDropdownOpen(false); }}
                    >
                      Delete for me
                    </button>
                  )}
                  {isOwn && onRequestDeleteForEveryone && !isDeleted && (
                    <button
                      type="button"
                      className="msger-msg-menu-item danger"
                      role="menuitem"
                      onClick={() => { onRequestDeleteForEveryone(message.id); setDropdownOpen(false); }}
                    >
                      Delete for everyone
                    </button>
                  )}
                </div>
              )}
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
                        <a href={url} target="_blank" rel="noreferrer">
                          <img src={url} alt={att.name || "Image"} loading="lazy" />
                        </a>
                      ) : isVideo ? (
                        <video src={url} controls playsInline className="msger-attachment-video" />
                      ) : (
                        <a
                          href={url}
                          target="_blank"
                          rel="noreferrer"
                          className="msger-attachment-file"
                        >
                          <svg
                            className="msger-attachment-file-icon"
                            viewBox="0 0 24 24"
                            fill="none"
                            stroke="currentColor"
                            strokeWidth="1.5"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                            aria-hidden
                          >
                            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                            <polyline points="14 2 14 8 20 8" />
                          </svg>
                          <span className="msger-attachment-file-name">
                            {att.name || "File"}
                          </span>
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
