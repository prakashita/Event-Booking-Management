/**
 * DeptRequirementActions
 *
 * Renders inline workflow actions (Accept / Reject / Need Confirmation) for a
 * single department request block inside the Details view.
 * Reply functionality is handled by the sibling DiscussionPanel component.
 *
 * Props:
 *   block             – department section block (has id, status, requestedTo, discussionThread)
 *   sectionKey        – "facility" | "it" | "marketing" | "transport"
 *   approvalRequestId – the parent ApprovalRequest id
 *   currentUserId     – viewer's user id
 *   currentUserEmail  – viewer's email; must match block.requestedTo to show actions
 *   viewerRole        – viewer's role string
 *   onActionDone      – () => void  — called after a PATCH action succeeds so the parent can reload
 */

import { useState, useCallback } from "react";
import api from "../services/api";

/* Role → API channel map */
const ROLE_TO_CHANNEL = {
  facility_manager: "facility",
  it: "it",
  marketing: "marketing",
  transport: "transport",
};

/* Channel → PATCH endpoint prefix */
const CHANNEL_ENDPOINT = {
  facility: "/facility/requests",
  it: "/it/requests",
  marketing: "/marketing/requests",
  transport: "/transport/requests",
};

function canActOnStatus(status) {
  const s = String(status || "").toLowerCase();
  return s === "pending" || s === "clarification_requested";
}

/* ─── Inline action bar ─────────────────────────────────────────────────── */
function ActionRow({ channel, requestId, onActionDone }) {
  const [phase, setPhase] = useState("idle"); // idle | confirm:{approved|rejected|clarification_requested}
  const [comment, setComment] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const startAction = (status) => {
    setPhase(`confirm:${status}`);
    setComment("");
    setError("");
  };

  const cancel = () => {
    setPhase("idle");
    setComment("");
    setError("");
  };

  const submit = useCallback(async () => {
    const pendingStatus = phase.replace("confirm:", "");
    const commentRequired = pendingStatus !== "approved";
    if (commentRequired && !comment.trim()) {
      setError("A comment is required.");
      return;
    }
    setSubmitting(true);
    setError("");
    try {
      await api.patchJson(`${CHANNEL_ENDPOINT[channel]}/${requestId}`, {
        status: pendingStatus,
        comment: comment.trim() || null,
      });
      cancel();
      onActionDone?.();
    } catch (e) {
      setError(e?.message || "Could not submit action.");
    } finally {
      setSubmitting(false);
    }
  }, [phase, comment, channel, requestId, onActionDone]);

  if (phase !== "idle") {
    const pendingStatus = phase.replace("confirm:", "");
    const isNeedConfirmation = pendingStatus === "clarification_requested";
    const label = pendingStatus === "approved"
      ? "Noted"
      : pendingStatus === "rejected"
        ? "Reject"
        : "Need Confirmation";

    return (
      <div className="dra-confirm-form">
        <p className="dra-confirm-label">
          {isNeedConfirmation
            ? "Describe what needs clarification from the requester:"
            : `Confirm: ${label}`}
        </p>
        {(isNeedConfirmation || pendingStatus === "rejected") && (
          <textarea
            className="dra-confirm-textarea"
            rows={3}
            value={comment}
            placeholder={isNeedConfirmation ? "Clarification message…" : "Reason (optional)…"}
            onChange={(e) => setComment(e.target.value)}
            disabled={submitting}
          />
        )}
        {error && <p className="form-error dra-error">{error}</p>}
        <div className="dra-confirm-btns">
          <button
            type="button"
            className="secondary-action"
            onClick={cancel}
            disabled={submitting}
          >
            Cancel
          </button>
          <button
            type="button"
            className={`primary-action${pendingStatus === "rejected" ? " dra-btn-reject" : ""}`}
            onClick={submit}
            disabled={submitting}
          >
            {submitting ? "Submitting…" : label}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="dra-action-row">
      <span className="dra-action-label">Your action:</span>
      <button
        type="button"
        className="dra-btn dra-btn--accept"
        onClick={() => startAction("approved")}
      >
        Noted
      </button>
      <button
        type="button"
        className="dra-btn dra-btn--confirm"
        onClick={() => startAction("clarification_requested")}
      >
        Need Confirmation
      </button>
      <button
        type="button"
        className="dra-btn dra-btn--reject"
        onClick={() => startAction("rejected")}
      >
        Reject
      </button>
    </div>
  );
}

/* ─── Main export ────────────────────────────────────────────────────────── */
export default function DeptRequirementActions({
  block,
  sectionKey,
  approvalRequestId,
  currentUserId,
  currentUserEmail,
  viewerRole,
  onActionDone,
}) {
  const channel = ROLE_TO_CHANNEL[viewerRole] || null;
  const isDeptViewer = channel === sectionKey;
  const isActionable = canActOnStatus(block?.status);

  // Only show action buttons to the user specifically assigned to this request.
  // This prevents the wrong dept user (same role, different email) from seeing
  // buttons that would trigger a 403 from the backend.
  const isAssignedUser =
    !block?.requestedTo ||
    block.requestedTo.trim().toLowerCase() === (currentUserEmail || "").trim().toLowerCase();

  const showActions = isDeptViewer && isActionable && isAssignedUser;

  if (!showActions) return null;

  return (
    <div className="dra-root">
      <ActionRow
        channel={channel}
        requestId={block.id}
        onActionDone={onActionDone}
      />
    </div>
  );
}
