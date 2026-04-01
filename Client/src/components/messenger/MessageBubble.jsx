import React from "react";

const MessageBubble = React.memo(function MessageBubble({
  message,
  isOwn,
  isRead,
  formatTime,
  resolveAttachmentUrl,
}) {
  return (
    <div className={`msger-msg${isOwn ? " own" : ""}`}>
      <div className="msger-bubble">
        <div className="msger-msg-meta">
          <span className="msger-msg-author">{message.sender_name}</span>
          <span>{formatTime(message.created_at)}</span>
        </div>
        {message.content ? (
          <p className="msger-msg-text">{message.content}</p>
        ) : null}
        {message.attachments?.length > 0 ? (
          <div className="msger-attachments">
            {message.attachments.map((att) => {
              const url = resolveAttachmentUrl(att.url);
              const isImage = att.content_type?.startsWith("image/");
              return (
                <div key={`${message.id}-${att.url}`} className="msger-attachment">
                  {isImage ? (
                    <img src={url} alt={att.name} />
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
        {isOwn ? (
          <div className="msger-read">{isRead ? "✓✓" : "✓"}</div>
        ) : null}
      </div>
    </div>
  );
});

export default MessageBubble;
