import { useRef, useEffect } from "react";
import MessageBubble from "./MessageBubble";
import MessageInput from "./MessageInput";

export default function ChatWindow({
  user,
  chatActiveUser,
  chatActiveEventThread,
  chatMessages,
  chatStatus,
  chatInput,
  chatFiles,
  chatTypingUser,
  chatHasMore,
  chatLoadingMore,
  chatConversationId,
  onChatInputChange,
  onSendMessage,
  onChatFiles,
  onRemoveChatFile,
  onLoadMore,
  onBack,
  formatChatTime,
  resolveAttachmentUrl,
}) {
  const listRef = useRef(null);

  useEffect(() => {
    if (listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [chatMessages.length]);

  const activeName = chatActiveEventThread
    ? chatActiveEventThread.title || "Event chat"
    : chatActiveUser?.name || "";

  const activeStatus = chatActiveEventThread
    ? `Group · ${chatActiveEventThread.participants?.length ?? 0} people`
    : chatActiveUser?.online
      ? "Online"
      : chatActiveUser?.last_seen
        ? `Last seen ${formatChatTime(chatActiveUser.last_seen)}`
        : "";

  const typingName = chatTypingUser?.name || "";

  return (
    <div
      className="msger-chat"
      role="dialog"
      aria-label={`Chat with ${activeName}`}
    >
      <div className="msger-chat-header">
        <button
          type="button"
          className="msger-back"
          onClick={onBack}
          aria-label="Back to conversations"
        >
          <svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M19 12H5M12 19l-7-7 7-7" />
          </svg>
        </button>
        <div className="msger-chat-info">
          <p className="msger-chat-name">{activeName}</p>
          {activeStatus ? (
            <p className="msger-chat-status">{activeStatus}</p>
          ) : null}
        </div>
      </div>

      <div className="msger-messages" ref={listRef}>
        {chatHasMore && chatMessages.length > 0 ? (
          <button
            type="button"
            className="msger-load-more"
            onClick={() =>
              onLoadMore(chatConversationId, chatMessages[0]?.created_at)
            }
            disabled={chatLoadingMore}
          >
            {chatLoadingMore ? "Loading..." : "Load earlier"}
          </button>
        ) : null}
        {chatStatus.status === "loading" ? (
          <p className="msger-note">Loading...</p>
        ) : null}
        {chatStatus.status === "error" ? (
          <p className="msger-note msger-error">{chatStatus.error}</p>
        ) : null}
        {chatMessages.map((message) => {
          const isOwn = message.sender_id === user.id;
          let isRead = false;
          if (chatActiveEventThread?.participants?.length) {
            const others = chatActiveEventThread.participants.filter(
              (pid) => pid !== user.id
            );
            isRead = others.some((pid) => message.read_by.includes(pid));
          } else if (chatActiveUser) {
            isRead = message.read_by.includes(chatActiveUser.id);
          }
          return (
            <MessageBubble
              key={message.id}
              message={message}
              isOwn={isOwn}
              isRead={isRead}
              formatTime={formatChatTime}
              resolveAttachmentUrl={resolveAttachmentUrl}
            />
          );
        })}
      </div>

      {typingName ? (
        <div className="msger-typing">{typingName} is typing...</div>
      ) : null}

      <MessageInput
        chatInput={chatInput}
        chatFiles={chatFiles}
        disabled={!chatActiveUser && !chatActiveEventThread}
        onInputChange={onChatInputChange}
        onSend={onSendMessage}
        onFileChange={onChatFiles}
        onRemoveFile={onRemoveChatFile}
      />
    </div>
  );
}
