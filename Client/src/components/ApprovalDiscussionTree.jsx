import { useState, useCallback, useEffect } from "react";
import api from "../services/api";
import { IconShieldCheck } from "./icons/EventModalIcons";
import DiscussionPanel from "./DiscussionPanel";

// Maps viewer role to the department string used in threads.
const ROLE_TO_DEPT = {
  facility_manager: "facility_manager",
  it: "it",
  marketing: "marketing",
  transport: "transport",
};

// Maps dept thread channel name to the channel used by openWorkflowActionModal.
const DEPT_TO_CHANNEL = {
  facility_manager: "facility",
  it: "it",
  marketing: "marketing",
  transport: "transport",
};

// Request statuses that allow dept actions.
const ACTIONABLE_STATUSES = new Set(["pending", "clarification_requested"]);

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
  // Dept action support
  viewerRole,
  onOpenActionModal,
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

  const handleSubmitReply = useCallback(
    async (threadId, message, replyToMessageId) => {
      if (!approvalRequestId || !threadId) return;
      await api.postJson(`/approvals/${approvalRequestId}/reply`, {
        thread_id: threadId,
        message,
        reply_to_message_id: replyToMessageId || undefined,
      });
      await fetchThreads();
      onRefresh?.();
    },
    [approvalRequestId, fetchThreads, onRefresh]
  );

  const handleOpenInChat = useCallback(
    (threadConvId) => openApprovalThread?.(threadConvId),
    [openApprovalThread]
  );

  // Determine if the current viewer's dept matches a given thread, and if the
  // request is in an actionable state, so we can surface dept action buttons.
  const getThreadActionModal = useCallback(
    (thread) => {
      if (!onOpenActionModal || !viewerRole) return undefined;
      const myDept = ROLE_TO_DEPT[viewerRole];
      if (!myDept || thread.department !== myDept) return undefined;
      const reqStatus = thread.dept_request_status;
      if (!reqStatus || !ACTIONABLE_STATUSES.has(reqStatus)) return undefined;
      const channel = DEPT_TO_CHANNEL[myDept];
      const requestId = thread.related_request_id;
      if (!channel || !requestId) return undefined;
      return (actionStatus, actionLabel) =>
        onOpenActionModal(channel, requestId, actionStatus, actionLabel);
    },
    [onOpenActionModal, viewerRole]
  );

  const handleThreadCreated = useCallback((newThread) => {
    setThreads((prev) => {
      const exists = prev.some((t) => t.id === newThread.id);
      return exists ? prev : [...prev, newThread];
    });
  }, []);

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
        <DiscussionPanel
          key={thread.id}
          thread={thread}
          currentUserId={currentUserId}
          onSubmitReply={handleSubmitReply}
          onOpenInChat={handleOpenInChat}
          onOpenActionModal={getThreadActionModal(thread)}
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