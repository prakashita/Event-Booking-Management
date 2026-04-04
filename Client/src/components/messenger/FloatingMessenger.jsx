import { useEffect } from "react";
import { useMessenger } from "./MessengerContext";
import MessengerHeader from "./MessengerHeader";
import ConversationList from "./ConversationList";
import ChatWindow from "./ChatWindow";

export default function FloatingMessenger() {
  const {
    panelOpen,
    togglePanel,
    closePanel,
    totalUnread,
    activeUser,
    activeEventThread,
    loadConversations,
    loadChatUsers,
  } = useMessenger();

  const hasActiveChat = !!(activeUser || activeEventThread);

  useEffect(() => {
    if (!panelOpen) return;
    if (typeof Notification === "undefined") return;
    if (Notification.permission !== "default") return;
    Notification.requestPermission().catch(() => {});
  }, [panelOpen]);

  useEffect(() => {
    const handleKey = (e) => {
      if (e.key === "Escape" && panelOpen) closePanel();
    };
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [panelOpen, closePanel]);

  const handleRefresh = () => {
    loadConversations();
    loadChatUsers();
  };

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
          <MessengerHeader onClose={closePanel} onRefresh={handleRefresh} />

          {hasActiveChat ? <ChatWindow /> : <ConversationList />}
        </div>
      ) : null}
    </>
  );
}
