import {
  createContext,
  useContext,
  useState,
  useRef,
  useMemo,
  useCallback,
  useEffect,
} from "react";
import api from "../../services/api";
import {
  MAX_CHAT_FILE_SIZE,
  ALLOWED_CHAT_MIME_TYPES,
  UPLOAD_ERRORS,
} from "../../constants/uploadConfig";

const MessengerContext = createContext(null);

export function useMessenger() {
  return useContext(MessengerContext);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatChatTime(dateStr) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return "";
  const now = new Date();
  const diff = now - d;
  if (diff < 60_000) return "Just now";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function resolveAttachmentUrl(url) {
  if (!url) return "";
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  const base = (import.meta.env.VITE_API_BASE_URL || "http://localhost:8000").replace(/\/$/, "");
  return `${base}${url}`;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

export function MessengerProvider({ children, user }) {
  // Panel visibility
  const [panelOpen, setPanelOpen] = useState(false);
  const togglePanel = useCallback(() => setPanelOpen((v) => !v), []);
  const openPanel = useCallback(() => setPanelOpen(true), []);
  const closePanel = useCallback(() => setPanelOpen(false), []);

  // Conversations & threads
  const [conversations, setConversations] = useState([]); // all conversations from API
  const [chatUsers, setChatUsers] = useState([]);

  // Active chat state
  const [activeConversation, setActiveConversation] = useState(null); // full conversation object
  const [activeUser, setActiveUser] = useState(null); // direct-chat partner
  const [activeEventThread, setActiveEventThread] = useState(null); // event thread

  // Messages
  const [messages, setMessages] = useState([]);
  const [chatStatus, setChatStatus] = useState({ status: "idle", error: "" });
  const [hasMore, setHasMore] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);

  // Input
  const [chatInput, setChatInput] = useState("");
  const [chatFiles, setChatFiles] = useState([]);
  const [isUploading, setIsUploading] = useState(false);

  // Reply state
  const [replyingTo, setReplyingTo] = useState(null); // { messageId, senderName, contentPreview }

  // Typing
  const [typingUser, setTypingUser] = useState(null);
  const typingTimeoutRef = useRef(null);

  // Filters
  const [searchQuery, setSearchQuery] = useState("");
  const [unreadOnly, setUnreadOnly] = useState(false);
  const [filterEventId, setFilterEventId] = useState(null);

  // Debounce ref for search
  const searchDebounceRef = useRef(null);

  // WebSocket
  const wsRef = useRef(null);
  const activeConversationIdRef = useRef("");
  const activeUserIdRef = useRef(null);
  const eventConvIdsRef = useRef(new Set());
  const panelOpenRef = useRef(false);
  const closeChatRef = useRef(() => {});
  const pendingApprovalThreadRef = useRef(null);

  // Keep refs in sync
  useEffect(() => {
    activeConversationIdRef.current = activeConversation?.id || "";
  }, [activeConversation]);

  useEffect(() => {
    activeUserIdRef.current = activeUser?.id || null;
  }, [activeUser]);

  useEffect(() => {
    panelOpenRef.current = panelOpen;
  }, [panelOpen]);

  // Derived data
  const chatEventThreads = useMemo(
    () => conversations.filter((c) => c.thread_kind === "event"),
    [conversations]
  );

  const directConversations = useMemo(
    () => conversations.filter((c) => c.thread_kind === "direct"),
    [conversations]
  );

  const workflowThreads = useMemo(
    () => conversations.filter((c) => c.thread_kind === "approval_thread"),
    [conversations]
  );

  const activeWorkflowChats = useMemo(
    () => workflowThreads.filter((c) => !c.thread_status || c.thread_status === "active" || c.thread_status === "waiting_for_faculty" || c.thread_status === "waiting_for_department"),
    [workflowThreads]
  );

  const archivedWorkflowChats = useMemo(
    () => workflowThreads.filter((c) => c.thread_status === "resolved" || c.thread_status === "closed"),
    [workflowThreads]
  );

  useEffect(() => {
    eventConvIdsRef.current = new Set(chatEventThreads.map((t) => t.id));
  }, [chatEventThreads]);

  // Total unread
  const totalUnread = useMemo(() => {
    return conversations.reduce((sum, c) => sum + (c.unread_count || 0), 0);
  }, [conversations]);

  // Unread maps for backward compatibility with existing components
  const chatUnreadByConversation = useMemo(() => {
    const m = {};
    for (const c of conversations) {
      m[c.id] = c.unread_count || 0;
    }
    return m;
  }, [conversations]);

  const chatUnreadByUser = useMemo(() => {
    const m = {};
    for (const c of directConversations) {
      if (c.other_user) {
        m[c.other_user.id] = c.unread_count || 0;
      }
    }
    return m;
  }, [directConversations]);

  // ---------------------------------------------------------------------------
  // API calls
  // ---------------------------------------------------------------------------

  const loadConversations = useCallback(
    async (opts = {}) => {
      if (!user) return;
      try {
        const params = new URLSearchParams();
        const sq = opts.search ?? searchQuery;
        if (sq) params.set("search", sq);
        if (opts.unreadOnly ?? unreadOnly) params.set("unread_only", "true");
        if (opts.eventId ?? filterEventId) params.set("event_id", opts.eventId ?? filterEventId);

        const qs = params.toString();
        const data = await api.getJson(`/chat/conversations/me${qs ? `?${qs}` : ""}`);
        setConversations(Array.isArray(data) ? data : []);
      } catch {
        // silent
      }
    },
    [user, searchQuery, unreadOnly, filterEventId]
  );

  const loadChatUsers = useCallback(async () => {
    if (!user) return;
    try {
      const data = await api.getJson("/chat/users");
      if (Array.isArray(data)) {
        setChatUsers(data);
      }
    } catch {
      // silent
    }
  }, [user]);

  const loadMessages = useCallback(
    async (conversationId, before) => {
      if (!conversationId) return;
      if (before) {
        setLoadingMore(true);
      } else {
        setChatStatus({ status: "loading", error: "" });
      }
      try {
        const params = new URLSearchParams({ limit: "50" });
        if (before) params.set("before", before);
        const data = await api.getJson(
          `/chat/conversations/${conversationId}/messages?${params.toString()}`
        );
        const msgs = Array.isArray(data) ? data : [];
        setMessages((prev) => (before ? [...msgs, ...prev] : msgs));
        setHasMore(msgs.length >= 50);
        setChatStatus({ status: "ready", error: "" });
      } catch (err) {
        setChatStatus({
          status: "error",
          error: err?.message || "Unable to load messages.",
        });
      } finally {
        setLoadingMore(false);
      }
    },
    []
  );

  const markConversationRead = useCallback(
    async (conversationId) => {
      if (!conversationId) return;
      try {
        await api.post(`/chat/read/${conversationId}`);
      } catch {
        // silent
      }
      // Locally zero-out unread for this conversation
      setConversations((prev) =>
        prev.map((c) => (c.id === conversationId ? { ...c, unread_count: 0 } : c))
      );
    },
    []
  );

  // ---------------------------------------------------------------------------
  // Conversation selection
  // ---------------------------------------------------------------------------

  const openEventThread = useCallback(
    async (thread) => {
      if (!thread?.id) return;
      setActiveUser(null);
      setActiveEventThread(thread);
      setActiveConversation(thread);
      setTypingUser(null);
      setMessages([]);
      setHasMore(true);
      setLoadingMore(false);
      setChatStatus({ status: "loading", error: "" });
      await loadMessages(thread.id);
      await markConversationRead(thread.id);
    },
    [loadMessages, markConversationRead]
  );

  const openMessengerForApprovalReply = useCallback(
    async ({ eventId, commentId, excerpt }) => {
      const shortRef = commentId ? String(commentId).slice(-8) : "";
      const line =
        excerpt && String(excerpt).trim() ? String(excerpt).trim().slice(0, 280) : "";
      const pre = `Regarding clarification${shortRef ? ` […${shortRef}]` : ""}${line ? `: ${line}` : ""}`;
      setChatInput(pre);
      openPanel();
      if (eventId) {
        pendingApprovalThreadRef.current = { eventId: String(eventId) };
        setFilterEventId(String(eventId));
        await loadConversations({ eventId: String(eventId) });
      } else {
        pendingApprovalThreadRef.current = null;
      }
    },
    [openPanel, loadConversations]
  );

  const openApprovalThread = useCallback(
    async (conversationId) => {
      if (!conversationId) return;
      openPanel();
      setChatInput("");
      try {
        // First, try to find the conversation in already-loaded list
        let conv = conversations.find((c) => String(c.id) === String(conversationId));
        if (!conv) {
          // Refresh conversations and search again
          const convData = await api.getJson("/chat/conversations/me");
          if (Array.isArray(convData)) {
            setConversations(convData);
            conv = convData.find((c) => String(c.id) === String(conversationId));
          }
        }
        if (conv) {
          setActiveConversation(conv);
          setActiveEventThread(null);
          setActiveUser(null);
          setTypingUser(null);
          setMessages([]);
          setHasMore(true);
          setLoadingMore(false);
          setChatStatus({ status: "loading", error: "" });
          await loadMessages(conversationId);
          await markConversationRead(conversationId);
        }
      } catch {
        // silently fail — user can navigate manually
      }
    },
    [openPanel, conversations, loadMessages, markConversationRead]
  );

  useEffect(() => {
    const pending = pendingApprovalThreadRef.current;
    if (!pending?.eventId) return;
    const thread = conversations.find(
      (c) => c.thread_kind === "event" && String(c.event_id || "") === String(pending.eventId)
    );
    if (thread) {
      pendingApprovalThreadRef.current = null;
      openEventThread(thread);
    }
  }, [conversations, openEventThread]);

  const startConversation = useCallback(
    async (targetUser) => {
      if (!targetUser) return;
      setActiveEventThread(null);
      setActiveUser(targetUser);
      setTypingUser(null);
      setMessages([]);
      setHasMore(true);
      setLoadingMore(false);
      setChatStatus({ status: "loading", error: "" });
      try {
        const data = await api.postJson("/chat/conversations", {
          user_id: targetUser.id,
        });
        if (data?.id) {
          setActiveConversation({
            ...data,
            participant_count: 2,
            participants_preview: [
              { id: user.id, name: user.name || "You" },
              { id: targetUser.id, name: targetUser.name || "Unknown" },
            ],
          });
          await loadMessages(data.id);
          await markConversationRead(data.id);
        }
      } catch (err) {
        setChatStatus({
          status: "error",
          error: err?.message || "Unable to start conversation.",
        });
      }
    },
    [loadMessages, markConversationRead, user]
  );

  const openConversation = useCallback(
    async (conv) => {
      if (!conv?.id) return;
      if (conv.thread_kind === "event") {
        await openEventThread(conv);
      } else if (conv.other_user) {
        await startConversation(conv.other_user);
      } else {
        // Fallback: open as generic conversation
        setActiveEventThread(null);
        setActiveUser(null);
        setActiveConversation(conv);
        setTypingUser(null);
        setMessages([]);
        setHasMore(true);
        setChatStatus({ status: "loading", error: "" });
        await loadMessages(conv.id);
        await markConversationRead(conv.id);
      }
    },
    [openEventThread, startConversation, loadMessages, markConversationRead]
  );

  const startReply = useCallback((msg) => {
    if (!msg) return;
    setReplyingTo({
      messageId: msg.id,
      senderName: msg.sender_name || "Unknown",
      contentPreview: (msg.content || "").slice(0, 200),
    });
  }, []);

  const clearReply = useCallback(() => setReplyingTo(null), []);

  const closeChat = useCallback(() => {
    setActiveUser(null);
    setActiveEventThread(null);
    setActiveConversation(null);
    setMessages([]);
    setTypingUser(null);
    setReplyingTo(null);
  }, []);

  useEffect(() => {
    closeChatRef.current = closeChat;
  }, [closeChat]);

  // ---------------------------------------------------------------------------
  // Send message
  // ---------------------------------------------------------------------------

  const uploadAttachment = useCallback(async (file) => {
    const formData = new FormData();
    formData.append("file", file);
    const res = await api.post("/chat/upload", formData);
    if (!res.ok) {
      let message = UPLOAD_ERRORS.UPLOAD_FAILED;
      try {
        const data = await res.json();
        if (typeof data?.message === "string") message = data.message;
        else if (typeof data?.detail === "string") message = data.detail;
      } catch {
        // use default
      }
      throw new Error(message);
    }
    const data = await res.json().catch(() => null);
    return data?.attachment;
  }, []);

  const sendMessage = useCallback(async () => {
    const trimmed = chatInput.trim();
    if (!trimmed && chatFiles.length === 0) return;
    if (!activeConversation?.id) {
      setChatStatus({ status: "error", error: "Select a chat to message." });
      return;
    }

    // Prevent double-submission
    if (isUploading) return;

    const clientId =
      typeof crypto !== "undefined" && crypto.randomUUID
        ? crypto.randomUUID()
        : `${Date.now()}-${Math.random().toString(16).slice(2)}`;

    try {
      if (chatFiles.length > 0) setIsUploading(true);
      const attachments =
        chatFiles.length > 0
          ? (await Promise.all(chatFiles.map(uploadAttachment))).filter(Boolean)
          : [];
      setIsUploading(false);

      // Optimistic UI
      const optimistic = {
        id: `client-${clientId}`,
        client_id: clientId,
        conversation_id: activeConversation.id,
        sender_id: user.id,
        sender_name: user.name,
        sender_email: user.email,
        content: trimmed,
        attachments,
        read_by: [user.id],
        created_at: new Date().toISOString(),
        is_deleted: false,
        deleted_for_everyone: false,
      };
      setMessages((prev) => [...prev, optimistic]);

      // Capture reply ref before clearing state
      const replyRef = replyingTo;

      // Try WebSocket first, fallback to REST
      const ws = wsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(
          JSON.stringify({
            type: "message",
            text: trimmed,
            attachments,
            conversation_id: activeConversation.id,
            client_id: clientId,
            reply_to_message_id: replyRef?.messageId || undefined,
          })
        );
      } else {
        await api.postJson("/chat/messages", {
          conversation_id: activeConversation.id,
          content: trimmed,
          attachments,
          reply_to_message_id: replyRef?.messageId || undefined,
        });
      }

      setChatInput("");
      setChatFiles([]);
      setReplyingTo(null);

      // Stop typing indicator
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(
          JSON.stringify({
            type: "typing",
            is_typing: false,
            conversation_id: activeConversation.id,
          })
        );
      }
    } catch (err) {
      setIsUploading(false);
      setChatStatus({
        status: "error",
        error: err?.message || UPLOAD_ERRORS.UPLOAD_FAILED,
      });
    }
  }, [activeConversation, chatInput, chatFiles, uploadAttachment, user, isUploading, replyingTo]);

  // ---------------------------------------------------------------------------
  // Message actions
  // ---------------------------------------------------------------------------

  const deleteMessageForEveryone = useCallback(async (messageId) => {
    if (!messageId) return;
    try {
      const res = await api.delete(`/chat/message/${messageId}`);
      if (res.ok) {
        setMessages((prev) =>
          prev.map((m) =>
            m.id === messageId
              ? {
                  ...m,
                  is_deleted: true,
                  deleted_for_everyone: true,
                  content: "This message was deleted",
                  attachments: [],
                  edited: false,
                  edited_at: null,
                }
              : m
          )
        );
      }
    } catch {
      // silent
    }
  }, []);

  const deleteMessageForMe = useCallback(async (messageId) => {
    if (!messageId) return;
    try {
      const res = await api.post(`/chat/message/${messageId}/delete-for-me`);
      if (res.ok) {
        setMessages((prev) => prev.filter((m) => m.id !== messageId));
      }
    } catch {
      // silent
    }
  }, []);

  const editMessage = useCallback(async (messageId, content) => {
    const trimmed = (content || "").trim();
    if (!messageId || !trimmed) return;
    const data = await api.patchJson(`/chat/message/${messageId}`, { content: trimmed });
    if (data?.id) {
      setMessages((prev) => prev.map((m) => (m.id === messageId ? { ...m, ...data } : m)));
    }
  }, []);

  // ---------------------------------------------------------------------------
  // Conversation actions
  // ---------------------------------------------------------------------------

  const hideConversation = useCallback(
    async (conversationId) => {
      if (!conversationId) return;
      try {
        const res = await api.delete(`/chat/conversation/${conversationId}`);
        if (res.ok) {
          setConversations((prev) => prev.filter((c) => c.id !== conversationId));
          if (activeConversation?.id === conversationId) {
            closeChat();
          }
        }
      } catch {
        // silent
      }
    },
    [activeConversation, closeChat]
  );

  const clearConversationMessages = useCallback(
    async (conversationId) => {
      if (!conversationId) return false;
      try {
        const res = await api.post(`/chat/conversations/${conversationId}/clear`);
        if (!res.ok) return false;
        if (activeConversation?.id === conversationId) {
          setMessages([]);
        }
        setConversations((prev) =>
          prev.map((c) =>
            c.id === conversationId ? { ...c, last_message: null, unread_count: 0 } : c
          )
        );
        return true;
      } catch {
        return false;
      }
    },
    [activeConversation]
  );

  const purgeConversation = useCallback(
    async (conversationId) => {
      if (!conversationId) return false;
      try {
        const res = await api.post(`/chat/conversations/${conversationId}/purge`);
        if (!res.ok) return false;
        setConversations((prev) => prev.filter((c) => c.id !== conversationId));
        if (activeConversation?.id === conversationId) {
          closeChat();
        }
        return true;
      } catch {
        return false;
      }
    },
    [activeConversation, closeChat]
  );

  // ---------------------------------------------------------------------------
  // Input handlers
  // ---------------------------------------------------------------------------

  const handleInputChange = useCallback(
    (e) => {
      const val = e.target.value;
      setChatInput(val);
      const ws = wsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN && activeConversation?.id) {
        ws.send(
          JSON.stringify({
            type: "typing",
            is_typing: true,
            conversation_id: activeConversation.id,
          })
        );
      }
      if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
      typingTimeoutRef.current = setTimeout(() => {
        const active = wsRef.current;
        if (active && active.readyState === WebSocket.OPEN && activeConversation?.id) {
          active.send(
            JSON.stringify({
              type: "typing",
              is_typing: false,
              conversation_id: activeConversation.id,
            })
          );
        }
      }, 1500);
    },
    [activeConversation]
  );

  const handleFiles = useCallback((e) => {
    const next = Array.from(e.target.files || []);
    e.target.value = "";
    if (!next.length) return;

    for (const file of next) {
      if (file.size > MAX_CHAT_FILE_SIZE) {
        setChatStatus({ status: "error", error: UPLOAD_ERRORS.FILE_TOO_LARGE });
        return;
      }
      if (!ALLOWED_CHAT_MIME_TYPES.has(file.type)) {
        setChatStatus({ status: "error", error: UPLOAD_ERRORS.UNSUPPORTED_TYPE });
        return;
      }
    }

    setChatFiles((prev) => [...prev, ...next]);
  }, []);

  const removeFile = useCallback((idx) => {
    setChatFiles((prev) => prev.filter((_, i) => i !== idx));
  }, []);

  // ---------------------------------------------------------------------------
  // Search debounce
  // ---------------------------------------------------------------------------

  const setSearch = useCallback(
    (q) => {
      setSearchQuery(q);
      if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
      searchDebounceRef.current = setTimeout(() => {
        loadConversations({ search: q });
      }, 350);
    },
    [loadConversations]
  );

  const toggleUnreadOnly = useCallback(() => {
    setUnreadOnly((prev) => {
      const next = !prev;
      loadConversations({ unreadOnly: next });
      return next;
    });
  }, [loadConversations]);

  // ---------------------------------------------------------------------------
  // WebSocket setup
  // ---------------------------------------------------------------------------

  useEffect(() => {
    if (!user) {
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      }
      setConversations([]);
      setChatUsers([]);
      setMessages([]);
      setActiveUser(null);
      setActiveEventThread(null);
      setActiveConversation(null);
      setChatStatus({ status: "idle", error: "" });
      setTypingUser(null);
      return;
    }

    // Initial data load
    loadConversations();
    loadChatUsers();

    const token = localStorage.getItem("auth_token");
    if (!token) return;

    const base = (import.meta.env.VITE_API_BASE_URL || "http://localhost:8000").replace(/\/$/, "");
    const wsBase = `${base.replace(/^http/, "ws")}/api/v1`;
    const ws = new WebSocket(`${wsBase}/chat/ws?token=${token}`);
    wsRef.current = ws;

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        if (data.type === "message" && data.message) {
          const incoming = data.message;
          const activeCid = activeConversationIdRef.current;

          if (incoming.conversation_id === activeCid) {
            if (incoming.client_id) {
              setMessages((prev) => {
                const hasMatch = prev.some((m) => m.client_id === incoming.client_id);
                return hasMatch
                  ? prev.map((m) => (m.client_id === incoming.client_id ? incoming : m))
                  : [...prev, incoming];
              });
            } else {
              setMessages((prev) => [...prev, incoming]);
            }
          } else {
            // Update unread in conversation list
            setConversations((prev) =>
              prev.map((c) =>
                c.id === incoming.conversation_id
                  ? {
                      ...c,
                      unread_count: (c.unread_count || 0) + 1,
                      last_message: {
                        text: (incoming.content || "").slice(0, 120),
                        sender_id: incoming.sender_id,
                        sender_name: incoming.sender_name,
                        created_at: incoming.created_at,
                        message_id: incoming.id,
                      },
                    }
                  : c
              )
            );
          }

          if (incoming.sender_id && incoming.sender_id !== user?.id) {
            const notify =
              typeof Notification !== "undefined" && Notification.permission === "granted";
            if (notify && (document.hidden || !panelOpenRef.current)) {
              try {
                const body =
                  (incoming.content && String(incoming.content).slice(0, 120)) ||
                  (incoming.attachments?.length ? "Sent an attachment" : "New message");
                new Notification(incoming.sender_name || "New message", {
                  body,
                  tag: `chat-${incoming.conversation_id}`,
                });
              } catch {
                // ignore
              }
            }
          }
          return;
        }

        if (data.type === "typing") {
          if (data.conversation_id !== activeConversationIdRef.current) return;
          setTypingUser(data.is_typing ? { id: data.user_id, name: data.user_name } : null);
          return;
        }

        if (data.type === "read" && data.message_ids) {
          setMessages((prev) =>
            prev.map((m) => {
              if (!data.message_ids.includes(m.id)) return m;
              if (m.read_by?.includes(data.user_id)) return m;
              return { ...m, read_by: [...(m.read_by || []), data.user_id] };
            })
          );
          return;
        }

        if (data.type === "read_conversation") {
          // Another user read the entire conversation
          if (data.conversation_id === activeConversationIdRef.current && data.user_id) {
            setMessages((prev) =>
              prev.map((m) => {
                if (m.read_by?.includes(data.user_id)) return m;
                return { ...m, read_by: [...(m.read_by || []), data.user_id] };
              })
            );
          }
          return;
        }

        if (data.type === "message_deleted") {
          if (data.conversation_id === activeConversationIdRef.current) {
            if (data.message) {
              setMessages((prev) =>
                prev.map((m) => (m.id === data.message_id ? { ...m, ...data.message } : m))
              );
            } else {
              setMessages((prev) =>
                prev.map((m) =>
                  m.id === data.message_id
                    ? {
                        ...m,
                        is_deleted: true,
                        deleted_for_everyone: true,
                        content: "This message was deleted",
                        attachments: [],
                        edited: false,
                        edited_at: null,
                      }
                    : m
                )
              );
            }
          }
          setConversations((prev) =>
            prev.map((c) => {
              if (c.id !== data.conversation_id) return c;
              const lm = c.last_message || {};
              if (lm.message_id === data.message_id || (!lm.message_id && data.message)) {
                return {
                  ...c,
                  last_message: data.message
                    ? {
                        text: (data.message.content || "").slice(0, 120),
                        sender_id: data.message.sender_id,
                        sender_name: data.message.sender_name,
                        created_at: data.message.created_at,
                        message_id: data.message_id,
                      }
                    : { ...lm, text: "This message was deleted" },
                };
              }
              return c;
            })
          );
          return;
        }

        if (data.type === "message_edited" && data.message) {
          const inc = data.message;
          if (inc.conversation_id === activeConversationIdRef.current) {
            setMessages((prev) => prev.map((m) => (m.id === inc.id ? { ...m, ...inc } : m)));
          }
          setConversations((prev) =>
            prev.map((c) => {
              if (c.id !== inc.conversation_id) return c;
              const lm = c.last_message || {};
              if (lm.message_id === inc.id) {
                return {
                  ...c,
                  last_message: {
                    ...lm,
                    text: (inc.content || "").slice(0, 120),
                    sender_name: inc.sender_name,
                  },
                };
              }
              return c;
            })
          );
          return;
        }

        if (data.type === "message_hidden") {
          if (
            data.conversation_id === activeConversationIdRef.current &&
            data.message_id
          ) {
            setMessages((prev) => prev.filter((m) => m.id !== data.message_id));
          }
          return;
        }

        if (data.type === "conversation_cleared") {
          if (data.conversation_id === activeConversationIdRef.current) {
            setMessages([]);
          }
          setConversations((prev) =>
            prev.map((c) =>
              c.id === data.conversation_id
                ? { ...c, last_message: null, unread_count: 0 }
                : c
            )
          );
          return;
        }

        if (data.type === "conversation_deleted") {
          setConversations((prev) => prev.filter((c) => c.id !== data.conversation_id));
          if (data.conversation_id === activeConversationIdRef.current) {
            closeChatRef.current();
          }
          return;
        }

        if (data.type === "presence") {
          setChatUsers((prev) =>
            prev.map((u) =>
              u.id === data.user_id
                ? { ...u, online: data.online, last_seen: data.last_seen }
                : u
            )
          );
          setActiveUser((prev) =>
            prev && prev.id === data.user_id
              ? { ...prev, online: data.online, last_seen: data.last_seen }
              : prev
          );
        }
      } catch {
        // Ignore malformed payloads
      }
    };

    return () => {
      ws.close();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user]);

  // Auto-send read receipts when messages change
  useEffect(() => {
    if (!user || messages.length === 0 || !activeConversation?.id) return;
    const unread = messages
      .filter((m) => m.sender_id !== user.id && !(m.read_by || []).includes(user.id))
      .map((m) => m.id);
    if (unread.length) {
      // Use WS if open, else REST fallback
      const ws = wsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: "read", message_ids: unread }));
      } else {
        api.post("/chat/read", JSON.stringify({ message_ids: unread }), {
          headers: { "Content-Type": "application/json" },
        }).catch(() => {});
      }
    }
  }, [messages, activeConversation, user]);

  // Sync active user with chatUsers changes (presence updates)
  useEffect(() => {
    if (!activeUser) return;
    const updated = chatUsers.find((u) => u.id === activeUser.id);
    if (updated && (updated.online !== activeUser.online || updated.last_seen !== activeUser.last_seen)) {
      setActiveUser(updated);
    }
  }, [chatUsers, activeUser]);

  // ---------------------------------------------------------------------------
  // Context value
  // ---------------------------------------------------------------------------

  const value = useMemo(
    () => ({
      // Panel
      panelOpen,
      togglePanel,
      openPanel,
      closePanel,

      // Data
      conversations,
      chatUsers,
      chatEventThreads,
      directConversations,
      workflowThreads,
      activeWorkflowChats,
      archivedWorkflowChats,
      totalUnread,
      chatUnreadByUser,
      chatUnreadByConversation,

      // Active state
      activeConversation,
      activeUser,
      activeEventThread,
      messages,
      chatStatus,
      hasMore,
      loadingMore,
      typingUser,

      // Input
      chatInput,
      chatFiles,
      isUploading,

      // Reply state
      replyingTo,
      startReply,
      clearReply,

      // Filters
      searchQuery,
      unreadOnly,
      filterEventId,
      setSearch,
      toggleUnreadOnly,
      setFilterEventId,

      // Actions
      loadConversations,
      loadChatUsers,
      loadMessages,
      openConversation,
      openEventThread,
      openMessengerForApprovalReply,
      openApprovalThread,
      startConversation,
      closeChat,
      sendMessage,
      deleteMessageForEveryone,
      deleteMessageForMe,
      deleteMessage: deleteMessageForEveryone,
      editMessage,
      hideConversation,
      deleteConversation: hideConversation,
      clearConversationMessages,
      purgeConversation,
      markConversationRead,
      handleInputChange,
      handleFiles,
      removeFile,

      // Utilities
      formatChatTime,
      resolveAttachmentUrl,

      // For backward compat with App.jsx
      user,
    }),
    [
      panelOpen,
      togglePanel,
      openPanel,
      closePanel,
      conversations,
      chatUsers,
      chatEventThreads,
      directConversations,
      workflowThreads,
      activeWorkflowChats,
      archivedWorkflowChats,
      totalUnread,
      chatUnreadByUser,
      chatUnreadByConversation,
      activeConversation,
      activeUser,
      activeEventThread,
      messages,
      chatStatus,
      hasMore,
      loadingMore,
      typingUser,
      chatInput,
      chatFiles,
      isUploading,
      replyingTo,
      startReply,
      clearReply,
      searchQuery,
      unreadOnly,
      filterEventId,
      setSearch,
      toggleUnreadOnly,
      setFilterEventId,
      loadConversations,
      loadChatUsers,
      loadMessages,
      openConversation,
      openEventThread,
      openMessengerForApprovalReply,
      openApprovalThread,
      startConversation,
      closeChat,
      sendMessage,
      deleteMessageForEveryone,
      deleteMessageForMe,
      editMessage,
      hideConversation,
      clearConversationMessages,
      purgeConversation,
      markConversationRead,
      handleInputChange,
      handleFiles,
      removeFile,
      user,
    ]
  );

  return (
    <MessengerContext.Provider value={value}>{children}</MessengerContext.Provider>
  );
}

export default MessengerContext;
