import { useState, useCallback, useEffect } from "react";
import api from "../services/api";
import { IconShieldCheck } from "./icons/EventModalIcons";
import { formatModalDateTime } from "../utils/eventDetailsView";

/* ─────────────────────────────────────────────
   Chat bubble for messages inside a thread
   ───────────────────────────────────────────── */
function ThreadMessage({ msg, isOwn }) {
  return (
    <li className={`adt-bubble-row${isOwn ? " adt-bubble-row--own" : ""}`}>
      {!isOwn && (
        <span className="adt-avatar" aria-hidden>
          {(msg.sender_name || "?")[0].toUpperCase()}
        </span>
      )}
      <div className="adt-bubble">
        {!isOwn && <span className="adt-bubble-sender">{msg.sender_name}</span>}
        <p className="adt-bubble-text">{msg.content || "\u2014"}</p>
        <span className="adt-bubble-time">
          {formatModalDateTime(msg.created_at) || ""}
        </span>
      </div>
    </li>
  );
}

/* ─────────────────────────────────────────────
   Single department conversation panel.
   canReply is ONLY based on participant membership,
   never on approval status.
   ───────────────────────────────────────────── */
function ThreadPanel({
  thread,
  currentUserId,
  approvalRequestId,
  activeReplyId,
  replyDraft,
  replySubmitting,
  postError,
  onStartReply,
  onChangeDraft,
  onCancelReply,
  onSubmitReply,
  onOpenInChat,
}) {
  const [expanded, setExpanded] = useState(true);
  const isReplying = activeReplyId === thread.id;
  const isResolved = thread.thread_status === "resolved";

  const userIsParticipant =
    Array.isArray(thread.participants) &&
    thread.participants.some((p) => String(p.id) === String(currentUserId));

  const canReply = userIsParticipant && !isResolved;

  const statusLabel =
    thread.thread_status === "waiting_for_faculty"
      ? "Waiting for faculty"
      : thread.thread_status === "waiting_for_department"
        ? "Waiting for department"
        : null;

  return (
    <div
      className={`adt-panel${isResolved ? " adt-panel--resolved" : ""}`}
      data-dept={thread.department}
    >
      <button
        type="button"
        className="adt-panel-header"
        onClick={() => setExpanded((v) => !v)}
        aria-expanded={expanded}
      >
        <span className="adt-dept-badge">{thread.department_label}</span>
        <span className="adt-msg-count">
          {thread.messages.length} msg{thread.messages.length !== 1 ? "s" : ""}
        </span>
        {isResolved && <span className="adt-resolved-chip">Resolved</span>}
        {!isResolved && statusLabel && (
          <span className="adt-turn-chip">{statusLabel}</span>
        )}
        <span
          className={`adt-chevron${expanded ? " adt-chevron--open" : ""}`}
          aria-hidden
        >
          &#9658;
        </span>
      </button>

      {expanded && (
        <div className="adt-panel-body">
          {thread.participants.length > 0 && (
            <p className="adt-participants">
              {thread.participants
                .map((p) => `${p.name}${p.role ? ` (${p.role})` : ""}`)
                .join(" \u00b7 ")}
            </p>
          )}

          {thread.messages.length === 0 && (
            <p className="adt-empty">No messages yet.</p>
          )}

          <ul
            className="adt-bubble-list"
            aria-label={`${thread.department_label} messages`}
          >
            {thread.messages.map((msg) => (
              <ThreadMessage
                key={msg.id}
                msg={msg}
                isOwn={String(msg.sender_id) === String(currentUserId)}
              />
            ))}
          </ul>

          {canReply && !isReplying && (
            <div className="adt-action-bar">
              <button
                type="button"
                className="adt-reply-btn"
                onClick={() => onStartReply(thread.id)}
              >
                Reply
              </button>
              <button
                type="button"
                className="adt-chat-btn"
                onClick={() => onOpenInChat(thread.id)}
              >
                Open in chat
              </button>
            </div>
          )}

          {isReplying && (
            <div className="adt-composer">
              <textarea
                className="adt-composer-textarea"
                rows={3}
                value={replyDraft}
                placeholder={`Reply to ${thread.department_label}\u2026`}
                onChange={(e) => onChangeDraft(e.target.value)}
                disabled={replySubmitting}
                autoFocus
              />
              {postError && (
                <p className="form-error adt-post-error">{postError}</p>
              )}
              <div className="adt-composer-actions">
                <button
                  type="button"
                  className="secondary-action"
                  onClick={onCancelReply}
                  disabled={replySubmitting}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="primary-action"
                  onClick={() => onSubmitReply(thread.id)}
                  disabled={replySubmitting || !replyDraft.trim()}
                >
                  {replySubmitting ? "Sending\u2026" : "Send"}
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

/* ─────────────────────────────────────────────
   "Start new discussion" — lets faculty open a
   thread with a dept that has no thread yet.
   ───────────────────────────────────────────── */
const DEPT_OPTIONS = [
  { value: "registrar", label: "Registrar" },
  { value: "facility_manager", label: "Facility" },
  { value: "it", label: "IT" },
  { value: "marketing", label: "Marketing" },
  { value: "transport", label: "Transport" },
  { value: "iqac", label: "IQAC" },
];

function NewThreadPanel({ approvalRequestId, existingDepts, isFaculty, onThreadCreated }) {
  const available = DEPT_OPTIONS.filter((d) => !existingDepts.includes(d.value));
  const [open, setOpen] = useState(false);
  const [dept, setDept] = useState("");
  const [msg, setMsg] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  if (!isFaculty || available.length === 0) return null;

  const handleSubmit = async () => {
    if (!dept || !approvalRequestId) return;
    setSubmitting(true);
    setError("");
    try {
      const thread = await api.postJson(
        `/approvals/${approvalRequestId}/threads/ensure`,
        { department: dept, message: msg.trim() || undefined }
      );
      setOpen(false);
      setDept("");
      setMsg("");
      onThreadCreated?.(thread);
    } catch (e) {
      setError(e?.message || "Could not start discussion.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="adt-new-thread">
      {!open ? (
        <button
          type="button"
          className="adt-new-thread-btn"
          onClick={() => setOpen(true)}
        >
          + Start new discussion
        </button>
      ) : (
        <div className="adt-new-thread-form">
          <p className="adt-new-thread-label">Start a discussion with:</p>
          <select
            className="adt-new-thread-select"
            value={dept}
            onChange={(e) => setDept(e.target.value)}
          >
            <option value="">&#8212; Select department &#8212;</option>
            {available.map((d) => (
              <option key={d.value} value={d.value}>
                {d.label}
              </option>
            ))}
          </select>
          <textarea
            className="adt-composer-textarea"
            rows={3}
            value={msg}
            placeholder="Optional opening message&#8230;"
            onChange={(e) => setMsg(e.target.value)}
            disabled={submitting}
          />
          {error && <p className="form-error adt-post-error">{error}</p>}
          <div className="adt-composer-actions">
            <button
              type="button"
              className="secondary-action"
              onClick={() => {
                setOpen(false);
                setDept("");
                setMsg("");
                setError("");
              }}
              disabled={submitting}
            >
              Cancel
            </button>
            <button
              type="button"
              className="primary-action"
              onClick={handleSubmit}
              disabled={submitting || !dept}
            >
              {submitting ? "Creating&#8230;" : "Start discussion"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ─────────────────────────────────────────────
   Main component
   ───────────────────────────────────────────── */
export default function ApprovalDiscussionTree({
  approvalRequestId,
  currentUserId,
  isFacultyViewer,
  onRefresh,
  openApprovalThread,
  // legacy props (ignored — kept for backward compat)
  rootsFromApi: _rootsFromApi,
  workflowLogs: _workflowLogs,
  approvalStatus: _approvalStatus,
  eventId: _eventId,
  canReply: _canReply,
  openMessengerForApprovalReply: _openMessengerForApprovalReply,
}) {
  const [threads, setThreads] = useState([]);
  const [loading, setLoading] = useState(false);
  const [activeReplyId, setActiveReplyId] = useState(null);
  const [replyDraft, setReplyDraft] = useState("");
  const [replySubmitting, setReplySubmitting] = useState(false);
  const [postError, setPostError] = useState("");

  const fetchThreads = useCallback(async () => {
    if (!approvalRequestId) return;
    setLoading(true);
    try {
      const data = await api.getJson(`/approvals/${approvalRequestId}/threads`);
      setThreads(Array.isArray(data) ? data : []);
    } catch {
      setThreads([]);
    } finally {
      setLoading(false);
    }
  }, [approvalRequestId]);

  useEffect(() => {
    fetchThreads();
  }, [fetchThreads]);

  const onStartReply = useCallback((threadId) => {
    setPostError("");
    setActiveReplyId(threadId);
    setReplyDraft("");
  }, []);

  const onCancelReply = useCallback(() => {
    setActiveReplyId(null);
    setReplyDraft("");
    setPostError("");
  }, []);

  const onSubmitReply = useCallback(
    async (threadId) => {
      const text = replyDraft.trim();
      if (!text || !approvalRequestId || !threadId) return;
      setReplySubmitting(true);
      setPostError("");
      try {
        await api.postJson(`/approvals/${approvalRequestId}/reply`, {
          thread_id: threadId,
          message: text,
        });
        setActiveReplyId(null);
        setReplyDraft("");
        await fetchThreads();
        onRefresh?.();
      } catch (e) {
        setPostError(e?.message || "Could not post reply.");
      } finally {
        setReplySubmitting(false);
      }
    },
    [replyDraft, approvalRequestId, fetchThreads, onRefresh]
  );

  const onOpenInChat = useCallback(
    (threadConvId) => openApprovalThread?.(threadConvId),
    [openApprovalThread]
  );

  const handleThreadCreated = useCallback(
    (newThread) => {
      setThreads((prev) => {
        const exists = prev.some((t) => t.id === newThread.id);
        return exists ? prev : [...prev, newThread];
      });
    },
    []
  );

  if (!approvalRequestId) return null;

  const existingDepts = threads.map((t) => t.department);

  return (
    <section className="adt-section" aria-labelledby="adt-heading">
      <div className="evt-section-head">
        <span className="evt-section-head-icon" aria-hidden>
          <IconShieldCheck size={22} />
        </span>
        <h4 id="adt-heading" className="evt-section-title evt-section-title--large">
          Discussion
        </h4>
      </div>

      {loading && (
        <p className="table-message adt-loading">Loading conversations&#8230;</p>
      )}

      {!loading && threads.length === 0 && (
        <p className="adt-empty-state">
          No department discussions yet.
          {isFacultyViewer
            ? " Use the button below to start a conversation with any department."
            : " A discussion will appear here when the registrar or a department sends a message."}
        </p>
      )}

      {threads.map((thread) => (
        <ThreadPanel
          key={thread.id}
          thread={thread}
          currentUserId={currentUserId}
          approvalRequestId={approvalRequestId}
          activeReplyId={activeReplyId}
          replyDraft={replyDraft}
          replySubmitting={replySubmitting}
          postError={activeReplyId === thread.id ? postError : ""}
          onStartReply={onStartReply}
          onChangeDraft={setReplyDraft}
          onCancelReply={onCancelReply}
          onSubmitReply={onSubmitReply}
          onOpenInChat={onOpenInChat}
        />
      ))}

      <NewThreadPanel
        approvalRequestId={approvalRequestId}
        existingDepts={existingDepts}
        isFaculty={isFacultyViewer}
        onThreadCreated={handleThreadCreated}
      />
    </section>
  );
}