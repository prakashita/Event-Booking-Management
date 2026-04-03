import {
  DeptIconFacility,
  DeptIconIqac,
  DeptIconIt,
  DeptIconMarketing,
  DeptIconTransport,
  IconCalendar,
  IconDocument,
  IconFlag,
  IconFlow,
  IconLayers,
  IconMapPin,
  IconStatusRing,
  IconUploadCloud,
  IconUser,
  IconUsersAudience,
  IconWallet
} from "./icons/EventModalIcons";
import {
  buildWorkflowStepperSteps,
  collectDepartmentRequirementSections,
  formatModalDateTime,
  normalizeDecisionStatusForWf,
  orderDepartmentSectionsForRole,
  viewerDepartmentKey,
  wfBadgeClass,
  wfBadgeLabel
} from "../utils/eventDetailsView";

const DEPT_ICONS = {
  marketing: DeptIconMarketing,
  facility: DeptIconFacility,
  it: DeptIconIt,
  transport: DeptIconTransport,
  iqac: DeptIconIqac
};

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
  const deptSections = orderDepartmentSectionsForRole(
    viewerRole,
    collectDepartmentRequirementSections(details, normalizeMarketingRequirements, transportRequestTypeLabel)
  );
  const highlightDept = viewerDepartmentKey(viewerRole);

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

      <section className="evt-requirements-section" aria-labelledby="evt-req-heading">
        <div className="evt-section-head">
          <span className="evt-section-head-icon" aria-hidden>
            <IconLayers size={22} />
          </span>
          <div>
            <h4 id="evt-req-heading" className="evt-section-title evt-section-title--large">
              Requirements by department
            </h4>
            <p className="evt-section-sub evt-section-sub--tight">
              Expand each card for phased requirements. Your department is listed first.
            </p>
          </div>
        </div>
        <div className="evt-req-deck">
          {deptSections.map((section, idx) => {
            const isYou = highlightDept && section.key === highlightDept;
            const defaultOpen = isYou || (!highlightDept && idx === 0);
            const IconCmp = DEPT_ICONS[section.iconKey] || DeptIconFacility;
            return (
              <details
                key={section.key}
                className={`evt-req-card${isYou ? " evt-req-card--you" : ""}`}
                defaultOpen={defaultOpen}
              >
                <summary className="evt-req-summary">
                  <span className="evt-req-summary-title">
                    <span className="evt-req-icon" aria-hidden>
                      <IconCmp />
                    </span>
                    {section.title}
                  </span>
                  {isYou ? (
                    <span className="evt-your-badge" title="Your department">
                      YOUR RESPONSIBILITY
                    </span>
                  ) : null}
                </summary>
                <div className="evt-req-card-body">
                  {section.blocks.map((block) => {
                    const wf = normalizeDecisionStatusForWf(block.status);
                    const marketingReq = block.marketingRequest;
                    const uploadFlags =
                      marketingReq && getMarketingDeliverableUploadFlags
                        ? getMarketingDeliverableUploadFlags(marketingReq)
                        : {};
                    const hasUploadSlots =
                      marketingReq &&
                      getMarketingDeliverableUploadFlags &&
                      Object.values(uploadFlags).some(Boolean);
                    return (
                      <div key={block.id} className="evt-req-block">
                        {block.subtitle ? <p className="evt-req-block-sub">{block.subtitle}</p> : null}
                        <div className="evt-req-block-status">
                          <span className={wfBadgeClass(wf)}>{wfBadgeLabel(wf)}</span>
                          <div className="evt-req-people">
                            {block.requestedTo ? (
                              <p className="evt-req-assignee">
                                <span className="evt-req-assignee-k">Assigned</span>{" "}
                                <a href={`mailto:${block.requestedTo}`}>{block.requestedTo}</a>
                              </p>
                            ) : null}
                            {block.decidedBy ? (
                              <p className="evt-req-decided">
                                <span className="evt-req-assignee-k">By</span>{" "}
                                <strong>{block.decidedBy}</strong>
                                {block.decidedAt ? (
                                  <span className="evt-req-at">
                                    {" "}
                                    · {formatModalDateTime(block.decidedAt) || ""}
                                  </span>
                                ) : null}
                              </p>
                            ) : null}
                          </div>
                        </div>
                        {block.phases.map((phase, pi) => (
                          <div key={`${block.id}-${phase.title}-${pi}`} className="evt-req-phase">
                            <p className="evt-req-phase-title">{phase.title}</p>
                            <ul className="evt-req-items">
                              {phase.items.map((item, ii) => (
                                <li key={`${item}-${ii}`}>{item}</li>
                              ))}
                            </ul>
                          </div>
                        ))}
                        {section.key === "iqac" && block.reportLink ? (
                          <p className="evt-req-report">
                            <a href={block.reportLink} target="_blank" rel="noreferrer">
                              {block.reportName || "View event report"}
                            </a>
                          </p>
                        ) : null}
                        {section.key === "marketing" ? (
                          <div className="evt-req-deliverables">
                            <p className="evt-req-phase-title">Uploaded deliverables</p>
                            {block.deliverables?.length ? (
                              <ul className="evt-req-items">
                                {block.deliverables.map((d, j) => (
                                  <li key={j}>
                                    {d.is_na ? (
                                      <span>{getMarketingDeliverableLabel(d.deliverable_type)}: N/A</span>
                                    ) : d.web_view_link ? (
                                      <a href={d.web_view_link} target="_blank" rel="noreferrer">
                                        {d.file_name || getMarketingDeliverableLabel(d.deliverable_type)}
                                      </a>
                                    ) : (
                                      <span>{d.file_name || getMarketingDeliverableLabel(d.deliverable_type)}</span>
                                    )}
                                  </li>
                                ))}
                              </ul>
                            ) : (
                              <p className="evt-req-empty-hint">No files uploaded yet.</p>
                            )}
                            {isMarketingViewer && marketingReq && onMarketingUpload ? (
                              <div className="evt-marketing-upload">
                                <button
                                  type="button"
                                  className="details-button upload evt-upload-btn"
                                  disabled={!hasUploadSlots}
                                  title={
                                    hasUploadSlots
                                      ? "Open the same upload flow as the marketing inbox"
                                      : "No file uploads for this request (during-event videoshoot / photoshoot only)."
                                  }
                                  onClick={() => onMarketingUpload(marketingReq)}
                                >
                                  <IconUploadCloud className="evt-upload-btn-icon" size={16} />
                                  Upload
                                </button>
                              </div>
                            ) : null}
                          </div>
                        ) : null}
                      </div>
                    );
                  })}
                </div>
              </details>
            );
          })}
        </div>
      </section>
    </div>
  );
}
