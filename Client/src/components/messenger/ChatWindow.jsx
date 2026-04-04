import { useRef, useEffect, useState, useCallback } from "react";
import { useMessenger } from "./MessengerContext";
import MessageBubble from "./MessageBubble";
import MessageInput from "./MessageInput";
import MessengerConfirmDialog from "./MessengerConfirmDialog";

export default function ChatWindow() {
  const {
    user,
    activeUser,
    activeEventThread,
    activeConversation,
    messages,
    chatStatus,
    chatInput,
    chatFiles,
    typingUser,
    hasMore,
    loadingMore,
    handleInputChange,
    sendMessage,
    handleFiles,
    removeFile,
    loadMessages,
    closeChat,
    deleteMessageForEveryone,
    deleteMessageForMe,
    editMessage,
    formatChatTime,
    resolveAttachmentUrl,
  } = useMessenger();

  const listRef = useRef(null);
  const [confirm, setConfirm] = useState(null);
  const [editingId, setEditingId] = useState(null);
  const [editDraft, setEditDraft] = useState("");
  const [editError, setEditError] = useState("");

  useEffect(() => {
    if (listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [messages.length, editingId]);

  const activeName = activeEventThread
    ? activeEventThread.title || "Event chat"
    : activeUser?.name || "";

  const activeStatus = activeEventThread
    ? `Group · ${activeEventThread.participants?.length ?? activeConversation?.participant_count ?? 0} people`
    : activeUser?.online
      ? "Online"
      : activeUser?.last_seen
        ? `Last seen ${formatChatTime(activeUser.last_seen)}`
        : "";

  const preview =
    activeConversation?.participants_preview ||
    activeEventThread?.participants_preview ||
    [];
  const participantCount =
    activeConversation?.participant_count ??
    activeEventThread?.participant_count ??
    preview.length ??
    0;
  const participantNamesTitle = preview.map((p) => p.name).filter(Boolean).join(", ");

  const typingName = typingUser?.name || "";

  const onStartEdit = useCallback((message) => {
    setEditError("");
    setEditingId(message.id);
    setEditDraft(message.content || "");
  }, []);

  const onCancelEdit = useCallback(() => {
    setEditingId(null);
    setEditDraft("");
    setEditError("");
  }, []);

  const onSaveEdit = useCallback(async () => {
    if (!editingId) return;
    setEditError("");
    try {
      await editMessage(editingId, editDraft);
      setEditingId(null);
      setEditDraft("");
    } catch (e) {
      setEditError(e?.message || "Could not save changes.");
    }
  }, [editingId, editDraft, editMessage]);

  const onRequestDeleteForEveryone = useCallback((messageId) => {
    setConfirm({ kind: "deleteEveryone", messageId });
  }, []);

  const handleConfirm = useCallback(async () => {
    if (!confirm) return;
    if (confirm.kind === "deleteEveryone" && confirm.messageId) {
      await deleteMessageForEveryone(confirm.messageId);
    }
    setConfirm(null);
  }, [confirm, deleteMessageForEveryone]);

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
          onClick={closeChat}
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
          {activeEventThread && participantCount > 0 ? (
            <div
              className="msger-chat-participants"
              title={participantNamesTitle || undefined}
            >
              <span className="msger-chat-participants-count">
                {participantCount} member{participantCount === 1 ? "" : "s"}
              </span>
              {participantNamesTitle ? (
                <span className="msger-chat-participants-names">
                  {participantNamesTitle}
                </span>
              ) : null}
            </div>
          ) : null}
        </div>
      </div>

      <div className="msger-messages" ref={listRef}>
        {hasMore && messages.length > 0 ? (
          <button
            type="button"
            className="msger-load-more"
            onClick={() =>
              loadMessages(activeConversation?.id, messages[0]?.created_at)
            }
            disabled={loadingMore}
          >
            {loadingMore ? "Loading..." : "Load earlier"}
          </button>
        ) : null}
        {chatStatus.status === "loading" ? (
          <p className="msger-note">Loading...</p>
        ) : null}
        {chatStatus.status === "error" ? (
          <p className="msger-note msger-error">{chatStatus.error}</p>
        ) : null}
        {editError ? <p className="msger-note msger-error">{editError}</p> : null}
        {messages.map((message) => {
          const isOwn = message.sender_id === user?.id;
          let isRead = false;
          if (activeEventThread?.participants?.length) {
            const others = activeEventThread.participants.filter(
              (pid) => pid !== user?.id
            );
            isRead = others.some((pid) => (message.read_by || []).includes(pid));
          } else if (activeUser) {
            isRead = (message.read_by || []).includes(activeUser.id);
          }
          return (
            <MessageBubble
              key={message.id}
              message={message}
              isOwn={isOwn}
              isRead={isRead}
              formatTime={formatChatTime}
              resolveAttachmentUrl={resolveAttachmentUrl}
              onDeleteForMe={deleteMessageForMe}
              onRequestDeleteForEveryone={onRequestDeleteForEveryone}
              onStartEdit={onStartEdit}
              isEditing={editingId === message.id}
              editDraft={editDraft}
              onEditDraftChange={setEditDraft}
              onSaveEdit={onSaveEdit}
              onCancelEdit={onCancelEdit}
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
        disabled={!activeUser && !activeEventThread}
        onInputChange={handleInputChange}
        onSend={sendMessage}
        onFileChange={handleFiles}
        onRemoveFile={removeFile}
      />

      <MessengerConfirmDialog
        open={confirm?.kind === "deleteEveryone"}
        title="Delete for everyone?"
        message="This message will be removed for all participants in the chat."
        confirmLabel="Delete for everyone"
        cancelLabel="Cancel"
        danger
        onConfirm={handleConfirm}
        onCancel={() => setConfirm(null)}
      />
    </div>
  );
}
