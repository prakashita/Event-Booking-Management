import { useEffect, useRef, useState } from "react";
import {
  DeptIconFacility,
  DeptIconIt,
  DeptIconMarketing,
  DeptIconTransport,
  IconCalendar,
  IconClipboard,
  IconDocument,
  IconFlow,
  IconMapPin,
  IconStatusRing,
  IconUploadCloud,
  IconUser,
  IconUsersAudience
} from "./icons/EventModalIcons";
import PremiumDatePicker from "./ui/PremiumDatePicker";
import PremiumTimePicker from "./ui/PremiumTimePicker";

const DEPT_TITLE = {
  facility: "Facility workflow",
  it: "IT support workflow",
  marketing: "Marketing workflow",
  transport: "Transport workflow"
};

const DEPT_REVIEW_LABEL = {
  facility: "Facility manager",
  it: "IT",
  marketing: "Marketing",
  transport: "Transport"
};

const DEPT_META = {
  facility: {
    eyebrow: "Operations",
    tone: "emerald",
    icon: DeptIconFacility,
    hint: "Facility support"
  },
  it: {
    eyebrow: "Technical readiness",
    tone: "blue",
    icon: DeptIconIt,
    hint: "Technical support"
  },
  marketing: {
    eyebrow: "Comms and creative",
    tone: "violet",
    icon: DeptIconMarketing,
    hint: "Marketing support"
  },
  transport: {
    eyebrow: "Movement plan",
    tone: "amber",
    icon: DeptIconTransport,
    hint: "Transport support"
  },
  review: {
    eyebrow: "Final verification",
    tone: "blue",
    icon: IconClipboard,
    hint: "Ready to submit"
  }
};

const REQUIREMENT_COPY = {
  facility: {
    venue_required: {
      icon: IconMapPin,
      title: "Venue setup",
      description: ""
    },
    refreshments: {
      icon: IconUsersAudience,
      title: "Refreshments",
      description: ""
    }
  },
  it: {
    online: {
      icon: IconFlow,
      title: "Online",
      description: ""
    },
    offline: {
      icon: IconMapPin,
      title: "Offline",
      description: ""
    },
    pa_system: {
      icon: IconStatusRing,
      title: "Audio system",
      description: ""
    },
    projection: {
      icon: IconDocument,
      title: "Projection",
      description: ""
    }
  },
  transport: {
    include_guest_cab: {
      icon: IconUser,
      title: "Cab for guest",
      description: ""
    },
    include_students: {
      icon: IconUsersAudience,
      title: "Students",
      description: ""
    }
  }
};

function eventValue(pendingEvent, eventForm, key) {
  return pendingEvent?.[key] || eventForm?.[key] || "";
}

function EventSummaryCard({ pendingEvent, eventForm, user, formatISTTime, activeDept, total, currentStep, collapsed, onToggleCollapse }) {
  const startDate = eventValue(pendingEvent, eventForm, "start_date");
  const endDate = eventValue(pendingEvent, eventForm, "end_date");
  const startTime = eventValue(pendingEvent, eventForm, "start_time");
  const endTime = eventValue(pendingEvent, eventForm, "end_time");
  const organizer = eventValue(pendingEvent, eventForm, "facilitator") || user?.name || user?.email || "Organizer";
  const eventName = eventValue(pendingEvent, eventForm, "name") || "Untitled event";
  const venue = eventValue(pendingEvent, eventForm, "venue_name") || "Venue pending";
  const MetaIcon = DEPT_META[activeDept]?.icon || IconClipboard;
  const summaryRows = [
    { label: "Date range", value: `${startDate || "--"}${endDate ? ` to ${endDate}` : ""}`, icon: IconCalendar },
    { label: "Time", value: `${formatISTTime(startTime) || "--"}${endTime ? ` to ${formatISTTime(endTime)}` : ""}`, icon: IconStatusRing },
    { label: "Organizer", value: organizer, icon: IconUser },
    { label: "Venue", value: venue, icon: IconMapPin }
  ];

  return (
    <aside className={`req-event-summary-card${collapsed ? " req-event-summary-card--collapsed" : ""}`}>
      <div className="req-summary-topline">
        <span className={`req-dept-mark req-dept-mark--${DEPT_META[activeDept]?.tone || "blue"}`} aria-hidden title={DEPT_REVIEW_LABEL[activeDept] || "Review"}>
          <MetaIcon size={20} />
        </span>
        <span className="req-summary-step" title={`Step ${currentStep} of ${total}`}>Step {currentStep} of {total}</span>
        <button
          type="button"
          className="req-summary-collapse-toggle"
          onClick={onToggleCollapse}
          aria-label={collapsed ? "Expand event summary" : "Collapse event summary"}
          title={collapsed ? "Expand summary" : "Collapse summary"}
        >
          <svg width="15" height="15" viewBox="0 0 15 15" fill="none" aria-hidden>
            <rect x="1" y="1" width="13" height="13" rx="2.5" stroke="currentColor" strokeWidth="1.35" />
            <line x1="5" y1="1" x2="5" y2="14" stroke="currentColor" strokeWidth="1.35" />
            {collapsed
              ? <path d="M8 5.5l2.5 2-2.5 2" stroke="currentColor" strokeWidth="1.35" strokeLinecap="round" strokeLinejoin="round" />
              : <path d="M10.5 5.5L8 7.5l2.5 2" stroke="currentColor" strokeWidth="1.35" strokeLinecap="round" strokeLinejoin="round" />
            }
          </svg>
        </button>
      </div>
      <div className="req-summary-title-group">
        <p className="req-summary-eyebrow">{DEPT_META[activeDept]?.eyebrow || "Department workflow"}</p>
        <h3>{eventName}</h3>
      </div>
      <div className="req-summary-meta">
        {summaryRows.map(({ label, value, icon: RowIcon }) => (
          <div className="req-summary-meta-row" key={label} title={`${label}: ${value}`}>
            <RowIcon size={17} />
            <div>
              <span>{label}</span>
              <strong>{value}</strong>
            </div>
          </div>
        ))}
      </div>
      <div className="req-summary-tags">
        <span>Cross-functional</span>
        <span>{DEPT_REVIEW_LABEL[activeDept] || "Review"}</span>
      </div>
      <p className="req-summary-hint">{DEPT_META[activeDept]?.hint || "Review every department before sending."}</p>
    </aside>
  );
}

function WorkflowLayout({ children, footer, activeDept, wizard, total, onClose, pendingEvent, eventForm, user, formatISTTime }) {
  const [summaryCollapsed, setSummaryCollapsed] = useState(false);
  const progress = wizard.phase === "review" ? 100 : Math.round(((wizard.stepIndex + 1) / Math.max(total, 1)) * 100);
  const currentStep = wizard.phase === "review" ? total : wizard.stepIndex + 1;

  return (
    <div className="approval-overlay req-workflow-overlay" role="dialog" aria-modal="true">
      <section className="req-workflow-panel" aria-labelledby="requirements-workflow-title">
        <div className="req-workflow-progress" aria-hidden>
          <span style={{ width: `${progress}%` }} />
        </div>
        <header className="req-workflow-header">
          <div>
            <p className="req-workflow-kicker">Send requirements</p>
            <h2 id="requirements-workflow-title">
              {wizard.phase === "review" ? "Review department requests" : DEPT_TITLE[activeDept] || "Department workflow"}
            </h2>
          </div>
          <div className="req-workflow-header-actions">
            <button type="button" className="modal-close req-workflow-close" onClick={onClose} aria-label="Close">
              &times;
            </button>
          </div>
        </header>
        <div className={`req-workflow-body${summaryCollapsed ? " req-workflow-body--summary-collapsed" : ""}`}>
          <EventSummaryCard
            pendingEvent={pendingEvent}
            eventForm={eventForm}
            user={user}
            formatISTTime={formatISTTime}
            activeDept={activeDept}
            total={total}
            currentStep={currentStep}
            collapsed={summaryCollapsed}
            onToggleCollapse={() => setSummaryCollapsed((prev) => !prev)}
          />
          <div className="req-workflow-main-wrap">
            <div className="req-workflow-main" key={`${wizard.phase}-${activeDept}`}>
              {children}
            </div>
            {footer ? <div className="req-workflow-footer-bar">{footer}</div> : null}
          </div>
        </div>
      </section>
    </div>
  );
}

function WorkflowSection({ eyebrow, title, hint, children }) {
  return (
    <section className="req-section">
      <div className="req-section-head">
        <div>
          {eyebrow ? <p>{eyebrow}</p> : null}
          <h4>{title}</h4>
        </div>
        {hint ? <span>{hint}</span> : null}
      </div>
      {children}
    </section>
  );
}

function WorkflowField({ label, children, wide = false, hint }) {
  return (
    <label className={`approval-field req-field${wide ? " req-field--wide" : ""}`}>
      <span>{label}</span>
      {children}
      {hint ? <small>{hint}</small> : null}
    </label>
  );
}

function RequirementCard({ icon: Icon, title, description, selected, onChange, type = "checkbox", name }) {
  return (
    <label className={`req-choice-card${selected ? " req-choice-card--selected" : ""}`}>
      <input type={type} name={name} checked={selected} onChange={onChange} />
      <span className="req-choice-icon" aria-hidden>
        <Icon size={20} />
      </span>
      <span className="req-choice-copy">
        <strong>{title}</strong>
        {description ? <span>{description}</span> : null}
      </span>
      <span className="req-choice-check" aria-hidden />
    </label>
  );
}

function NotesField({ label, value, onChange, placeholder }) {
  const textareaRef = useRef(null);
  const count = (value || "").length;

  useEffect(() => {
    const node = textareaRef.current;
    if (!node) return;
    node.style.height = "auto";
    node.style.height = `${Math.min(node.scrollHeight, 360)}px`;
    node.style.overflowY = node.scrollHeight > 360 ? "auto" : "hidden";
  }, [value]);

  return (
    <WorkflowField label={label} wide hint={`${count} characters`}>
      <textarea
        ref={textareaRef}
        rows="3"
        placeholder={placeholder}
        value={value}
        onChange={onChange}
      />
    </WorkflowField>
  );
}

function TimeQuickChips({ value, onChange }) {
  const slots = ["09:00", "10:00", "14:00", "16:00"];
  return (
    <div className="req-time-chips" aria-label="Suggested time slots">
      {slots.map((slot) => (
        <button
          key={slot}
          type="button"
          className={value === slot ? "active" : ""}
          onClick={() => onChange({ target: { value: slot } })}
        >
          {slot}
        </button>
      ))}
    </div>
  );
}

function TransportDateTimeFields({ form, handleFieldChange, prefix }) {
  const dateKey = prefix === "guest_pickup" ? "guest_pickup_date" : prefix === "guest_dropoff" ? "guest_dropoff_date" : "student_date";
  const timeKey = prefix === "guest_pickup" ? "guest_pickup_time" : prefix === "guest_dropoff" ? "guest_dropoff_time" : "student_time";
  return (
    <>
      <WorkflowField label={prefix === "guest_dropoff" ? "Drop off date" : "Date"}>
        <PremiumDatePicker value={form[dateKey]} onChange={handleFieldChange(dateKey)} />
      </WorkflowField>
      <WorkflowField label={prefix === "guest_dropoff" ? "Drop off time" : "Time"}>
        <PremiumTimePicker value={form[timeKey]} onChange={handleFieldChange(timeKey)} />
        <TimeQuickChips value={form[timeKey]} onChange={handleFieldChange(timeKey)} />
      </WorkflowField>
    </>
  );
}

function ContactGrid({ user, toValue, onToChange, placeholder }) {
  return (
    <section className="req-section req-section--routing">
      <div className="req-form-grid">
        <WorkflowField label="From">
          <input type="email" value={user?.email || ""} readOnly />
        </WorkflowField>
        <WorkflowField label="To">
          <input type="email" placeholder={placeholder} value={toValue} onChange={onToChange} />
        </WorkflowField>
      </div>
    </section>
  );
}

function ReviewLine({ label, children, muted }) {
  const [expanded, setExpanded] = useState(false);
  const text = String(children || "");
  const canExpand = label === "Notes" && text.length > 120;
  return (
    <li className={muted ? "req-review-muted" : ""}>
      <span>{label}</span>
      <strong className={canExpand && !expanded ? "req-review-note--clamped" : ""}>{children}</strong>
      {canExpand ? (
        <button type="button" className="req-review-expand" onClick={() => setExpanded((prev) => !prev)}>
          {expanded ? "Show less" : "Show more"}
        </button>
      ) : null}
    </li>
  );
}

export default function RequirementsWizardModal({
  wizard,
  user,
  pendingEvent,
  eventForm,
  formatISTTime,
  facilityForm,
  transportForm,
  marketingForm,
  itForm,
  marketingGroups,
  onClose,
  onPrev,
  onNext,
  onSkip,
  onSendAll,
  handleFacilityFieldChange,
  handleFacilityToggle,
  handleTransportFieldChange,
  setTransportForm,
  handleMarketingFieldChange,
  handleMarketingToggle,
  marketingAttachmentFiles = [],
  marketingAttachmentsInputRef,
  onMarketingAttachmentsPick,
  onRemoveMarketingAttachment,
  maxMarketingAttachmentFiles = 10,
  maxMarketingAttachmentFileMb = 25,
  handleItFieldChange,
  handleItToggle,
  setItForm
}) {
  if (!wizard.open) return null;

  const stepKey = wizard.phase === "edit" ? wizard.steps[wizard.stepIndex] : wizard.steps[0];
  const total = wizard.steps.length;
  const wizardCanSend = wizard.steps.some((s) => !wizard.skipped[s]);

  const marketingCheckedLines = () => {
    const lines = [];
    for (const group of marketingGroups) {
      for (const field of group.fields) {
        if (marketingForm.marketing_requirements?.[group.key]?.[field.key]) {
          lines.push(`${group.title}: ${field.label}`);
        }
      }
    }
    return lines;
  };

  const renderFooter = () => (
    <>
      {wizard.error ? <p className="form-error wizard-form-error">{wizard.error}</p> : null}
      {wizard.phase === "edit" ? (
        <div className="modal-actions requirements-modal-actions req-sticky-actions">
          <button type="button" className="secondary-action" onClick={onPrev} disabled={wizard.stepIndex <= 0}>
            Back
          </button>
          <button type="button" className="secondary-action req-action-quiet" onClick={onSkip}>
            Skip
          </button>
          <button type="button" className="primary-action req-primary-action" onClick={onNext}>
            {wizard.stepIndex >= wizard.steps.length - 1 ? "Review" : "Next"}
          </button>
        </div>
      ) : (
        <div className="modal-actions requirements-modal-actions req-sticky-actions">
          <button type="button" className="secondary-action" onClick={onPrev}>
            Back
          </button>
          <button
            type="button"
            className="primary-action req-primary-action"
            onClick={onSendAll}
            disabled={wizard.status === "loading" || !wizardCanSend}
          >
            {wizard.status === "loading" ? "Sending..." : "Submit requests"}
          </button>
        </div>
      )}
    </>
  );

  return (
    <WorkflowLayout
      activeDept={wizard.phase === "review" ? "review" : stepKey}
      wizard={wizard}
      total={total}
      onClose={onClose}
      pendingEvent={pendingEvent}
      eventForm={eventForm}
      user={user}
      formatISTTime={formatISTTime}
      footer={renderFooter()}
    >
      {wizard.phase === "edit" && stepKey === "facility" ? (
        <>
          <ContactGrid
            user={user}
            toValue={facilityForm.to}
            onToChange={handleFacilityFieldChange("to")}
            placeholder="facilitymanager@campus.edu"
          />
          <WorkflowSection title="Facility support">
            <div className="req-choice-grid">
              <RequirementCard
                {...REQUIREMENT_COPY.facility.venue_required}
                selected={facilityForm.venue_required}
                onChange={handleFacilityToggle("venue_required")}
              />
              <RequirementCard
                {...REQUIREMENT_COPY.facility.refreshments}
                selected={facilityForm.refreshments}
                onChange={handleFacilityToggle("refreshments")}
              />
            </div>
          </WorkflowSection>
          <WorkflowSection title="Additional details">
            <NotesField
              label="Notes"
              placeholder="Add room layout, headcount, hospitality, or setup details."
              value={facilityForm.other_notes}
              onChange={handleFacilityFieldChange("other_notes")}
            />
          </WorkflowSection>
        </>
      ) : null}

      {wizard.phase === "edit" && stepKey === "it" ? (
        <>
          <ContactGrid user={user} toValue={itForm.to} onToChange={handleItFieldChange("to")} placeholder="it@campus.edu" />
          <WorkflowSection title="Event mode">
            <div className="req-choice-grid req-choice-grid--two">
              <RequirementCard
                {...REQUIREMENT_COPY.it.online}
                type="radio"
                name="it_event_mode_wizard"
                selected={itForm.event_mode === "online"}
                onChange={() => setItForm((prev) => ({ ...prev, event_mode: "online" }))}
              />
              <RequirementCard
                {...REQUIREMENT_COPY.it.offline}
                type="radio"
                name="it_event_mode_wizard"
                selected={itForm.event_mode === "offline"}
                onChange={() => setItForm((prev) => ({ ...prev, event_mode: "offline" }))}
              />
            </div>
          </WorkflowSection>
          <WorkflowSection title="Technical services">
            <div className="req-choice-grid req-choice-grid--two">
              <RequirementCard {...REQUIREMENT_COPY.it.pa_system} selected={itForm.pa_system} onChange={handleItToggle("pa_system")} />
              <RequirementCard {...REQUIREMENT_COPY.it.projection} selected={itForm.projection} onChange={handleItToggle("projection")} />
            </div>
          </WorkflowSection>
          <WorkflowSection title="Additional details">
            <NotesField
              label="Notes"
              placeholder="Mention microphones, display source, streaming, recording, or special equipment."
              value={itForm.other_notes}
              onChange={handleItFieldChange("other_notes")}
            />
          </WorkflowSection>
        </>
      ) : null}

      {wizard.phase === "edit" && stepKey === "marketing" ? (
        <>
          <ContactGrid
            user={user}
            toValue={marketingForm.to}
            onToChange={handleMarketingFieldChange("to")}
            placeholder="marketing@campus.edu"
          />
          <WorkflowSection title="Marketing deliverables">
            <div className="req-marketing-groups">
              {marketingGroups.map((group) => (
                <div key={group.key} className="req-mini-section">
                  <div className="req-mini-section-head">
                    <IconClipboard size={16} />
                    <span>{group.title}</span>
                  </div>
                  <div className="req-choice-grid req-choice-grid--compact">
                    {group.fields.map((field) => (
                      <RequirementCard
                        key={`${group.key}-${field.key}`}
                        icon={IconDocument}
                        title={field.label}
                        description=""
                        selected={Boolean(marketingForm.marketing_requirements?.[group.key]?.[field.key])}
                        onChange={handleMarketingToggle(group.key, field.key)}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </WorkflowSection>
          <WorkflowSection title="Notes and documents">
            <div className="req-form-grid">
              <NotesField
                label="Notes"
                placeholder="Add copy direction, branding notes, expected deliverables, or deadlines."
                value={marketingForm.other_notes}
                onChange={handleMarketingFieldChange("other_notes")}
              />
              <WorkflowField
                label="Attachments"
                wide
                hint={`Any additional documents are optional · Up to ${maxMarketingAttachmentFiles} files, ${maxMarketingAttachmentFileMb} MB each`}
              >
                <div className="req-file-drop">
                  <IconUploadCloud size={20} />
                  <span className="req-file-drop-copy">Drop files here or browse</span>
                  <input
                    ref={marketingAttachmentsInputRef}
                    type="file"
                    multiple
                    className="marketing-requester-docs-input"
                    onChange={onMarketingAttachmentsPick}
                    onDragOver={(event) => event.preventDefault()}
                    onDrop={(event) => {
                      event.preventDefault();
                      onMarketingAttachmentsPick({ target: { files: event.dataTransfer.files, value: "" } });
                    }}
                    accept=".pdf,.doc,.docx,.png,.jpg,.jpeg,.webp,.txt,application/pdf"
                  />
                </div>
                {marketingAttachmentFiles.length ? (
                  <ul className="marketing-attachment-chips req-attachment-chips">
                    {marketingAttachmentFiles.map((f, i) => (
                      <li key={`${f.name}-${i}-${f.size}`}>
                        <span>{f.name}</span>
                        <button
                          type="button"
                          className="link-button marketing-attachment-remove"
                          onClick={() => onRemoveMarketingAttachment(i)}
                        >
                          Remove
                        </button>
                      </li>
                    ))}
                  </ul>
                ) : null}
              </WorkflowField>
            </div>
          </WorkflowSection>
        </>
      ) : null}

      {wizard.phase === "edit" && stepKey === "transport" ? (
        <>
          <ContactGrid
            user={user}
            toValue={transportForm.to}
            onToChange={handleTransportFieldChange("to")}
            placeholder="transport@campus.edu"
          />
          <WorkflowSection title="Transport type">
            <div className="req-choice-grid req-choice-grid--two">
              <RequirementCard
                {...REQUIREMENT_COPY.transport.include_guest_cab}
                selected={transportForm.include_guest_cab}
                onChange={(e) => setTransportForm((prev) => ({ ...prev, include_guest_cab: e.target.checked }))}
              />
              <RequirementCard
                {...REQUIREMENT_COPY.transport.include_students}
                selected={transportForm.include_students}
                onChange={(e) => setTransportForm((prev) => ({ ...prev, include_students: e.target.checked }))}
              />
            </div>
          </WorkflowSection>
          {transportForm.include_guest_cab ? (
            <WorkflowSection title="Guest cab">
              <div className="req-transport-columns">
                <div className="req-transport-card">
                  <p>Pickup</p>
                  <WorkflowField label="Location">
                    <input
                      type="text"
                      value={transportForm.guest_pickup_location}
                      onChange={handleTransportFieldChange("guest_pickup_location")}
                      placeholder="Address or landmark"
                    />
                  </WorkflowField>
                  <TransportDateTimeFields form={transportForm} handleFieldChange={handleTransportFieldChange} prefix="guest_pickup" />
                </div>
                <div className="req-transport-card">
                  <p>Drop</p>
                  <WorkflowField label="Location">
                    <input
                      type="text"
                      value={transportForm.guest_dropoff_location}
                      onChange={handleTransportFieldChange("guest_dropoff_location")}
                      placeholder="Address or landmark"
                    />
                  </WorkflowField>
                  <TransportDateTimeFields form={transportForm} handleFieldChange={handleTransportFieldChange} prefix="guest_dropoff" />
                </div>
              </div>
            </WorkflowSection>
          ) : null}
          {transportForm.include_students ? (
            <WorkflowSection title="Student transport">
              <div className="req-form-grid">
                <WorkflowField label="Number of students">
                  <input
                    type="number"
                    min="1"
                    step="1"
                    value={transportForm.student_count}
                    onChange={handleTransportFieldChange("student_count")}
                  />
                </WorkflowField>
                <WorkflowField label="Kind of transport">
                  <input
                    type="text"
                    value={transportForm.student_transport_kind}
                    onChange={handleTransportFieldChange("student_transport_kind")}
                    placeholder="e.g. bus, van"
                  />
                </WorkflowField>
                <TransportDateTimeFields form={transportForm} handleFieldChange={handleTransportFieldChange} prefix="student" />
                <WorkflowField label="Pick up point" wide>
                  <input
                    type="text"
                    value={transportForm.student_pickup_point}
                    onChange={handleTransportFieldChange("student_pickup_point")}
                    placeholder="Meeting point for students"
                  />
                </WorkflowField>
              </div>
            </WorkflowSection>
          ) : null}
          <WorkflowSection title="Additional details">
            <NotesField
              label="Notes"
              placeholder="Add route, waiting time, guest phone, or vehicle preferences."
              value={transportForm.other_notes}
              onChange={handleTransportFieldChange("other_notes")}
            />
          </WorkflowSection>
        </>
      ) : null}

      {wizard.phase === "review" ? (
        <>
          <WorkflowSection title="Final check">
            <div className="req-review-grid">
              {wizard.steps.map((dept) => (
                <article key={dept} className={`req-review-card${wizard.skipped[dept] ? " req-review-card--muted" : ""}`}>
                  <div className="req-review-card-head">
                    <span className={`req-dept-mark req-dept-mark--${DEPT_META[dept]?.tone || "blue"}`} aria-hidden>
                      {(() => {
                        const Icon = DEPT_META[dept]?.icon || IconClipboard;
                        return <Icon size={18} />;
                      })()}
                    </span>
                    <div>
                      <h4>{DEPT_REVIEW_LABEL[dept]}</h4>
                      <p>{wizard.skipped[dept] ? "Skipped" : "Ready to send"}</p>
                    </div>
                  </div>
                  {wizard.skipped[dept] ? (
                    <p className="req-review-skipped">This request will not be sent.</p>
                  ) : dept === "facility" ? (
                    <ul className="req-review-list">
                      <ReviewLine label="To">{facilityForm.to || "(default desk)"}</ReviewLine>
                      <ReviewLine label="Venue setup">{facilityForm.venue_required ? "Yes" : "No"}</ReviewLine>
                      <ReviewLine label="Refreshments">{facilityForm.refreshments ? "Yes" : "No"}</ReviewLine>
                      {facilityForm.other_notes?.trim() ? <ReviewLine label="Notes">{facilityForm.other_notes.trim()}</ReviewLine> : null}
                    </ul>
                  ) : dept === "it" ? (
                    <ul className="req-review-list">
                      <ReviewLine label="To">{itForm.to || "(default desk)"}</ReviewLine>
                      <ReviewLine label="Mode">{itForm.event_mode === "online" ? "Online" : "Offline"}</ReviewLine>
                      <ReviewLine label="Audio system">{itForm.pa_system ? "Yes" : "No"}</ReviewLine>
                      <ReviewLine label="Projection">{itForm.projection ? "Yes" : "No"}</ReviewLine>
                      {itForm.other_notes?.trim() ? <ReviewLine label="Notes">{itForm.other_notes.trim()}</ReviewLine> : null}
                    </ul>
                  ) : dept === "marketing" ? (
                    <ul className="req-review-list">
                      <ReviewLine label="To">{marketingForm.to || "(default desk)"}</ReviewLine>
                      {marketingCheckedLines().length ? (
                        marketingCheckedLines().map((line) => <ReviewLine key={line} label="Item">{line}</ReviewLine>)
                      ) : (
                        <ReviewLine label="Items" muted>No items selected</ReviewLine>
                      )}
                      {marketingForm.other_notes?.trim() ? <ReviewLine label="Notes">{marketingForm.other_notes.trim()}</ReviewLine> : null}
                      {marketingAttachmentFiles.length ? <ReviewLine label="Files">{marketingAttachmentFiles.length} attached</ReviewLine> : null}
                    </ul>
                  ) : dept === "transport" ? (
                    <ul className="req-review-list">
                      <ReviewLine label="To">{transportForm.to || "(default desk)"}</ReviewLine>
                      <ReviewLine label="Guest cab">{transportForm.include_guest_cab ? "Yes" : "No"}</ReviewLine>
                      <ReviewLine label="Students">{transportForm.include_students ? "Yes" : "No"}</ReviewLine>
                      {transportForm.include_guest_cab ? (
                        <ReviewLine label="Guest">
                          {transportForm.guest_pickup_location || "-"} to {transportForm.guest_dropoff_location || "-"}
                        </ReviewLine>
                      ) : null}
                      {transportForm.include_students ? (
                        <ReviewLine label="Students">
                          {transportForm.student_count || "-"} via {transportForm.student_transport_kind || "-"}
                        </ReviewLine>
                      ) : null}
                      {transportForm.other_notes?.trim() ? <ReviewLine label="Notes">{transportForm.other_notes.trim()}</ReviewLine> : null}
                    </ul>
                  ) : null}
                </article>
              ))}
            </div>
            {!wizardCanSend ? (
              <p className="req-empty-state">All departments were skipped. Go back to include at least one request.</p>
            ) : null}
          </WorkflowSection>
        </>
      ) : null}
    </WorkflowLayout>
  );
}
