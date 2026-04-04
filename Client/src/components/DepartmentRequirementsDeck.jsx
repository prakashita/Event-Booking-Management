import {
  DeptIconFacility,
  DeptIconIqac,
  DeptIconIt,
  DeptIconMarketing,
  DeptIconTransport,
  IconLayers,
  IconUploadCloud
} from "./icons/EventModalIcons";
import { formatModalDateTime, normalizeDecisionStatusForWf, viewerDepartmentKey, wfBadgeClass, wfBadgeLabel } from "../utils/eventDetailsView";

const DEPT_ICONS = {
  marketing: DeptIconMarketing,
  facility: DeptIconFacility,
  it: DeptIconIt,
  transport: DeptIconTransport,
  iqac: DeptIconIqac
};

export default function DepartmentRequirementsDeck({
  deptSections,
  viewerRole,
  getMarketingDeliverableLabel,
  isMarketingViewer = false,
  onMarketingUpload,
  getMarketingDeliverableUploadFlags,
  deckSubtitle,
  deckEmptyMessage,
  sectionId = "evt-req-heading"
}) {
  const highlightDept = viewerDepartmentKey(viewerRole);

  if (!deptSections?.length) {
    return (
      <section className="evt-requirements-section" aria-labelledby={sectionId}>
        <div className="evt-section-head">
          <span className="evt-section-head-icon" aria-hidden>
            <IconLayers size={22} />
          </span>
          <div>
            <h4 id={sectionId} className="evt-section-title evt-section-title--large">
              Requirements by department
            </h4>
            {deckSubtitle ? (
              <p className="evt-section-sub evt-section-sub--tight">{deckSubtitle}</p>
            ) : null}
          </div>
        </div>
        <p className="evt-req-empty-hint evt-req-empty-hint--boxed">
          {deckEmptyMessage ||
            "No departmental requirement rows to show. After approval, linked Facility, IT, Marketing, and Transport requests appear here when available."}
        </p>
      </section>
    );
  }

  return (
    <section className="evt-requirements-section" aria-labelledby={sectionId}>
      <div className="evt-section-head">
        <span className="evt-section-head-icon" aria-hidden>
          <IconLayers size={22} />
        </span>
        <div>
          <h4 id={sectionId} className="evt-section-title evt-section-title--large">
            Requirements by department
          </h4>
          <p className="evt-section-sub evt-section-sub--tight">
            {deckSubtitle ||
              "Expand each card for phased requirements. Your department is listed first when applicable."}
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
                              <span className="evt-req-assignee-k">By</span> <strong>{block.decidedBy}</strong>
                              {block.decidedAt ? (
                                <span className="evt-req-at"> · {formatModalDateTime(block.decidedAt) || ""}</span>
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
  );
}
