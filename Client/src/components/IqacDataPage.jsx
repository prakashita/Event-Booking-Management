/**
 * IQAC Data Collection: SSR/NAAC form sections plus criteria evidence collection.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { SimpleIcon } from "./icons";
import { Modal } from "./ui";
import IqacTemplateDownloadCard from "./IqacTemplateDownloadCard";
import api from "../services/api";
import { MAX_PDF_FILE_SIZE, PDF_SIZE_ERROR_MESSAGE } from "../constants/uploadConfig";

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
  { key: "programmes_offered", code: "1.1", label: "Number of Programmes offered year wise for last five years" },
  { key: "students", code: "2.1", label: "Number of students year wise during the last five years" },
  { key: "outgoing_students", code: "2.2", label: "Number of outgoing / final year students year wise during the last five years" },
  { key: "exam_appeared", code: "2.3", label: "Number of students appeared in the University examination year wise during the last five years" },
  { key: "revaluation_applications", code: "2.4", label: "Number of revaluation applications year wise during the last 5 years" },
  { key: "courses", code: "3.1", label: "Number of courses in all Programmes year wise during the last five years" },
  { key: "full_time_teachers", code: "3.2", label: "Number of full time teachers year wise during the last five years" },
  { key: "sanctioned_posts", code: "3.3", label: "Number of sanctioned posts year wise during the last five years" },
  { key: "eligible_applications", code: "4.1", label: "Number of eligible applications received for admissions to all the Programmes year wise during the last five years" },
  { key: "reserved_seats", code: "4.2", label: "Number of seats earmarked for reserved category as per GOI/State Govt rule year wise during the last five years" },
  { key: "expenditure_excluding_salary", code: "4.5", label: "Total Expenditure excluding salary year wise during the last five years (INR in Lakhs)", valueRowLabel: "Expenditure" },
];

const EXTENDED_PROFILE_SECTIONS = [
  {
    index: "1",
    title: "Programme",
    items: [
      { type: "year", key: "programmes_offered" },
      { type: "single", key: "departments_offering_programmes", code: "1.2", label: "Number of departments offering academic programmes" },
    ],
  },
  {
    index: "2",
    title: "Student",
    items: [
      { type: "year", key: "students" },
      { type: "year", key: "outgoing_students" },
      { type: "year", key: "exam_appeared" },
      { type: "year", key: "revaluation_applications" },
    ],
  },
  {
    index: "3",
    title: "Academic",
    items: [
      { type: "year", key: "courses" },
      { type: "year", key: "full_time_teachers" },
      { type: "year", key: "sanctioned_posts" },
    ],
  },
  {
    index: "4",
    title: "Institution",
    items: [
      { type: "year", key: "eligible_applications" },
      { type: "year", key: "reserved_seats" },
      { type: "single", key: "total_classrooms_seminar_halls", code: "4.3", label: "Total number of classrooms and seminar halls" },
      { type: "single", key: "total_computers_academic", code: "4.4", label: "Total number of computers in the campus for academic purpose" },
      { type: "year", key: "expenditure_excluding_salary" },
    ],
  },
];

const STAFF_STATUSES = ["Sanctioned", "Recruited", "Yet to Recruit", "On Contract"];
const TEACHING_ROLES = ["Professor", "Associate Professor", "Assistant Professor"];
const GENDER_COLUMNS = ["Male", "Female", "Others", "Total"];
const QUALIFICATIONS = ["D.Sc/D.Litt", "Ph.D.", "M.Phil.", "PG"];
const ACADEMIC_YEAR_LABELS = ["Year 1", "Year 2", "Year 3", "Year 4", "Year 5"];
const CAMPUS_LOCATIONS = ["Urban", "Semi Urban", "Rural", "Tribal", "Hill"];

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

function affiliatedInstitutionRows() {
  return [{ college_type: "", permanent_affiliation: "", temporary_affiliation: "" }];
}

function collegeTypeAffiliationRows() {
  return [
    { college_type: "Education/Teachers Training", permanent: "", temporary: "", total: "" },
    { college_type: "Business administration/Commerce/Management/Finance", permanent: "", temporary: "", total: "" },
    { college_type: "Universal/Common to all Disciplines", permanent: "", temporary: "", total: "" },
  ];
}

function mergeRowsByKey(rows, fallbackRows, keyName, valueMapper = (row) => row) {
  const source = Array.isArray(rows) ? rows : [];
  return fallbackRows.map((fallbackRow) => {
    const match = source.find((row) => row?.[keyName] === fallbackRow[keyName]);
    return match ? { ...fallbackRow, ...valueMapper(match) } : fallbackRow;
  });
}

function normalizeCollegeTypeAffiliations(rows, fallbackRows) {
  return mergeRowsByKey(rows, fallbackRows, "college_type", (row) => ({
    permanent: row.permanent ?? row.permanent_affiliation ?? "",
    temporary: row.temporary ?? row.temporary_affiliation ?? "",
    total: row.total ?? "",
  }));
}

function normalizeCampuses(rows, fallbackRows) {
  const source = cloneRows(rows, fallbackRows);
  return source.map((row) => {
    const oldCampusTypeWasLocation = CAMPUS_LOCATIONS.includes(row.campus_type) && !row.location;
    return oldCampusTypeWasLocation
      ? { ...row, campus_type: "", location: row.campus_type }
      : row;
  });
}

function createProfileData() {
  return {
    basic_information: { name: "", address: "", city: "", pin: "", state: "", website: "" },
    contacts: [{ designation: "", name: "", telephone: "", mobile: "", fax: "", email: "" }],
    institution: { nature: "", status: "", type: "" },
    establishment: { establishment_date: "", status_prior: "", establishment_date_if_applicable: "" },
    recognition: { ugc_2f_date: "", ugc_12b_date: "", other_agencies: [] },
    upe_recognized: "",
    campuses: [{
      campus_type: "", address: "", location: "", campus_area_acres: "", built_up_area_sq_mts: "",
      programmes_offered: "", establishment_date: "", recognition_date: "",
    }],
    academic_information: {
      affiliated_institutions: affiliatedInstitutionRows(),
      college_type_affiliations: collegeTypeAffiliationRows(),
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
      sra_programmes: [{ programme: "", regulatory_authority: "", recognition_year: "", intake: "" }],
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
    const recognitionValue = value.recognition || {};
    const { other_agency_name, other_agency_date, ...cleanRecognitionValue } = recognitionValue;
    const legacyRecognitionAgency =
      (other_agency_name || other_agency_date)
        ? [{ agency_name: other_agency_name || "", date: other_agency_date || "" }]
        : [];
    const recognitionExtraRows = Array.isArray(recognitionValue.other_agencies)
      ? recognitionValue.other_agencies
      : legacyRecognitionAgency;
    return {
      ...base,
      ...value,
      basic_information: { ...base.basic_information, ...(value.basic_information || {}) },
      institution: { ...base.institution, ...(value.institution || {}) },
      establishment: { ...base.establishment, ...(value.establishment || {}) },
      recognition: {
        ...base.recognition,
        ...cleanRecognitionValue,
        other_agencies: recognitionExtraRows,
      },
      academic_information: {
        ...base.academic_information,
        ...(value.academic_information || {}),
        affiliated_institutions: cloneRows(
          value.academic_information?.affiliated_institutions &&
            !value.academic_information?.college_type_affiliations
            ? base.academic_information.affiliated_institutions
            : value.academic_information?.affiliated_institutions,
          base.academic_information.affiliated_institutions
        ),
        college_type_affiliations: normalizeCollegeTypeAffiliations(
          value.academic_information?.college_type_affiliations ||
            value.academic_information?.affiliated_institutions,
          base.academic_information.college_type_affiliations
        ),
        college_details: cloneRows(value.academic_information?.college_details, base.academic_information.college_details),
        sra_programmes: cloneRows(value.academic_information?.sra_programmes, base.academic_information.sra_programmes),
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
      campuses: normalizeCampuses(value.campuses, base.campuses),
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

function NaacSection({ title, children, note = "", eyebrow = "" }) {
  return (
    <section className="naac-section">
      <div className="naac-section-head">
        {eyebrow ? <span>{eyebrow}</span> : null}
        <h4>{title}</h4>
        {note ? <p>{note}</p> : null}
      </div>
      {children}
    </section>
  );
}

function NaacTable({ children, minWidth = 760, className = "", colgroup = null }) {
  return (
    <div className="naac-table-wrap">
      <table className={`naac-table${className ? ` ${className}` : ""}`} style={{ minWidth }}>
        {colgroup ? (
          <colgroup>
            {colgroup.map((width, index) => (
              <col key={index} style={width ? { width } : undefined} />
            ))}
          </colgroup>
        ) : null}
        {children}
      </table>
    </div>
  );
}

function NaacTableRow({ children, className = "" }) {
  return <tr className={className}>{children}</tr>;
}

function NaacInputCell({
  value,
  onChange,
  type = "text",
  numeric = false,
  compact = false,
  placeholder = "",
  ariaLabel = "",
}) {
  return (
    <input
      aria-label={ariaLabel}
      className={compact ? "naac-cell-input naac-cell-input--compact" : "naac-cell-input"}
      type={numeric ? "text" : type}
      value={value || ""}
      placeholder={placeholder}
      onChange={(event) => onChange(numeric ? sanitizeNumber(event.target.value) : event.target.value)}
    />
  );
}

function NaacTextareaCell({ value, onChange, rows = 2, placeholder = "", ariaLabel = "" }) {
  return (
    <textarea
      aria-label={ariaLabel}
      className="naac-cell-textarea"
      rows={rows}
      value={value || ""}
      placeholder={placeholder}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

function NaacYesNoCell({ value, onChange, ariaLabel = "Yes or No" }) {
  return (
    <span className="naac-yesno-cell" role="group" aria-label={ariaLabel}>
      {["Yes", "No"].map((option) => (
        <button
          key={option}
          type="button"
          className={value === option ? "naac-yesno-choice naac-yesno-choice--active" : "naac-yesno-choice"}
          onClick={() => onChange(option)}
        >
          {option}
        </button>
      ))}
    </span>
  );
}

function TextInputCell(props) {
  return <NaacInputCell {...props} type="text" />;
}

function NumberInputCell(props) {
  return <NaacInputCell {...props} numeric compact />;
}

function DateInputCell(props) {
  return <NaacInputCell {...props} type="date" />;
}

function TextAreaCell(props) {
  return <NaacTextareaCell {...props} />;
}

function YesNoCell(props) {
  return <NaacYesNoCell {...props} />;
}

function FixedRowsWithDynamicExtraRows({
  title,
  fixedRows,
  extraRows,
  onFixedDateChange,
  onExtraChange,
  onAdd,
  onRemove,
  addLabel = "Add Recognition Agency",
}) {
  return (
    <NaacSection title={title}>
      <NaacTable minWidth={820} className="naac-recognition-table" colgroup={["50%", "34%", "16%"]}>
        <thead>
          <NaacTableRow>
            <th colSpan="3">Date of Recognition as a University by UGC or Any Other National Agency</th>
          </NaacTableRow>
          <NaacTableRow>
            <th>Under Section</th>
            <th>Date</th>
            <th className="naac-actions-col">Actions</th>
          </NaacTableRow>
        </thead>
        <tbody>
          {fixedRows.map((row) => (
            <NaacTableRow key={row.key}>
              <th scope="row">{row.label}</th>
              <td>
                <DateInputCell value={row.date} ariaLabel={`${row.label} date`} onChange={(value) => onFixedDateChange(row.key, value)} />
              </td>
              <td className="naac-actions-col">
                <span className="naac-fixed-row-note">Fixed</span>
              </td>
            </NaacTableRow>
          ))}
          {(extraRows || []).map((row, rowIndex) => (
            <NaacTableRow key={rowIndex}>
              <td>
                <TextInputCell value={row.agency_name} placeholder="Agency/Section name" ariaLabel="Agency or section name" onChange={(value) => onExtraChange(rowIndex, "agency_name", value)} />
              </td>
              <td>
                <DateInputCell value={row.date} ariaLabel="Recognition agency date" onChange={(value) => onExtraChange(rowIndex, "date", value)} />
              </td>
              <td className="naac-actions-col">
                <button type="button" className="naac-row-remove" onClick={() => onRemove(rowIndex)}>Remove</button>
              </td>
            </NaacTableRow>
          ))}
        </tbody>
      </NaacTable>
      <button type="button" className="naac-add-row" onClick={onAdd}>
        {addLabel}
      </button>
    </NaacSection>
  );
}

function RepeatableRowsTable({
  title,
  rows,
  columns,
  onCellChange,
  onAdd,
  onRemove,
  note = "",
  minWidth = 860,
  addLabel = "Add Row",
}) {
  return (
    <NaacSection title={title} note={note}>
      <NaacTable minWidth={minWidth} colgroup={columns.map((col) => col.width || null).concat(onRemove ? ["104px"] : [])}>
        <thead>
          <NaacTableRow>
            {columns.map((col) => (
              <th key={col.key} className={col.compact ? "naac-col-compact" : ""}>{col.label}</th>
            ))}
            {onRemove ? <th className="naac-actions-col">Actions</th> : null}
          </NaacTableRow>
        </thead>
        <tbody>
          {(rows || []).map((row, rowIndex) => (
            <NaacTableRow key={rowIndex}>
              {columns.map((col) => (
                <td key={col.key} className={`${col.wide ? "naac-cell-wide" : ""}${col.compact ? " naac-cell-compact" : ""}`}>
                  {col.readonly ? (
                    <span className="naac-readonly-cell">{row[col.key]}</span>
                  ) : col.type === "select" ? (
                    <select
                      className="naac-cell-input"
                      value={row[col.key] || ""}
                      onChange={(event) => onCellChange(rowIndex, col.key, event.target.value)}
                      aria-label={col.label}
                    >
                      <option value="">Select</option>
                      {(col.options || []).map((option) => <option key={option} value={option}>{option}</option>)}
                    </select>
                  ) : col.type === "textarea" ? (
                    <TextAreaCell
                      value={row[col.key]}
                      rows={col.rows || 2}
                      ariaLabel={col.label}
                      onChange={(value) => onCellChange(rowIndex, col.key, value)}
                    />
                  ) : col.type === "date" ? (
                    <DateInputCell
                      value={row[col.key]}
                      ariaLabel={col.label}
                      onChange={(value) => onCellChange(rowIndex, col.key, value)}
                    />
                  ) : col.numeric ? (
                    <NumberInputCell
                      value={row[col.key]}
                      ariaLabel={col.label}
                      onChange={(value) => onCellChange(rowIndex, col.key, value)}
                    />
                  ) : (
                    <TextInputCell
                      type={col.type || "text"}
                      value={row[col.key]}
                      compact={col.compact}
                      ariaLabel={col.label}
                      onChange={(value) => onCellChange(rowIndex, col.key, value)}
                    />
                  )}
                </td>
              ))}
              {onRemove ? (
                <td className="naac-actions-col">
                  <button type="button" className="naac-row-remove" onClick={() => onRemove(rowIndex)}>Remove</button>
                </td>
              ) : null}
            </NaacTableRow>
          ))}
        </tbody>
      </NaacTable>
      {onAdd ? (
        <button type="button" className="naac-add-row" onClick={onAdd}>
          {addLabel}
        </button>
      ) : null}
    </NaacSection>
  );
}

function StaffMatrixTable({ title, rows, grouped = false, onCellChange }) {
  const minWidth = grouped ? 1180 : 620;
  return (
    <NaacSection title={title}>
      <NaacTable minWidth={minWidth} className="naac-matrix-table">
        {grouped ? (
          <thead>
            <NaacTableRow>
              <th rowSpan="2">Teaching Faculty</th>
              {TEACHING_ROLES.map((role) => <th key={role} colSpan={GENDER_COLUMNS.length}>{role}</th>)}
            </NaacTableRow>
            <NaacTableRow>
              {TEACHING_ROLES.flatMap((role) => GENDER_COLUMNS.map((gender) => <th key={`${role}-${gender}`}>{gender}</th>))}
            </NaacTableRow>
          </thead>
        ) : (
          <thead>
            <NaacTableRow>
              <th>Staff</th>
              {GENDER_COLUMNS.map((gender) => <th key={gender}>{gender}</th>)}
            </NaacTableRow>
          </thead>
        )}
        <tbody>
          {(rows || []).map((row, rowIndex) => (
            <NaacTableRow key={row.status || rowIndex}>
              <th scope="row">{row.status}</th>
              {(grouped ? TEACHING_ROLES.flatMap((role) => GENDER_COLUMNS.map((gender) => `${role}_${gender}`)) : GENDER_COLUMNS).map((key) => (
                <td key={key}>
                  <NaacInputCell compact numeric value={row[key]} ariaLabel={`${row.status} ${key}`} onChange={(value) => onCellChange(rowIndex, key, value)} />
                </td>
              ))}
            </NaacTableRow>
          ))}
        </tbody>
      </NaacTable>
    </NaacSection>
  );
}

function QualificationMatrixTable({ title, rows, onCellChange }) {
  return (
    <NaacSection title={title}>
      <NaacTable minWidth={1100} className="naac-matrix-table naac-qualification-table">
        <thead>
          <NaacTableRow>
            <th rowSpan="2">Highest Qualification</th>
            {TEACHING_ROLES.map((role) => <th key={role} colSpan="3">{role}</th>)}
            <th rowSpan="2">Total</th>
          </NaacTableRow>
          <NaacTableRow>
            {TEACHING_ROLES.flatMap((role) => GENDER_COLUMNS.slice(0, 3).map((gender) => <th key={`${role}-${gender}`}>{gender}</th>))}
          </NaacTableRow>
        </thead>
        <tbody>
          {(rows || []).map((row, rowIndex) => (
            <NaacTableRow key={row.qualification || rowIndex}>
              <th scope="row">{row.qualification}</th>
              {TEACHING_ROLES.flatMap((role) => GENDER_COLUMNS.slice(0, 3).map((gender) => `${role}_${gender}`)).map((key) => (
                <td key={key}>
                  <NaacInputCell compact numeric value={row[key]} ariaLabel={`${row.qualification} ${key}`} onChange={(value) => onCellChange(rowIndex, key, value)} />
                </td>
              ))}
              <td>
                <NaacInputCell compact numeric value={row.Total} ariaLabel={`${row.qualification} total`} onChange={(value) => onCellChange(rowIndex, "Total", value)} />
              </td>
            </NaacTableRow>
          ))}
        </tbody>
      </NaacTable>
    </NaacSection>
  );
}

function StudentEnrolmentTable({ title, rows, onCellChange, programmeKey = "programme" }) {
  const rowSpans = (rows || []).reduce((acc, row) => {
    const label = row[programmeKey] || "";
    acc[label] = (acc[label] || 0) + 1;
    return acc;
  }, {});
  const seen = {};
  return (
    <NaacSection title={title}>
      <NaacTable minWidth={980} className="naac-student-table">
        <thead>
          <NaacTableRow>
            <th>{programmeKey === "programme" ? "Programme" : "Integrated Programme"}</th>
            <th>Gender</th>
            <th>From the State Where University is Located</th>
            <th>From Other States of India</th>
            <th>NRI Students</th>
            <th>Foreign Students</th>
            <th>Total</th>
          </NaacTableRow>
        </thead>
        <tbody>
          {(rows || []).map((row, rowIndex) => {
            const label = row[programmeKey] || "";
            const isFirst = !seen[label];
            seen[label] = true;
            return (
              <NaacTableRow key={`${label}-${row.gender}-${rowIndex}`}>
                {isFirst ? <th rowSpan={rowSpans[label]} scope="rowgroup">{label}</th> : null}
                <th scope="row">{row.gender}</th>
                {["from_state", "from_other_states", "nri", "foreign", "total"].map((key) => (
                  <td key={key}>
                    <NaacInputCell compact numeric value={row[key]} ariaLabel={`${label} ${row.gender} ${key}`} onChange={(value) => onCellChange(rowIndex, key, value)} />
                  </td>
                ))}
              </NaacTableRow>
            );
          })}
        </tbody>
      </NaacTable>
    </NaacSection>
  );
}

function IntegratedProgrammeEnrolmentTable({ rows, onCellChange }) {
  return (
    <NaacSection title="Integrated Programme Enrolment">
      <NaacTable minWidth={920} className="naac-student-table">
        <thead>
          <NaacTableRow>
            <th>Integrated Programme</th>
            <th>From the state where university is located</th>
            <th>From other states of India</th>
            <th>NRI Students</th>
            <th>Foreign Students</th>
            <th>Total</th>
          </NaacTableRow>
        </thead>
        <tbody>
          {(rows || []).map((row, rowIndex) => (
            <NaacTableRow key={row.gender || rowIndex}>
              <th scope="row">{row.gender}</th>
              {["from_state", "from_other_states", "nri", "foreign", "total"].map((key) => (
                <td key={key}>
                  <NumberInputCell value={row[key]} ariaLabel={`${row.gender} ${key}`} onChange={(value) => onCellChange(rowIndex, key, value)} />
                </td>
              ))}
            </NaacTableRow>
          ))}
        </tbody>
      </NaacTable>
    </NaacSection>
  );
}

function SimpleKeyValueTable({ title, rows, onCellChange, note = "", minWidth = 560 }) {
  return (
    <NaacSection title={title} note={note}>
      <NaacTable minWidth={minWidth} className="naac-key-value-table" colgroup={["70%", "30%"]}>
        <tbody>
          {(rows || []).map((row, rowIndex) => (
            <NaacTableRow key={row.label || row.key || rowIndex}>
              <th scope="row">{row.label}</th>
              <td>
                <NaacInputCell
                  compact
                  numeric={row.numeric !== false}
                  value={row.value}
                  ariaLabel={row.label}
                  onChange={(value) => onCellChange(rowIndex, value)}
                />
              </td>
            </NaacTableRow>
          ))}
        </tbody>
      </NaacTable>
    </NaacSection>
  );
}

function ExecSummaryWritingCard({ title, value, onChange, guidance, placeholder, warnAt = null }) {
  const taRef = useRef(null);
  const [focused, setFocused] = useState(false);
  const words = countWords(value);
  const isWarn = warnAt !== null && words > warnAt;

  const applyAutoGrow = useCallback((el) => {
    if (!el) return;
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
  }, []);

  useEffect(() => {
    applyAutoGrow(taRef.current);
  }, [value, applyAutoGrow]);

  return (
    <div className={`exec-sum-card${focused ? " exec-sum-card--focused" : ""}${isWarn ? " exec-sum-card--warn" : ""}`}>
      <div className="exec-sum-card-header">
        <span className="exec-sum-card-title">{title}</span>
        {guidance && <span className="exec-sum-guidance-chip">{guidance}</span>}
      </div>
      <textarea
        ref={taRef}
        className="exec-sum-textarea"
        value={value || ""}
        placeholder={placeholder || ""}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        onInput={(e) => applyAutoGrow(e.currentTarget)}
        onChange={(e) => onChange(e.target.value)}
      />
      <div className="exec-sum-footer">
        <span className={`exec-sum-word-count${isWarn ? " exec-sum-word-count--warn" : ""}`}>
          {words.toLocaleString()}{warnAt !== null ? ` / ${warnAt} words` : " words"}
          {isWarn && <span className="exec-sum-word-over"> · Over limit</span>}
        </span>
      </div>
    </div>
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
  const totalWarn = totalWords > 5000;

  return (
    <div className="iqac-ssr-editor-grid">
      <div className={`exec-sum-status-strip${totalWarn ? " exec-sum-status-strip--warn" : ""}`}>
        <span className="exec-sum-status-label">
          Every HEI shall prepare an Executive Summary highlighting the main features of the institution.
        </span>
        <span className={`exec-sum-status-count${totalWarn ? " exec-sum-status-count--warn" : ""}`}>
          {totalWords.toLocaleString()} / 5,000 words
          {totalWarn && <span className="exec-sum-status-over"> · Over limit</span>}
        </span>
      </div>
      <ExecSummaryWritingCard
        title="1. Introductory Note on the Institution"
        value={data.introductory_note}
        guidance="Location, vision, mission, type and founding background of the institution."
        placeholder="Provide a brief introduction covering location, type, founding year, vision, mission, and key characteristics of the institution…"
        onChange={(value) => update("introductory_note", value)}
      />
      <ExecSummaryWritingCard
        title="2. Criterion-wise Summary"
        value={data.criteria_summary}
        guidance="Summarise the institution's functioning criterion-wise — not more than 250 words per criterion."
        placeholder="Provide a concise summary for each of the seven NAAC criteria, highlighting key achievements and performance indicators…"
        warnAt={250}
        onChange={(value) => update("criteria_summary", value)}
      />
      <ExecSummaryWritingCard
        title="3. SWOC Analysis"
        value={data.swoc_analysis}
        guidance="Brief note on Strengths, Weaknesses, Opportunities and Challenges."
        placeholder={"Strengths: …\n\nWeaknesses: …\n\nOpportunities: …\n\nChallenges: …"}
        onChange={(value) => update("swoc_analysis", value)}
      />
      <ExecSummaryWritingCard
        title="4. Additional Information about the Institution"
        value={data.additional_information}
        guidance="Any additional information about the institution other than already stated."
        placeholder="Include notable achievements, collaborations, special initiatives, or other relevant details not covered in the criteria summary…"
        onChange={(value) => update("additional_information", value)}
      />
      <ExecSummaryWritingCard
        title="5. Overall Conclusive Explication"
        value={data.conclusive_explication}
        guidance="Overall conclusive explication about the institution's functioning."
        placeholder="Provide a concluding narrative that synthesises the institution's overall performance, commitment to quality, and future direction…"
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
  const updateRecognitionExtra = (rowIndex, key, value) => {
    const rows = [...(data.recognition?.other_agencies || [])];
    rows[rowIndex] = { ...rows[rowIndex], [key]: value };
    patch("recognition", "other_agencies", rows);
  };
  const updateIntegratedProgramme = (key, value) => {
    onChange((prev) => ({ ...prev, integrated_programmes: { ...(prev.integrated_programmes || {}), [key]: value } }));
  };

  const basic = data.basic_information || {};
  const recognition = data.recognition || {};
  const establishment = data.establishment || {};
  const institution = data.institution || {};
  const academic = data.academic_information || {};
  const hrdcRows = [
    { label: "Year of Establishment", value: data.hrdc?.year_of_establishment },
    { label: "Number of UGC Orientation Programmes", value: data.hrdc?.orientation_programmes },
    { label: "Number of UGC Refresher Course", value: data.hrdc?.refresher_courses },
    { label: "Number of University's own Programmes", value: data.hrdc?.own_programmes },
    { label: "Total Number of Programmes Conducted (last five years)", value: data.hrdc?.total_programmes_last_five_years },
  ];

  return (
    <div className="iqac-ssr-editor-grid naac-profile-editor">
      <NaacSection title="Basic Information">
        <NaacTable minWidth={720} className="naac-basic-table" colgroup={["22%", "22%", "20%", "36%"]}>
          <tbody>
            <NaacTableRow>
              <th colSpan="4" className="naac-super-label">Name and Address of the University</th>
            </NaacTableRow>
            <NaacTableRow>
              <th scope="row">Name</th>
              <td colSpan="3">
                <NaacInputCell value={basic.name} ariaLabel="Name of University" onChange={(value) => patch("basic_information", "name", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <th scope="row">Address</th>
              <td colSpan="3">
                <NaacTextareaCell value={basic.address} rows={3} ariaLabel="Address" onChange={(value) => patch("basic_information", "address", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <th scope="row">City</th>
              <td>
                <NaacInputCell compact value={basic.city} ariaLabel="City" onChange={(value) => patch("basic_information", "city", value)} />
              </td>
              <th scope="row">Pin</th>
              <td>
                <NaacInputCell compact numeric value={basic.pin} ariaLabel="Pin" onChange={(value) => patch("basic_information", "pin", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <th scope="row">State</th>
              <td>
                <NaacInputCell compact value={basic.state} ariaLabel="State" onChange={(value) => patch("basic_information", "state", value)} />
              </td>
              <th scope="row">Website</th>
              <td>
                <NaacInputCell type="url" value={basic.website} ariaLabel="Website" onChange={(value) => patch("basic_information", "website", value)} />
              </td>
            </NaacTableRow>
          </tbody>
        </NaacTable>
      </NaacSection>

      <RepeatableRowsTable
        title="Contacts for Communication"
        rows={data.contacts || []}
        minWidth={980}
        columns={[
          { key: "designation", label: "Designation", width: "16%" },
          { key: "name", label: "Name", width: "22%", wide: true },
          { key: "telephone", label: "Telephone with STD Code", width: "15%" },
          { key: "mobile", label: "Mobile", width: "13%" },
          { key: "fax", label: "Fax", width: "11%", compact: true },
          { key: "email", label: "Email", type: "email", width: "23%", wide: true },
        ]}
        onCellChange={(row, key, value) => updateRow("contacts", row, key, value)}
        onAdd={() => setRows("contacts", [...(data.contacts || []), { designation: "", name: "", telephone: "", mobile: "", fax: "", email: "" }])}
        onRemove={(index) => setRows("contacts", (data.contacts || []).filter((_, i) => i !== index))}
      />
      {emailErrors.length ? <p className="form-error">Invalid email in contact row(s): {emailErrors.join(", ")}</p> : null}

      <NaacSection title="Nature of University / Type / Establishment Details">
        <NaacTable minWidth={860} colgroup={["22%", "28%", "22%", "28%"]}>
          <tbody>
            <NaacTableRow>
              <th scope="row">Nature of University</th>
              <td>
                <NaacInputCell value={institution.nature} ariaLabel="Nature of University" onChange={(value) => patch("institution", "nature", value)} />
              </td>
              <th scope="row">Institution Status</th>
              <td>
                <NaacInputCell value={institution.status} ariaLabel="Institution status" onChange={(value) => patch("institution", "status", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <th scope="row">Type of University</th>
              <td colSpan="3">
                <NaacInputCell value={institution.type} ariaLabel="Type of University" onChange={(value) => patch("institution", "type", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <th rowSpan="3" scope="rowgroup">Establishment Details</th>
              <td>Establishment Date of the University</td>
              <td colSpan="2">
                <NaacInputCell type="date" value={establishment.establishment_date} ariaLabel="Establishment date" onChange={(value) => patch("establishment", "establishment_date", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <td>Status Prior to Establishment, if applicable</td>
              <td colSpan="2">
                <NaacInputCell value={establishment.status_prior} ariaLabel="Status prior to establishment" onChange={(value) => patch("establishment", "status_prior", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <td>Establishment Date, if applicable</td>
              <td colSpan="2">
                <NaacInputCell type="date" value={establishment.establishment_date_if_applicable} ariaLabel="Establishment date if applicable" onChange={(value) => patch("establishment", "establishment_date_if_applicable", value)} />
              </td>
            </NaacTableRow>
          </tbody>
        </NaacTable>
      </NaacSection>

      <FixedRowsWithDynamicExtraRows
        title="Recognition Details"
        fixedRows={[
          { key: "ugc_2f_date", label: "2f of UGC", date: recognition.ugc_2f_date },
          { key: "ugc_12b_date", label: "12B of UGC", date: recognition.ugc_12b_date },
        ]}
        extraRows={recognition.other_agencies || []}
        onFixedDateChange={(key, value) => patch("recognition", key, value)}
        onExtraChange={updateRecognitionExtra}
        onAdd={() => patch("recognition", "other_agencies", [...(recognition.other_agencies || []), { agency_name: "", date: "" }])}
        onRemove={(index) => patch("recognition", "other_agencies", (recognition.other_agencies || []).filter((_, i) => i !== index))}
      />

      <NaacSection title="University with Potential for Excellence">
        <NaacTable minWidth={640} colgroup={["78%", "22%"]}>
          <tbody>
            <NaacTableRow>
              <th scope="row">Is the University Recognised as a 'University with Potential for Excellence (UPE)' by the UGC?</th>
              <td>
                <NaacYesNoCell value={data.upe_recognized} ariaLabel="UPE recognition" onChange={(value) => onChange((prev) => ({ ...prev, upe_recognized: value }))} />
              </td>
            </NaacTableRow>
          </tbody>
        </NaacTable>
      </NaacSection>

      <RepeatableRowsTable
        title="Location, Area and Activity of Campus"
        rows={data.campuses || []}
        minWidth={1160}
        columns={[
          { key: "campus_type", label: "Campus Type", width: "12%" },
          { key: "address", label: "Address", type: "textarea", width: "22%", wide: true },
          { key: "location", label: "Location", type: "select", options: CAMPUS_LOCATIONS, width: "12%" },
          { key: "campus_area_acres", label: "Campus Area in Acres", numeric: true, width: "10%", compact: true },
          { key: "built_up_area_sq_mts", label: "Built up Area in sq.mts.", numeric: true, width: "10%", compact: true },
          { key: "programmes_offered", label: "Programmes Offered", width: "18%", wide: true },
          { key: "establishment_date", label: "Date of Establishment", type: "date", width: "13%" },
          { key: "recognition_date", label: "Date of Recognition by UGC/MHRD", type: "date", width: "13%" },
        ]}
        onCellChange={(row, key, value) => updateRow("campuses", row, key, value)}
        onAdd={() => setRows("campuses", [...(data.campuses || []), createProfileData().campuses[0]])}
        onRemove={(index) => setRows("campuses", (data.campuses || []).filter((_, i) => i !== index))}
      />

      <div className="naac-academic-title">Academic Information</div>

      <NaacSection
        title="Affiliated Institutions to the University"
        note="Not applicable for private and deemed to be Universities"
      >
        <div className="naac-academic-stack">
          <NaacTable minWidth={820} colgroup={["34%", "33%", "33%"]}>
            <thead>
              <NaacTableRow>
                <th>College Type</th>
                <th>Number of colleges with permanent affiliation</th>
                <th>Number of colleges with temporary affiliation</th>
              </NaacTableRow>
            </thead>
            <tbody>
              {(academic.affiliated_institutions || []).map((row, rowIndex) => (
                <NaacTableRow key={rowIndex}>
                  <td>
                    <TextInputCell value={row.college_type} ariaLabel="College Type" onChange={(value) => updateNestedRow("academic_information", "affiliated_institutions", rowIndex, "college_type", value)} />
                  </td>
                  <td>
                    <NumberInputCell value={row.permanent_affiliation} ariaLabel="Number of colleges with permanent affiliation" onChange={(value) => updateNestedRow("academic_information", "affiliated_institutions", rowIndex, "permanent_affiliation", value)} />
                  </td>
                  <td>
                    <NumberInputCell value={row.temporary_affiliation} ariaLabel="Number of colleges with temporary affiliation" onChange={(value) => updateNestedRow("academic_information", "affiliated_institutions", rowIndex, "temporary_affiliation", value)} />
                  </td>
                </NaacTableRow>
              ))}
            </tbody>
          </NaacTable>

          <NaacTable minWidth={760} className="naac-affiliation-type-table" colgroup={["42%", "19%", "19%", "20%"]}>
            <thead>
              <NaacTableRow>
                <th>Type of Colleges</th>
                <th>Permanent</th>
                <th>Temporary</th>
                <th>Total</th>
              </NaacTableRow>
            </thead>
            <tbody>
              {(academic.college_type_affiliations || []).map((row, rowIndex) => (
                <NaacTableRow key={row.college_type || rowIndex}>
                  <th scope="row">{row.college_type}</th>
                  {["permanent", "temporary", "total"].map((key) => (
                    <td key={key}>
                      <NumberInputCell value={row[key]} ariaLabel={`${row.college_type} ${key}`} onChange={(value) => updateNestedRow("academic_information", "college_type_affiliations", rowIndex, key, value)} />
                    </td>
                  ))}
                </NaacTableRow>
              ))}
            </tbody>
          </NaacTable>
        </div>
      </NaacSection>

      <SimpleKeyValueTable
        title="Furnish the Details of Colleges under University"
        rows={academic.college_details || []}
        onCellChange={(row, value) => updateNestedRow("academic_information", "college_details", row, "value", value)}
      />

      <NaacSection title="SRA Recognised Programmes">
        <NaacTable minWidth={760} colgroup={["70%", "30%"]}>
          <tbody>
            <NaacTableRow>
              <th scope="row">Is the University Offering any Programmes Recognized by any Statutory Regulatory authority (SRA)</th>
              <td>
                <YesNoCell value={academic.sra_recognized} ariaLabel="SRA recognised programmes" onChange={(value) => patch("academic_information", "sra_recognized", value)} />
              </td>
            </NaacTableRow>
          </tbody>
        </NaacTable>
      </NaacSection>

      <StaffTables data={data} updateStaff={updateStaff} updateQualification={updateQualification} />

      <RepeatableRowsTable
        title="Distinguished Academicians Appointed"
        rows={data.distinguished_academicians || []}
        minWidth={720}
        columns={[
          { key: "role", label: "Role", readonly: true, width: "38%", wide: true },
          { key: "male", label: "Male", numeric: true, compact: true },
          { key: "female", label: "Female", numeric: true, compact: true },
          { key: "others", label: "Others", numeric: true, compact: true },
          { key: "total", label: "Total", numeric: true, compact: true },
        ]}
        onCellChange={(row, key, value) => updateRow("distinguished_academicians", row, key, value)}
      />

      <RepeatableRowsTable
        title="Chairs Instituted by the University"
        rows={data.chairs || []}
        minWidth={920}
        columns={[
          { key: "sl_no", label: "Sl.No", numeric: true, width: "10%", compact: true },
          { key: "department", label: "Name of Department", width: "26%", wide: true },
          { key: "chair", label: "Name of Chair", width: "24%", wide: true },
          { key: "sponsor", label: "Name of Sponsor Organisation/Agency", width: "40%", wide: true },
        ]}
        onCellChange={(row, key, value) => updateRow("chairs", row, key, value)}
        onAdd={() => setRows("chairs", [...(data.chairs || []), { sl_no: "", department: "", chair: "", sponsor: "" }])}
        onRemove={(index) => setRows("chairs", (data.chairs || []).filter((_, i) => i !== index))}
      />

      <StudentEnrolmentTable
        title="Students Enrolled during the Current Academic Year"
        rows={data.student_enrolment || []}
        onCellChange={(row, key, value) => updateRow("student_enrolment", row, key, value)}
      />

      <NaacSection title="Integrated Programmes">
        <NaacTable minWidth={720} colgroup={["64%", "36%"]}>
          <tbody>
            <NaacTableRow>
              <th scope="row">Does the university offer any integrated programmes?</th>
              <td>
                <YesNoCell value={data.integrated_programmes?.offered} ariaLabel="Integrated programmes offered" onChange={(value) => updateIntegratedProgramme("offered", value)} />
              </td>
            </NaacTableRow>
            <NaacTableRow>
              <th scope="row">Total number of integrated programmes</th>
              <td>
                <NumberInputCell value={data.integrated_programmes?.total_programmes} ariaLabel="Total integrated programmes" onChange={(value) => updateIntegratedProgramme("total_programmes", value)} />
              </td>
            </NaacTableRow>
          </tbody>
        </NaacTable>
      </NaacSection>

      <IntegratedProgrammeEnrolmentTable
        rows={data.integrated_programmes?.enrolment || []}
        onCellChange={(row, key, value) => updateNestedRow("integrated_programmes", "enrolment", row, key, value)}
      />

      <SimpleKeyValueTable
        title="UGC HRDC Details"
        note="Details of UGC Human Resource Development Centre, if applicable."
        rows={hrdcRows}
        onCellChange={(row, value) => patch("hrdc", ["year_of_establishment", "orientation_programmes", "refresher_courses", "own_programmes", "total_programmes_last_five_years"][row], value)}
      />

      <RepeatableRowsTable
        title="Evaluative Report of the Departments"
        rows={data.department_reports || []}
        minWidth={760}
        columns={[
          { key: "department_name", label: "Department Name", width: "45%", wide: true },
          { key: "report_reference", label: "Upload Report / File Reference", width: "55%", wide: true },
        ]}
        onCellChange={(row, key, value) => updateRow("department_reports", row, key, value)}
        onAdd={() => setRows("department_reports", [...(data.department_reports || []), { department_name: "", report_reference: "" }])}
        onRemove={(index) => setRows("department_reports", (data.department_reports || []).filter((_, i) => i !== index))}
      />
    </div>
  );
}

function StaffTables({ data, updateStaff, updateQualification }) {
  return (
    <>
      <NaacSection title="Teaching / Non-Teaching / Technical Staff" note="Details of Teaching and Non-Teaching Staff of University">
        <div className="naac-staff-stack">
          <StaffMatrixTable title="Teaching Faculty" grouped rows={data.staff?.teaching || []} onCellChange={(row, key, value) => updateStaff("teaching", row, key, value)} />
          <StaffMatrixTable title="Non-Teaching Staff" rows={data.staff?.non_teaching || []} onCellChange={(row, key, value) => updateStaff("non_teaching", row, key, value)} />
          <StaffMatrixTable title="Technical Staff" rows={data.staff?.technical || []} onCellChange={(row, key, value) => updateStaff("technical", row, key, value)} />
        </div>
      </NaacSection>
      <NaacSection title="Qualification Details of Teaching Staff">
        <div className="naac-staff-stack">
          <QualificationMatrixTable title="Permanent Teachers" rows={data.qualification_details?.permanent_teachers || []} onCellChange={(row, key, value) => updateQualification("permanent_teachers", row, key, value)} />
          <QualificationMatrixTable title="Temporary Teachers" rows={data.qualification_details?.temporary_teachers || []} onCellChange={(row, key, value) => updateQualification("temporary_teachers", row, key, value)} />
          <QualificationMatrixTable title="Part Time Teachers" rows={data.qualification_details?.part_time_teachers || []} onCellChange={(row, key, value) => updateQualification("part_time_teachers", row, key, value)} />
        </div>
      </NaacSection>
    </>
  );
}

function getExtendedMetric(metricKey) {
  return EXTENDED_PROFILE_METRICS.find((metric) => metric.key === metricKey) || {};
}

function MetricYearTable({ metric, yearLabels, values, onYearChange, onValueChange }) {
  const safeYears = [...(yearLabels || ACADEMIC_YEAR_LABELS), "", "", "", "", ""].slice(0, 5);
  const safeValues = [...(Array.isArray(values) ? values : []), "", "", "", "", ""].slice(0, 5);
  const valueRowLabel = metric.valueRowLabel || "Number";
  return (
    <div className="extended-metric-block">
      <h5>{metric.code} {metric.label}</h5>
      <NaacTable minWidth={760} className="extended-year-table" colgroup={["17%", "16.6%", "16.6%", "16.6%", "16.6%", "16.6%"]}>
        <tbody>
          <NaacTableRow>
            <th scope="row">Year</th>
            {safeYears.map((year, index) => (
              <td key={`year-${index}`}>
                <TextInputCell value={year} ariaLabel={`Year ${index + 1}`} onChange={(value) => onYearChange(index, value)} />
              </td>
            ))}
          </NaacTableRow>
          <NaacTableRow>
            <th scope="row">{valueRowLabel}</th>
            {safeValues.map((value, index) => (
              <td key={`value-${index}`}>
                <NumberInputCell value={value} ariaLabel={`${metric.code} ${valueRowLabel} ${index + 1}`} onChange={(nextValue) => onValueChange(index, nextValue)} />
              </td>
            ))}
          </NaacTableRow>
        </tbody>
      </NaacTable>
    </div>
  );
}

function SingleMetricInput({ code, label, value, onChange }) {
  return (
    <div className="extended-single-metric">
      <label>
        <span>{code} {label}</span>
        <NumberInputCell value={value} ariaLabel={`${code} ${label}`} onChange={onChange} />
      </label>
    </div>
  );
}

function ExtendedProfileSection({ index, title, children }) {
  return (
    <section className="extended-profile-section">
      <h4><span>{index}</span> {title}:</h4>
      <div className="extended-profile-section-body">
        {children}
      </div>
    </section>
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
  const setSingleMetric = (key, value) => {
    onChange((prev) => ({ ...prev, [key]: sanitizeNumber(value) }));
  };
  const yearLabels = [...(data.year_labels || ACADEMIC_YEAR_LABELS), "", "", "", "", ""].slice(0, 5);

  return (
    <div className="extended-profile-editor">
      <div className="extended-profile-title">3. Extended Profile of the University</div>
      {EXTENDED_PROFILE_SECTIONS.map((section) => (
        <ExtendedProfileSection key={section.title} index={section.index} title={section.title}>
          {section.items.map((item) => {
            if (item.type === "single") {
              return (
                <SingleMetricInput
                  key={item.key}
                  code={item.code}
                  label={item.label}
                  value={data[item.key]}
                  onChange={(value) => setSingleMetric(item.key, value)}
                />
              );
            }
            const metric = getExtendedMetric(item.key);
            return (
              <MetricYearTable
                key={item.key}
                metric={metric}
                yearLabels={yearLabels}
                values={data.metrics?.[item.key]}
                onYearChange={setYear}
                onValueChange={(index, value) => setMetricValue(item.key, index, value)}
              />
            );
          })}
        </ExtendedProfileSection>
      ))}
    </div>
  );
}

function ReadOnlyQifNote() {
  return (
    <article className="qif-note-panel">
      <h3>4. Quality Indicator Framework (QIF)</h3>
      <h4>Essential Note:</h4>
      <p>The SSR has to be filled in an online format available on the NAAC website.</p>
      <p>The QIF given below presents the Metrics under each Key Indicator (KI) for all the seven Criteria.</p>
      <div className="qif-note-list-block">
        <p>While going through the QIF, details are given below each Metric in the form of:</p>
        <ul>
          <li>data required</li>
          <li>formula for calculating the information, wherever required, and</li>
          <li>File description &ndash; for uploading of document where so-ever required.</li>
        </ul>
      </div>
      <p>These will help Institutions in the preparation of their SSR.</p>
      <p>For some Qualitative Metrics (QlM) which seek descriptive data it is specified as to what kind of information has to be given and how much. It is advisable to keep data accordingly compiled beforehand.</p>
      <p>For the Quantitative Metrics (QnM) wherever formula is given, it must be noted that these are given merely to inform the HEIs about the manner in which data submitted will be used. That is the actual online format seeks only data in specified manner which will be processed digitally.</p>
      <p>Metric wise weightage is also given.</p>
      <p>The actual online format may change slightly from the QIF given in this Manual, in order to bring compatibility with IT design. Observe this carefully while filling up.</p>
    </article>
  );
}

function QifEditor() {
  return (
    <div className="qif-readonly-page">
      <ReadOnlyQifNote />
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
  const [pdfExporting, setPdfExporting] = useState(false);
  const [pdfExportError, setPdfExportError] = useState("");
  const [docxExporting, setDocxExporting] = useState(false);
  const [docxExportError, setDocxExportError] = useState("");
  const [exportMenuOpen, setExportMenuOpen] = useState(false);

  const handleGeneratePdf = useCallback(async () => {
    setExportMenuOpen(false);
    setPdfExporting(true);
    setPdfExportError("");
    try {
      const blob = await api.downloadSsrPdf();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `IQAC_SSR_NAAC_Report_${new Date().toISOString().slice(0, 10)}.pdf`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      setPdfExportError(err?.message || "PDF generation failed. Please try again.");
    } finally {
      setPdfExporting(false);
    }
  }, []);

  const handleGenerateDocx = useCallback(async () => {
    setExportMenuOpen(false);
    setDocxExporting(true);
    setDocxExportError("");
    try {
      const blob = await api.downloadSsrDocx();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `IQAC_SSR_NAAC_Report_${new Date().toISOString().slice(0, 10)}.docx`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch (err) {
      setDocxExportError(err?.message || "Word generation failed. Please try again.");
    } finally {
      setDocxExporting(false);
    }
  }, []);

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
    const file = uploadFile.files[0];
    if (
      (file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf")) &&
      file.size > MAX_PDF_FILE_SIZE
    ) {
      setUploadError(PDF_SIZE_ERROR_MESSAGE);
      return;
    }
    setUploading(true);
    setUploadError("");
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
          <div className="iqac-ssr-head-actions">
            <span className="iqac-badge">IQAC Portal Only</span>
            <div className="iqac-export-wrap">
              <button
                type="button"
                className="iqac-pdf-btn"
                disabled={pdfExporting || docxExporting || ssrLoading}
                onClick={() => setExportMenuOpen((o) => !o)}
                title="Export the full NAAC SSR report"
              >
                {(pdfExporting || docxExporting) ? (
                  <>
                    <span className="iqac-pdf-btn-spinner" aria-hidden="true" />
                    Exporting…
                  </>
                ) : (
                  <>
                    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true">
                      <path d="M3 15v2a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-2" strokeLinecap="round"/>
                      <path d="M10 3v9m0 0-3-3m3 3 3-3" strokeLinecap="round" strokeLinejoin="round"/>
                    </svg>
                    Export Report ▾
                  </>
                )}
              </button>
              {exportMenuOpen && (
                <div className="iqac-export-dropdown">
                  <button type="button" className="iqac-export-option" onClick={handleGeneratePdf}>
                    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true" width="16" height="16">
                      <rect x="3" y="2" width="14" height="16" rx="1.5" />
                      <path d="M7 7h6M7 10h6M7 13h4" strokeLinecap="round"/>
                    </svg>
                    Export as PDF
                  </button>
                  <button type="button" className="iqac-export-option iqac-export-option--word" onClick={handleGenerateDocx}>
                    <svg viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true" width="16" height="16">
                      <rect x="3" y="2" width="14" height="16" rx="1.5" />
                      <path d="M6 7l2 7 2-4 2 4 2-7" strokeLinecap="round" strokeLinejoin="round"/>
                    </svg>
                    Export as Word (.docx)
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
        {pdfExportError ? (
          <p className="iqac-template-message iqac-template-message--error">{pdfExportError}</p>
        ) : null}
        {docxExportError ? (
          <p className="iqac-template-message iqac-template-message--error">{docxExportError}</p>
        ) : null}
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
                <div className="iqac-export-wrap">
                  <button
                    type="button"
                    className="iqac-pdf-btn iqac-pdf-btn--compact"
                    disabled={pdfExporting || docxExporting}
                    onClick={() => setExportMenuOpen((o) => !o)}
                    title="Export the full SSR report"
                  >
                    {(pdfExporting || docxExporting) ? "Exporting…" : "Export Report ▾"}
                  </button>
                  {exportMenuOpen && (
                    <div className="iqac-export-dropdown iqac-export-dropdown--up">
                      <button type="button" className="iqac-export-option" onClick={handleGeneratePdf}>
                        Export as PDF
                      </button>
                      <button type="button" className="iqac-export-option iqac-export-option--word" onClick={handleGenerateDocx}>
                        Export as Word (.docx)
                      </button>
                    </div>
                  )}
                </div>
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
