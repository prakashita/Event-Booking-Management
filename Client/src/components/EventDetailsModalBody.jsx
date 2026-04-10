import {
  IconCalendar,
  IconDocument,
  IconFlag,
  IconFlow,
  IconMapPin,
  IconStatusRing,
  IconUser,
  IconUsersAudience,
  IconWallet
} from "./icons/EventModalIcons";
import DepartmentRequirementsDeck from "./DepartmentRequirementsDeck";
import ApprovalDiscussionTree from "./ApprovalDiscussionTree";
import { useMessenger } from "./messenger/MessengerContext";
import {
  buildWorkflowStepperSteps,
  collectDepartmentRequirementSections,
  formatModalDateTime,
  formatWorkflowRoleLabel,
  orderDepartmentSectionsForRole,
  wfBadgeClass,
  wfBadgeLabel
} from "../utils/eventDetailsView";

export default function EventDetailsModalBody({
  details,
  fallbackEventName,
  formatISTTime,
  normalizeMarketingRequirements,
  getMarketingDeliverableLabel,
  viewerRole,
  transportRequestTypeLabel,
  isMarketingViewer = false,
  onMarketingUpload,
  getMarketingDeliverableUploadFlags,
  currentUserId,
  currentUserEmail,
  openApprovalThread,
  onOpenActionModal,
  onRefreshDetails,
}) {
  const event = details?.event;
  const eventName = event?.name || fallbackEventName || "—";
  const rawAudience = event?.intendedAudience ?? event?.intended_audience ?? null;
  const audienceOther = event?.intendedAudienceOther ?? event?.intended_audience_other ?? null;
  const intendedAudience = Array.isArray(rawAudience)
    ? rawAudience.join(", ") + (audienceOther ? ` (Others: ${audienceOther})` : "")
    : rawAudience
      ? String(rawAudience) + (audienceOther ? ` (Others: ${audienceOther})` : "")
      : null;
  const steps = buildWorkflowStepperSteps(details);
  const deptSections = orderDepartmentSectionsForRole(
    viewerRole,
    collectDepartmentRequirementSections(details, normalizeMarketingRequirements, transportRequestTypeLabel)
  );
  const scheduleStart =
    event?.start_date && event?.start_time
      ? `${event.start_date} · ${formatISTTime(event.start_time)}`
      : "—";
  const scheduleEnd =
    event?.end_date && event?.end_time
      ? `${event.end_date} · ${formatISTTime(event.end_time)}`
      : "—";

  return (
    <div className="event-details-body">
      <section className="evt-overview-card" aria-labelledby="evt-overview-heading">
        <div className="evt-section-head">
          <span className="evt-section-head-icon" aria-hidden>
            <IconDocument size={22} />
          </span>
          <h4 id="evt-overview-heading" className="evt-section-title evt-section-title--large">
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
              <p className="details-value">{eventName}</p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconMapPin size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Venue</p>
              <p className="details-value">{event?.venue_name || "—"}</p>
            </div>
          </div>
          <div className="evt-overview-field">
            <span className="evt-overview-field-icon" aria-hidden>
              <IconUser size={18} />
            </span>
            <div className="evt-overview-field-body">
              <p className="details-label">Facilitator</p>
              <p className="details-value">{event?.facilitator || "—"}</p>
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
                  {event?.budget != null ? `Rs ${Number(event.budget).toLocaleString()}` : "—"}
                </span>
                {event?.budget_breakdown_web_view_link ? (
                  <button
                    type="button"
                    className="details-button"
                    onClick={() =>
                      window.open(event.budget_breakdown_web_view_link, "_blank", "noopener,noreferrer")
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
                {event?.status ? (
                  <span className={`status-pill ${String(event.status).toLowerCase()}`}>{event.status}</span>
                ) : (
                  "—"
                )}
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
              <p className="details-value">{event?.description || "—"}</p>
            </div>
          </div>
        </div>
      </section>

      <section className="evt-workflow-section" aria-labelledby="evt-workflow-heading">
        <div className="evt-section-head">
          <span className="evt-section-head-icon" aria-hidden>
            <IconFlow size={22} />
          </span>
          <div>
            <h4 id="evt-workflow-heading" className="evt-section-title evt-section-title--large">
              Approval flow
            </h4>
            <p className="evt-section-sub evt-section-sub--tight">
              Registrar through IQAC. Multiple requests for one team are aggregated into a single status.
            </p>
          </div>
        </div>
        <ol className="evt-workflow-stepper">
          {steps.map((step, idx) => (
            <li key={step.key} className="evt-workflow-step">
              <div className="evt-workflow-connector" aria-hidden={idx === steps.length - 1} />
              <div className="evt-workflow-step-inner">
                <div className="evt-workflow-step-head">
                  <span className="evt-workflow-step-label">{step.label}</span>
                  <span className={wfBadgeClass(step.status)}>{wfBadgeLabel(step.status)}</span>
                </div>
                <div className="evt-workflow-meta">
                  {step.assignee ? (
                    <div className="evt-workflow-meta-block">
                      <span className="evt-meta-k">Assigned / contact</span>
                      <span className="evt-meta-v">{step.assignee}</span>
                    </div>
                  ) : step.status === "none" ? (
                    <span className="evt-meta-muted">No record yet</span>
                  ) : null}
                  {step.at ? (
                    <div className="evt-workflow-meta-block">
                      <span className="evt-meta-k">Updated</span>
                      <span className="evt-meta-v">{formatModalDateTime(step.at) || "—"}</span>
                    </div>
                  ) : null}
                </div>
              </div>
            </li>
          ))}
        </ol>
      </section>

      {details?.approval_request?.id && currentUserId ? (
        <ApprovalDiscussionTree
          approvalRequestId={details.approval_request.id}
          currentUserId={currentUserId}
          isFacultyViewer={viewerRole === "faculty"}
          viewerRole={viewerRole}
          onRefresh={onRefreshDetails}
          openApprovalThread={openApprovalThread}
          onOpenActionModal={onOpenActionModal}
        />
      ) : null}

      <DepartmentRequirementsDeck
        deptSections={deptSections}
        viewerRole={viewerRole}
        getMarketingDeliverableLabel={getMarketingDeliverableLabel}
        isMarketingViewer={isMarketingViewer}
        onMarketingUpload={onMarketingUpload}
        getMarketingDeliverableUploadFlags={getMarketingDeliverableUploadFlags}
        deckSubtitle="Expand each card for phased requirements. Your department is listed first."
      />
    </div>
  );
}

export function ConnectedEventDetailsModalBody(props) {
  const { openApprovalThread } = useMessenger();
  return (
    <EventDetailsModalBody
      {...props}
      openApprovalThread={openApprovalThread}
    />
  );
}
