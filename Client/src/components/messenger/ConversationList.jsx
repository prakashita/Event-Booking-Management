import { useState, useMemo } from "react";
import ConversationItem from "./ConversationItem";

export default function ConversationList({
  chatUsers,
  chatEventThreads,
  chatActiveUser,
  chatActiveEventThread,
  chatUnreadByConversation,
  onStartConversation,
  onOpenEventThread,
}) {
  const [search, setSearch] = useState("");

  const filteredUsers = useMemo(() => {
    if (!search.trim()) return chatUsers;
    const q = search.toLowerCase();
    return chatUsers.filter((u) => (u.name || "").toLowerCase().includes(q));
  }, [chatUsers, search]);

  const filteredThreads = useMemo(() => {
    if (!search.trim()) return chatEventThreads;
    const q = search.toLowerCase();
    return chatEventThreads.filter((t) =>
      (t.title || "").toLowerCase().includes(q)
    );
  }, [chatEventThreads, search]);

  return (
    <div className="msger-convos">
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
          placeholder="Search conversations..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="msger-search-input"
        />
      </div>

      <div className="msger-convo-list">
        {filteredThreads.length > 0 ? (
          <>
            <p className="msger-section-label">Event Chats</p>
            {filteredThreads.map((thread) => {
              const tname = thread.title || "Event";
              const avatarLabel =
                tname.trim().charAt(0).toUpperCase() || "E";
              const unread = chatUnreadByConversation[thread.id] || 0;
              const n = thread.participants?.length ?? 0;
              return (
                <ConversationItem
                  key={thread.id}
                  name={tname}
                  avatarLabel={avatarLabel}
                  isActive={chatActiveEventThread?.id === thread.id}
                  isEvent
                  unread={unread}
                  meta={`${n} in chat`}
                  onClick={() => onOpenEventThread(thread)}
                />
              );
            })}
          </>
        ) : null}

        <p className="msger-section-label">People</p>
        {filteredUsers.map((chatUser) => {
          const name = chatUser.name || "Unknown";
          const avatarLabel = name.trim().charAt(0).toUpperCase() || "?";
          return (
            <ConversationItem
              key={chatUser.id}
              name={name}
              avatarLabel={avatarLabel}
              isActive={chatActiveUser?.id === chatUser.id}
              unread={chatUser.unread || 0}
              online={chatUser.online}
              onClick={() => onStartConversation(chatUser)}
            />
          );
        })}
        {filteredUsers.length === 0 ? (
          <p className="msger-note">No users found.</p>
        ) : null}
      </div>
    </div>
  );
}
