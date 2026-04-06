import { useMemo } from "react";
import {
  IconCalendar,
  IconDocument,
  IconEnvelope,
  IconFlag,
  IconMapPin,
  IconShieldCheck,
  IconStatusRing,
  IconUser,
  IconUsersAudience,
  IconWallet
} from "./icons/EventModalIcons";
import ApprovalDiscussionTree from "./ApprovalDiscussionTree";
import DepartmentRequirementsDeck from "./DepartmentRequirementsDeck";
import { useMessenger } from "./messenger/MessengerContext";
import {
  buildRegistrarFallbackDeptSections,
  collectDepartmentRequirementSections,
  formatModalDateTime,
  formatWorkflowActionTypeLabel,
  formatWorkflowRoleLabel,
  nestApprovalDiscussionFromLogs,
  normalizeDecisionStatusForWf,
  orderDepartmentSectionsForRole,
  wfBadgeClass,
  wfBadgeLabel
} from "../utils/eventDetailsView";

export default function ApprovalDetailsModalBody({
  request,
  eventDetails,
  detailsStatus,
  detailsError,
  formatISTTime,
  normalizeMarketingRequirements,
  getMarketingDeliverableLabel,
  transportRequestTypeLabel,
  openMessengerForApprovalReply,
  openApprovalThread,
  onRefreshApprovalDetails,
  approvalDiscussionCanReply = false,
  currentUserId,
  viewerRole = "registrar",
}) {
  const intendedAudience = request?.intendedAudience ?? request?.intended_audience ?? null;
  const realApprovalId = request?.approval_request_id || String(request?.id || "").replace(/^approval-/, "");
  const scheduleStart =
    request?.start_date && request?.start_time
      ? `${request.start_date} · ${formatISTTime(request.start_time)}`
      : "—";
  const scheduleEnd =
    request?.end_date && request?.end_time
      ? `${request.end_date} · ${formatISTTime(request.end_time)}`
      : "—";

  const eventLifecycleStatus = eventDetails?.event?.status;
  const approvalWf = normalizeDecisionStatusForWf(request?.status);
  const actionLogs = Array.isArray(eventDetails?.workflow_action_logs)
    ? eventDetails.workflow_action_logs
    : [];
  const discussionRoots =
    detailsStatus === "ready" && realApprovalId
      ? eventDetails?.approval_discussion_threads?.length > 0
        ? eventDetails.approval_discussion_threads
        : nestApprovalDiscussionFromLogs(actionLogs, realApprovalId)
      : [];

  const deptSections = useMemo(() => {
    if (detailsStatus === "ready" && eventDetails) {
      return orderDepartmentSectionsForRole(
        viewerRole,
        collectDepartmentRequirementSections(
          eventDetails,
          normalizeMarketingRequirements,
          transportRequestTypeLabel
        )
      );
    }
    return buildRegistrarFallbackDeptSections(request?.requirements || []);
  }, [detailsStatus, eventDetails, request?.requirements, normalizeMarketingRequirements, transportRequestTypeLabel, viewerRole]);

  const isFacultyViewer = viewerRole === "faculty";
  const deckSubtitle =
    detailsStatus === "ready" && eventDetails
      ? isFacultyViewer
        ? "Department requirement statuses for your event."
        : "Linked to the approved event record. Status reflects each team's request queue."
      : detailsStatus === "error"
        ? "Could not load the event record; showing any submitted intent from the approval only."
        : !request?.event_id
          ? isFacultyViewer
            ? "Requirements will appear here once the registrar approves your request."
            : "No event record yet (pending approval). After approval, this section loads linked Facility, IT, Marketing, Transport, and IQAC data."
          : "Showing data derived from the approval record.";

  return (
    <div className="event-details-body approval-details-body">
      <section className="evt-overview-card" aria-labelledby="approval-overview-heading">
        <div className="evt-section-head">
          <span className="evt-section-head-icon" aria-hidden>
            <IconDocument size={22} />
          </span>
          <h4 id="approval-overview-heading" className="evt-section-title evt-section-title--large">
            Event overview
          </h4>
        </div>
        <div className="evt-overview-grid">
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconFlag size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Event name</p>
              <p className="details-value">{request?.event_name || "—"}</p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconEnvelope size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Requester</p>
              <p className="details-value">
                {request?.requester_email ? (
                  <a href={`mailto:${request.requester_email}`}>{request.requester_email}</a>
                ) : (
                  "—"
                )}
              </p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconUser size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Facilitator</p>
              <p className="details-value">{request?.facilitator || "—"}</p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconMapPin size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Venue</p>
              <p className="details-value">{request?.venue_name || "—"}</p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconUsersAudience size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Intended audience</p>
              <p className="details-value">{intendedAudience || "—"}</p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconWallet size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Budget</p>
              <div className="details-value details-budget-row">
                <span className="details-budget-amount">
                  {request?.budget != null && request?.budget !== "" && !isNaN(Number(request.budget))
                    ? `Rs ${Number(request.budget).toLocaleString()}`
                    : "—"}
                </span>
                {request?.budget_breakdown_web_view_link ? (
                  <button
                    type="button"
                    className="details-button"
                    onClick={() =>
                      window.open(request.budget_breakdown_web_view_link, "_blank", "noopener,noreferrer")
                    }
                  >
                    Budget breakdown (PDF)
                  </button>
                ) : null}
              </div>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconStatusRing size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Status</p>
              <p className="details-value">
                <span className={wfBadgeClass(approvalWf)}>{wfBadgeLabel(approvalWf)}</span>
                {eventLifecycleStatus ? (
                  <span className="approval-event-status-hint">
                    {" "}
                    · Event:{" "}
                    <span className={`status-pill ${String(eventLifecycleStatus).toLowerCase()}`}>
                      {eventLifecycleStatus}
                    </span>
                  </span>
                ) : null}
              </p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconCalendar size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Start</p>
              <p className="details-value">{scheduleStart}</p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconCalendar size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">End</p>
              <p className="details-value">{scheduleEnd}</p>
            </div>
          </div>
          <div className="evt-overview-field evt-overview-wide">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconDocument size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Description</p>
              <p className="details-value">{request?.description || "—"}</p>
            </div>
          </div>
        </div>
      </section>

      <section className="evt-approval-context-card" aria-labelledby="approval-context-heading">
        <div className="evt-section-head">
          <span className="evt-section-head-icon" aria-hidden>
            <IconShieldCheck size={22} />
          </span>
          <h4 id="approval-context-heading" className="evt-section-title evt-section-title--large">
            Approval context
          </h4>
        </div>
        <div className="evt-approval-context-grid">
          <div className="evt-approval-context-row">
            <span className="evt-meta-k">Requested to</span>
            <span className="evt-approval-context-value">
              {request?.requested_to ? (
                <a href={`mailto:${request.requested_to}`}>{request.requested_to}</a>
              ) : (
                "—"
              )}
            </span>
          </div>
          <div className="evt-approval-context-row">
            <span className="evt-meta-k">Current status</span>
            <span className={wfBadgeClass(approvalWf)}>{wfBadgeLabel(approvalWf)}</span>
          </div>
          <div className="evt-approval-context-row">
            <span className="evt-meta-k">Role</span>
            <span className="evt-approval-context-value">Registrar review</span>
          </div>
          {request?.decided_by ? (
            <div className="evt-approval-context-row">
              <span className="evt-meta-k">Decided by</span>
              <span className="evt-approval-context-value">{request.decided_by}</span>
            </div>
          ) : null}
        </div>
        {request?.discussion_status && request?.status === "clarification_requested" ? (
          <div className={`approval-discussion-status-banner ${
            request.discussion_status === "waiting_for_faculty"
              ? "approval-discussion-status-banner--waiting-faculty"
              : "approval-discussion-status-banner--waiting-dept"
          }`}>
            {request.discussion_status === "waiting_for_faculty"
              ? isFacultyViewer
                ? "The registrar has requested clarification. Please review and reply."
                : "Waiting for the faculty to respond to your clarification request."
              : isFacultyViewer
                ? "Your reply has been sent. Waiting for the registrar to review."
                : "The faculty has replied. Please review their response."}
          </div>
        ) : null}
      </section>

      {realApprovalId ? (
        <ApprovalDiscussionTree
          approvalRequestId={realApprovalId}
          currentUserId={currentUserId}
          isFacultyViewer={isFacultyViewer}
          onRefresh={onRefreshApprovalDetails}
          openApprovalThread={openApprovalThread}
          rootsFromApi={eventDetails?.approval_discussion_threads}
          workflowLogs={actionLogs}
          approvalStatus={request?.status}
          eventId={request?.event_id}
          canReply={approvalDiscussionCanReply}
          openMessengerForApprovalReply={openMessengerForApprovalReply}
        />
      ) : null}
      {detailsStatus === "ready" && discussionRoots.length === 0 && actionLogs.length > 0 ? (
        <section className="evt-action-history-section" aria-labelledby="approval-action-history-heading">
          <div className="evt-section-head">
            <span className="evt-section-head-icon" aria-hidden>
              <IconShieldCheck size={22} />
            </span>
            <h4 id="approval-action-history-heading" className="evt-section-title evt-section-title--large">
              Action history / comments
            </h4>
          </div>
          <ul className="evt-action-history-list">
            {actionLogs.map((log) => (
              <li key={log.id} className="evt-action-history-item">
                <div className="evt-action-history-head">
                  <span className="evt-action-history-role">{formatWorkflowRoleLabel(log.role)}</span>
                  <span className="evt-action-history-action">{formatWorkflowActionTypeLabel(log.action_type)}</span>
                </div>
                <p className="evt-action-history-comment">{log.comment}</p>
                <div className="evt-action-history-meta">
                  <span>By {log.action_by || "—"}</span>
                  <span>{formatModalDateTime(log.created_at) || "—"}</span>
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {detailsStatus === "loading" ? (
        <section className="evt-requirements-section">
          <p className="table-message">Loading departmental requirements from the event record…</p>
        </section>
      ) : (
        <>
          {detailsError ? <p className="form-error evt-approval-details-err">{detailsError}</p> : null}
          <DepartmentRequirementsDeck
            deptSections={deptSections}
            viewerRole={viewerRole}
            getMarketingDeliverableLabel={getMarketingDeliverableLabel}
            deckSubtitle={deckSubtitle}
            sectionId="approval-req-heading"
          />
        </>
      )}

      <section className="evt-notes-card" aria-labelledby="approval-notes-heading">
        <div className="evt-section-head">
          <span className="evt-section-head-icon" aria-hidden>
            <IconDocument size={22} />
          </span>
          <h4 id="approval-notes-heading" className="evt-section-title evt-section-title--large">
            Notes and description
          </h4>
        </div>
        <div className="evt-notes-stack">
          <div>
            <p className="details-label">Other notes</p>
            <p className="details-value evt-notes-prose">{request?.other_notes || "—"}</p>
          </div>
          <div>
            <p className="details-label">Description</p>
            <p className="details-value evt-notes-prose">{request?.description || "—"}</p>
          </div>
        </div>
      </section>
    </div>
  );
}

export function ConnectedApprovalDetailsModalBody(props) {
  const { openMessengerForApprovalReply, openApprovalThread } = useMessenger();
  return (
    <ApprovalDetailsModalBody
      {...props}
      openMessengerForApprovalReply={openMessengerForApprovalReply}
      openApprovalThread={openApprovalThread}
    />
  );
}
