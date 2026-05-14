/**
 * PublicationViewModal — read-only detailed view of a single publication.
 *
 * Sections:
 *  1. Header  — type badge, title, close
 *  2. Submitter row — by / date
 *  3. Citation preview
 *  4. Core details grid — all non-empty fields
 *  5. Links / DOI / File
 *  6. Notes / Annotation
 *  7. Footer actions — Edit, [Delete shown from parent]
 */
import { memo, useCallback } from "react";
import { PUBLICATION_FIELD_DEFINITIONS, PUB_META } from "../../constants";
import { PublicationIcon } from "./PublicationFormModal";
import {
  PUBLICATION_SOURCE_ICON_PATHS,
  getPublicationDetails,
  getPublicationDisplayTitle,
  getPublicationFieldValue,
  getPublicationSourceConfig,
  getPublicationSourceKey,
} from "./publicationUtils";

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatDateStr(value) {
  if (!value) return null;
  try {
    const d = new Date(value);
    if (isNaN(d.getTime())) return String(value);
    return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
  } catch {
    return String(value);
  }
}

function buildCitation(item, format) {
  const rawAuthor = item.author || "";
  const author = rawAuthor.startsWith("[") || rawAuthor.startsWith("{") ? "" : rawAuthor;
  const title = getPublicationDisplayTitle(item);
  const container =
    getPublicationFieldValue(item, "container_title") || item.publisher || "";
  const issued =
    getPublicationFieldValue(item, "issued_date") ||
    item.publication_date ||
    item.year ||
    "";
  const doi = getPublicationFieldValue(item, "doi") || item.doi || "";
  const url = doi
    ? `https://doi.org/${String(doi).replace(/^https?:\/\/doi\.org\/?/i, "")}`
    : getPublicationFieldValue(item, "url") || item.url || "";
  const ic = container ? `*${container}*` : "";
  if (!format || format === "mla")
    return [author, `"${title}"`, ic, issued, url].filter(Boolean).join(", ");
  if (format === "apa")
    return [author, issued && `(${issued})`, title, ic, url].filter(Boolean).join(". ").replace(/\.\./g, ".");
  if (format === "harvard")
    return [author, issued, title, ic, url].filter(Boolean).join(", ");
  if (format === "chicago")
    return [author, `"${title}"`, ic, issued, url].filter(Boolean).join(", ");
  if (format === "ieee")
    return [author, `"${title},"`, ic, issued, url].filter(Boolean).join(", ");
  return [author, title, container, issued, url].filter(Boolean).join(", ");
}

function renderCitation(citation) {
  if (!citation) return null;
  return citation.split(/(\*[^*]+\*)/g).map((seg, i) =>
    seg.startsWith("*") && seg.endsWith("*") ? (
      <em key={i}>{seg.slice(1, -1)}</em>
    ) : (
      <span key={i}>{seg}</span>
    )
  );
}

// The master field list used in detail view — covers all source types.
const DETAIL_FIELD_ORDER = [
  "title", "content",
  "issued_date", "accessed_date", "composed_date", "submitted_date",
  "container_title", "collection_title",
  "volume", "issue", "pages", "page_number", "number",
  "edition", "medium",
  "publisher", "publisher_place",
  "doi", "url", "pdf_url",
  "source", "organization",
  "archive_collection", "place_country", "place_region", "place_locality",
  "subtitle", "description",
  "status",
];

// Top-level legacy fields also shown when set.
const LEGACY_TOP_FIELDS = [
  ["article_title", "Article Title"],
  ["book_title", "Book Title"],
  ["report_title", "Report Title"],
  ["video_title", "Video Title"],
  ["page_title", "Page Title"],
  ["journal_name", "Journal Name"],
  ["website_name", "Website Name"],
  ["newspaper_name", "Newspaper Name"],
  ["platform", "Platform"],
  ["publisher", "Publisher"],
  ["volume", "Volume"],
  ["issue", "Issue"],
  ["pages", "Pages"],
  ["doi", "DOI"],
  ["url", "URL"],
  ["edition", "Edition"],
  ["year", "Year"],
  ["creator", "Creator"],
  ["organization", "Organization"],
];

// ─── Detail row ───────────────────────────────────────────────────────────────

const DetailRow = memo(function DetailRow({ label, value, isLink, isUrl }) {
  if (!value && value !== 0) return null;
  const display = String(value).trim();
  if (!display) return null;
  return (
    <div className="pv-detail-row">
      <dt className="pv-detail-label">{label}</dt>
      <dd className="pv-detail-value">
        {isLink || isUrl ? (
          <a
            href={display.startsWith("http") ? display : `https://${display}`}
            target="_blank"
            rel="noopener noreferrer"
            className="pv-link"
          >
            {display}
            <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6"/>
              <polyline points="15 3 21 3 21 9"/>
              <line x1="10" y1="14" x2="21" y2="3"/>
            </svg>
          </a>
        ) : display}
      </dd>
    </div>
  );
});

// ─── Main component ───────────────────────────────────────────────────────────

const PublicationViewModal = memo(function PublicationViewModal({
  item,
  citationFormat,
  onClose,
  onEdit,
  onDeleteRequest,
  canEdit,
  canDelete,
}) {
  const sourceKey = getPublicationSourceKey(item.source_type || item.pub_type);
  const meta =
    PUB_META[item.source_type || item.pub_type] ||
    PUB_META[sourceKey] || { label: item.pub_type || "Publication", color: "#666" };
  const sourceConfig = getPublicationSourceConfig(sourceKey);
  const citation = buildCitation(item, citationFormat || item.citation_format || "mla");
  const details = getPublicationDetails(item);
  const title = getPublicationDisplayTitle(item);
  const submittedDate = item.created_at
    ? formatDateStr(item.created_at)
    : null;
  const issuedDate =
    getPublicationFieldValue(item, "issued_date") ||
    item.publication_date ||
    item.year || null;

  const handleOverlayMouseDown = useCallback(
    (e) => { if (e.target === e.currentTarget) onClose(); },
    [onClose]
  );

  // Collect all displayable fields
  const shownDetailFields = [];
  const seenLabels = new Set();

  // Details dict fields
  for (const field of DETAIL_FIELD_ORDER) {
    const def = PUBLICATION_FIELD_DEFINITIONS[field];
    const label = def?.label || field;
    if (seenLabels.has(label)) continue;
    const rawValue = details[field] ?? item[field];
    if (!rawValue && rawValue !== 0) continue;
    const value = Array.isArray(rawValue)
      ? rawValue.map((v) => String(v).trim()).filter(Boolean).join(", ")
      : String(rawValue).trim();
    if (!value) continue;
    seenLabels.add(label);
    shownDetailFields.push({
      label,
      value,
      isUrl: field === "url" || field === "pdf_url",
    });
  }

  // Legacy top-level fields not already shown
  for (const [field, label] of LEGACY_TOP_FIELDS) {
    if (seenLabels.has(label)) continue;
    const rawValue = item[field];
    if (!rawValue) continue;
    const value = String(rawValue).trim();
    if (!value) continue;
    seenLabels.add(label);
    shownDetailFields.push({
      label,
      value,
      isUrl: field === "url" || field === "pdf_url",
    });
  }

  const doiValue = getPublicationFieldValue(item, "doi") || item.doi || null;
  const urlValue = getPublicationFieldValue(item, "url") || item.url || null;
  const pdfUrl = getPublicationFieldValue(item, "pdf_url") || item.pdf_url || null;
  const fileLink = item.web_view_link || null;
  const hasLinks = doiValue || urlValue || pdfUrl || fileLink;

  return (
    <div
      className="modal-overlay pub-view-overlay"
      role="dialog"
      aria-modal="true"
      aria-label={`View publication: ${title}`}
      onMouseDown={handleOverlayMouseDown}
    >
      <div className="modal-card pub-view-card">
        {/* ── Header ── */}
        <div className="modal-header pub-view-header">
          <div className="pub-view-header-left">
            <span
              className={`pub-type-badge pub-type-${sourceKey || "unknown"} pub-view-type-badge`}
            >
              <span className="pub-badge-icon">
                <PublicationIcon sourceKey={sourceKey} />
              </span>
              {meta.label}
            </span>
            <h3 className="pub-view-title" title={title}>{title}</h3>
          </div>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">
            &times;
          </button>
        </div>

        {/* ── Scrollable body ── */}
        <div className="pub-view-body">
          {/* Submitter row */}
          {(() => {
            const rawA = item.author || "";
            const safeAuthor = (rawA.startsWith("[") || rawA.startsWith("{")) ? "" : rawA;
            return (safeAuthor || item.created_by_name || submittedDate) ? (
            <div className="pub-view-meta-row">
              <div className="pub-view-avatar" aria-hidden="true">
                {(item.created_by_name || safeAuthor || "P").charAt(0).toUpperCase()}
              </div>
              <div className="pub-view-meta-info">
                {item.created_by_name && (
                  <span className="pub-view-submitter">
                    <strong>Submitted by</strong> {item.created_by_name}
                  </span>
                )}
                {safeAuthor && (
                  <span className="pub-view-author-row">
                    <strong>Author</strong> {safeAuthor}
                  </span>
                )}
                {submittedDate && (
                  <span className="pub-view-date">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
                      <line x1="16" y1="2" x2="16" y2="6"/>
                      <line x1="8" y1="2" x2="8" y2="6"/>
                      <line x1="3" y1="10" x2="21" y2="10"/>
                    </svg>
                    {submittedDate}
                    {issuedDate && issuedDate !== submittedDate && (
                      <span className="pub-view-issued"> · Published {issuedDate}</span>
                    )}
                  </span>
                )}
              </div>
            </div>
          ) : null;
          })()}

          {/* Citation format badge */}
          {item.citation_format && (
            <div className="pub-view-section pub-view-section-citation">
              <div className="pub-view-section-label">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M4 19.5A2.5 2.5 0 016.5 17H20"/>
                  <path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z"/>
                </svg>
                Citation ({(item.citation_format || "mla").toUpperCase()})
              </div>
              <blockquote className="pub-view-citation">
                {renderCitation(citation)}
              </blockquote>
            </div>
          )}

          {/* Details grid */}
          {shownDetailFields.length > 0 && (
            <div className="pub-view-section">
              <div className="pub-view-section-label">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <line x1="8" y1="6" x2="21" y2="6"/>
                  <line x1="8" y1="12" x2="21" y2="12"/>
                  <line x1="8" y1="18" x2="21" y2="18"/>
                  <line x1="3" y1="6" x2="3.01" y2="6"/>
                  <line x1="3" y1="12" x2="3.01" y2="12"/>
                  <line x1="3" y1="18" x2="3.01" y2="18"/>
                </svg>
                Publication Details
              </div>
              <dl className="pv-detail-grid">
                {shownDetailFields.map(({ label, value, isUrl }) => (
                  <DetailRow key={label} label={label} value={value} isUrl={isUrl} />
                ))}
              </dl>
            </div>
          )}

          {/* Links / DOI */}
          {hasLinks && (
            <div className="pub-view-section">
              <div className="pub-view-section-label">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71"/>
                  <path d="M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71"/>
                </svg>
                Links
              </div>
              <div className="pub-view-links">
                {doiValue && (
                  <a
                    href={`https://doi.org/${String(doiValue).replace(/^https?:\/\/doi\.org\/?/i, "")}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="pub-action-btn pub-action-doi"
                  >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <circle cx="12" cy="12" r="10"/>
                      <line x1="2" y1="12" x2="22" y2="12"/>
                      <path d="M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20"/>
                    </svg>
                    DOI
                  </a>
                )}
                {urlValue && (
                  <a
                    href={urlValue}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="pub-action-btn pub-action-url"
                  >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6"/>
                      <polyline points="15 3 21 3 21 9"/>
                      <line x1="10" y1="14" x2="21" y2="3"/>
                    </svg>
                    Visit URL
                  </a>
                )}
                {pdfUrl && (
                  <a
                    href={pdfUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="pub-action-btn pub-action-file"
                  >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                      <polyline points="14 2 14 8 20 8"/>
                    </svg>
                    PDF
                  </a>
                )}
                {fileLink && (
                  <a
                    href={fileLink}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="pub-action-btn pub-action-file"
                  >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                      <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                      <polyline points="14 2 14 8 20 8"/>
                    </svg>
                    View File
                  </a>
                )}
              </div>
            </div>
          )}

          {/* Annotation / Notes */}
          {(item.others || item.note) && (
            <div className="pub-view-section">
              <div className="pub-view-section-label">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/>
                </svg>
                Annotation / Notes
              </div>
              <p className="pub-view-notes">{item.others || item.note}</p>
            </div>
          )}

          {/* Audit Information */}
          <div className="pub-view-section pub-audit-section">
            <div className="pub-view-section-label">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <circle cx="12" cy="12" r="10"/>
                <polyline points="12 6 12 12 16 14"/>
              </svg>
              Audit Information
            </div>
            <div className="pub-audit-grid">
              <div className="pub-audit-row">
                <span className="pub-audit-label">Created by</span>
                <span className="pub-audit-value">
                  {item.created_by_name || item.created_by_email || "Unknown"}
                </span>
              </div>
              <div className="pub-audit-row">
                <span className="pub-audit-label">Created at</span>
                <span className="pub-audit-value">
                  {item.created_at ? formatDateStr(item.created_at) : "—"}
                </span>
              </div>
              <div className="pub-audit-row">
                <span className="pub-audit-label">Last updated by</span>
                <span className="pub-audit-value">
                  {item.updated_by_name || item.updated_by_email || "Not updated yet"}
                </span>
              </div>
              <div className="pub-audit-row">
                <span className="pub-audit-label">Last updated at</span>
                <span className="pub-audit-value">
                  {item.updated_at ? formatDateStr(item.updated_at) : "Not updated yet"}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* ── Footer ── */}
        <div className="modal-actions pub-view-footer">
          <button type="button" className="secondary-action" onClick={onClose}>
            Close
          </button>
          {canDelete && (
            <button
              type="button"
              className="pub-view-delete-btn"
              onClick={() => onDeleteRequest(item)}
            >
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <polyline points="3 6 5 6 21 6"/>
                <path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/>
                <path d="M10 11v6"/>
                <path d="M14 11v6"/>
                <path d="M9 6V4h6v2"/>
              </svg>
              Delete
            </button>
          )}
          {canEdit && (
            <button type="button" className="primary-action" onClick={() => onEdit(item)}>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/>
                <path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/>
              </svg>
              Edit Publication
            </button>
          )}
        </div>
      </div>
    </div>
  );
});

export default PublicationViewModal;
