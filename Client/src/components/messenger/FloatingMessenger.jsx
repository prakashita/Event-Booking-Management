import { useEffect, useMemo } from "react";
import { useMessenger } from "./MessengerContext";
import MessengerHeader from "./MessengerHeader";
import ConversationList from "./ConversationList";
import ChatWindow from "./ChatWindow";

export default function FloatingMessenger({
  user,
  chatUsers,
  chatEventThreads,
  chatActiveUser,
  chatActiveEventThread,
  chatUnreadByUser,
  chatUnreadByConversation,
  chatMessages,
  chatStatus,
  chatInput,
  chatFiles,
  chatTypingUser,
  chatHasMore,
  chatLoadingMore,
  chatConversationId,
  onStartConversation,
  onOpenEventThread,
  onRefresh,
  onChatInputChange,
  onSendMessage,
  onChatFiles,
  onRemoveChatFile,
  onLoadMore,
  onCloseChat,
  formatChatTime,
  resolveAttachmentUrl,
}) {
  const { panelOpen, togglePanel, closePanel } = useMessenger();
  const hasActiveChat = !!(chatActiveUser || chatActiveEventThread);

  const totalUnread = useMemo(() => {
    const userUnread = Object.values(chatUnreadByUser || {}).reduce(
      (a, b) => a + b,
      0
    );
    const convUnread = Object.values(chatUnreadByConversation || {}).reduce(
      (a, b) => a + b,
      0
    );
    return userUnread + convUnread;
  }, [chatUnreadByUser, chatUnreadByConversation]);

  useEffect(() => {
    const handleKey = (e) => {
      if (e.key === "Escape" && panelOpen) closePanel();
    };
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [panelOpen, closePanel]);

  if (!user) return null;

  return (
    <>
      {/* Toggle Button */}
      {!panelOpen ? (
        <button
          type="button"
          className="msger-toggle"
          onClick={togglePanel}
          aria-label="Open messenger"
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor">
            <path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z" />
          </svg>
          {totalUnread > 0 ? (
            <span className="msger-badge">
              {totalUnread > 99 ? "99+" : totalUnread}
            </span>
          ) : null}
        </button>
      ) : null}

      {/* Messenger Panel */}
      {panelOpen ? (
        <div
          className="msger-panel"
          role="complementary"
          aria-label="Messenger"
        >
          <MessengerHeader onClose={closePanel} onRefresh={onRefresh} />

          {hasActiveChat ? (
            <ChatWindow
              user={user}
              chatActiveUser={chatActiveUser}
              chatActiveEventThread={chatActiveEventThread}
              chatMessages={chatMessages}
              chatStatus={chatStatus}
              chatInput={chatInput}
              chatFiles={chatFiles}
              chatTypingUser={chatTypingUser}
              chatHasMore={chatHasMore}
              chatLoadingMore={chatLoadingMore}
              chatConversationId={chatConversationId}
              onChatInputChange={onChatInputChange}
              onSendMessage={onSendMessage}
              onChatFiles={onChatFiles}
              onRemoveChatFile={onRemoveChatFile}
              onLoadMore={onLoadMore}
              onBack={onCloseChat}
              formatChatTime={formatChatTime}
              resolveAttachmentUrl={resolveAttachmentUrl}
            />
          ) : (
            <ConversationList
              chatUsers={chatUsers}
              chatEventThreads={chatEventThreads}
              chatActiveUser={chatActiveUser}
              chatActiveEventThread={chatActiveEventThread}
              chatUnreadByConversation={chatUnreadByConversation}
              onStartConversation={onStartConversation}
              onOpenEventThread={onOpenEventThread}
            />
          )}
        </div>
      ) : null}
    </>
  );
}
