import { useState, useCallback, useEffect, useRef } from "react";
import api from "../services/api";
import { IconShieldCheck } from "./icons/EventModalIcons";
import DiscussionPanel from "./DiscussionPanel";

// Maps viewer role to the department string used in threads.
// Facility/IT/Marketing/Transport roles use dept-request threads.
// Approval-stage roles (deputy_registrar, finance_team, registrar, vice_chancellor)
// have their own stage-specific keys; they are identified by participant membership
// on the backend so no client-side dept-key filtering is needed for them.
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
  { value: "deputy_registrar", label: "Deputy Registrar" },
  { value: "finance_team", label: "Finance" },
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
  // Registrar-level inline action props
  isApprovalActionable,
  approvalRequestItemId,
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
  const [inlineActOpen, setInlineActOpen] = useState(false);
  const inlineActRef = useRef(null);

  // Close dropdown on outside click
  useEffect(() => {
    if (!inlineActOpen) return;
    function handleOutside(e) {
      if (inlineActRef.current && !inlineActRef.current.contains(e.target)) {
        setInlineActOpen(false);
      }
    }
    document.addEventListener("mousedown", handleOutside);
    return () => document.removeEventListener("mousedown", handleOutside);
  }, [inlineActOpen]);

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

  // Registrar-level roles can take approval actions inline from the discussion area
  const isRegistrarLevelRole = !ROLE_TO_DEPT[viewerRole] && !isFacultyViewer && viewerRole;
  const showInlineApprovalActions = isRegistrarLevelRole && isApprovalActionable && onOpenActionModal && approvalRequestItemId;

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
          isApprovalResolved={isApprovalActionable === false}
        />
      ))}

      {/* Inline approval action dropdown for registrar/deputy/finance — shown after discussions */}
      {showInlineApprovalActions ? (
        <div className="adt-approval-inline-actions" ref={inlineActRef}>
          <div className="adt-approval-inline-actions-row">
            <p className="adt-approval-inline-actions-label">Action on this request</p>
            <div className="msger-wf-action-root">
              <button
                type="button"
                className={`msger-wf-action-trigger${inlineActOpen ? " open" : ""}`}
                onClick={() => setInlineActOpen((v) => !v)}
                aria-haspopup="true"
                aria-expanded={inlineActOpen}
              >
                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>
                Take action
                <svg width="9" height="9" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>
              </button>
              {inlineActOpen && (
                <div className="msger-wf-action-menu" role="menu">
                  <button
                    type="button" role="menuitem"
                    className="msger-wf-action-item msger-wf-action-item--approve"
                    onClick={() => { setInlineActOpen(false); onOpenActionModal("approval", approvalRequestItemId, "approved", "Approve"); }}
                  >
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden><polyline points="20 6 9 17 4 12"/></svg>
                    Approve
                  </button>
                  <button
                    type="button" role="menuitem"
                    className="msger-wf-action-item msger-wf-action-item--clarify"
                    onClick={() => { setInlineActOpen(false); onOpenActionModal("approval", approvalRequestItemId, "clarification_requested", "Need clarification"); }}
                  >
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden><path d="M12 22c5.523 0 10-4.477 10-10S17.523 2 12 2 2 6.477 2 12s4.477 10 10 10z"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/></svg>
                    Need clarification
                  </button>
                  <button
                    type="button" role="menuitem"
                    className="msger-wf-action-item msger-wf-action-item--reject"
                    onClick={() => { setInlineActOpen(false); onOpenActionModal("approval", approvalRequestItemId, "rejected", "Reject"); }}
                  >
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                    Reject
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      ) : isRegistrarLevelRole && isApprovalActionable === false ? (
        <div className="adt-approval-resolved-state">
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden><polyline points="20 6 9 17 4 12"/></svg>
          <span>This request has been reviewed and is no longer actionable.</span>
        </div>
      ) : null}

      <NewThreadPanel
        approvalRequestId={approvalRequestId}
        existingDepts={existingDepts}
        isFaculty={isFacultyViewer}
        onThreadCreated={handleThreadCreated}
      />
    </section>
  );
}