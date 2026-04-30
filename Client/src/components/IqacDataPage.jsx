/**
 * IQAC Data Collection: SSR/NAAC form sections plus criteria evidence collection.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { SimpleIcon } from "./icons";
import { Modal } from "./ui";
import IqacTemplateDownloadCard from "./IqacTemplateDownloadCard";
import api from "../services/api";

const SUBFOLDERS_VISIBLE = 3; // show first N, then "... +M more sub-folders"
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(iso) {
  if (!iso) return "—";
  try {
    const d = new Date(iso);
    return d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }) +
      " at " +
      d.toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
  } catch {
    return iso;
  }
}

function countWords(value) {
  return String(value || "").trim().split(/\s+/).filter(Boolean).length;
}

function limitWords(value, maxWords) {
  const words = String(value || "").trim().split(/\s+/).filter(Boolean);
  return words.length <= maxWords ? value : words.slice(0, maxWords).join(" ");
}

function sanitizeNumber(value) {
  return String(value ?? "").replace(/[^\d.]/g, "").replace(/(\..*)\./g, "$1");
}

function cloneRows(rows, fallbackRows) {
  return Array.isArray(rows) && rows.length ? rows : fallbackRows;
}

// Folder icon (large for card header)
const FOLDER_PATH = "M4 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5zm2 0v4h12V5H6zm0 6v8h12v-8H6z";
// Document icon for item tiles
const DOC_PATH = "M7 2h6l4 4v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm0 2v14h10V8h-4V4H7zm2 2h4v2H9V6z";
const SHEET_PATH = "M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm2 4v3h10V7H7Zm0 5v5h4v-5H7Zm6 0v5h4v-5h-4Z";
const PROFILE_PATH = "M12 2a5 5 0 0 1 5 5v1h1a2 2 0 0 1 2 2v10H4V10a2 2 0 0 1 2-2h1V7a5 5 0 0 1 5-5Zm-3 6h6V7a3 3 0 0 0-6 0v1Zm-1 6h8v2H8v-2Z";
const CHART_PATH = "M5 19V5h2v14H5Zm6 0V9h2v10h-2Zm6 0V3h2v16h-2ZM3 21h18v-2H3v2Z";
const GUIDE_PATH = "M5 4a2 2 0 0 1 2-2h10v18H7a2 2 0 0 1-2-2V4Zm3 2v2h6V6H8Zm0 4v2h8v-2H8Zm0 4v2h5v-2H8Z";

const CRITERIA_SUMMARY_FIELDS = [
  "Curricular Aspects",
  "Teaching-Learning & Evaluation",
  "Research, Innovations & Extension",
  "Infrastructure & Learning Resources",
  "Student Support & Progression",
  "Governance, Leadership & Management",
  "Institutional Values & Best Practices",
];

const SSR_CARDS = [
  {
    key: "executive_summary",
    title: "Executive Summary",
    text: "Narrative summary, criterion notes, SWOC, additional information, and conclusion.",
    icon: SHEET_PATH,
  },
  {
    key: "university_profile",
    title: "Profile of the University",
    text: "Basic information, recognition, campus, academic, staff, student, and department details.",
    icon: PROFILE_PATH,
  },
  {
    key: "extended_profile",
    title: "Extended Profile of the University",
    text: "Five-year programme, student, academic, admission, infrastructure, and expenditure data.",
    icon: CHART_PATH,
  },
  {
    key: "qif",
    title: "Quality Indicator Framework",
    text: "QIF preparation notes connected to the seven criteria evidence structure below.",
    icon: GUIDE_PATH,
  },
];

const EXTENDED_PROFILE_METRICS = [
  { key: "programmes_offered", code: "1.1", label: "Number of programmes offered year-wise for last five years" },
  { key: "students", code: "2.1", label: "Number of students year-wise during last five years" },
  { key: "outgoing_students", code: "2.2", label: "Number of outgoing / final year students year-wise during last five years" },
  { key: "exam_appeared", code: "2.3", label: "Number of students appeared in university examination year-wise during last five years" },
  { key: "revaluation_applications", code: "2.4", label: "Number of revaluation applications year-wise during last five years" },
  { key: "courses", code: "3.1", label: "Number of courses in all programmes year-wise during last five years" },
  { key: "full_time_teachers", code: "3.2", label: "Number of full-time teachers year-wise during last five years" },
  { key: "sanctioned_posts", code: "3.3", label: "Number of sanctioned posts year-wise during last five years" },
  { key: "eligible_applications", code: "4.1", label: "Eligible applications received for admissions year-wise" },
  { key: "reserved_seats", code: "4.2", label: "Reserved category seats year-wise" },
  { key: "expenditure_excluding_salary", code: "4.5", label: "Total expenditure excluding salary year-wise in INR Lakhs" },
];

const STAFF_STATUSES = ["Sanctioned", "Recruited", "Yet to Recruit", "On Contract"];
const TEACHING_ROLES = ["Professor", "Associate Professor", "Assistant Professor"];
const GENDER_COLUMNS = ["Male", "Female", "Others", "Total"];
const QUALIFICATIONS = ["D.Sc/D.Litt", "Ph.D.", "M.Phil.", "PG"];
const ACADEMIC_YEAR_LABELS = ["Year 1", "Year 2", "Year 3", "Year 4", "Year 5"];

function createExecutiveSummaryData() {
  return {
    introductory_note: "",
    criteria_summary: "",
    swoc_analysis: "",
    additional_information: "",
    conclusive_explication: "",
  };
}

function staffRows(columns = GENDER_COLUMNS) {
  return STAFF_STATUSES.map((status) => ({
    status,
    ...Object.fromEntries(columns.map((col) => [col, ""])),
  }));
}

function qualificationRows() {
  return QUALIFICATIONS.map((qualification) => {
    const row = { qualification };
    TEACHING_ROLES.forEach((role) => {
      GENDER_COLUMNS.slice(0, 3).forEach((gender) => {
        row[`${role}_${gender}`] = "";
      });
    });
    row.Total = "";
    return row;
  });
}

function createProfileData() {
  return {
    basic_information: { name: "", address: "", city: "", pin: "", state: "", website: "" },
    contacts: [{ designation: "", name: "", telephone: "", mobile: "", fax: "", email: "" }],
    institution: { nature: "", status: "", type: "" },
    establishment: { establishment_date: "", status_prior: "", establishment_date_if_applicable: "" },
    recognition: { ugc_2f_date: "", ugc_12b_date: "", other_agency_name: "", other_agency_date: "" },
    upe_recognized: "",
    campuses: [{
      campus_type: "", address: "", location: "", campus_area_acres: "", built_up_area_sq_mts: "",
      programmes_offered: "", establishment_date: "", recognition_date: "",
    }],
    academic_information: {
      affiliated_institutions: [
        { college_type: "Education/Teachers Training", permanent_affiliation: "", temporary_affiliation: "" },
        { college_type: "Business administration/Commerce/Management/Finance", permanent_affiliation: "", temporary_affiliation: "" },
        { college_type: "Universal/Common to all Disciplines", permanent_affiliation: "", temporary_affiliation: "" },
      ],
      college_details: [
        { label: "Constituent Colleges", value: "" },
        { label: "Affiliated Colleges", value: "" },
        { label: "Colleges Under 2(f)", value: "" },
        { label: "Colleges Under 2(f) and 12B", value: "" },
        { label: "NAAC Accredited Colleges", value: "" },
        { label: "Colleges with Potential for Excellence (UGC)", value: "" },
        { label: "Autonomous Colleges", value: "" },
        { label: "Colleges with Postgraduate Departments", value: "" },
        { label: "Colleges with Research Departments", value: "" },
        { label: "University Recognized Research Institutes/Centers", value: "" },
      ],
      sra_recognized: "",
      sra_details: "",
    },
    staff: {
      teaching: staffRows(TEACHING_ROLES.flatMap((role) => GENDER_COLUMNS.map((gender) => `${role}_${gender}`))),
      non_teaching: staffRows(),
      technical: staffRows(),
    },
    qualification_details: {
      permanent_teachers: qualificationRows(),
      temporary_teachers: qualificationRows(),
      part_time_teachers: qualificationRows(),
    },
    distinguished_academicians: [
      { role: "Emeritus Professor", male: "", female: "", others: "", total: "" },
      { role: "Adjunct Professor", male: "", female: "", others: "", total: "" },
      { role: "Visiting Professor", male: "", female: "", others: "", total: "" },
    ],
    chairs: [{ sl_no: "", department: "", chair: "", sponsor: "" }],
    student_enrolment: [
      { programme: "PG", gender: "Male", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "PG", gender: "Female", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "PG", gender: "Others", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "UG", gender: "Male", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "UG", gender: "Female", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "UG", gender: "Others", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "PG Diploma recognized by statutory authority including university", gender: "Male", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "PG Diploma recognized by statutory authority including university", gender: "Female", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      { programme: "PG Diploma recognized by statutory authority including university", gender: "Others", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
    ],
    integrated_programmes: {
      offered: "",
      total_programmes: "",
      enrolment: [
        { gender: "Male", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
        { gender: "Female", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
        { gender: "Others", from_state: "", from_other_states: "", nri: "", foreign: "", total: "" },
      ],
    },
    hrdc: { year_of_establishment: "", orientation_programmes: "", refresher_courses: "", own_programmes: "", total_programmes_last_five_years: "" },
    department_reports: [{ department_name: "", report_reference: "" }],
  };
}

function createExtendedProfileData() {
  return {
    year_labels: [...ACADEMIC_YEAR_LABELS],
    departments_offering_programmes: "",
    total_classrooms_seminar_halls: "",
    total_computers_academic: "",
    metrics: Object.fromEntries(EXTENDED_PROFILE_METRICS.map((metric) => [metric.key, ["", "", "", "", ""]])),
  };
}

function createQifData() {
  return {
    preparation_notes: "",
    qualitative_metrics_notes: "",
    quantitative_metrics_notes: "",
    file_description_notes: "",
  };
}

function defaultDataFor(sectionKey) {
  if (sectionKey === "executive_summary") return createExecutiveSummaryData();
  if (sectionKey === "university_profile") return createProfileData();
  if (sectionKey === "extended_profile") return createExtendedProfileData();
  if (sectionKey === "qif") return createQifData();
  return {};
}

function normalizeSectionData(sectionKey, data) {
  const value = data && typeof data === "object" ? data : {};
  if (sectionKey === "executive_summary") {
    const base = createExecutiveSummaryData();
    const cleanValue = { ...value };
    delete cleanValue.criteria_summaries;
    delete cleanValue.swoc;
    const legacyCriteriaSummary = value.criteria_summary || Object.entries(value.criteria_summaries || {})
      .map(([key, text]) => {
        const label = CRITERIA_SUMMARY_FIELDS[Number(key) - 1] || `Criterion ${key}`;
        return text ? `${label}\n${text}` : "";
      })
      .filter(Boolean)
      .join("\n\n");
    const legacySwoc = value.swoc_analysis || Object.entries(value.swoc || {})
      .map(([key, text]) => text ? `${key.replace(/_/g, " ")}\n${text}` : "")
      .filter(Boolean)
      .join("\n\n");
    return {
      ...base,
      ...cleanValue,
      criteria_summary: legacyCriteriaSummary,
      swoc_analysis: legacySwoc,
    };
  }
  if (sectionKey === "extended_profile") {
    const base = createExtendedProfileData();
    const metrics = { ...base.metrics, ...(value.metrics || {}) };
    EXTENDED_PROFILE_METRICS.forEach((metric) => {
      metrics[metric.key] = Array.isArray(metrics[metric.key])
        ? [...metrics[metric.key], "", "", "", "", ""].slice(0, 5)
        : ["", "", "", "", ""];
    });
    return { ...base, ...value, year_labels: [...(value.year_labels || base.year_labels), "", "", "", "", ""].slice(0, 5), metrics };
  }
  if (sectionKey === "qif") {
    return { ...createQifData(), ...value };
  }
  if (sectionKey === "university_profile") {
    const base = createProfileData();
    return {
      ...base,
      ...value,
      basic_information: { ...base.basic_information, ...(value.basic_information || {}) },
      institution: { ...base.institution, ...(value.institution || {}) },
      establishment: { ...base.establishment, ...(value.establishment || {}) },
      recognition: { ...base.recognition, ...(value.recognition || {}) },
      academic_information: {
        ...base.academic_information,
        ...(value.academic_information || {}),
        affiliated_institutions: cloneRows(value.academic_information?.affiliated_institutions, base.academic_information.affiliated_institutions),
        college_details: cloneRows(value.academic_information?.college_details, base.academic_information.college_details),
      },
      staff: {
        teaching: cloneRows(value.staff?.teaching, base.staff.teaching),
        non_teaching: cloneRows(value.staff?.non_teaching, base.staff.non_teaching),
        technical: cloneRows(value.staff?.technical, base.staff.technical),
      },
      qualification_details: {
        permanent_teachers: cloneRows(value.qualification_details?.permanent_teachers, base.qualification_details.permanent_teachers),
        temporary_teachers: cloneRows(value.qualification_details?.temporary_teachers, base.qualification_details.temporary_teachers),
        part_time_teachers: cloneRows(value.qualification_details?.part_time_teachers, base.qualification_details.part_time_teachers),
      },
      integrated_programmes: {
        ...base.integrated_programmes,
        ...(value.integrated_programmes || {}),
        enrolment: cloneRows(value.integrated_programmes?.enrolment, base.integrated_programmes.enrolment),
      },
      hrdc: { ...base.hrdc, ...(value.hrdc || {}) },
      contacts: cloneRows(value.contacts, base.contacts),
      campuses: cloneRows(value.campuses, base.campuses),
      distinguished_academicians: cloneRows(value.distinguished_academicians, base.distinguished_academicians),
      chairs: cloneRows(value.chairs, base.chairs),
      student_enrolment: cloneRows(value.student_enrolment, base.student_enrolment),
      department_reports: cloneRows(value.department_reports, base.department_reports),
    };
  }
  return value;
}

function createDefaultSsrData() {
  return Object.fromEntries(SSR_CARDS.map((card) => [card.key, defaultDataFor(card.key)]));
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

function formatFieldName(path = "") {
  return String(path)
    .replace(/\./g, " / ")
    .replace(/_/g, " ")
    .replace(/\b\w/g, (match) => match.toUpperCase());
}

function valueToLines(value) {
  if (value === null || value === undefined || value === "") return ["(blank)"];
  if (typeof value === "string") {
    const chunks = value.split(/\n{2,}|\n/).map((line) => line.trim()).filter(Boolean);
    return chunks.length ? chunks : ["(blank)"];
  }
  return JSON.stringify(value, null, 2).split("\n");
}

function Field({ label, value, onChange, type = "text", placeholder = "", required = false, error = "", className = "" }) {
  return (
    <label className={`iqac-ssr-field${error ? " iqac-ssr-field--error" : ""}${className ? ` ${className}` : ""}`}>
      <span>{label}</span>
      <input
        type={type}
        value={value || ""}
        placeholder={placeholder}
        required={required}
        onChange={(event) => onChange(event.target.value)}
      />
      {error ? <em>{error}</em> : null}
    </label>
  );
}

function NumericField(props) {
  return (
    <Field
      {...props}
      type="text"
      onChange={(value) => props.onChange(sanitizeNumber(value))}
    />
  );
}

function TextareaField({ label, value, onChange, rows = 4, hint = "", maxWords = null, guidance = "", className = "" }) {
  const words = countWords(value);
  return (
    <label className={`iqac-ssr-field iqac-ssr-field--wide${className ? ` ${className}` : ""}`}>
      <span>{label}</span>
      {guidance ? <span className="iqac-field-guidance">{guidance}</span> : null}
      <textarea
        rows={rows}
        value={value || ""}
        onChange={(event) => onChange(maxWords ? limitWords(event.target.value, maxWords) : event.target.value)}
      />
      <small className={maxWords && words >= maxWords ? "iqac-ssr-word-limit" : ""}>
        {hint}
        {maxWords ? `${hint ? " · " : ""}${words}/${maxWords} words` : ""}
      </small>
    </label>
  );
}

function YesNoField({ label, value, onChange }) {
  return (
    <label className="iqac-ssr-field iqac-yesno-field">
      <span>{label}</span>
      <span className="iqac-yesno-control" role="group" aria-label={label}>
        {["Yes", "No"].map((option) => (
          <button
            key={option}
            type="button"
            className={value === option ? "iqac-yesno-option iqac-yesno-option--active" : "iqac-yesno-option"}
            onClick={() => onChange(option)}
          >
            {option}
          </button>
        ))}
      </span>
    </label>
  );
}

function FormSection({ title, children, note = "" }) {
  return (
    <section className="iqac-ssr-form-section">
      <div className="iqac-ssr-form-section-head">
        <h4>{title}</h4>
        {note ? <p>{note}</p> : null}
      </div>
      {children}
    </section>
  );
}

function RepeatableTable({ title, rows, columns, onCellChange, onAdd, onRemove, note = "" }) {
  return (
    <FormSection title={title} note={note}>
      <div className="iqac-ssr-table-wrap">
        <table className="iqac-ssr-table">
          <thead>
            <tr>
              {columns.map((col) => <th key={col.key}>{col.label}</th>)}
              {onRemove ? <th>Actions</th> : null}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, rowIndex) => (
              <tr key={rowIndex}>
                {columns.map((col) => (
                  <td key={col.key}>
                    {col.readonly ? (
                      <span className="iqac-ssr-cell-label">{row[col.key]}</span>
                    ) : col.type === "select" ? (
                      <select value={row[col.key] || ""} onChange={(event) => onCellChange(rowIndex, col.key, event.target.value)}>
                        <option value="">Select</option>
                        {(col.options || []).map((option) => <option key={option} value={option}>{option}</option>)}
                      </select>
                    ) : col.numeric ? (
                      <input type="text" value={row[col.key] || ""} onChange={(event) => onCellChange(rowIndex, col.key, sanitizeNumber(event.target.value))} />
                    ) : (
                      <input type={col.type || "text"} value={row[col.key] || ""} onChange={(event) => onCellChange(rowIndex, col.key, event.target.value)} />
                    )}
                  </td>
                ))}
                {onRemove ? (
                  <td>
                    <button type="button" className="details-button reject" onClick={() => onRemove(rowIndex)}>Remove</button>
                  </td>
                ) : null}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {onAdd ? (
        <button type="button" className="secondary-action iqac-ssr-add-row" onClick={onAdd}>
          Add row
        </button>
      ) : null}
    </FormSection>
  );
}

function ExecutiveSummaryEditor({ data, onChange }) {
  const update = (key, value) => {
    onChange((prev) => {
      const rest = { ...prev };
      delete rest.criteria_summaries;
      delete rest.swoc;
      return { ...rest, [key]: value };
    });
  };
  const totalWords =
    countWords(data.introductory_note) +
    countWords(data.criteria_summary) +
    countWords(data.swoc_analysis) +
    countWords(data.additional_information) +
    countWords(data.conclusive_explication);

  return (
    <div className="iqac-ssr-editor-grid">
      <div className="iqac-ssr-guidance-intro">
        Every HEI applying for the A&amp;A process shall prepare an Executive Summary highlighting the main features of the Institution.
      </div>
      <div className={`iqac-ssr-total-words${totalWords > 5000 ? " iqac-ssr-total-words--warn" : ""}`}>
        The Executive summary shall not be more than 5000 words. Current count: {totalWords}/5000 words.
      </div>
      <TextareaField
        label="Introductory Note on the Institution"
        value={data.introductory_note}
        rows={7}
        guidance="Location, vision, mission, type of institution, etc."
        onChange={(value) => update("introductory_note", value)}
      />
      <TextareaField
        label="Criterion-wise Summary"
        value={data.criteria_summary}
        rows={10}
        guidance="Summarise the institution's functioning criterion-wise in not more than 250 words for each criterion."
        onChange={(value) => update("criteria_summary", value)}
      />
      <TextareaField
        label="SWOC Analysis"
        value={data.swoc_analysis}
        rows={8}
        guidance="Brief note on Strengths, Weaknesses, Opportunities and Challenges."
        onChange={(value) => update("swoc_analysis", value)}
      />
      <TextareaField
        label="Additional Information about the Institution"
        value={data.additional_information}
        rows={7}
        guidance="Any additional information about the institution other than already stated."
        onChange={(value) => update("additional_information", value)}
      />
      <TextareaField
        label="Overall Conclusive Explication"
        value={data.conclusive_explication}
        rows={7}
        guidance="Overall conclusive explication about the institution's functioning."
        onChange={(value) => update("conclusive_explication", value)}
      />
    </div>
  );
}

function ProfileEditor({ data, onChange, emailErrors }) {
  const patch = (section, key, value) => onChange((prev) => ({ ...prev, [section]: { ...(prev[section] || {}), [key]: value } }));
  const setRows = (section, rows) => onChange((prev) => ({ ...prev, [section]: rows }));
  const setNestedRows = (section, nested, rows) => onChange((prev) => ({
    ...prev,
    [section]: { ...(prev[section] || {}), [nested]: rows },
  }));
  const updateRow = (section, rowIndex, key, value) => {
    const rows = [...(data[section] || [])];
    rows[rowIndex] = { ...rows[rowIndex], [key]: value };
    setRows(section, rows);
  };
  const updateNestedRow = (section, nested, rowIndex, key, value) => {
    const rows = [...(data[section]?.[nested] || [])];
    rows[rowIndex] = { ...rows[rowIndex], [key]: value };
    setNestedRows(section, nested, rows);
  };
  const updateStaff = (group, rowIndex, key, value) => {
    const rows = [...(data.staff?.[group] || [])];
    rows[rowIndex] = { ...rows[rowIndex], [key]: value };
    onChange((prev) => ({ ...prev, staff: { ...(prev.staff || {}), [group]: rows } }));
  };
  const updateQualification = (group, rowIndex, key, value) => {
    const rows = [...(data.qualification_details?.[group] || [])];
    rows[rowIndex] = { ...rows[rowIndex], [key]: value };
    onChange((prev) => ({ ...prev, qualification_details: { ...(prev.qualification_details || {}), [group]: rows } }));
  };

  const basic = data.basic_information || {};
  const recognition = data.recognition || {};
  const establishment = data.establishment || {};
  const institution = data.institution || {};
  const academic = data.academic_information || {};

  return (
    <div className="iqac-ssr-editor-grid">
      <FormSection title="Basic Information">
        <div className="iqac-profile-basic-grid">
          <Field className="iqac-field-span-all" label="Name of College/University" value={basic.name} onChange={(value) => patch("basic_information", "name", value)} />
          <TextareaField className="iqac-field-span-all" label="Address" value={basic.address} rows={4} onChange={(value) => patch("basic_information", "address", value)} />
          <Field label="City" value={basic.city} onChange={(value) => patch("basic_information", "city", value)} />
          <NumericField label="PIN" value={basic.pin} onChange={(value) => patch("basic_information", "pin", value)} />
          <Field label="State" value={basic.state} onChange={(value) => patch("basic_information", "state", value)} />
          <Field className="iqac-field-span-two" type="url" label="Website" value={basic.website} onChange={(value) => patch("basic_information", "website", value)} />
        </div>
      </FormSection>

      <RepeatableTable
        title="Contacts for Communication"
        rows={data.contacts || []}
        columns={[
          { key: "designation", label: "Designation" },
          { key: "name", label: "Name" },
          { key: "telephone", label: "Telephone with STD Code" },
          { key: "mobile", label: "Mobile" },
          { key: "fax", label: "Fax" },
          { key: "email", label: "Email", type: "email" },
        ]}
        onCellChange={(row, key, value) => updateRow("contacts", row, key, value)}
        onAdd={() => setRows("contacts", [...(data.contacts || []), { designation: "", name: "", telephone: "", mobile: "", fax: "", email: "" }])}
        onRemove={(index) => setRows("contacts", (data.contacts || []).filter((_, i) => i !== index))}
      />
      {emailErrors.length ? <p className="form-error">Invalid email in contact row(s): {emailErrors.join(", ")}</p> : null}

      <FormSection title="Nature and Status">
        <div className="iqac-ssr-grid-3">
          <Field label="Nature of University" value={institution.nature} onChange={(value) => patch("institution", "nature", value)} />
          <Field label="Institution Status" value={institution.status} onChange={(value) => patch("institution", "status", value)} />
          <Field label="Type of University" value={institution.type} onChange={(value) => patch("institution", "type", value)} />
        </div>
      </FormSection>

      <FormSection title="Establishment Details">
        <div className="iqac-ssr-grid-3">
          <Field type="date" label="Establishment Date" value={establishment.establishment_date} onChange={(value) => patch("establishment", "establishment_date", value)} />
          <Field label="Status Prior to Establishment" value={establishment.status_prior} onChange={(value) => patch("establishment", "status_prior", value)} />
          <Field type="date" label="Establishment Date, if applicable" value={establishment.establishment_date_if_applicable} onChange={(value) => patch("establishment", "establishment_date_if_applicable", value)} />
        </div>
      </FormSection>

      <FormSection title="Recognition Details">
        <div className="iqac-ssr-grid-3">
          <Field type="date" label="2f of UGC Date" value={recognition.ugc_2f_date} onChange={(value) => patch("recognition", "ugc_2f_date", value)} />
          <Field type="date" label="12B of UGC Date" value={recognition.ugc_12b_date} onChange={(value) => patch("recognition", "ugc_12b_date", value)} />
          <Field label="Other National Agency" value={recognition.other_agency_name} onChange={(value) => patch("recognition", "other_agency_name", value)} />
          <Field type="date" label="Other Agency Recognition Date" value={recognition.other_agency_date} onChange={(value) => patch("recognition", "other_agency_date", value)} />
          <YesNoField label="Recognised as University with Potential for Excellence (UPE)" value={data.upe_recognized} onChange={(value) => onChange((prev) => ({ ...prev, upe_recognized: value }))} />
        </div>
      </FormSection>

      <RepeatableTable
        title="Location, Area and Activity of Campus"
        rows={data.campuses || []}
        columns={[
          { key: "campus_type", label: "Campus Type", type: "select", options: ["Urban", "Semi Urban", "Rural", "Tribal", "Hill"] },
          { key: "address", label: "Address" },
          { key: "location", label: "Location" },
          { key: "campus_area_acres", label: "Campus Area in Acres", numeric: true },
          { key: "built_up_area_sq_mts", label: "Built-up Area in sq.mts.", numeric: true },
          { key: "programmes_offered", label: "Programmes Offered" },
          { key: "establishment_date", label: "Date of Establishment", type: "date" },
          { key: "recognition_date", label: "Date of Recognition by UGC/MHRD", type: "date" },
        ]}
        onCellChange={(row, key, value) => updateRow("campuses", row, key, value)}
        onAdd={() => setRows("campuses", [...(data.campuses || []), createProfileData().campuses[0]])}
        onRemove={(index) => setRows("campuses", (data.campuses || []).filter((_, i) => i !== index))}
      />

      <RepeatableTable
        title="Affiliated Institutions to the University"
        note="Not applicable for private and deemed to be universities."
        rows={academic.affiliated_institutions || []}
        columns={[
          { key: "college_type", label: "College Type", readonly: true },
          { key: "permanent_affiliation", label: "Number with permanent affiliation", numeric: true },
          { key: "temporary_affiliation", label: "Number with temporary affiliation", numeric: true },
        ]}
        onCellChange={(row, key, value) => updateNestedRow("academic_information", "affiliated_institutions", row, key, value)}
      />

      <RepeatableTable
        title="Details of Colleges under University"
        rows={academic.college_details || []}
        columns={[
          { key: "label", label: "College Detail", readonly: true },
          { key: "value", label: "Number / Detail", numeric: true },
        ]}
        onCellChange={(row, key, value) => updateNestedRow("academic_information", "college_details", row, key, value)}
      />

      <FormSection title="Statutory Regulatory Authority Recognition">
        <div className="iqac-ssr-grid-2">
          <YesNoField label="Programmes recognized by any SRA" value={academic.sra_recognized} onChange={(value) => patch("academic_information", "sra_recognized", value)} />
          <Field label="SRA Details" value={academic.sra_details} onChange={(value) => patch("academic_information", "sra_details", value)} />
        </div>
      </FormSection>

      <StaffTables data={data} updateStaff={updateStaff} updateQualification={updateQualification} />

      <RepeatableTable
        title="Distinguished Academicians Appointed"
        rows={data.distinguished_academicians || []}
        columns={[
          { key: "role", label: "Role", readonly: true },
          { key: "male", label: "Male", numeric: true },
          { key: "female", label: "Female", numeric: true },
          { key: "others", label: "Others", numeric: true },
          { key: "total", label: "Total", numeric: true },
        ]}
        onCellChange={(row, key, value) => updateRow("distinguished_academicians", row, key, value)}
      />

      <RepeatableTable
        title="Chairs Instituted by the University"
        rows={data.chairs || []}
        columns={[
          { key: "sl_no", label: "Sl.No", numeric: true },
          { key: "department", label: "Name of Department" },
          { key: "chair", label: "Name of Chair" },
          { key: "sponsor", label: "Name of Sponsor Organisation/Agency" },
        ]}
        onCellChange={(row, key, value) => updateRow("chairs", row, key, value)}
        onAdd={() => setRows("chairs", [...(data.chairs || []), { sl_no: "", department: "", chair: "", sponsor: "" }])}
        onRemove={(index) => setRows("chairs", (data.chairs || []).filter((_, i) => i !== index))}
      />

      <RepeatableTable
        title="Students Enrolled during the Current Academic Year"
        rows={data.student_enrolment || []}
        columns={[
          { key: "programme", label: "Programme", readonly: true },
          { key: "gender", label: "Gender", readonly: true },
          { key: "from_state", label: "From the State", numeric: true },
          { key: "from_other_states", label: "From Other States of India", numeric: true },
          { key: "nri", label: "NRI Students", numeric: true },
          { key: "foreign", label: "Foreign Students", numeric: true },
          { key: "total", label: "Total", numeric: true },
        ]}
        onCellChange={(row, key, value) => updateRow("student_enrolment", row, key, value)}
      />

      <FormSection title="Integrated Programmes">
        <div className="iqac-ssr-grid-2">
          <YesNoField label="Does the university offer integrated programmes?" value={data.integrated_programmes?.offered} onChange={(value) => onChange((prev) => ({ ...prev, integrated_programmes: { ...(prev.integrated_programmes || {}), offered: value } }))} />
          <NumericField label="Total number of integrated programmes" value={data.integrated_programmes?.total_programmes} onChange={(value) => onChange((prev) => ({ ...prev, integrated_programmes: { ...(prev.integrated_programmes || {}), total_programmes: value } }))} />
        </div>
      </FormSection>
      <RepeatableTable
        title="Integrated Programme Enrolment"
        rows={data.integrated_programmes?.enrolment || []}
        columns={[
          { key: "gender", label: "Gender", readonly: true },
          { key: "from_state", label: "From the State", numeric: true },
          { key: "from_other_states", label: "From Other States of India", numeric: true },
          { key: "nri", label: "NRI Students", numeric: true },
          { key: "foreign", label: "Foreign Students", numeric: true },
          { key: "total", label: "Total", numeric: true },
        ]}
        onCellChange={(row, key, value) => updateNestedRow("integrated_programmes", "enrolment", row, key, value)}
      />

      <FormSection title="UGC Human Resource Development Centre">
        <div className="iqac-ssr-grid-3">
          {[
            ["year_of_establishment", "Year of Establishment"],
            ["orientation_programmes", "Number of UGC Orientation Programmes"],
            ["refresher_courses", "Number of UGC Refresher Course"],
            ["own_programmes", "Number of University's own Programmes"],
            ["total_programmes_last_five_years", "Total Number of Programmes Conducted (last five years)"],
          ].map(([key, label]) => (
            <NumericField key={key} label={label} value={data.hrdc?.[key]} onChange={(value) => patch("hrdc", key, value)} />
          ))}
        </div>
      </FormSection>

      <RepeatableTable
        title="Evaluative Report of the Departments"
        rows={data.department_reports || []}
        columns={[
          { key: "department_name", label: "Department Name" },
          { key: "report_reference", label: "Upload Report / File Reference" },
        ]}
        onCellChange={(row, key, value) => updateRow("department_reports", row, key, value)}
        onAdd={() => setRows("department_reports", [...(data.department_reports || []), { department_name: "", report_reference: "" }])}
        onRemove={(index) => setRows("department_reports", (data.department_reports || []).filter((_, i) => i !== index))}
      />
    </div>
  );
}

function StaffTables({ data, updateStaff, updateQualification }) {
  const teachingColumns = [
    { key: "status", label: "Teaching Faculty", readonly: true },
    ...TEACHING_ROLES.flatMap((role) => GENDER_COLUMNS.map((gender) => ({ key: `${role}_${gender}`, label: `${role} ${gender}`, numeric: true }))),
  ];
  const genderColumns = [
    { key: "status", label: "Staff" },
    ...GENDER_COLUMNS.map((gender) => ({ key: gender, label: gender, numeric: true })),
  ];
  const qualificationColumns = [
    { key: "qualification", label: "Highest Qualification", readonly: true },
    ...TEACHING_ROLES.flatMap((role) => GENDER_COLUMNS.slice(0, 3).map((gender) => ({ key: `${role}_${gender}`, label: `${role} ${gender}`, numeric: true }))),
    { key: "Total", label: "Total", numeric: true },
  ];
  return (
    <>
      <RepeatableTable title="Teaching Faculty" rows={data.staff?.teaching || []} columns={teachingColumns} onCellChange={(row, key, value) => updateStaff("teaching", row, key, value)} />
      <RepeatableTable title="Non-Teaching Staff" rows={data.staff?.non_teaching || []} columns={genderColumns} onCellChange={(row, key, value) => updateStaff("non_teaching", row, key, value)} />
      <RepeatableTable title="Technical Staff" rows={data.staff?.technical || []} columns={genderColumns} onCellChange={(row, key, value) => updateStaff("technical", row, key, value)} />
      <RepeatableTable title="Qualification Details - Permanent Teachers" rows={data.qualification_details?.permanent_teachers || []} columns={qualificationColumns} onCellChange={(row, key, value) => updateQualification("permanent_teachers", row, key, value)} />
      <RepeatableTable title="Qualification Details - Temporary Teachers" rows={data.qualification_details?.temporary_teachers || []} columns={qualificationColumns} onCellChange={(row, key, value) => updateQualification("temporary_teachers", row, key, value)} />
      <RepeatableTable title="Qualification Details - Part Time Teachers" rows={data.qualification_details?.part_time_teachers || []} columns={qualificationColumns} onCellChange={(row, key, value) => updateQualification("part_time_teachers", row, key, value)} />
    </>
  );
}

function ExtendedProfileEditor({ data, onChange }) {
  const setYear = (index, value) => {
    onChange((prev) => {
      const year_labels = [...(prev.year_labels || ACADEMIC_YEAR_LABELS)];
      year_labels[index] = value;
      return { ...prev, year_labels };
    });
  };
  const setMetricValue = (metricKey, index, value) => {
    onChange((prev) => {
      const metricValues = [...(prev.metrics?.[metricKey] || ["", "", "", "", ""])];
      metricValues[index] = sanitizeNumber(value);
      return { ...prev, metrics: { ...(prev.metrics || {}), [metricKey]: metricValues } };
    });
  };
  return (
    <div className="iqac-ssr-editor-grid">
      <FormSection title="Year Labels" note="Edit labels to match the five-year NAAC cycle.">
        <div className="iqac-ssr-year-labels">
          {(data.year_labels || ACADEMIC_YEAR_LABELS).map((year, index) => (
            <Field key={index} label={`Year ${index + 1}`} value={year} onChange={(value) => setYear(index, value)} />
          ))}
        </div>
      </FormSection>
      <FormSection title="Single-value Institution Fields">
        <div className="iqac-ssr-grid-3">
          <NumericField label="1.2 Number of departments offering academic programmes" value={data.departments_offering_programmes} onChange={(value) => onChange((prev) => ({ ...prev, departments_offering_programmes: value }))} />
          <NumericField label="4.3 Total classrooms and seminar halls" value={data.total_classrooms_seminar_halls} onChange={(value) => onChange((prev) => ({ ...prev, total_classrooms_seminar_halls: value }))} />
          <NumericField label="4.4 Total computers for academic purpose" value={data.total_computers_academic} onChange={(value) => onChange((prev) => ({ ...prev, total_computers_academic: value }))} />
        </div>
      </FormSection>
      <FormSection title="Year-wise Metrics">
        <div className="iqac-ssr-table-wrap">
          <table className="iqac-ssr-table iqac-ssr-yearly-table">
            <thead>
              <tr>
                <th>Metric</th>
                {(data.year_labels || ACADEMIC_YEAR_LABELS).map((year, index) => <th key={index}>{year || `Year ${index + 1}`}</th>)}
              </tr>
            </thead>
            <tbody>
              {EXTENDED_PROFILE_METRICS.map((metric) => (
                <tr key={metric.key}>
                  <td><strong>{metric.code}</strong> {metric.label}</td>
                  {(data.metrics?.[metric.key] || ["", "", "", "", ""]).map((value, index) => (
                    <td key={index}>
                      <input type="text" value={value || ""} onChange={(event) => setMetricValue(metric.key, index, event.target.value)} />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </FormSection>
    </div>
  );
}

function QifEditor() {
  const notes = [
    {
      title: "Connected Criteria",
      text: "QIF is connected to the seven IQAC criteria below, where the final evidence upload and document flow continues.",
    },
    {
      title: "Key Indicators and Metrics",
      text: "The framework contains Key Indicators and metric-wise requirements under each criterion.",
    },
    {
      title: "Qualitative and Quantitative Metrics",
      text: "Qualitative metrics require descriptive information, while quantitative metrics use specified data and calculations.",
    },
    {
      title: "Data, Formulas, Files and Weightage",
      text: "Each metric may include data requirements, formulas where applicable, file descriptions for evidence upload, and metric-wise weightage.",
    },
    {
      title: "Online Format Note",
      text: "The actual online format may vary slightly for IT design compatibility, so this section is kept as read-only guidance for now.",
    },
  ];
  return (
    <div className="iqac-ssr-editor-grid">
      <div className="iqac-qif-note">
        <h4>QIF Guidance</h4>
        <p>The SSR is filled in NAAC's online format. QIF presents the metrics under each Key Indicator for all seven criteria and helps the institution prepare data before entering the online SSR.</p>
        <ul>
          <li>Data required for each metric</li>
          <li>Formula guidance wherever required</li>
          <li>File descriptions for upload evidence</li>
          <li>Qualitative and quantitative metric preparation notes</li>
          <li>Metric-wise weightage and IT-format compatibility changes</li>
        </ul>
      </div>
      <div className="iqac-qif-readonly-grid">
        {notes.map((note) => (
          <article key={note.title} className="iqac-qif-readonly-card">
            <h5>{note.title}</h5>
            <p>{note.text}</p>
          </article>
        ))}
      </div>
    </div>
  );
}

export default function IqacDataPage({ canDeleteIqacFiles = false }) {
  const [criteria, setCriteria] = useState([]);
  const [counts, setCounts] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [panel, setPanel] = useState(null);
  const [files, setFiles] = useState([]);
  const [filesLoading, setFilesLoading] = useState(false);
  const [uploadFile, setUploadFile] = useState(null);
  const [uploadDesc, setUploadDesc] = useState("");
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState("");
  const [ssrData, setSsrData] = useState(createDefaultSsrData);
  const [ssrSavedData, setSsrSavedData] = useState(createDefaultSsrData);
  const [ssrMeta, setSsrMeta] = useState({});
  const [ssrLoading, setSsrLoading] = useState(true);
  const [ssrError, setSsrError] = useState("");
  const [activeSsrKey, setActiveSsrKey] = useState("");
  const [saveState, setSaveState] = useState({ status: "idle", message: "" });
  const [profileEmailErrors, setProfileEmailErrors] = useState([]);
  const [ssrHistory, setSsrHistory] = useState({});
  const [historyLoading, setHistoryLoading] = useState(false);
  const [activeHistoryItem, setActiveHistoryItem] = useState(null);
  const [historyDetailLoading, setHistoryDetailLoading] = useState(false);
  const [historyActionLoading, setHistoryActionLoading] = useState("");
  const [historyOpen, setHistoryOpen] = useState(false);

  const activeSsrCard = useMemo(() => SSR_CARDS.find((card) => card.key === activeSsrKey) || null, [activeSsrKey]);
  const activeSsrIndex = useMemo(() => SSR_CARDS.findIndex((card) => card.key === activeSsrKey), [activeSsrKey]);
  const activeSsrData = activeSsrKey ? (ssrData[activeSsrKey] || defaultDataFor(activeSsrKey)) : null;
  const activeSavedSsrData = activeSsrKey ? (ssrSavedData[activeSsrKey] || defaultDataFor(activeSsrKey)) : null;
  const hasUnsavedSsrChanges = Boolean(
    activeSsrKey && stableStringify(activeSsrData) !== stableStringify(activeSavedSsrData)
  );

  const loadCriteria = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [critRes, countRes] = await Promise.all([
        api.get("/iqac/criteria"),
        api.get("/iqac/counts"),
      ]);
      if (!critRes.ok) throw new Error("Failed to load criteria");
      const data = await critRes.json();
      setCriteria(Array.isArray(data) ? data : []);
      setCounts((await countRes.json()) || {});
    } catch (e) {
      setError(e?.message || "Failed to load criteria");
      setCriteria([]);
      setCounts({});
    } finally {
      setLoading(false);
    }
  }, []);

  const loadSsrSections = useCallback(async () => {
    setSsrLoading(true);
    setSsrError("");
    try {
      const res = await api.get("/iqac/ssr-sections");
      if (!res.ok) throw new Error("Failed to load SSR sections");
      const data = await res.json();
      const nextData = createDefaultSsrData();
      const nextMeta = {};
      (Array.isArray(data) ? data : []).forEach((section) => {
        if (!section?.section_key) return;
        nextData[section.section_key] = normalizeSectionData(section.section_key, section.data);
        nextMeta[section.section_key] = section;
      });
      setSsrData(nextData);
      setSsrSavedData(nextData);
      setSsrMeta(nextMeta);
    } catch (e) {
      setSsrError(e?.message || "Failed to load SSR sections");
    } finally {
      setSsrLoading(false);
    }
  }, []);

  const loadSectionHistory = useCallback(async (sectionKey) => {
    if (!sectionKey) return;
    setHistoryLoading(true);
    try {
      const res = await api.get(`/iqac/ssr-sections/${sectionKey}/history`);
      if (!res.ok) return;
      const data = await res.json();
      setSsrHistory((prev) => ({ ...prev, [sectionKey]: Array.isArray(data) ? data : [] }));
    } catch {
      // history is non-critical; silently ignore
    } finally {
      setHistoryLoading(false);
    }
  }, []);

  const openSsrSection = (sectionKey) => {
    setActiveSsrKey(sectionKey);
    setSaveState({ status: "idle", message: "" });
    setProfileEmailErrors([]);
    setActiveHistoryItem(null);
    setHistoryOpen(false);
  };

  const closeSsrSection = () => {
    setActiveSsrKey("");
    setActiveHistoryItem(null);
    setHistoryOpen(false);
  };

  const requestCloseSsrSection = () => {
    if (hasUnsavedSsrChanges && !window.confirm("You have unsaved changes. Close without saving?")) {
      return;
    }
    closeSsrSection();
  };

  const openHistoryDrawer = () => {
    if (!activeSsrKey) return;
    setHistoryOpen(true);
    setActiveHistoryItem(null);
    loadSectionHistory(activeSsrKey);
  };

  const openHistoryDetails = async (item) => {
    if (!activeSsrKey || !item?.id) return;
    if (activeHistoryItem?.id === item.id && activeHistoryItem?.previous_data) {
      setActiveHistoryItem(null);
      return;
    }
    setActiveHistoryItem(item);
    setHistoryDetailLoading(true);
    try {
      const res = await api.get(`/iqac/ssr-sections/${activeSsrKey}/history/${item.id}`);
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.detail || "Failed to load history details");
      setActiveHistoryItem(payload);
    } catch (e) {
      setSaveState({ status: "error", message: e?.message || "Failed to load history details" });
    } finally {
      setHistoryDetailLoading(false);
    }
  };

  useEffect(() => {
    loadCriteria();
    loadSsrSections();
  }, [loadCriteria, loadSsrSections]);

  const updateActiveSsrData = (updater) => {
    if (!activeSsrKey) return;
    setSaveState({ status: "idle", message: "" });
    setProfileEmailErrors([]);
    setSsrData((prev) => {
      const current = prev[activeSsrKey] || defaultDataFor(activeSsrKey);
      return { ...prev, [activeSsrKey]: typeof updater === "function" ? updater(current) : updater };
    });
  };

  const validateActiveSsr = () => {
    if (activeSsrKey !== "university_profile") return true;
    const invalidRows = (ssrData.university_profile?.contacts || [])
      .map((row, index) => ({ email: (row.email || "").trim(), index: index + 1 }))
      .filter((row) => row.email && !EMAIL_RE.test(row.email))
      .map((row) => String(row.index));
    setProfileEmailErrors(invalidRows);
    if (invalidRows.length) {
      setSaveState({ status: "error", message: "Fix invalid contact email addresses before saving." });
      return false;
    }
    return true;
  };

  const saveActiveSsr = async ({ silent = false } = {}) => {
    if (!activeSsrKey || !validateActiveSsr()) return false;
    if (!hasUnsavedSsrChanges) {
      setSaveState({ status: "success", message: "No changes detected." });
      return true;
    }
    setSaveState({ status: "loading", message: "" });
    try {
      const res = await api.put(`/iqac/ssr-sections/${activeSsrKey}`, { data: ssrData[activeSsrKey] || {} });
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.detail || "Save failed");
      const normalizedData = normalizeSectionData(activeSsrKey, payload.data);
      setSsrData((prev) => ({ ...prev, [activeSsrKey]: normalizedData }));
      setSsrSavedData((prev) => ({ ...prev, [activeSsrKey]: normalizedData }));
      setSsrMeta((prev) => ({ ...prev, [activeSsrKey]: payload }));
      setSaveState({
        status: "success",
        message: payload.no_changes ? "No changes detected." : (silent ? "Saved before moving." : "Saved successfully."),
      });
      if (historyOpen) loadSectionHistory(activeSsrKey);
      return true;
    } catch (e) {
      setSaveState({ status: "error", message: e?.message || "Save failed" });
      return false;
    }
  };

  const moveSsrStep = async (direction) => {
    if (activeSsrIndex < 0) return;
    const nextIndex = activeSsrIndex + direction;
    if (nextIndex < 0 || nextIndex >= SSR_CARDS.length) return;
    if (hasUnsavedSsrChanges) {
      const shouldSave = window.confirm("You have unsaved changes. Save current section before moving?");
      if (!shouldSave) return;
      const saved = await saveActiveSsr({ silent: true });
      if (!saved) return;
    }
    setActiveSsrKey(SSR_CARDS[nextIndex].key);
    setActiveHistoryItem(null);
    setHistoryOpen(false);
    setProfileEmailErrors([]);
    setSaveState({ status: "idle", message: "" });
  };

  const restoreHistoryVersion = async (item) => {
    if (!activeSsrKey || !item?.id) return;
    if (!window.confirm("Restore this historical version? This will replace the current section and create a new history entry.")) return;
    setHistoryActionLoading(item.id);
    try {
      const res = await api.post(`/iqac/ssr-sections/${activeSsrKey}/restore/${item.id}`, {});
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.detail || "Restore failed");
      const normalizedData = normalizeSectionData(activeSsrKey, payload.data);
      setSsrData((prev) => ({ ...prev, [activeSsrKey]: normalizedData }));
      setSsrSavedData((prev) => ({ ...prev, [activeSsrKey]: normalizedData }));
      setSsrMeta((prev) => ({ ...prev, [activeSsrKey]: payload }));
      setSaveState({ status: "success", message: payload.no_changes ? "No changes detected." : "Version restored." });
      setActiveHistoryItem(null);
      loadSectionHistory(activeSsrKey);
    } catch (e) {
      setSaveState({ status: "error", message: e?.message || "Restore failed" });
    } finally {
      setHistoryActionLoading("");
    }
  };

  useEffect(() => {
    if (!activeSsrKey) return undefined;
    const onKeyDown = (event) => {
      if (event.key === "Escape") {
        event.preventDefault();
        requestCloseSsrSection();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [activeSsrKey, hasUnsavedSsrChanges]);

  const loadFiles = useCallback(async (criterion, subFolder, item) => {
    setFilesLoading(true);
    try {
      const res = await api.get(`/iqac/folders/${criterion}/${encodeURIComponent(subFolder)}/${encodeURIComponent(item)}/files`);
      if (!res.ok) throw new Error("Failed to load files");
      const data = await res.json();
      setFiles(Array.isArray(data) ? data : []);
    } catch {
      setFiles([]);
    } finally {
      setFilesLoading(false);
    }
  }, []);

  const getSubfolderCount = (criterionId, subId) => {
    const c = counts[String(criterionId)];
    if (!c || !c[subId]) return 0;
    return Object.values(c[subId]).reduce((a, n) => a + n, 0);
  };

  const getItemCount = (criterionId, subId, itemId) => {
    const c = counts[String(criterionId)];
    if (!c || !c[subId]) return 0;
    return c[subId][itemId] ?? 0;
  };

  const openCriterion = (c, action) => {
    const readOnly = action === "view";
    setPanel({
      step: "subfolders",
      criterion: c.id,
      title: c.title,
      subFolders: c.subFolders || [],
      readOnly,
    });
  };

  const openSubfolder = (sub) => {
    setPanel((prev) => ({
      ...prev,
      step: "items",
      subFolder: sub.id,
      subFolderTitle: sub.title,
      items: sub.items || [],
    }));
  };

  const openItem = (itemIdOrObj) => {
    const itemId = typeof itemIdOrObj === "string" ? itemIdOrObj : itemIdOrObj?.id;
    const itemTitle = typeof itemIdOrObj === "object" && itemIdOrObj?.title ? itemIdOrObj.title : itemId;
    setPanel((prev) => ({
      ...prev,
      step: "files",
      item: itemId,
      itemTitle,
    }));
    loadFiles(panel.criterion, panel.subFolder, itemId);
    setUploadFile(null);
    setUploadDesc("");
    setUploadError("");
  };

  const closePanel = () => {
    setPanel(null);
    setFiles([]);
  };

  const handleUpload = async (e) => {
    e.preventDefault();
    if (!uploadFile?.files?.[0] || !panel) return;
    setUploading(true);
    setUploadError("");
    const file = uploadFile.files[0];
    const form = new FormData();
    form.append("file", file);
    form.append("description", uploadDesc);
    try {
      const res = await api.post(
        `/iqac/folders/${panel.criterion}/${encodeURIComponent(panel.subFolder)}/${encodeURIComponent(panel.item)}/files`,
        form
      );
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || "Upload failed");
      }
      const added = await res.json();
      setFiles((prev) => [added, ...prev]);
      setUploadFile(null);
      setUploadDesc("");
      if (uploadFile.value) uploadFile.value = "";
      loadCriteria();
    } catch (e) {
      setUploadError(e?.message || "Upload failed");
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async (fileId) => {
    if (!canDeleteIqacFiles) return;
    if (!window.confirm("Delete this file?")) return;
    try {
      const res = await api.delete(`/iqac/files/${fileId}`);
      if (!res.ok) throw new Error("Delete failed");
      setFiles((prev) => prev.filter((f) => f.id !== fileId));
      loadCriteria();
    } catch {}
  };

  const getMimeType = (fileName) => {
    const ext = (fileName || "").toLowerCase().split(".").pop();
    if (ext === "pdf") return "application/pdf";
    if (ext === "doc") return "application/msword";
    if (ext === "docx") return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    return "application/octet-stream";
  };

  const handleView = (fileId, fileName) => {
    const token = api.getToken();
    const url = `${api.getBaseUrl()}/iqac/files/${fileId}/download`;
    if (!token) return;
    fetch(url, { headers: { Authorization: `Bearer ${token}` } })
      .then((r) => (r.ok ? r.blob() : null))
      .then(async (blob) => {
        if (!blob) return;
        const type = getMimeType(fileName);
        const viewBlob = type !== "application/octet-stream" ? new Blob([await blob.arrayBuffer()], { type }) : blob;
        const u = URL.createObjectURL(viewBlob);
        const w = window.open(u, "_blank", "noopener,noreferrer");
        if (w) setTimeout(() => URL.revokeObjectURL(u), 5000);
        else URL.revokeObjectURL(u);
      })
      .catch(() => {});
  };

  const handleDownload = (fileId, fileName) => {
    const token = api.getToken();
    const url = `${api.getBaseUrl()}/iqac/files/${fileId}/download`;
    if (token) {
      fetch(url, { headers: { Authorization: `Bearer ${token}` } })
        .then((r) => (r.ok ? r.blob() : null))
        .then((blob) => {
          if (!blob) return;
          const u = URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = u;
          a.download = fileName || "file";
          a.click();
          URL.revokeObjectURL(u);
        })
        .catch(() => {});
    } else {
      const a = document.createElement("a");
      a.href = url;
      a.download = fileName || "file";
      a.click();
    }
  };

  const renderActiveSsrEditor = () => {
    if (!activeSsrKey) return null;
    const data = ssrData[activeSsrKey] || defaultDataFor(activeSsrKey);
    if (activeSsrKey === "executive_summary") return <ExecutiveSummaryEditor data={data} onChange={updateActiveSsrData} />;
    if (activeSsrKey === "university_profile") return <ProfileEditor data={data} onChange={updateActiveSsrData} emailErrors={profileEmailErrors} />;
    if (activeSsrKey === "extended_profile") return <ExtendedProfileEditor data={data} onChange={updateActiveSsrData} />;
    if (activeSsrKey === "qif") return <QifEditor />;
    return null;
  };

  return (
    <div className="primary-column iqac-page">
      <header className="iqac-header">
        <div>
          <h2 className="iqac-title">IQAC Data Collection</h2>
          <p className="iqac-subtitle">Manage IQAC criteria folders and sub-folders (IQAC Committee Only)</p>
        </div>
      </header>

      <IqacTemplateDownloadCard />

      <section className="iqac-ssr-section">
        <div className="iqac-structure-head">
          <h3 className="iqac-structure-title">SSR / NAAC Data Entry</h3>
          <span className="iqac-badge">IQAC Portal Only</span>
        </div>
        {ssrError ? <p className="iqac-template-message iqac-template-message--error">{ssrError}</p> : null}
        <div className="iqac-ssr-cards-grid">
          {SSR_CARDS.map((card) => {
            const meta = ssrMeta[card.key];
            const editorName = meta?.updated_by_name || meta?.updated_by_email || null;
            const editedAt = meta?.updated_at;
            return (
              <button
                key={card.key}
                type="button"
                className="iqac-ssr-card"
                onClick={() => openSsrSection(card.key)}
              >
                <span className="iqac-ssr-card-icon" aria-hidden="true">
                  <SimpleIcon path={card.icon} />
                </span>
                <span className="iqac-ssr-card-body">
                  <strong>{card.title}</strong>
                  <small>{card.text}</small>
                  <span className="iqac-ssr-card-meta">
                    {editorName ? (
                      <>
                        <span className="iqac-ssr-card-meta-row">
                          <span className="iqac-ssr-card-meta-label">Last edited by:</span>
                          <span className="iqac-ssr-card-meta-value">{editorName}</span>
                        </span>
                        <span className="iqac-ssr-card-meta-row">
                          <span className="iqac-ssr-card-meta-label">Last edited on:</span>
                          <span className="iqac-ssr-card-meta-value">{formatDate(editedAt)}</span>
                        </span>
                      </>
                    ) : (
                      <span className="iqac-ssr-card-meta-empty">Not edited yet</span>
                    )}
                  </span>
                </span>
                <span className="iqac-ssr-card-arrow" aria-hidden="true">›</span>
              </button>
            );
          })}
        </div>
      </section>

      {activeSsrCard ? (
        <div
          className="iqac-ssr-modal-overlay"
          role="presentation"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) requestCloseSsrSection();
          }}
        >
          <section
            className="iqac-ssr-modal iqac-ssr-modal--guided"
            role="dialog"
            aria-modal="true"
            aria-labelledby="iqac-ssr-modal-title"
            onMouseDown={(event) => event.stopPropagation()}
          >
            <div className="iqac-ssr-modal-topbar">
              <div className="iqac-ssr-modal-title-block">
                <span>Step {activeSsrIndex + 1} of {SSR_CARDS.length}</span>
                <h3 id="iqac-ssr-modal-title">{activeSsrCard.title}</h3>
                <p>{activeSsrCard.text}</p>
              </div>
              <div className="iqac-ssr-topbar-actions">
                <button type="button" className="secondary-action" onClick={openHistoryDrawer}>
                  History
                </button>
                <button type="button" className="secondary-action" disabled={saveState.status === "loading" || ssrLoading} onClick={() => saveActiveSsr()}>
                  {saveState.status === "loading" ? "Saving..." : "Save"}
                </button>
                {activeSsrIndex > 0 ? (
                  <button type="button" className="secondary-action" onClick={() => moveSsrStep(-1)}>
                    Previous
                  </button>
                ) : null}
                {activeSsrIndex < SSR_CARDS.length - 1 ? (
                  <button type="button" className="primary-action" onClick={() => moveSsrStep(1)}>
                    Next
                  </button>
                ) : (
                  <button type="button" className="primary-action" onClick={requestCloseSsrSection}>
                    Finish/Close
                  </button>
                )}
                <button type="button" className="secondary-action" onClick={requestCloseSsrSection}>
                  Close
                </button>
                <button type="button" className="iqac-ssr-modal-x" onClick={requestCloseSsrSection} aria-label="Close SSR modal">
                  ×
                </button>
              </div>
            </div>

            <div className="iqac-ssr-stepper" aria-label="SSR section steps">
              {SSR_CARDS.map((card, index) => (
                <span
                  key={card.key}
                  className={`iqac-ssr-step-pill${index === activeSsrIndex ? " iqac-ssr-step-pill--active" : ""}${index < activeSsrIndex ? " iqac-ssr-step-pill--done" : ""}`}
                >
                  <span>{index + 1}</span>
                  {card.title}
                </span>
              ))}
            </div>

            <div className="iqac-ssr-modal-shell">
              <div className="iqac-ssr-modal-body">
                {hasUnsavedSsrChanges ? <span className="iqac-ssr-unsaved-dot">Unsaved changes</span> : null}
                {ssrLoading ? <p className="iqac-files-loading">Loading SSR data...</p> : renderActiveSsrEditor()}
                {saveState.message ? (
                  <p className={`iqac-ssr-save-message iqac-ssr-save-message--${saveState.status}`}>
                    {saveState.message}
                  </p>
                ) : null}
              </div>

              <aside className={`iqac-ssr-history-drawer${historyOpen ? " iqac-ssr-history-drawer--open" : ""}`} aria-hidden={!historyOpen}>
                <div className="iqac-history-panel-head">
                  <div>
                    <h4>Edit History</h4>
                    <span className="iqac-history-panel-note">Last 5 days only</span>
                  </div>
                  <button type="button" className="iqac-history-close" onClick={() => setHistoryOpen(false)} aria-label="Close history">
                    →
                  </button>
                </div>
                {historyLoading ? (
                  <p className="iqac-history-loading">Loading history...</p>
                ) : (ssrHistory[activeSsrKey] || []).length === 0 ? (
                  <p className="iqac-history-empty">No edits in the last 5 days.</p>
                ) : (
                  <ul className="iqac-history-list">
                    {(ssrHistory[activeSsrKey] || []).map((item) => {
                      const isActive = activeHistoryItem?.id === item.id;
                      const fieldDiffs = isActive ? (activeHistoryItem.field_diffs || {}) : {};
                      return (
                        <li key={item.id} className={`iqac-history-item${isActive ? " iqac-history-item--active" : ""}`}>
                          <div className="iqac-history-item-meta">
                            <span className="iqac-history-editor">{item.edited_by_name || item.edited_by_email || "IQAC user"}</span>
                            {item.edited_by_email ? <span className="iqac-history-email">{item.edited_by_email}</span> : null}
                            <span className="iqac-history-time">{formatDate(item.edited_at)}</span>
                          </div>
                          <p className="iqac-history-summary">{item.change_summary || `${activeSsrCard.title} updated.`}</p>
                          <span className="iqac-history-section-name">{activeSsrCard.title}</span>
                          {item.changed_fields?.length > 0 && (
                            <div className="iqac-history-fields">
                              {item.changed_fields.slice(0, 3).map((field) => (
                                <span key={field} className="iqac-history-field-tag">{formatFieldName(field)}</span>
                              ))}
                              {item.changed_fields.length > 3 && (
                                <span className="iqac-history-field-tag iqac-history-field-more">+{item.changed_fields.length - 3}</span>
                              )}
                            </div>
                          )}
                          <div className="iqac-history-actions">
                            <button type="button" className="iqac-history-details-btn" onClick={() => openHistoryDetails(item)}>
                              {isActive ? "Hide details" : "View Details"}
                            </button>
                            <button
                              type="button"
                              className="iqac-history-details-btn iqac-history-restore-btn"
                              disabled={historyActionLoading === item.id}
                              onClick={() => restoreHistoryVersion(item)}
                            >
                              {historyActionLoading === item.id ? "Restoring..." : "Restore this version"}
                            </button>
                          </div>
                          {isActive && (
                            <div className="iqac-history-details">
                              {historyDetailLoading ? (
                                <p>Loading exact changes...</p>
                              ) : Object.keys(fieldDiffs).length > 0 ? (
                                Object.entries(fieldDiffs).map(([field, diff]) => (
                                  <div key={field} className="iqac-diff-field">
                                    <h5>{formatFieldName(field)}</h5>
                                    <div className="iqac-diff-block">
                                      <span className="iqac-diff-label iqac-diff-label--removed">Previous</span>
                                      {valueToLines(diff.previous).map((line, index) => (
                                        <code key={`old-${index}`} className="iqac-diff-line iqac-diff-line--removed">- {line}</code>
                                      ))}
                                    </div>
                                    <div className="iqac-diff-block">
                                      <span className="iqac-diff-label iqac-diff-label--added">New</span>
                                      {valueToLines(diff.new).map((line, index) => (
                                        <code key={`new-${index}`} className="iqac-diff-line iqac-diff-line--added">+ {line}</code>
                                      ))}
                                    </div>
                                  </div>
                                ))
                              ) : (
                                <span>No individual field changes detected.</span>
                              )}
                              <button
                                type="button"
                                className="primary-action iqac-history-detail-restore"
                                disabled={historyActionLoading === item.id}
                                onClick={() => restoreHistoryVersion(item)}
                              >
                                Restore this version
                              </button>
                            </div>
                          )}
                        </li>
                      );
                    })}
                  </ul>
                )}
              </aside>
            </div>
          </section>
        </div>
      ) : null}

      {loading ? (
        <div className="iqac-loading">
          <p>Loading…</p>
        </div>
      ) : error ? (
        <div className="iqac-error">
          <p>{error}</p>
        </div>
      ) : (
        <section className="iqac-structure-section">
          <div className="iqac-structure-head">
            <span className="iqac-badge">IQAC Committee Only</span>
          </div>

          <div className="iqac-cards-grid">
            {criteria.map((c) => {
              const subFolders = c.subFolders || [];
              const visible = subFolders.slice(0, SUBFOLDERS_VISIBLE);
              const rest = subFolders.length - SUBFOLDERS_VISIBLE;
              return (
                <article key={c.id} className="iqac-criterion-card">
                  <div className="iqac-card-header">
                    <span className="iqac-card-folder-icon" aria-hidden="true">
                      <SimpleIcon path={FOLDER_PATH} />
                    </span>
                    <h4 className="iqac-card-title">Criterion {c.id}: {c.title}</h4>
                  </div>
                  <ul className="iqac-card-sub-list">
                    {visible.map((sub) => (
                      <li key={sub.id} className="iqac-card-sub-row">
                        <span className="iqac-card-sub-icon" aria-hidden="true">
                          <SimpleIcon path={FOLDER_PATH} />
                        </span>
                        <span className="iqac-card-sub-code">{sub.id}</span>
                        <span className="iqac-card-sub-name">{sub.title}</span>
                        <span className="iqac-card-sub-count">{getSubfolderCount(c.id, sub.id)}</span>
                      </li>
                    ))}
                    {rest > 0 && (
                      <li className="iqac-card-sub-more">... +{rest} more sub-folders</li>
                    )}
                  </ul>
                  <div className="iqac-card-actions">
                    <button
                      type="button"
                      className="iqac-btn iqac-btn-view"
                      onClick={() => openCriterion(c, "view")}
                      aria-label="View criterion"
                    >
                      <SimpleIcon path="M10.5 12a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0ZM12 3c4.97 0 9 3.134 9 7 0 2.5-1.5 4.75-3.8 6.2L15 18l-2.2-1.8C10.5 14.75 9 12.5 9 10c0-3.866 4.03-7 9-7Z" />
                      View
                    </button>
                    <button
                      type="button"
                      className="iqac-btn iqac-btn-open"
                      onClick={() => openCriterion(c, "open")}
                      aria-label="Open criterion"
                    >
                      <SimpleIcon path={FOLDER_PATH} />
                      Open
                    </button>
                  </div>
                </article>
              );
            })}
          </div>
        </section>
      )}

      {panel && (
        <Modal
          title={
            (panel.step === "subfolders"
              ? `Criterion ${panel.criterion}: ${panel.title}`
              : panel.step === "items"
                ? `${panel.subFolder}: ${panel.subFolderTitle}`
                : `${panel.subFolder} → ${panel.itemTitle ?? panel.item}`) +
            (panel.readOnly ? " (View only)" : "")
          }
          onClose={closePanel}
        >
          <div className="iqac-panel-body">
            {panel.step === "subfolders" && (
              <div className="iqac-subfolders">
                {(panel.subFolders || []).map((sub) => (
                  <button
                    key={sub.id}
                    type="button"
                    className="iqac-subfolder-btn"
                    onClick={() => openSubfolder(sub)}
                  >
                    <SimpleIcon path={FOLDER_PATH} />
                    {sub.id} — {sub.title}
                  </button>
                ))}
              </div>
            )}

            {panel.step === "items" && (
              <div className="iqac-items-tiles">
                {(panel.items || []).map((it) => {
                  const id = typeof it === "string" ? it : it?.id;
                  const title = typeof it === "object" && it?.title ? it.title : id;
                  const n = getItemCount(panel.criterion, panel.subFolder, id);
                  return (
                    <button
                      key={id}
                      type="button"
                      className="iqac-item-tile"
                      onClick={() => openItem(it)}
                    >
                      <span className="iqac-item-tile-icon">
                        <SimpleIcon path={DOC_PATH} />
                      </span>
                      <span className="iqac-item-tile-label">{id} {title}</span>
                      <span className="iqac-item-tile-count">{n} file{n !== 1 ? "s" : ""}</span>
                    </button>
                  );
                })}
              </div>
            )}

            {panel.step === "files" && (
              <div className="iqac-files-view">
                {panel.readOnly && (
                  <p className="iqac-readonly-hint">
                    You are viewing in read-only mode. Use <strong>Open</strong> on the card to upload files.
                    {canDeleteIqacFiles ? " You can delete files from there." : ""}
                  </p>
                )}
                {!panel.readOnly && (
                  <form className="iqac-upload-form" onSubmit={handleUpload}>
                    <div className="iqac-upload-row">
                      <input
                        type="file"
                        accept=".pdf,.doc,.docx"
                        ref={(el) => setUploadFile(el)}
                        onChange={() => setUploadError("")}
                      />
                      <input
                        type="text"
                        placeholder="Description (optional)"
                        value={uploadDesc}
                        onChange={(e) => setUploadDesc(e.target.value)}
                        className="iqac-upload-desc"
                      />
                      <button type="submit" className="primary-action" disabled={uploading || !uploadFile?.files?.[0]}>
                        {uploading ? "Uploading…" : "Upload"}
                      </button>
                    </div>
                    {uploadError && <p className="form-error iqac-upload-err">{uploadError}</p>}
                    <p className="form-hint">Max 10 MB. PDF, DOC, DOCX only.</p>
                  </form>
                )}

                {filesLoading ? (
                  <p className="iqac-files-loading">Loading…</p>
                ) : files.length === 0 ? (
                  <p className="iqac-files-empty">No documents uploaded yet.</p>
                ) : (
                  <ul className="iqac-file-list">
                    {files.map((f) => (
                      <li key={f.id} className="iqac-file-row">
                        <div className="iqac-file-info">
                          <span className="iqac-file-name">{f.fileName}</span>
                          <span className="iqac-file-meta">
                            {formatBytes(f.size)} · {formatDate(f.uploadedAt)}
                            {f.description ? ` · ${f.description}` : ""}
                          </span>
                        </div>
                        <div className="iqac-file-actions">
                          <button type="button" className="details-button iqac-btn-view-file" onClick={() => handleView(f.id, f.fileName)} title="Open in new tab">
                            View
                          </button>
                          <button type="button" className="details-button" onClick={() => handleDownload(f.id, f.fileName)}>
                            Download
                          </button>
                          {!panel.readOnly && canDeleteIqacFiles && (
                            <button type="button" className="details-button reject" onClick={() => handleDelete(f.id)}>
                              Delete
                            </button>
                          )}
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}
