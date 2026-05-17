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

const IST_LOCALE_OPTS = { timeZone: "Asia/Kolkata" };

function formatChatTime(dateStr) {
  if (!dateStr) return "";
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return "";
  const now = new Date();
  const diff = now - d;
  if (diff < 60_000) return "Just now";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  return d.toLocaleDateString("en-IN", { ...IST_LOCALE_OPTS, month: "short", day: "numeric" });
}

function resolveAttachmentUrl(url) {
  if (!url) return "";
  if (url.startsWith("http://") || url.startsWith("https://")) return url;
  const base = (import.meta.env.VITE_API_BASE_URL || "http://localhost:8000").replace(/\/$/, "");
  return `${base}${url}`;
}

function sortConvsByActivity(convs) {
  return [...convs].sort((a, b) => {
    const ta = new Date(a.last_message?.created_at || a.updated_at || 0).getTime();
    const tb = new Date(b.last_message?.created_at || b.updated_at || 0).getTime();
    return tb - ta;
  });
}

function getMessagePreview(message) {
  const text = (message?.content || "").trim();
  if (text) return text.slice(0, 120);
  const attachments = message?.attachments || [];
  if (attachments.length > 1) return `${attachments.length} attachments`;
  if (attachments.length === 1) {
    const [attachment] = attachments;
    if (attachment?.content_type?.startsWith("image/")) return "Sent an image";
    return attachment?.name ? `Sent ${attachment.name}` : "Sent an attachment";
  }
  return "New message";
}

function mergeMessagesByIdentity(currentMessages, incomingMessages) {
  const merged = [...currentMessages];
  for (const incoming of incomingMessages) {
    const idx = merged.findIndex(
      (existing) =>
        existing.id === incoming.id ||
        (incoming.client_id && existing.client_id === incoming.client_id)
    );
    if (idx >= 0) {
      merged[idx] = { ...merged[idx], ...incoming };
    } else {
      merged.push(incoming);
    }
  }
  return merged.sort(
    (a, b) => new Date(a.created_at || 0).getTime() - new Date(b.created_at || 0).getTime()
  );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

export function MessengerProvider({ children, user, onOpenWorkflowAction }) {
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

  // Stable refs for filter state (prevents loadConversations from being recreated on keystroke)
  const searchQueryRef = useRef(searchQuery);
  const unreadOnlyRef = useRef(unreadOnly);
  const filterEventIdRef = useRef(filterEventId);
  useEffect(() => { searchQueryRef.current = searchQuery; }, [searchQuery]);
  useEffect(() => { unreadOnlyRef.current = unreadOnly; }, [unreadOnly]);
  useEffect(() => { filterEventIdRef.current = filterEventId; }, [filterEventId]);

  // Stable refs for active state (prevents sendMessage from being recreated on every state change)
  const activeConversationStateRef = useRef(activeConversation);
  const chatInputRef = useRef(chatInput);
  const chatFilesRef = useRef(chatFiles);
  const replyingToRef = useRef(replyingTo);
  const isUploadingRef = useRef(isUploading);
  useEffect(() => { activeConversationStateRef.current = activeConversation; }, [activeConversation]);
  useEffect(() => { chatInputRef.current = chatInput; }, [chatInput]);
  useEffect(() => { chatFilesRef.current = chatFiles; }, [chatFiles]);
  useEffect(() => { replyingToRef.current = replyingTo; }, [replyingTo]);
  useEffect(() => { isUploadingRef.current = isUploading; }, [isUploading]);

  // Stable ref for conversations (prevents openApprovalThread from being recreated on every WS msg)
  const conversationsRef = useRef(conversations);
  useEffect(() => { conversationsRef.current = conversations; }, [conversations]);

  // WebSocket
  const wsRef = useRef(null);
  const activeConversationIdRef = useRef("");
  const activeUserIdRef = useRef(null);
  const eventConvIdsRef = useRef(new Set());
  const panelOpenRef = useRef(false);
  const closeChatRef = useRef(() => {});
  const pendingApprovalThreadRef = useRef(null);
  const reconnectTimerRef = useRef(null);
  // Tracks consecutive failed reconnect attempts for exponential backoff
  const reconnectAttemptRef = useRef(0);

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
        // Use refs for filter state so this callback stays stable across filter changes
        const sq = opts.search !== undefined ? opts.search : searchQueryRef.current;
        const uo = opts.unreadOnly !== undefined ? opts.unreadOnly : unreadOnlyRef.current;
        const eid = opts.eventId !== undefined ? opts.eventId : filterEventIdRef.current;
        if (sq) params.set("search", sq);
        if (uo) params.set("unread_only", "true");
        if (eid) params.set("event_id", eid);

        const qs = params.toString();
        const data = await api.getJson(`/chat/conversations/me${qs ? `?${qs}` : ""}`);
        setConversations(sortConvsByActivity(Array.isArray(data) ? data : []));
      } catch {
        // silent
      }
    },
    [user] // stable: filter state is accessed via refs
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
      const shouldMergeIntoActive = !before && conversationId === activeConversationIdRef.current;
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
        if (activeConversationIdRef.current !== conversationId) {
          return;
        }
        const msgs = Array.isArray(data) ? data : [];
        setMessages((prev) => {
          if (before) return mergeMessagesByIdentity(msgs, prev);
          if (shouldMergeIntoActive && prev.some((m) => m.conversation_id === conversationId)) {
            return mergeMessagesByIdentity(prev, msgs);
          }
          return msgs;
        });
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
      // Synchronously update the ref BEFORE async loadMessages to prevent WS race
      activeConversationIdRef.current = thread.id;
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
        // Use ref to avoid recreating this callback on every conversations update
        let conv = conversationsRef.current.find((c) => String(c.id) === String(conversationId));
        if (!conv) {
          // Refresh conversations and search again
          const convData = await api.getJson("/chat/conversations/me");
          if (Array.isArray(convData)) {
            setConversations(sortConvsByActivity(convData));
            conv = convData.find((c) => String(c.id) === String(conversationId));
          }
        }
        if (conv) {
          // Synchronously update the ref BEFORE async loadMessages to prevent WS race
          activeConversationIdRef.current = String(conversationId);
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
    [openPanel, loadMessages, markConversationRead] // removed `conversations` dep — using ref instead
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
          // Synchronously update the ref BEFORE async loadMessages
          activeConversationIdRef.current = data.id;
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
      } else {
        // Synchronously update the ref BEFORE async loadMessages to prevent WS race
        activeConversationIdRef.current = conv.id;
        setActiveEventThread(null);
        setActiveUser(conv.other_user || null);
        setActiveConversation(conv);
        setTypingUser(null);
        setMessages([]);
        setHasMore(true);
        setLoadingMore(false);
        setChatStatus({ status: "loading", error: "" });
        await loadMessages(conv.id);
        await markConversationRead(conv.id);
      }
    },
    [openEventThread, loadMessages, markConversationRead]
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
    // Read all state from stable refs to avoid stale closures
    const activeConv = activeConversationStateRef.current;
    const trimmed = (chatInputRef.current || "").trim();
    const files = chatFilesRef.current;
    const replyRef = replyingToRef.current;

    if (!trimmed && files.length === 0) return;
    if (!activeConv?.id) {
      setChatStatus({ status: "error", error: "Select a chat to message." });
      return;
    }

    // Prevent double-submission
    if (isUploadingRef.current) return;

    const clientId =
      typeof crypto !== "undefined" && crypto.randomUUID
        ? crypto.randomUUID()
        : `${Date.now()}-${Math.random().toString(16).slice(2)}`;

    try {
      if (files.length > 0) setIsUploading(true);
      const attachments =
        files.length > 0
          ? (await Promise.all(files.map(uploadAttachment))).filter(Boolean)
          : [];
      setIsUploading(false);

      // Optimistic UI
      const optimistic = {
        id: `client-${clientId}`,
        client_id: clientId,
        conversation_id: activeConv.id,
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

      // Clear input state immediately for responsive UI
      setChatInput("");
      setChatFiles([]);
      setReplyingTo(null);

      // Try WebSocket first, fallback to REST
      const ws = wsRef.current;
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(
          JSON.stringify({
            type: "message",
            text: trimmed,
            attachments,
            conversation_id: activeConv.id,
            client_id: clientId,
            reply_to_message_id: replyRef?.messageId || undefined,
          })
        );
      } else {
        const confirmed = await api.postJson("/chat/messages", {
          conversation_id: activeConv.id,
          content: trimmed,
          attachments,
          client_id: clientId, // Include client_id so WS broadcast can be deduplicated
          reply_to_message_id: replyRef?.messageId || undefined,
        });
        // Replace the optimistic entry with the server-confirmed message to
        // prevent duplication if the WS broadcast arrives with client_id.
        if (confirmed?.id) {
          setMessages((prev) =>
            prev.some((m) => m.client_id === clientId)
              ? prev.map((m) =>
                  m.client_id === clientId ? { ...confirmed, client_id: clientId } : m
                )
              : prev
          );
        }
      }

      // Stop typing indicator
      const ws2 = wsRef.current;
      if (ws2 && ws2.readyState === WebSocket.OPEN) {
        ws2.send(
          JSON.stringify({
            type: "typing",
            is_typing: false,
            conversation_id: activeConv.id,
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
  }, [uploadAttachment, user]); // stable: all state accessed via refs

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
      const activeConv = activeConversationStateRef.current;
      if (ws && ws.readyState === WebSocket.OPEN && activeConv?.id) {
        ws.send(
          JSON.stringify({
            type: "typing",
            is_typing: true,
            conversation_id: activeConv.id,
          })
        );
      }
      if (typingTimeoutRef.current) clearTimeout(typingTimeoutRef.current);
      typingTimeoutRef.current = setTimeout(() => {
        const active = wsRef.current;
        const activeConvNow = activeConversationStateRef.current;
        if (active && active.readyState === WebSocket.OPEN && activeConvNow?.id) {
          active.send(
            JSON.stringify({
              type: "typing",
              is_typing: false,
              conversation_id: activeConvNow.id,
            })
          );
        }
      }, 1500);
    },
    [] // stable: reads activeConversation via ref
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
    let destroyed = false;

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        if (["message", "message.created", "attachment.created"].includes(data.type) && data.message) {
          const incoming = data.message;
          const activeCid = activeConversationIdRef.current;
          const knownConversation = conversationsRef.current.some(
            (c) => c.id === incoming.conversation_id
          );

          if (incoming.conversation_id === activeCid) {
            setMessages((prev) => mergeMessagesByIdentity(prev, [incoming]));
            // Keep the conversation list last_message preview in sync
            setConversations((prev) =>
              prev.map((c) =>
                c.id === incoming.conversation_id
                  ? {
                      ...c,
                      unread_count: 0,
                      last_message: {
                        text: getMessagePreview(incoming),
                        sender_id: incoming.sender_id,
                        sender_name: incoming.sender_name,
                        created_at: incoming.created_at,
                        message_id: incoming.id,
                      },
                    }
                  : c
              )
            );
          } else {
            // Update conversation list — re-sort by latest activity
            setConversations((prev) => {
              const hasConversation = prev.some((c) => c.id === incoming.conversation_id);
              if (!hasConversation) return prev;
              const updated = prev.map((c) =>
                c.id === incoming.conversation_id
                  ? {
                      ...c,
                      // Only increment unread for messages from other users, not your own
                      unread_count:
                        incoming.sender_id !== user?.id
                          ? (c.unread_count || 0) + 1
                          : c.unread_count,
                      last_message: {
                        text: getMessagePreview(incoming),
                        sender_id: incoming.sender_id,
                        sender_name: incoming.sender_name,
                        created_at: incoming.created_at,
                        message_id: incoming.id,
                      },
                    }
                  : c
              );
              return sortConvsByActivity(updated);
            });
          }

          if (!knownConversation) {
            loadConversations();
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

        if (["message_deleted", "message.deleted"].includes(data.type)) {
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

        if (["message_edited", "message.updated"].includes(data.type) && data.message) {
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

    ws.onerror = () => {};
    ws.onopen = () => {
      // Successful connection — reset the backoff counter
      reconnectAttemptRef.current = 0;
      // On every (re)connect, reload conversation list so missed messages surface.
      // Only reload the active thread if one is open.
      loadConversations();
      loadChatUsers();
      const activeCid = activeConversationIdRef.current;
      if (activeCid) {
        loadMessages(activeCid);
      }
    };
    ws.onclose = (event) => {
      if (destroyed) return;
      wsRef.current = null;
      // Reconnect unless the server rejected our token (1008)
      if (event.code !== 1008) {
        // Exponential backoff: 3s, 6s, 12s, 24s, capped at 30s, plus random jitter (±1s)
        const attempt = reconnectAttemptRef.current;
        const baseDelay = Math.min(30000, 3000 * Math.pow(2, attempt));
        const jitter = Math.random() * 1000;
        reconnectAttemptRef.current = attempt + 1;
        reconnectTimerRef.current = setTimeout(() => {
          if (destroyed || wsRef.current) return;
          const rToken = localStorage.getItem("auth_token");
          if (!rToken) return;
          // Create a fresh WS and attach the same shared handlers
          const rWs = new WebSocket(`${wsBase}/chat/ws?token=${rToken}`);
          wsRef.current = rWs;
          rWs.onmessage = ws.onmessage;
          rWs.onerror = ws.onerror;
          rWs.onopen = ws.onopen;
          rWs.onclose = ws.onclose;
        }, baseDelay + jitter);
      }
    };

    return () => {
      destroyed = true;
      // Reset backoff counter so next session starts fresh
      reconnectAttemptRef.current = 0;
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current);
        reconnectTimerRef.current = null;
      }
      if (wsRef.current) {
        wsRef.current.close();
        wsRef.current = null;
      } else {
        ws.close();
      }
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

      // Workflow action callback (passed from App.jsx)
      onOpenWorkflowAction: onOpenWorkflowAction || null,

      // For backward compat with App.jsx
      user,
    }),
    [
      panelOpen,
      onOpenWorkflowAction,
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
