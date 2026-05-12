/**
 * PublicationFormModal — the type-specific citation form modal.
 *
 * Performance guarantees:
 *  - All state (form fields) is LOCAL to this component.
 *    No App.jsx state is touched while filling in the form.
 *  - Date fields use PublicationDateField (native <input type="date">).
 *    Zero portal/rAF/getBoundingClientRect overhead.
 *  - Heavy libraries (jsPDF, FullCalendar, tippy) are not imported here.
 *
 */
import { memo, useCallback, useMemo, useState } from "react";
import { CITATION_FORMAT_OPTIONS, PUBLICATION_FIELD_DEFINITIONS } from "../../constants";
import PublicationDateField from "./PublicationDateField";
import {
  FEATURED_PUBLICATION_EXTRA_FIELDS,
  PUBLICATION_SOURCE_ICON_PATHS,
  FEATURED_PUBLICATION_FORM_FIELDS,
  getDefaultPublicationForm,
  getPublicationFieldGroups
} from "./publicationUtils";

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
          rows={2}
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

/**
 * Custom memo comparator for PublicationScribbrFieldRow.
 *
 * Problem: `form` is the entire form state object — a new reference on every
 * keypress. Without a custom comparator, ALL field rows re-render whenever
 * ANY single field changes, because Object.is(newForm, oldForm) === false.
 *
 * Fix: compare only the specific form values that each row type actually reads.
 *  - annotation  → form.note, form.others, noteVisible
 *  - archiveGroup → form[sf.field] for each subField
 *  - range/radio  → form[row.field]
 *  - toggleDate / toggleField → form[row.field] + form[row.flag]
 *  - date / field (default)   → form[row.field]
 *
 * Result: typing in "Title" only re-renders the Title row; all other rows
 * bail out immediately regardless of the new form object reference.
 */
function scribbrFieldRowPropsEqual(prev, next) {
  if (prev.row !== next.row) return false;
  if (prev.onFieldChange !== next.onFieldChange) return false;
  if (prev.onSetFieldValue !== next.onSetFieldValue) return false;
  if (prev.onShowAnnotation !== next.onShowAnnotation) return false;
  if (prev.onAnnotationChange !== next.onAnnotationChange) return false;
  if (prev.onRemoveAnnotation !== next.onRemoveAnnotation) return false;

  const row = next.row;

  if (row.type === "annotation") {
    const prevNote = prev.form.note || prev.form.others || "";
    const nextNote = next.form.note || next.form.others || "";
    return prev.noteVisible === next.noteVisible && prevNote === nextNote;
  }

  if (row.type === "archiveGroup") {
    return (row.subFields || []).every(
      (sf) => prev.form[sf.field] === next.form[sf.field]
    );
  }

  // date, range, radio, toggleDate, toggleField, default field
  const fieldSame = row.field
    ? prev.form[row.field] === next.form[row.field]
    : true;
  const flagSame = row.flag
    ? Boolean(prev.form[row.flag]) === Boolean(next.form[row.flag])
    : true;
  return fieldSame && flagSame;
}

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
              autoComplete="off"
              spellCheck={false}
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
                autoComplete="off"
                spellCheck={false}
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
          autoComplete="off"
          spellCheck={false}
        />
      </div>
    </section>
  );
}, scribbrFieldRowPropsEqual);

// ─── Featured fields (Scribbr-style layout) ───────────────────────────────────

const PublicationFeaturedFields = memo(function PublicationFeaturedFields({
  rows,
  form,
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
  const [noteVisible, setNoteVisible] = useState(false);

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

  const metadataOpen = useMemo(
    () =>
      metadataFields.some(
        (fieldKey) => requiredFieldSet.has(fieldKey) || recommendedFieldSet.has(fieldKey)
      ),
    [metadataFields, recommendedFieldSet, requiredFieldSet]
  );
  const shouldShowNoteField =
    noteVisible || noteFields.some((fieldKey) => form[fieldKey]) || form.others;

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

  const handleSubmit = useCallback(
    (event) => {
      event.preventDefault();
      onSubmit({ ...form });
    },
    [form, onSubmit]
  );

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
