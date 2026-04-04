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
import {
  buildWorkflowStepperSteps,
  collectDepartmentRequirementSections,
  formatModalDateTime,
  formatWorkflowActionTypeLabel,
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
  getMarketingDeliverableUploadFlags
}) {
  const event = details?.event;
  const eventName = event?.name || fallbackEventName || "—";
  const intendedAudience = event?.intendedAudience ?? event?.intended_audience ?? null;
  const steps = buildWorkflowStepperSteps(details);
  const actionLogs = Array.isArray(details?.workflow_action_logs) ? details.workflow_action_logs : [];
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

      {actionLogs.length > 0 ? (
        <section className="evt-action-history-section" aria-labelledby="evt-action-history-heading">
          <div className="evt-section-head">
            <span className="evt-section-head-icon" aria-hidden>
              <IconFlow size={22} />
            </span>
            <h4 id="evt-action-history-heading" className="evt-section-title evt-section-title--large">
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
