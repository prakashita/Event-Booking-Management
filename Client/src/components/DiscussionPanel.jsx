import { useState, useCallback } from "react";
import { formatModalDateTime } from "../utils/eventDetailsView";

/* ── Role label map — maps raw role strings to display labels ── */
const PARTICIPANT_ROLE_LABELS = {
  faculty: "Faculty",
  deputy_registrar: "Deputy Registrar",
  finance_team: "Finance Team",
  registrar: "Registrar",
  vice_chancellor: "Vice Chancellor",
  facility_manager: "Facility",
  it: "IT",
  marketing: "Marketing",
  transport: "Transport",
  iqac: "IQAC",
};

function formatParticipantRole(role) {
  return PARTICIPANT_ROLE_LABELS[String(role || "").toLowerCase()] || role;
}

/* ── Inline quoted reply preview (inside a bubble) ── */
function InlineMsgReplyQuote({ snapshot }) {
  if (!snapshot) return null;
  return (
    <div className="dp-msg-reply-quote">
      <span className="dp-msg-reply-author">{snapshot.sender_name}</span>
      <p className="dp-msg-reply-preview">{snapshot.content_preview}</p>
    </div>
  );
}

/* ── Reply bar shown above the composer ── */
function ReplyBar({ snapshot, onDismiss }) {
  if (!snapshot) return null;
  return (
    <div className="dp-reply-bar">
      <div className="dp-reply-bar-content">
        <span className="dp-reply-bar-author">{snapshot.sender_name}</span>
        <p className="dp-reply-bar-preview">{snapshot.content_preview}</p>
      </div>
      <button
        type="button"
        className="dp-reply-bar-dismiss"
        aria-label="Cancel reply"
        onClick={onDismiss}
      >
        ×
      </button>
    </div>
  );
}

/* ── Single chat bubble ── */
function ThreadMessage({ msg, isOwn, onStartReply }) {
  return (
    <li
      className={`adt-bubble-row${isOwn ? " adt-bubble-row--own" : ""}`}
      data-message-id={msg.id}
    >
      {!isOwn && (
        <span className="adt-avatar" aria-hidden="true">
          {(msg.sender_name || "?")[0].toUpperCase()}
        </span>
      )}
      <div className="adt-bubble">
        {!isOwn && (
          <span className="adt-bubble-sender">{msg.sender_name}</span>
        )}
        {msg.reply_to_snapshot && (
          <InlineMsgReplyQuote snapshot={msg.reply_to_snapshot} />
        )}
        <p className="adt-bubble-text">{msg.content || "\u2014"}</p>
        <div className="adt-bubble-footer">
          <span className="adt-bubble-time">
            {formatModalDateTime(msg.created_at) || ""}
          </span>
          {onStartReply && (
            <button
              type="button"
              className="adt-bubble-reply-btn"
              aria-label="Reply to this message"
              onClick={() => onStartReply(msg)}
            >
              &#8629; Reply
            </button>
          )}
        </div>
      </div>
    </li>
  );
}

/* ── DiscussionPanel ──────────────────────────────────────────────────────
   Renders a single department conversation thread inline.

   Props:
     thread              – ApprovalThreadInfo from GET /approvals/{id}/threads
     currentUserId       – the viewer's user ID
     onSubmitReply       – async (threadId, message, replyToMessageId?) => void
     onOpenInChat        – (conversationId) => void
     onOpenActionModal   – (status, actionLabel) => void  (dept action buttons)
──────────────────────────────────────────────────────────────────────── */
export default function DiscussionPanel({
  thread,
  currentUserId,
  onSubmitReply,
  onOpenInChat,
  onOpenActionModal,
  isApprovalResolved = false,
}) {
  const isLocked_init =
    thread.thread_status === "resolved" || thread.thread_status === "closed";
  const [expanded, setExpanded] = useState(!isLocked_init);
  const [replyingToMsg, setReplyingToMsg] = useState(null); // full message object
  const [draft, setDraft] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [postError, setPostError] = useState("");

  const isLocked =
    thread.thread_status === "resolved" || thread.thread_status === "closed";

  const userIsParticipant =
    Array.isArray(thread.participants) &&
    thread.participants.some((p) => String(p.id) === String(currentUserId));

  const canReply = userIsParticipant && !isLocked;

  const statusLabel =
    thread.thread_status === "waiting_for_faculty"
      ? "Waiting for faculty"
      : thread.thread_status === "waiting_for_department"
        ? "Waiting for department"
        : null;

  const closedLabel =
    thread.thread_status === "closed" ? "Closed" : "Resolved";

  const handleStartReply = useCallback((msg) => {
    setReplyingToMsg(msg);
    setPostError("");
  }, []);

  const handleCancelReply = useCallback(() => {
    setReplyingToMsg(null);
    setDraft("");
    setPostError("");
  }, []);

  const handleSubmit = useCallback(async () => {
    const text = draft.trim();
    if (!text) return;
    setSubmitting(true);
    setPostError("");
    try {
      await onSubmitReply(thread.id, text, replyingToMsg?.id || null);
      setDraft("");
      setReplyingToMsg(null);
    } catch (e) {
      setPostError(e?.message || "Could not post reply.");
    } finally {
      setSubmitting(false);
    }
  }, [draft, onSubmitReply, thread.id, replyingToMsg]);

  return (
    <div
      className={`adt-panel${isLocked ? " adt-panel--resolved" : ""}${isApprovalResolved && !isLocked ? " adt-panel--approval-resolved" : ""}`}
      data-dept={thread.department}
    >
      {/* Collapsible header */}
      <button
        type="button"
        className="adt-panel-header"
        onClick={() => setExpanded((v) => !v)}
        aria-expanded={expanded}
      >
        <span className="adt-dept-badge">{thread.department_label}</span>
        <span className="adt-msg-count">
          {thread.messages.length} msg
          {thread.messages.length !== 1 ? "s" : ""}
        </span>
        {isLocked && (
          <span className="adt-resolved-chip">{closedLabel}</span>
        )}
        {!isLocked && statusLabel && (
          <span className="adt-turn-chip">{statusLabel}</span>
        )}
        <span
          className={`adt-chevron${expanded ? " adt-chevron--open" : ""}`}
          aria-hidden="true"
        >
          &#9658;
        </span>
      </button>

      {expanded && (
        <div className="adt-panel-body">
          {/* Locked banner */}
          {isLocked && (
            <div className="dp-locked-banner" role="status">
              <svg
                width="13"
                height="13"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden="true"
              >
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
              <span>
                This discussion is {closedLabel.toLowerCase()}.
                {thread.closed_at
                  ? ` Since ${formatModalDateTime(thread.closed_at)}.`
                  : ""}
              </span>
            </div>
          )}

          {/* Participants + privacy notice */}
          {thread.participants.length > 0 && (
            <div className="adt-participants-block">
              <p className="adt-participants">
                {thread.participants
                  .map((p) => `${p.name}${p.role ? ` (${formatParticipantRole(p.role)})` : ""}`)
                  .join(" \u00b7 ")}
              </p>
              <p className="adt-privacy-notice">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
                {" "}Only visible to this thread&#39;s participants
              </p>
            </div>
          )}

          {/* Messages */}
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
                onStartReply={canReply ? handleStartReply : null}
              />
            ))}
          </ul>

          {/* Composer (only when canReply) */}
          {canReply && (
            <div className="adt-composer">
              {replyingToMsg && (
                <ReplyBar
                  snapshot={{
                    sender_name: replyingToMsg.sender_name,
                    content_preview: (replyingToMsg.content || "").slice(0, 200),
                  }}
                  onDismiss={handleCancelReply}
                />
              )}
              <textarea
                className="adt-composer-textarea"
                rows={3}
                value={draft}
                placeholder={
                  replyingToMsg
                    ? `Reply to ${replyingToMsg.sender_name}\u2026`
                    : `Message ${thread.department_label}\u2026`
                }
                onChange={(e) => setDraft(e.target.value)}
                disabled={submitting}
              />
              {postError && (
                <p className="form-error adt-post-error">{postError}</p>
              )}
              <div className="adt-composer-actions">
                {onOpenInChat && (
                  <button
                    type="button"
                    className="adt-chat-btn"
                    onClick={() => onOpenInChat(thread.id)}
                  >
                    Open in chat
                  </button>
                )}
                {onOpenActionModal && (
                  <span className="dp-action-btns">
                    <button
                      type="button"
                      className="dp-action-btn dp-action-btn--approve"
                      onClick={() => onOpenActionModal("approved", "Noted")}
                    >
                      Noted
                    </button>
                    <button
                      type="button"
                      className="dp-action-btn dp-action-btn--reject"
                      onClick={() => onOpenActionModal("rejected", "Reject")}
                    >
                      Reject
                    </button>
                    <button
                      type="button"
                      className="dp-action-btn dp-action-btn--clarify"
                      onClick={() => onOpenActionModal("clarification_requested", "Need clarification")}
                    >
                      Need clarification
                    </button>
                  </span>
                )}
                <button
                  type="button"
                  className="primary-action"
                  onClick={handleSubmit}
                  disabled={submitting || !draft.trim()}
                >
                  {submitting ? "Sending\u2026" : "Send"}
                </button>
              </div>
            </div>
          )}

          {/* When viewer is not a participant, just offer Open in chat + action */}
          {!canReply && (onOpenInChat || onOpenActionModal) && (
            <div className="adt-action-bar">
              {onOpenInChat && (
                <button
                  type="button"
                  className="adt-chat-btn"
                  onClick={() => onOpenInChat(thread.id)}
                >
                  Open in chat
                </button>
              )}
              {onOpenActionModal && (
                <span className="dp-action-btns">
                  <button
                    type="button"
                    className="dp-action-btn dp-action-btn--approve"
                    onClick={() => onOpenActionModal("approved", "Noted")}
                  >
                    Noted
                  </button>
                  <button
                    type="button"
                    className="dp-action-btn dp-action-btn--reject"
                    onClick={() => onOpenActionModal("rejected", "Reject")}
                  >
                    Reject
                  </button>
                  <button
                    type="button"
                    className="dp-action-btn dp-action-btn--clarify"
                    onClick={() => onOpenActionModal("clarification_requested", "Need clarification")}
                  >
                    Need clarification
                  </button>
                </span>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
