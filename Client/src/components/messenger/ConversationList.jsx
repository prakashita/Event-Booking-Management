import { useState, useMemo } from "react";
import { useMessenger } from "./MessengerContext";
import ConversationItem from "./ConversationItem";
import MessengerConfirmDialog from "./MessengerConfirmDialog";

export default function ConversationList() {
  const {
    conversations,
    chatUsers,
    chatEventThreads,
    activeWorkflowChats,
    archivedWorkflowChats,
    chatUnreadByConversation,
    activeUser,
    activeEventThread,
    activeConversation,
    searchQuery,
    unreadOnly,
    setSearch,
    toggleUnreadOnly,
    startConversation,
    openEventThread,
    openConversation,
    openApprovalThread,
    clearConversationMessages,
    purgeConversation,
    formatChatTime,
  } = useMessenger();

  const [actionDialog, setActionDialog] = useState(null);

  // Tabs: "messages" | "workflow" | "people"
  const [tab, setTab] = useState("messages");

  // People-tab local search (doesn't hit API)
  const [peopleSearch, setPeopleSearch] = useState("");

  const filteredUsers = useMemo(() => {
    if (!peopleSearch.trim()) return chatUsers;
    const q = peopleSearch.toLowerCase();
    return chatUsers.filter((u) => (u.name || "").toLowerCase().includes(q));
  }, [chatUsers, peopleSearch]);

  // Unread counts per tab for badges
  const directConvs = conversations.filter((c) => c.thread_kind === "direct");
  const messagesUnread = chatEventThreads.reduce(
    (acc, t) => acc + (chatUnreadByConversation[t.id] || 0),
    0
  ) + directConvs.reduce((acc, c) => acc + (c.unread_count || 0), 0);
  const workflowUnread = activeWorkflowChats.reduce(
    (acc, c) => acc + (c.unread_count || 0),
    0
  );

  return (
    <div className="msger-convos">
      {/* Search bar */}
      <div className="msger-search">
        <svg
          width="16"
          height="16"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <circle cx="11" cy="11" r="8" />
          <path d="M21 21l-4.35-4.35" />
        </svg>
        <input
          type="text"
          placeholder={tab === "people" ? "Search people..." : "Search conversations..."}
          value={tab === "people" ? peopleSearch : searchQuery}
          onChange={(e) =>
            tab === "people"
              ? setPeopleSearch(e.target.value)
              : setSearch(e.target.value)
          }
          className="msger-search-input"
        />
      </div>

      {/* Filter bar — Tabs: Messages | Workflow | People */}
      <div className="msger-filters">
        <button
          type="button"
          className={`msger-filter-tab${tab === "messages" ? " active" : ""}`}
          onClick={() => setTab("messages")}
        >
          Chats
          {messagesUnread > 0 && (
            <span className="msger-filter-count">{messagesUnread > 99 ? "99+" : messagesUnread}</span>
          )}
        </button>
        <button
          type="button"
          className={`msger-filter-tab${tab === "workflow" ? " active" : ""}`}
          onClick={() => setTab("workflow")}
        >
          Workflow
          {workflowUnread > 0 && (
            <span className="msger-filter-count">{workflowUnread > 99 ? "99+" : workflowUnread}</span>
          )}
        </button>
        <button
          type="button"
          className={`msger-filter-tab${tab === "people" ? " active" : ""}`}
          onClick={() => setTab("people")}
        >
          People
        </button>
        {tab === "messages" && (
          <button
            type="button"
            className={`msger-filter-btn${unreadOnly ? " active" : ""}`}
            onClick={toggleUnreadOnly}
            title="Show unread only"
          >
            Unread
          </button>
        )}
      </div>

      <div className="msger-convo-list">
        {tab === "messages" ? (
          <>
            {conversations.length === 0 ? (
              <p className="msger-note">
                {searchQuery || unreadOnly
                  ? "No matching conversations."
                  : "No conversations yet."}
              </p>
            ) : null}

            {/* Event threads first, then direct */}
            {chatEventThreads.length > 0 ? (
              <>
                <p className="msger-section-label">Event Chats</p>
                {chatEventThreads.map((thread) => {
                  const tname = thread.title || "Event";
                  const avatarLabel = tname.trim().charAt(0).toUpperCase() || "E";
                  const unread = chatUnreadByConversation[thread.id] || 0;
                  const n =
                    thread.participant_count ??
                    thread.participants?.length ??
                    0;
                  const namesTitle = (thread.participants_preview || [])
                    .map((p) => p.name)
                    .filter(Boolean)
                    .join(", ");
                  const lm = thread.last_message;
                  const meta = lm
                    ? `${lm.sender_name || ""}: ${(lm.text || "").slice(0, 40)}`
                    : "No messages yet";
                  return (
                    <ConversationItem
                      key={thread.id}
                      name={tname}
                      avatarLabel={avatarLabel}
                      isActive={activeEventThread?.id === thread.id}
                      isEvent
                      unread={unread}
                      memberCountLabel={n > 0 ? `${n} member${n === 1 ? "" : "s"}` : ""}
                      participantNamesTitle={namesTitle}
                      meta={meta}
                      time={lm?.created_at ? formatChatTime(lm.created_at) : ""}
                      onClick={() => openEventThread(thread)}
                      onClearChat={() =>
                        setActionDialog({
                          kind: "clear",
                          id: thread.id,
                          name: tname,
                        })
                      }
                      onPurgeChat={() =>
                        setActionDialog({
                          kind: "purge",
                          id: thread.id,
                          name: tname,
                        })
                      }
                    />
                  );
                })}
              </>
            ) : null}

            {directConvs.length > 0 ? (
              <>
                <p className="msger-section-label">Direct Messages</p>
                {directConvs.map((conv) => {
                    const ou = conv.other_user;
                    const name = ou?.name || "Unknown";
                    const avatarLabel = name.trim().charAt(0).toUpperCase() || "?";
                    const unread = conv.unread_count || 0;
                    const lm = conv.last_message;
                    const meta = lm ? (lm.text || "").slice(0, 50) : "";
                    const dmtitle = (conv.participants_preview || [])
                      .map((p) => p.name)
                      .filter(Boolean)
                      .join(", ");
                    return (
                      <ConversationItem
                        key={conv.id}
                        name={name}
                        avatarLabel={avatarLabel}
                        isActive={activeUser?.id === ou?.id}
                        unread={unread}
                        online={ou?.online}
                        participantNamesTitle={dmtitle || ou?.name}
                        meta={meta}
                        time={lm?.created_at ? formatChatTime(lm.created_at) : ""}
                        onClick={() => openConversation(conv)}
                        onClearChat={() =>
                          setActionDialog({
                            kind: "clear",
                            id: conv.id,
                            name,
                          })
                        }
                        onPurgeChat={() =>
                          setActionDialog({
                            kind: "purge",
                            id: conv.id,
                            name,
                          })
                        }
                      />
                    );
                  })}
              </>
            ) : null}

            {chatEventThreads.length === 0 && directConvs.length === 0 && (
              <p className="msger-note">No chats yet.</p>
            )}
          </>
        ) : tab === "workflow" ? (
          <>
            {activeWorkflowChats.length > 0 ? (
              <>
                <p className="msger-section-label">Active Discussions</p>
                {activeWorkflowChats.map((conv) => {
                  const deptLabel = conv.department_label || conv.department || "Discussion";
                  const name = conv.event_title || `Event Discussion`;
                  const avatarLabel = deptLabel.trim().charAt(0).toUpperCase() || "W";
                  const unread = conv.unread_count || 0;
                  const lm = conv.last_message;
                  const meta = lm ? (lm.text || "").slice(0, 50) : "";
                  return (
                    <ConversationItem
                      key={conv.id}
                      name={name}
                      avatarLabel={avatarLabel}
                      isActive={activeConversation?.id === conv.id}
                      isWorkflow
                      isLocked={false}
                      workflowLabel={deptLabel}
                      unread={unread}
                      meta={meta}
                      time={lm?.created_at ? formatChatTime(lm.created_at) : ""}
                      onClick={() => openApprovalThread(conv.id)}
                    />
                  );
                })}
              </>
            ) : null}

            {archivedWorkflowChats.length > 0 ? (
              <>
                <p className="msger-section-label msger-section-label--muted">Archived Discussions</p>
                {archivedWorkflowChats.map((conv) => {
                  const deptLabel = conv.department_label || conv.department || "Discussion";
                  const name = conv.event_title || `Event Discussion`;
                  const avatarLabel = deptLabel.trim().charAt(0).toUpperCase() || "W";
                  const lm = conv.last_message;
                  const meta = lm ? (lm.text || "").slice(0, 50) : "";
                  return (
                    <ConversationItem
                      key={conv.id}
                      name={name}
                      avatarLabel={avatarLabel}
                      isActive={activeConversation?.id === conv.id}
                      isWorkflow
                      isLocked
                      workflowLabel={deptLabel}
                      unread={0}
                      meta={meta}
                      time={lm?.created_at ? formatChatTime(lm.created_at) : ""}
                      onClick={() => openApprovalThread(conv.id)}
                    />
                  );
                })}
              </>
            ) : null}

            {activeWorkflowChats.length === 0 && archivedWorkflowChats.length === 0 && (
              <p className="msger-note">No workflow discussions.</p>
            )}
          </>
        ) : (
          <>
            <p className="msger-section-label">People</p>
            {filteredUsers.map((chatUser) => {
              const name = chatUser.name || "Unknown";
              const avatarLabel = name.trim().charAt(0).toUpperCase() || "?";
              return (
                <ConversationItem
                  key={chatUser.id}
                  name={name}
                  avatarLabel={avatarLabel}
                  isActive={activeUser?.id === chatUser.id}
                  unread={chatUser.unread || 0}
                  online={chatUser.online}
                  onClick={() => startConversation(chatUser)}
                />
              );
            })}
            {filteredUsers.length === 0 ? (
              <p className="msger-note">No users found.</p>
            ) : null}
          </>
        )}
      </div>

      <MessengerConfirmDialog
        open={actionDialog?.kind === "clear"}
        title="Clear this chat?"
        message={`Are you sure you want to clear "${actionDialog?.name || "this chat"}"? Messages will be removed for all participants, but the conversation will stay open.`}
        confirmLabel="Clear chat"
        cancelLabel="Cancel"
        danger
        onConfirm={async () => {
          if (actionDialog?.id) await clearConversationMessages(actionDialog.id);
          setActionDialog(null);
        }}
        onCancel={() => setActionDialog(null)}
      />
      <MessengerConfirmDialog
        open={actionDialog?.kind === "purge"}
        title="Delete this chat?"
        message={`Are you sure you want to delete "${actionDialog?.name || "this chat"}"? The conversation and all messages will be permanently removed for everyone.`}
        confirmLabel="Delete chat"
        cancelLabel="Cancel"
        danger
        onConfirm={async () => {
          if (actionDialog?.id) await purgeConversation(actionDialog.id);
          setActionDialog(null);
        }}
        onCancel={() => setActionDialog(null)}
      />
    </div>
  );
}
