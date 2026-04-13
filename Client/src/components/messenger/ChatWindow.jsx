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
    isUploading,
    typingUser,
    hasMore,
    loadingMore,
    replyingTo,
    startReply,
    clearReply,
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
    onOpenWorkflowAction,
  } = useMessenger();

  const listRef = useRef(null);
  const actionMenuRef = useRef(null);
  const [confirm, setConfirm] = useState(null);
  const [editingId, setEditingId] = useState(null);
  const [editDraft, setEditDraft] = useState("");
  const [editError, setEditError] = useState("");
  const [actionMenuOpen, setActionMenuOpen] = useState(false);

  // Close action menu on outside click
  useEffect(() => {
    if (!actionMenuOpen) return;
    function handleOutside(e) {
      if (actionMenuRef.current && !actionMenuRef.current.contains(e.target)) {
        setActionMenuOpen(false);
      }
    }
    document.addEventListener("mousedown", handleOutside);
    return () => document.removeEventListener("mousedown", handleOutside);
  }, [actionMenuOpen]);

  useEffect(() => {
    if (listRef.current) {
      listRef.current.scrollTop = listRef.current.scrollHeight;
    }
  }, [messages.length, editingId]);

  const activeName = activeEventThread
    ? activeEventThread.title || "Event chat"
    : activeUser?.name || "";

  const isWorkflowThread =
    activeConversation?.thread_kind === "approval_thread";

  const isThreadLocked =
    isWorkflowThread &&
    (activeConversation?.thread_status === "resolved" ||
      activeConversation?.thread_status === "closed");

  // For workflow threads, show dept label in sub-header
  const workflowDeptLabel = isWorkflowThread
    ? activeConversation?.department_label ||
      activeConversation?.department ||
      "Workflow Discussion"
    : null;

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
          {workflowDeptLabel ? (
            <p className="msger-chat-status msger-workflow-dept-label">{workflowDeptLabel}</p>
          ) : activeStatus ? (
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

        {isWorkflowThread && !isThreadLocked && onOpenWorkflowAction && (
          <div className="msger-wf-action-root" ref={actionMenuRef}>
            <button
              type="button"
              className={`msger-wf-action-trigger${actionMenuOpen ? " open" : ""}`}
              onClick={() => setActionMenuOpen((v) => !v)}
              aria-haspopup="true"
              aria-expanded={actionMenuOpen}
              title="Take workflow action"
            >
              <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/>
              </svg>
              Action
              <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style={{marginLeft:2}}>
                <path d="M6 9l6 6 6-6"/>
              </svg>
            </button>
            {actionMenuOpen && (
              <div className="msger-wf-action-menu" role="menu">
                <button
                  type="button"
                  role="menuitem"
                  className="msger-wf-action-item msger-wf-action-item--approve"
                  onClick={() => {
                    setActionMenuOpen(false);
                    const channel = activeConversation?.department || "registrar";
                    const requestId = activeConversation?.related_request_id || activeConversation?.approval_request_id;
                    onOpenWorkflowAction(channel, requestId, "approved", "Approve");
                  }}
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="20 6 9 17 4 12"/></svg>
                  Approve
                </button>
                <button
                  type="button"
                  role="menuitem"
                  className="msger-wf-action-item msger-wf-action-item--clarify"
                  onClick={() => {
                    setActionMenuOpen(false);
                    const channel = activeConversation?.department || "registrar";
                    const requestId = activeConversation?.related_request_id || activeConversation?.approval_request_id;
                    onOpenWorkflowAction(channel, requestId, "clarification_requested", "Need clarification");
                  }}
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10z"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>
                  Need clarification
                </button>
                <button
                  type="button"
                  role="menuitem"
                  className="msger-wf-action-item msger-wf-action-item--reject"
                  onClick={() => {
                    setActionMenuOpen(false);
                    const channel = activeConversation?.department || "registrar";
                    const requestId = activeConversation?.related_request_id || activeConversation?.approval_request_id;
                    onOpenWorkflowAction(channel, requestId, "rejected", "Reject");
                  }}
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                  Reject
                </button>
              </div>
            )}
          </div>
        )}
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
              onStartReply={isThreadLocked ? null : startReply}
            />
          );
        })}
      </div>

      {typingName ? (
        <div className="msger-typing">{typingName} is typing...</div>
      ) : null}

      {isThreadLocked ? (
        <div className="msger-thread-locked-banner" role="status">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
          <span>
            This discussion is{" "}
            {activeConversation?.thread_status === "closed" ? "closed" : "resolved"}
            {activeConversation?.closed_at
              ? ` since ${formatChatTime(activeConversation.closed_at)}`
              : ""}
            .
          </span>
        </div>
      ) : (
        <>
          {replyingTo && (
            <div className="msger-reply-bar">
              <div className="msger-reply-bar-content">
                <span className="msger-reply-bar-author">{replyingTo.senderName}</span>
                <p className="msger-reply-bar-preview">{replyingTo.contentPreview}</p>
              </div>
              <button
                type="button"
                className="msger-reply-bar-dismiss"
                aria-label="Cancel reply"
                onClick={clearReply}
              >
                ×
              </button>
            </div>
          )}
          <MessageInput
            chatInput={chatInput}
            chatFiles={chatFiles}
            disabled={!activeUser && !activeEventThread && !isWorkflowThread}
            isUploading={isUploading}
            onInputChange={handleInputChange}
            onSend={sendMessage}
            onFileChange={handleFiles}
            onRemoveFile={removeFile}
          />
        </>
      )}

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
