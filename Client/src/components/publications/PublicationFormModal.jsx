/**
 * PublicationFormModal — the type-specific citation form modal.
 *
 * Performance guarantees:
 *  - All state (form fields, contributors) is LOCAL to this component.
 *    No App.jsx state is touched while filling in the form.
 *  - Contributor updates replace one array slot; only
 *    the changed row re-renders (memo + stable key).
 *  - Date fields use PublicationDateField (native <input type="date">).
 *    Zero portal/rAF/getBoundingClientRect overhead.
 *  - Heavy libraries (jsPDF, FullCalendar, tippy) are not imported here.
 *
 */
import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CITATION_FORMAT_OPTIONS, PUBLICATION_FIELD_DEFINITIONS } from "../../constants";
import PublicationDateField from "./PublicationDateField";
import PublicationContributorSection from "./PublicationContributorSection";
import {
  FEATURED_PUBLICATION_EXTRA_FIELDS,
  PUBLICATION_SOURCE_ICON_PATHS,
  FEATURED_PUBLICATION_FORM_FIELDS,
  getDefaultPublicationForm,
  getPublicationFieldGroups,
  createPublicationContributor
} from "./publicationUtils";

const CONTRIBUTOR_ADD_BUDGET_MS = 50;
let contributorPerfSequence = 0;

function beginContributorPerfMark(action, startLength, requiresLengthIncrease = false) {
  if (typeof performance === "undefined") return null;
  contributorPerfSequence += 1;
  const id = `publication-contributor-${action.toLowerCase().replace(/\s+/g, "-")}-${contributorPerfSequence}`;
  const startMark = `${id}-click`;
  performance.mark(startMark);
  return { action, id, startLength, startMark, requiresLengthIncrease };
}

function finishContributorPerfMark(pending) {
  if (!pending || typeof performance === "undefined") return;
  const endMark = `${pending.id}-commit`;
  const measureName = `${pending.id}-click-to-render`;
  performance.mark(endMark);
  performance.measure(measureName, pending.startMark, endMark);
  const entries = performance.getEntriesByName(measureName);
  const measure = entries[entries.length - 1];
  const duration = measure?.duration ?? 0;
  const rounded = Math.round(duration * 100) / 100;
  const log = duration <= CONTRIBUTOR_ADD_BUDGET_MS ? console.info : console.warn;
  log.call(
    console,
    `[publication-perf] ${pending.action} click-to-render: ${rounded}ms ` +
      `(budget ${CONTRIBUTOR_ADD_BUDGET_MS}ms)`
  );
  performance.clearMarks(pending.startMark);
  performance.clearMarks(endMark);
  performance.clearMeasures(measureName);
}

// ─── Shared icon ─────────────────────────────────────────────────────────────

export function PublicationIcon({ sourceKey, className = "" }) {
  const path =
    PUBLICATION_SOURCE_ICON_PATHS[sourceKey] || PUBLICATION_SOURCE_ICON_PATHS.default;
  return (
    <svg className={className} viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d={path} />
    </svg>
  );
}

// ─── Requirement badge ────────────────────────────────────────────────────────

const PublicationRequirementBadge = memo(function PublicationRequirementBadge({
  requirement
}) {
  if (requirement === "required")
    return <span className="pub-field-badge pub-field-badge-required">Required</span>;
  if (requirement === "recommended")
    return <span className="pub-field-badge">Recommended</span>;
  return <span className="pub-field-badge pub-field-badge-optional">Optional</span>;
});

// ─── Generic field ────────────────────────────────────────────────────────────

const PublicationField = memo(function PublicationField({
  fieldKey,
  value,
  required,
  requirement,
  onFieldChange,
  onSetFieldValue
}) {
  const field = PUBLICATION_FIELD_DEFINITIONS[fieldKey] || { label: fieldKey, type: "text" };
  const handleChange = useCallback(
    (event) => onFieldChange(fieldKey, event),
    [fieldKey, onFieldChange]
  );
  const handleToday = useCallback(() => {
    onSetFieldValue(fieldKey, new Date().toISOString().slice(0, 10));
  }, [fieldKey, onSetFieldValue]);

  if (fieldKey === "contributors") return null;

  const label = (
    <span>
      {field.label} {required ? <span className="req">*</span> : null}
      <PublicationRequirementBadge requirement={requirement} />
    </span>
  );

  if (field.type === "date") {
    return (
      <label className="form-field pub-date-field">
        {label}
        <div className="pub-date-picker-row">
          <PublicationDateField
            value={value || ""}
            onChange={handleChange}
            required={required}
          />
          {field.todayShortcut ? (
            <button
              type="button"
              className="secondary-action pub-today-btn"
              onClick={handleToday}
            >
              Today
            </button>
          ) : null}
        </div>
      </label>
    );
  }

  if (field.type === "textarea") {
    return (
      <label className="form-field">
        {label}
        <textarea
          rows={fieldKey === "contributors" ? 3 : 2}
          placeholder={field.placeholder || ""}
          value={value || ""}
          onChange={handleChange}
          required={required}
        />
      </label>
    );
  }

  if (field.type === "select") {
    return (
      <label className="form-field">
        {label}
        <select value={value || ""} onChange={handleChange} required={required}>
          <option value="">Select</option>
          {(field.options || []).map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
      </label>
    );
  }

  return (
    <label className="form-field">
      {label}
      <input
        type={field.type || "text"}
        placeholder={field.placeholder || ""}
        value={value || ""}
        onChange={handleChange}
        required={required}
      />
    </label>
  );
});

// ─── Field section ────────────────────────────────────────────────────────────

const PublicationFieldSection = memo(function PublicationFieldSection({
  title,
  fields,
  className = "",
  form,
  requiredFieldSet,
  recommendedFieldSet,
  onFieldChange,
  onSetFieldValue
}) {
  const uniqueFields = useMemo(() => [...new Set(fields || [])], [fields]);
  if (!uniqueFields.length) return null;

  return (
    <section className={`pub-field-section ${className}`.trim()}>
      {title ? (
        <div className="pub-field-section-head">
          <h4>{title}</h4>
        </div>
      ) : null}
      <div className="pub-dynamic-grid">
        {uniqueFields.map((fieldKey) => (
          <PublicationField
            key={fieldKey}
            fieldKey={fieldKey}
            value={form[fieldKey]}
            required={requiredFieldSet.has(fieldKey)}
            requirement={
              requiredFieldSet.has(fieldKey)
                ? "required"
                : recommendedFieldSet.has(fieldKey)
                ? "recommended"
                : "optional"
            }
            onFieldChange={onFieldChange}
            onSetFieldValue={onSetFieldValue}
          />
        ))}
      </div>
    </section>
  );
});

// ─── Scribbr date control (uses native date field) ────────────────────────────

const PublicationScribbrDateControl = memo(function PublicationScribbrDateControl({
  row,
  value,
  onFieldChange,
  onSetFieldValue
}) {
  const handleDateChange = useCallback(
    (event) => onFieldChange(row.field, event),
    [onFieldChange, row.field]
  );
  const handleToday = useCallback(() => {
    onSetFieldValue(row.field, new Date().toISOString().slice(0, 10));
  }, [onSetFieldValue, row.field]);

  return (
    <div className="pub-premium-date-control">
      <PublicationDateField
        value={value || ""}
        onChange={handleDateChange}
      />
      {row.todayShortcut ? (
        <button type="button" className="pub-link-button" onClick={handleToday}>
          Set to today
        </button>
      ) : null}
    </div>
  );
});

// ─── Scribbr field row ────────────────────────────────────────────────────────

const PublicationScribbrFieldRow = memo(function PublicationScribbrFieldRow({
  row,
  form,
  noteVisible,
  onFieldChange,
  onSetFieldValue,
  onShowAnnotation,
  onAnnotationChange,
  onRemoveAnnotation
}) {
  const handleInputChange = useCallback(
    (event) => onFieldChange(row.field, event),
    [onFieldChange, row.field]
  );
  const handleFlagChange = useCallback(
    (event) => onSetFieldValue(row.flag, event.target.checked),
    [onSetFieldValue, row.flag]
  );
  const handleRadioChange = useCallback(
    (event) => onSetFieldValue(row.field, event.target.value),
    [onSetFieldValue, row.field]
  );

  if (row.type === "annotation") {
    const visible = noteVisible || form.note || form.others;
    return (
      <section key="annotation" className="pub-scribbr-row">
        <div className="pub-scribbr-label">
          <strong>Annotation</strong>
        </div>
        <div className="pub-scribbr-control">
          {visible ? (
            <div className="pub-annotation-editor">
              <textarea
                rows={3}
                value={form.note || form.others}
                onChange={onAnnotationChange}
              />
              <button
                type="button"
                className="pub-link-button pub-remove-annotation"
                onClick={onRemoveAnnotation}
              >
                Remove annotation
              </button>
            </div>
          ) : (
            <button
              type="button"
              className="secondary-action pub-annotation-button"
              onClick={onShowAnnotation}
            >
              Add annotation
            </button>
          )}
        </div>
      </section>
    );
  }

  if (row.type === "date") {
    return (
      <section key={row.field} className="pub-scribbr-row">
        <div className="pub-scribbr-label">
          <strong>{row.label}</strong>
        </div>
        <div className="pub-scribbr-control">
          <PublicationScribbrDateControl
            row={row}
            value={form[row.field]}
            onFieldChange={onFieldChange}
            onSetFieldValue={onSetFieldValue}
          />
        </div>
      </section>
    );
  }

  if (row.type === "range") {
    return (
      <section key={row.field} className="pub-scribbr-row">
        <div className="pub-scribbr-label">
          <strong>{row.label}</strong>
        </div>
        <div className="pub-scribbr-control pub-range-control">
          <input type="text" value={form[row.field] || ""} onChange={handleInputChange} />
          <label className="pub-inline-checkbox">
            <input
              type="checkbox"
              checked={Boolean(form[row.flag])}
              onChange={handleFlagChange}
            />
            <span>Range</span>
          </label>
        </div>
      </section>
    );
  }

  if (row.type === "radio") {
    return (
      <section key={row.field} className="pub-scribbr-row">
        <div className="pub-scribbr-label">
          <strong>{row.label}</strong>
        </div>
        <div className="pub-scribbr-control pub-radio-group">
          {row.options.map((option) => (
            <label key={option}>
              <input
                type="radio"
                name={`publication-${row.field}`}
                value={option}
                checked={(form[row.field] || row.options[0]) === option}
                onChange={handleRadioChange}
              />
              <span>{option}</span>
            </label>
          ))}
        </div>
      </section>
    );
  }

  if (row.type === "toggleDate") {
    return (
      <section key={row.flag} className="pub-scribbr-row">
        <div className="pub-scribbr-label" />
        <div className="pub-scribbr-control">
          <label className="pub-inline-checkbox">
            <input
              type="checkbox"
              checked={Boolean(form[row.flag])}
              onChange={handleFlagChange}
            />
            <span>{row.label}</span>
          </label>
          {form[row.flag] ? (
            <PublicationScribbrDateControl
              row={row}
              value={form[row.field]}
              onFieldChange={onFieldChange}
              onSetFieldValue={onSetFieldValue}
            />
          ) : null}
        </div>
      </section>
    );
  }

  if (row.type === "toggleField") {
    const toggleLabel = row.toggleLabel || row.label;
    return (
      <section key={row.flag} className="pub-scribbr-row">
        <div className="pub-scribbr-label" />
        <div className="pub-scribbr-control">
          <label className="pub-inline-checkbox">
            <input
              type="checkbox"
              checked={Boolean(form[row.flag])}
              onChange={handleFlagChange}
            />
            <span>{toggleLabel}</span>
          </label>
          {form[row.flag] ? (
            <input
              type="text"
              aria-label={row.fieldLabel || row.label}
              placeholder={row.fieldLabel || row.label}
              value={form[row.field] || ""}
              onChange={handleInputChange}
            />
          ) : null}
        </div>
      </section>
    );
  }

  if (row.type === "archiveGroup") {
    return (
      <section key="archiveGroup" className="pub-scribbr-row">
        <div className="pub-scribbr-label">
          <strong>{row.label}</strong>
        </div>
        <div className="pub-scribbr-control pub-archive-sub-group">
          {row.subFields.map(({ field, label }) => (
            <label key={field} className="pub-archive-sub-field">
              <span className="pub-archive-sub-label">{label}</span>
              <input
                type="text"
                value={form[field] || ""}
                onChange={(e) => onFieldChange(field, e)}
                aria-label={label}
              />
            </label>
          ))}
        </div>
      </section>
    );
  }

  return (
    <section key={row.field} className="pub-scribbr-row">
      <div className="pub-scribbr-label">
        <strong>{row.label}</strong>
        {row.required ? <span>Required</span> : null}
      </div>
      <div className="pub-scribbr-control">
        <input
          type={row.inputType || "text"}
          placeholder={row.placeholder || ""}
          value={form[row.field] || ""}
          onChange={handleInputChange}
          required={Boolean(row.required)}
        />
      </div>
    </section>
  );
});

// ─── Featured fields (Scribbr-style layout) ───────────────────────────────────

const PublicationFeaturedFields = memo(function PublicationFeaturedFields({
  rows,
  form,
  contributorsVisible,
  contributors,
  contributorsRequired,
  contributorsRecommended,
  onAddPerson,
  onAddOrganization,
  onToggleContributor,
  onRemoveContributor,
  onSwitchContributorKind,
  onUpdateContributor,
  noteVisible,
  onFieldChange,
  onSetFieldValue,
  onShowAnnotation,
  onAnnotationChange,
  onRemoveAnnotation
}) {
  return (
    <div className="pub-scribbr-fields">
      {rows.map((row, index) => {
        if (row.type === "contributors") {
          return (
            <PublicationContributorSection
              key="contributors"
              visible={contributorsVisible}
              contributors={contributors}
              required={contributorsRequired}
              recommended={contributorsRecommended}
              onAddPerson={onAddPerson}
              onAddOrganization={onAddOrganization}
              onToggleContributor={onToggleContributor}
              onRemoveContributor={onRemoveContributor}
              onSwitchContributorKind={onSwitchContributorKind}
              onUpdateContributor={onUpdateContributor}
            />
          );
        }
        return (
          <PublicationScribbrFieldRow
            key={`${row.type}-${row.field || row.flag || index}`}
            row={row}
            form={form}
            noteVisible={noteVisible}
            onFieldChange={onFieldChange}
            onSetFieldValue={onSetFieldValue}
            onShowAnnotation={onShowAnnotation}
            onAnnotationChange={onAnnotationChange}
            onRemoveAnnotation={onRemoveAnnotation}
          />
        );
      })}
    </div>
  );
});

// ─── Main modal ───────────────────────────────────────────────────────────────

const PublicationFormModal = memo(function PublicationFormModal({
  modal,
  initialPubType,
  publicationCitationFormat,
  onClose,
  onBackToTypes,
  onSubmit
}) {
  // Local-only state — no App.jsx state touched during form editing.
  const [form, setForm] = useState(() => getDefaultPublicationForm(initialPubType));
  const [contributors, setContributors] = useState(() => []);
  const [noteVisible, setNoteVisible] = useState(false);
  const pendingContributorPerfRef = useRef(null);

  useEffect(() => {
    if (!modal.open) return;
    const nextForm = getDefaultPublicationForm(initialPubType);
    setForm(nextForm);
    setContributors([]);
    setNoteVisible(false);
  }, [initialPubType, modal.open]);

  const fieldGroups = useMemo(
    () => getPublicationFieldGroups(form.pubType),
    [form.pubType]
  );
  const {
    selectedSourceConfig,
    selectedSourceKey,
    featuredFormRows,
    selectedFieldSet,
    requiredFieldSet,
    recommendedFieldSet,
    titleFields,
    containerFields,
    dateFields,
    noteFields,
    metadataFields
  } = fieldGroups;

  const selectedSourceStyle = useMemo(
    () => ({ "--pub-card-color": selectedSourceConfig.color }),
    [selectedSourceConfig.color]
  );
  const selectedSourceIconStyle = useMemo(
    () => ({ color: selectedSourceConfig.color }),
    [selectedSourceConfig.color]
  );

  const contributorsVisible = selectedFieldSet.includes("contributors");
  const contributorsRequired = requiredFieldSet.has("contributors");
  const contributorsRecommended = recommendedFieldSet.has("contributors");
  const metadataOpen = useMemo(
    () =>
      metadataFields.some(
        (fieldKey) => requiredFieldSet.has(fieldKey) || recommendedFieldSet.has(fieldKey)
      ),
    [metadataFields, recommendedFieldSet, requiredFieldSet]
  );
  const shouldShowNoteField =
    noteVisible || noteFields.some((fieldKey) => form[fieldKey]) || form.others;

  useEffect(() => {
    const pending = pendingContributorPerfRef.current;
    if (
      !pending ||
      (pending.requiresLengthIncrease && contributors.length <= pending.startLength)
    )
      return;
    pendingContributorPerfRef.current = null;
    finishContributorPerfMark(pending);
  }, [contributors]);

  const onOverlayMouseDown = useCallback(
    (event) => {
      if (event.target === event.currentTarget) onClose();
    },
    [onClose]
  );
  const handleSourceTypeClick = useCallback(() => {
    onClose();
    onBackToTypes();
  }, [onBackToTypes, onClose]);

  const handleFieldChange = useCallback((field, event) => {
    if (field === "file") {
      setForm((prev) => ({ ...prev, file: event.target.files?.[0] || null }));
      return;
    }
    setForm((prev) => ({ ...prev, [field]: event.target.value }));
  }, []);

  const handleNameChange = useCallback(
    (event) => handleFieldChange("name", event),
    [handleFieldChange]
  );
  const handleCitationFormatChange = useCallback(
    (event) => handleFieldChange("citation_format", event),
    [handleFieldChange]
  );
  const handleFileChange = useCallback(
    (event) => handleFieldChange("file", event),
    [handleFieldChange]
  );

  const setPublicationFieldValue = useCallback((field, value) => {
    setForm((prev) => ({ ...prev, [field]: value }));
  }, []);

  const handleAnnotationChange = useCallback((event) => {
    setForm((prev) => ({ ...prev, note: event.target.value, others: event.target.value }));
  }, []);
  const showAnnotation = useCallback(() => setNoteVisible(true), []);
  const removeAnnotation = useCallback(() => {
    setNoteVisible(false);
    setForm((prev) => ({ ...prev, note: "", others: "" }));
  }, []);

  const addPerson = useCallback(() => {
    setContributors((prev) => {
      pendingContributorPerfRef.current = beginContributorPerfMark(
        "Add person",
        prev.length,
        true
      );
      return [
        ...prev,
        createPublicationContributor("person", { collapsed: false })
      ];
    });
  }, []);

  const addOrganization = useCallback(() => {
    setContributors((prev) => {
      pendingContributorPerfRef.current = beginContributorPerfMark(
        "Add organization",
        prev.length,
        true
      );
      return [
        ...prev,
        createPublicationContributor("organization", { collapsed: false })
      ];
    });
  }, []);

  const updatePublicationContributor = useCallback((clientId, field, value) => {
    setContributors((prev) => {
      const index = prev.findIndex((c) => c.client_id === clientId);
      if (index === -1 || prev[index][field] === value) return prev;
      const next = prev.slice();
      next[index] = { ...prev[index], [field]: value };
      return next;
    });
  }, []);

  const switchPublicationContributorKind = useCallback((clientId, kind) => {
    setContributors((prev) => {
      const index = prev.findIndex((c) => c.client_id === clientId);
      if (index === -1 || prev[index].kind === kind) return prev;
      const c = prev[index];
      const next = prev.slice();
      pendingContributorPerfRef.current = beginContributorPerfMark(
        `Switch ${kind}`,
        prev.length
      );
      if (kind === "organization") {
        next[index] = {
          ...c,
          kind: "organization",
          name: c.name || ""
        };
        return next;
      }
      next[index] = {
        ...c,
        kind: "person",
        title: c.title || "",
        initials: c.initials || "",
        first_name: c.first_name || "",
        infix: c.infix || "",
        last_name: c.last_name || "",
        suffix: c.suffix || ""
      };
      return next;
    });
  }, []);

  const togglePublicationContributor = useCallback((clientId) => {
    setContributors((prev) => {
      const index = prev.findIndex((c) => c.client_id === clientId);
      if (index === -1) return prev;
      const next = prev.slice();
      next[index] = { ...prev[index], collapsed: !prev[index].collapsed };
      return next;
    });
  }, []);

  const removePublicationContributor = useCallback((clientId) => {
    setContributors((prev) => {
      const index = prev.findIndex((c) => c.client_id === clientId);
      if (index === -1) return prev;
      const next = prev.slice();
      next.splice(index, 1);
      return next;
    });
  }, []);

  const handleSubmit = useCallback(
    (event) => {
      event.preventDefault();
      onSubmit({ ...form, contributors });
    },
    [contributors, form, onSubmit]
  );

  if (!modal.open) return null;

  return (
    <div
      className="modal-overlay pub-form-overlay"
      role="dialog"
      aria-modal="true"
      onMouseDown={onOverlayMouseDown}
    >
      <div className="modal-card pub-form-card">
        <div className="modal-header">
          <div>
            <h3 className="pub-form-modal-title">
              <PublicationIcon sourceKey={selectedSourceKey} />
              {selectedSourceConfig.label} Citation
            </h3>
          </div>
          <button type="button" className="modal-close" onClick={onClose}>
            &times;
          </button>
        </div>
        <form className="pub-form" onSubmit={handleSubmit}>
          <section className="pub-field-section pub-source-section">
            <div className="pub-field-section-head">
              <h4>Source type</h4>
            </div>
            <button
              type="button"
              className="pub-selected-source"
              style={selectedSourceStyle}
              onClick={handleSourceTypeClick}
            >
              <span
                className="pub-type-icon"
                aria-hidden="true"
                style={selectedSourceIconStyle}
              >
                <PublicationIcon sourceKey={selectedSourceKey} />
              </span>
              <span>
                <strong>{selectedSourceConfig.label}</strong>
                <small>{selectedSourceConfig.desc}</small>
              </span>
            </button>
          </section>

          {featuredFormRows ? (
          <PublicationFeaturedFields
              rows={featuredFormRows}
              form={form}
              contributorsVisible={contributorsVisible}
              contributors={contributors}
              contributorsRequired={contributorsRequired}
              contributorsRecommended={contributorsRecommended}
              onAddPerson={addPerson}
              onAddOrganization={addOrganization}
              onToggleContributor={togglePublicationContributor}
              onRemoveContributor={removePublicationContributor}
              onSwitchContributorKind={switchPublicationContributorKind}
              onUpdateContributor={updatePublicationContributor}
              noteVisible={noteVisible}
              onFieldChange={handleFieldChange}
              onSetFieldValue={setPublicationFieldValue}
              onShowAnnotation={showAnnotation}
              onAnnotationChange={handleAnnotationChange}
              onRemoveAnnotation={removeAnnotation}
            />
          ) : (
            <>
              <label className="form-field">
                <span>
                  Record Label <span className="req">*</span>
                </span>
                <input
                  type="text"
                  placeholder="Short identifier, e.g. Smith2024"
                  value={form.name}
                  onChange={handleNameChange}
                  required
                />
              </label>

              <label className="form-field">
                <span>Citation Format</span>
                <select
                  value={form.citation_format || publicationCitationFormat}
                  onChange={handleCitationFormatChange}
                >
                  {CITATION_FORMAT_OPTIONS.map((item) => (
                    <option key={item.value} value={item.value}>
                      {item.label}
                    </option>
                  ))}
                </select>
              </label>

              <PublicationFieldSection
                title="Title or Content"
                fields={titleFields}
                form={form}
                requiredFieldSet={requiredFieldSet}
                recommendedFieldSet={recommendedFieldSet}
                onFieldChange={handleFieldChange}
                onSetFieldValue={setPublicationFieldValue}
              />
              <PublicationFieldSection
                title="Container / Collection / Source"
                fields={containerFields}
                form={form}
                requiredFieldSet={requiredFieldSet}
                recommendedFieldSet={recommendedFieldSet}
                onFieldChange={handleFieldChange}
                onSetFieldValue={setPublicationFieldValue}
              />
              <PublicationContributorSection
                visible={contributorsVisible}
                contributors={contributors}
                required={contributorsRequired}
                recommended={contributorsRecommended}
                onAddPerson={addPerson}
                onAddOrganization={addOrganization}
                onToggleContributor={togglePublicationContributor}
                onRemoveContributor={removePublicationContributor}
                onSwitchContributorKind={switchPublicationContributorKind}
                onUpdateContributor={updatePublicationContributor}
              />
              <PublicationFieldSection
                title="Date fields"
                fields={dateFields}
                form={form}
                requiredFieldSet={requiredFieldSet}
                recommendedFieldSet={recommendedFieldSet}
                onFieldChange={handleFieldChange}
                onSetFieldValue={setPublicationFieldValue}
              />
              {metadataFields.length ? (
                <details className="pub-optional-details" open={metadataOpen}>
                  <summary>
                    <span>Publisher, Identifiers, and Source Details</span>
                    <span>{metadataFields.length} fields</span>
                  </summary>
                  <PublicationFieldSection
                    fields={metadataFields}
                    className="pub-field-section-embedded"
                    form={form}
                    requiredFieldSet={requiredFieldSet}
                    recommendedFieldSet={recommendedFieldSet}
                    onFieldChange={handleFieldChange}
                    onSetFieldValue={setPublicationFieldValue}
                  />
                </details>
              ) : null}

              <label className="form-field">
                <span>PDF File (optional, max 10 MB)</span>
                <input
                  type="file"
                  accept=".pdf,application/pdf"
                  onChange={handleFileChange}
                />
              </label>

              {shouldShowNoteField ? (
                <label className="form-field pub-note-field">
                  <span>Optional note</span>
                  <textarea
                    rows="2"
                    placeholder="Add a short citation note"
                    value={form.note || form.others}
                    onChange={handleAnnotationChange}
                  />
                </label>
              ) : (
                <button type="button" className="pub-add-note-btn" onClick={showAnnotation}>
                  Add note
                </button>
              )}
            </>
          )}

          {modal.status === "error" ? (
            <p className="form-error">{modal.error}</p>
          ) : null}

          <div className="modal-actions">
            <button
              type="button"
              className="secondary-action"
              onClick={handleSourceTypeClick}
            >
              ← Back
            </button>
            <button type="button" className="secondary-action" onClick={onClose}>
              Cancel
            </button>
            <button
              type="submit"
              className="primary-action"
              disabled={modal.status === "loading"}
            >
              {modal.status === "loading" ? "Submitting..." : "Submit"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
});

export default PublicationFormModal;
