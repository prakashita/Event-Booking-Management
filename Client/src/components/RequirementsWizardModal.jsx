const DEPT_TITLE = {
  facility: "FACILITY MANAGER REQUEST",
  it: "IT SUPPORT REQUEST",
  marketing: "MARKETING REQUEST",
  transport: "TRANSPORT REQUEST"
};

const DEPT_REVIEW_LABEL = {
  facility: "Facility manager",
  it: "IT",
  marketing: "Marketing",
  transport: "Transport"
};

function EventSummary({ pendingEvent, eventForm, formatISTTime }) {
  return (
    <div className="approval-summary">
      <p>
        <strong>Event:</strong> {pendingEvent?.name || eventForm.name || "Untitled event"}
      </p>
      <p>
        <strong>Date:</strong> {pendingEvent?.start_date || eventForm.start_date || "--"}{" "}
        {pendingEvent?.end_date
          ? `to ${pendingEvent.end_date}`
          : eventForm.end_date
            ? `to ${eventForm.end_date}`
            : ""}
      </p>
      <p>
        <strong>Time:</strong> {formatISTTime(pendingEvent?.start_time || eventForm.start_time) || "--"}{" "}
        {pendingEvent?.end_time
          ? `to ${formatISTTime(pendingEvent.end_time)}`
          : eventForm.end_time
            ? `to ${formatISTTime(eventForm.end_time)}`
            : ""}
      </p>
    </div>
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

  const stepKey = wizard.phase === "edit" ? wizard.steps[wizard.stepIndex] : null;
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

  return (
    <div className="approval-overlay" role="dialog" aria-modal="true">
      <div className="marketing-card marketing-card--scrollable">
        <div className="approval-header">
          <h3>{wizard.phase === "review" ? "Review requirements" : DEPT_TITLE[stepKey] || "Requirements"}</h3>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">
            &times;
          </button>
        </div>

        {wizard.phase === "edit" ? (
          <p className="form-hint wizard-step-hint">
            Step {wizard.stepIndex + 1} of {total}. Use Next to continue, Prev to go back, or Skip to exclude this
            department.
          </p>
        ) : null}

        <div className="approval-form requirements-scroll-form">
          <div className="requirements-form-scroll">
        {wizard.phase === "edit" && stepKey === "facility" ? (
          <>
            <div className="approval-grid">
              <label className="approval-field">
                <span>From</span>
                <input type="email" value={user?.email || ""} readOnly />
              </label>
              <label className="approval-field">
                <span>To</span>
                <input
                  type="email"
                  placeholder="facilitymanager@campus.edu"
                  value={facilityForm.to}
                  onChange={handleFacilityFieldChange("to")}
                />
              </label>
            </div>
            <EventSummary pendingEvent={pendingEvent} eventForm={eventForm} formatISTTime={formatISTTime} />
            <div className="approval-requirements">
              <p>Requirements:</p>
              <label>
                <input
                  type="checkbox"
                  checked={facilityForm.venue_required}
                  onChange={handleFacilityToggle("venue_required")}
                />
                Venue setup
              </label>
              <label>
                <input
                  type="checkbox"
                  checked={facilityForm.refreshments}
                  onChange={handleFacilityToggle("refreshments")}
                />
                Refreshments
              </label>
            </div>
            <label className="approval-field">
              <span>Others</span>
              <textarea
                rows="4"
                placeholder="Add additional notes for the facility manager."
                value={facilityForm.other_notes}
                onChange={handleFacilityFieldChange("other_notes")}
              />
            </label>
          </>
        ) : null}

        {wizard.phase === "edit" && stepKey === "it" ? (
          <>
            <div className="approval-grid">
              <label className="approval-field">
                <span>From</span>
                <input type="email" value={user?.email || ""} readOnly />
              </label>
              <label className="approval-field">
                <span>To</span>
                <input
                  type="email"
                  placeholder="it@campus.edu"
                  value={itForm.to}
                  onChange={handleItFieldChange("to")}
                />
              </label>
            </div>
            <EventSummary pendingEvent={pendingEvent} eventForm={eventForm} formatISTTime={formatISTTime} />
            <div className="marketing-requirements">
              <p>Event mode</p>
              <div className="marketing-grid">
                <label>
                  <input
                    type="radio"
                    name="it_event_mode_wizard"
                    value="online"
                    checked={itForm.event_mode === "online"}
                    onChange={() => setItForm((prev) => ({ ...prev, event_mode: "online" }))}
                  />
                  Online
                </label>
                <label>
                  <input
                    type="radio"
                    name="it_event_mode_wizard"
                    value="offline"
                    checked={itForm.event_mode === "offline"}
                    onChange={() => setItForm((prev) => ({ ...prev, event_mode: "offline" }))}
                  />
                  Offline
                </label>
              </div>
            </div>
            <div className="marketing-requirements">
              <p>Requirements:</p>
              <div className="marketing-grid">
                <label>
                  <input type="checkbox" checked={itForm.pa_system} onChange={handleItToggle("pa_system")} />
                  PA System
                </label>
                <label>
                  <input type="checkbox" checked={itForm.projection} onChange={handleItToggle("projection")} />
                  Projection
                </label>
              </div>
            </div>
            <label className="approval-field">
              <span>Others</span>
              <textarea
                rows="4"
                placeholder="Add additional notes for IT."
                value={itForm.other_notes}
                onChange={handleItFieldChange("other_notes")}
              />
            </label>
          </>
        ) : null}

        {wizard.phase === "edit" && stepKey === "marketing" ? (
          <>
            <div className="approval-grid">
              <label className="approval-field">
                <span>From</span>
                <input type="email" value={user?.email || ""} readOnly />
              </label>
              <label className="approval-field">
                <span>To</span>
                <input
                  type="email"
                  placeholder="marketing@campus.edu"
                  value={marketingForm.to}
                  onChange={handleMarketingFieldChange("to")}
                />
              </label>
            </div>
            <EventSummary pendingEvent={pendingEvent} eventForm={eventForm} formatISTTime={formatISTTime} />
            <div className="marketing-requirements">
              <p>Requirements:</p>
              {marketingGroups.map((group) => (
                <div key={group.key} className="marketing-group">
                  <p className="form-hint">{group.title}</p>
                  <div className="marketing-grid">
                    {group.fields.map((field) => (
                      <label key={`${group.key}-${field.key}`}>
                        <input
                          type="checkbox"
                          checked={Boolean(marketingForm.marketing_requirements?.[group.key]?.[field.key])}
                          onChange={handleMarketingToggle(group.key, field.key)}
                        />
                        {field.label}
                      </label>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            <label className="approval-field">
              <span>Others</span>
              <textarea
                rows="4"
                placeholder="Add additional notes for the marketing team."
                value={marketingForm.other_notes}
                onChange={handleMarketingFieldChange("other_notes")}
              />
            </label>
            <label className="approval-field">
              <span>Any necessary documents (optional)</span>
              <input
                ref={marketingAttachmentsInputRef}
                type="file"
                multiple
                className="marketing-requester-docs-input"
                onChange={onMarketingAttachmentsPick}
                accept=".pdf,.doc,.docx,.png,.jpg,.jpeg,.webp,.txt,application/pdf"
              />
              <p className="form-hint">
                Up to {maxMarketingAttachmentFiles} files, {maxMarketingAttachmentFileMb} MB each (PDF, Word, images,
                text). Files upload after the request is created; Google must be connected.
              </p>
              {marketingAttachmentFiles.length ? (
                <ul className="marketing-attachment-chips">
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
            </label>
          </>
        ) : null}

        {wizard.phase === "edit" && stepKey === "transport" ? (
          <>
              <div className="approval-grid">
                <label className="approval-field">
                  <span>From</span>
                  <input type="email" value={user?.email || ""} readOnly />
                </label>
                <label className="approval-field">
                  <span>To</span>
                  <input
                    type="email"
                    placeholder="transport@campus.edu"
                    value={transportForm.to}
                    onChange={handleTransportFieldChange("to")}
                  />
                </label>
              </div>
              <EventSummary pendingEvent={pendingEvent} eventForm={eventForm} formatISTTime={formatISTTime} />
              <div className="approval-requirements">
                <p>Transport arrangement (you can select both)</p>
                <label>
                  <input
                    type="checkbox"
                    checked={transportForm.include_guest_cab}
                    onChange={(e) =>
                      setTransportForm((prev) => ({
                        ...prev,
                        include_guest_cab: e.target.checked
                      }))
                    }
                  />
                  Cab for guest
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={transportForm.include_students}
                    onChange={(e) =>
                      setTransportForm((prev) => ({
                        ...prev,
                        include_students: e.target.checked
                      }))
                    }
                  />
                  Students (off-campus event)
                </label>
              </div>
              {transportForm.include_guest_cab ? (
                <div className="form-grid" style={{ marginTop: "0.75rem" }}>
                  <p className="details-sublabel" style={{ gridColumn: "1 / -1", margin: 0 }}>
                    Guest cab
                  </p>
                  <label className="approval-field">
                    <span>Pick up location</span>
                    <input
                      type="text"
                      value={transportForm.guest_pickup_location}
                      onChange={handleTransportFieldChange("guest_pickup_location")}
                      placeholder="Address or landmark"
                    />
                  </label>
                  <label className="approval-field">
                    <span>Pick up date</span>
                    <input
                      type="date"
                      value={transportForm.guest_pickup_date}
                      onChange={handleTransportFieldChange("guest_pickup_date")}
                    />
                  </label>
                  <label className="approval-field">
                    <span>Pick up time</span>
                    <input
                      type="time"
                      value={transportForm.guest_pickup_time}
                      onChange={handleTransportFieldChange("guest_pickup_time")}
                    />
                  </label>
                  <label className="approval-field">
                    <span>Drop off location</span>
                    <input
                      type="text"
                      value={transportForm.guest_dropoff_location}
                      onChange={handleTransportFieldChange("guest_dropoff_location")}
                      placeholder="Address or landmark"
                    />
                  </label>
                  <label className="approval-field">
                    <span>Drop off date (optional)</span>
                    <input
                      type="date"
                      value={transportForm.guest_dropoff_date}
                      onChange={handleTransportFieldChange("guest_dropoff_date")}
                    />
                  </label>
                  <label className="approval-field">
                    <span>Drop off time</span>
                    <input
                      type="time"
                      value={transportForm.guest_dropoff_time}
                      onChange={handleTransportFieldChange("guest_dropoff_time")}
                    />
                  </label>
                </div>
              ) : null}
              {transportForm.include_students ? (
                <div className="form-grid" style={{ marginTop: "0.75rem" }}>
                  <p className="details-sublabel" style={{ gridColumn: "1 / -1", margin: 0 }}>
                    Student transport
                  </p>
                  <label className="approval-field">
                    <span>Number of students</span>
                    <input
                      type="number"
                      min="1"
                      step="1"
                      value={transportForm.student_count}
                      onChange={handleTransportFieldChange("student_count")}
                    />
                  </label>
                  <label className="approval-field">
                    <span>Kind of transport</span>
                    <input
                      type="text"
                      value={transportForm.student_transport_kind}
                      onChange={handleTransportFieldChange("student_transport_kind")}
                      placeholder="e.g. bus, van"
                    />
                  </label>
                  <label className="approval-field">
                    <span>Date</span>
                    <input
                      type="date"
                      value={transportForm.student_date}
                      onChange={handleTransportFieldChange("student_date")}
                    />
                  </label>
                  <label className="approval-field">
                    <span>Time</span>
                    <input
                      type="time"
                      value={transportForm.student_time}
                      onChange={handleTransportFieldChange("student_time")}
                    />
                  </label>
                  <label className="approval-field" style={{ gridColumn: "1 / -1" }}>
                    <span>Pick up point</span>
                    <input
                      type="text"
                      value={transportForm.student_pickup_point}
                      onChange={handleTransportFieldChange("student_pickup_point")}
                      placeholder="Meeting point for students"
                    />
                  </label>
                </div>
              ) : null}
              <label className="approval-field">
                <span>Additional notes</span>
                <textarea
                  rows="3"
                  placeholder="Any other details for transport."
                  value={transportForm.other_notes}
                  onChange={handleTransportFieldChange("other_notes")}
                />
              </label>
          </>
        ) : null}

        {wizard.phase === "review" ? (
          <>
              <EventSummary pendingEvent={pendingEvent} eventForm={eventForm} formatISTTime={formatISTTime} />
              {wizard.steps.map((dept) => (
                <div key={dept} className="approval-summary" style={{ marginTop: "1rem" }}>
                  <p>
                    <strong>{DEPT_REVIEW_LABEL[dept]}</strong>
                  </p>
                  {wizard.skipped[dept] ? (
                    <p className="form-hint">Skipped — this request will not be sent.</p>
                  ) : dept === "facility" ? (
                    <ul className="form-hint" style={{ margin: "0.25rem 0 0 1rem" }}>
                      <li>To: {facilityForm.to || "(default desk)"}</li>
                      <li>Venue setup: {facilityForm.venue_required ? "Yes" : "No"}</li>
                      <li>Refreshments: {facilityForm.refreshments ? "Yes" : "No"}</li>
                      {facilityForm.other_notes?.trim() ? <li>Notes: {facilityForm.other_notes.trim()}</li> : null}
                    </ul>
                  ) : dept === "it" ? (
                    <ul className="form-hint" style={{ margin: "0.25rem 0 0 1rem" }}>
                      <li>To: {itForm.to || "(default desk)"}</li>
                      <li>Mode: {itForm.event_mode === "online" ? "Online" : "Offline"}</li>
                      <li>PA system: {itForm.pa_system ? "Yes" : "No"}</li>
                      <li>Projection: {itForm.projection ? "Yes" : "No"}</li>
                      {itForm.other_notes?.trim() ? <li>Notes: {itForm.other_notes.trim()}</li> : null}
                    </ul>
                  ) : dept === "marketing" ? (
                    <ul className="form-hint" style={{ margin: "0.25rem 0 0 1rem" }}>
                      <li>To: {marketingForm.to || "(default desk)"}</li>
                      {marketingCheckedLines().length ? (
                        marketingCheckedLines().map((line) => <li key={line}>{line}</li>)
                      ) : (
                        <li>No items selected</li>
                      )}
                      {marketingForm.other_notes?.trim() ? <li>Notes: {marketingForm.other_notes.trim()}</li> : null}
                      {marketingAttachmentFiles.length ? (
                        <li>
                          Attached files: {marketingAttachmentFiles.length} (uploads after send)
                        </li>
                      ) : null}
                    </ul>
                  ) : dept === "transport" ? (
                    <ul className="form-hint" style={{ margin: "0.25rem 0 0 1rem" }}>
                      <li>To: {transportForm.to || "(default desk)"}</li>
                      <li>Guest cab: {transportForm.include_guest_cab ? "Yes" : "No"}</li>
                      <li>Students: {transportForm.include_students ? "Yes" : "No"}</li>
                      {transportForm.include_guest_cab ? (
                        <li>
                          Guest: {transportForm.guest_pickup_location || "—"} → {transportForm.guest_dropoff_location || "—"}{" "}
                          ({transportForm.guest_pickup_date || "—"} {transportForm.guest_pickup_time || ""})
                        </li>
                      ) : null}
                      {transportForm.include_students ? (
                        <li>
                          Students: {transportForm.student_count || "—"} via {transportForm.student_transport_kind || "—"} on{" "}
                          {transportForm.student_date || "—"} {transportForm.student_time || ""} @ {transportForm.student_pickup_point || "—"}
                        </li>
                      ) : null}
                      {transportForm.other_notes?.trim() ? <li>Notes: {transportForm.other_notes.trim()}</li> : null}
                    </ul>
                  ) : null}
                </div>
              ))}
              {!wizardCanSend ? (
                <p className="form-hint" style={{ marginTop: "1rem" }}>
                  All departments were skipped. Close or go back to include at least one request.
                </p>
              ) : null}
          </>
        ) : null}
          </div>
        </div>

        {wizard.error ? <p className="form-error wizard-form-error">{wizard.error}</p> : null}

        {wizard.phase === "edit" ? (
          <div className="modal-actions requirements-modal-actions">
            <button
              type="button"
              className="secondary-action"
              onClick={onPrev}
              disabled={wizard.stepIndex <= 0}
            >
              Prev
            </button>
            <button type="button" className="secondary-action" onClick={onSkip}>
              Skip
            </button>
            <button type="button" className="primary-action" onClick={onNext}>
              {wizard.stepIndex >= wizard.steps.length - 1 ? "Review" : "Next"}
            </button>
          </div>
        ) : (
          <div className="modal-actions requirements-modal-actions">
            <button type="button" className="secondary-action" onClick={onPrev}>
              Prev
            </button>
            <button
              type="button"
              className="primary-action"
              onClick={onSendAll}
              disabled={wizard.status === "loading" || !wizardCanSend}
            >
              {wizard.status === "loading" ? "Sending..." : "Send"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
