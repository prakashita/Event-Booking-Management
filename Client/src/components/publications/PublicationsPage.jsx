/**
 * PublicationsPage — self-contained publications route component.
 *
 * All publication state lives here. Nothing bleeds into App.jsx.
 * Network requests: only loadPublications (on mount + sort change) and
 * submitPublication (on explicit submit). No request on date-picker open,
 * contributor add, or contributor type switch.
 *
 * Performance marks:
 *   pub-page-render-start / end
 *   pub-modal-open-start
 */
import { memo, useCallback, useEffect, useMemo, useState } from "react";
import {
  CITATION_FORMAT_OPTIONS,
  FEATURED_SOURCE_TYPE_KEYS,
  PUBLICATION_FIELD_DEFINITIONS,
  PUB_META,
  SOURCE_TYPE_OPTIONS
} from "../../constants";
import PublicationFormModal, { PublicationIcon } from "./PublicationFormModal";
import {
  FEATURED_PUBLICATION_EXTRA_FIELDS,
  PUBLICATION_DETAIL_FIELDS,
  formatPublicationContributors,
  getPublicationDisplayTitle,
  getPublicationFieldValue,
  getPublicationSortDate,
  getPublicationSourceConfig,
  getPublicationSourceKey,
  isPublicationFieldEmpty,
  normalizePublicationContributors
} from "./publicationUtils";

// ─── Citation helpers (no deps, pure render) ─────────────────────────────────

function getCitationPieces(item) {
  const author = getPublicationFieldValue(item, "contributors") || item.author || "";
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
  return { author, title, container, issued, url };
}

function formatPublicationCitation(item, format) {
  const { author, title, container, issued, url } = getCitationPieces(item);
  const italicContainer = container ? `*${container}*` : "";
  if (!format || format === "mla") {
    return [author, `"${title}"`, italicContainer, issued, url]
      .filter(Boolean)
      .join(", ");
  }
  if (format === "apa") {
    return [author, issued && `(${issued})`, title, italicContainer, url]
      .filter(Boolean)
      .join(". ")
      .replace(/\.\./g, ".");
  }
  if (format === "harvard")
    return [author, issued, title, italicContainer, url].filter(Boolean).join(", ");
  if (format === "chicago")
    return [author, `"${title}"`, italicContainer, issued, url]
      .filter(Boolean)
      .join(", ");
  if (format === "ieee")
    return [author, `"${title},"`, italicContainer, issued, url]
      .filter(Boolean)
      .join(", ");
  return [author, title, container, issued, url].filter(Boolean).join(", ");
}

function renderMlaCitation(citation) {
  if (!citation) return null;
  return citation.split(/(\*[^*]+\*)/g).map((seg, index) =>
    seg.startsWith("*") && seg.endsWith("*") ? (
      <em key={index} className="mla-italic">
        {seg.slice(1, -1)}
      </em>
    ) : (
      <span key={index}>{seg}</span>
    )
  );
}

// ─── Main page ────────────────────────────────────────────────────────────────

const PublicationsPage = memo(function PublicationsPage({
  user,
  apiFetch,
  apiBaseUrl,
  onSuccess
}) {
  // ── Publication modal state ────────────────────────────────────────────────
  const [publicationTypeModal, setPublicationTypeModal] = useState({ open: false });
  const [publicationModal, setPublicationModal] = useState({
    open: false,
    status: "idle",
    error: ""
  });
  const [selectedPublicationType, setSelectedPublicationType] = useState("webpage");

  // ── List state ─────────────────────────────────────────────────────────────
  const [publicationsState, setPublicationsState] = useState({
    status: "idle",
    items: [],
    error: ""
  });
  const [publicationSort, setPublicationSort] = useState("date_desc");
  const [publicationTypeFilter, setPublicationTypeFilter] = useState("");
  const [publicationCitationFormat, setPublicationCitationFormat] = useState("mla");
  const [publicationCitationFilter, setPublicationCitationFilter] = useState("");
  const [publicationSearch, setPublicationSearch] = useState("");
  const [publicationDateStart, setPublicationDateStart] = useState("");
  const [publicationDateEnd, setPublicationDateEnd] = useState("");

  // ── Load ──────────────────────────────────────────────────────────────────

  const loadPublications = useCallback(async () => {
    const token = localStorage.getItem("auth_token");
    if (!token) {
      setPublicationsState({ status: "error", items: [], error: "Missing auth token." });
      return;
    }
    setPublicationsState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const [sortBy, order] = publicationSort.split("_");
      const params = new URLSearchParams({ sort: sortBy, order: order || "desc" });
      const res = await apiFetch(`${apiBaseUrl}/publications?${params.toString()}`);
      if (!res.ok) throw new Error("Unable to load publications.");
      const data = await res.json();
      const items = Array.isArray(data) ? data : (data.items ?? []);
      setPublicationsState({ status: "ready", items, error: "" });
    } catch (err) {
      setPublicationsState({
        status: "error",
        items: [],
        error: err?.message || "Unable to load publications."
      });
    }
  }, [apiBaseUrl, apiFetch, publicationSort]);

  useEffect(() => {
    if (!user) return;
    loadPublications();
  }, [user, loadPublications]);

  // ── Modal open/close handlers ─────────────────────────────────────────────

  const handlePublicationTypeOpen = useCallback(() => {
    setPublicationTypeModal({ open: true });
  }, []);

  const handlePublicationTypeClose = useCallback(() => {
    setPublicationTypeModal({ open: false });
  }, []);

  const handlePublicationTypeSelect = useCallback((pubType) => {
    setPublicationTypeModal({ open: false });
    setSelectedPublicationType(pubType);
    setPublicationModal({ open: true, status: "idle", error: "" });
  }, []);

  const handlePublicationOpen = useCallback(() => {
    handlePublicationTypeOpen();
  }, [handlePublicationTypeOpen]);

  const handlePublicationClose = useCallback(() => {
    setPublicationModal({ open: false, status: "idle", error: "" });
  }, []);

  const handlePublicationBackToTypes = useCallback(() => {
    setPublicationTypeModal({ open: true });
  }, []);

  // Escape key for modals
  useEffect(() => {
    if (!publicationModal.open && !publicationTypeModal.open) return undefined;
    const handleEscape = (event) => {
      if (event.key !== "Escape") return;
      if (publicationModal.open) {
        handlePublicationClose();
        return;
      }
      if (publicationTypeModal.open) {
        handlePublicationTypeClose();
      }
    };
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [
    publicationModal.open,
    publicationTypeModal.open,
    handlePublicationClose,
    handlePublicationTypeClose
  ]);

  // ── Submit ────────────────────────────────────────────────────────────────

  const submitPublication = useCallback(
    async (submittedForm) => {
      const f = submittedForm;
      const pt = getPublicationSourceKey(f.pubType);
      const sourceConfig = getPublicationSourceConfig(pt);
      const generatedRecordName = (
        f.name ||
        f.title ||
        f.content ||
        f.container_title ||
        sourceConfig.label ||
        "Publication"
      ).trim();
      let validationError = null;
      if (!generatedRecordName) {
        validationError = "Please add a title or source name for this publication.";
      } else {
        const missingField = (sourceConfig.requiredFields || []).find((field) =>
          isPublicationFieldEmpty(f, field)
        );
        if (missingField) {
          validationError = `Please fill the required ${
            PUBLICATION_FIELD_DEFINITIONS[missingField]?.label || missingField
          } field.`;
        }
      }
      if (validationError) {
        setPublicationModal({ open: true, status: "error", error: validationError });
        return;
      }
      setPublicationModal({ open: true, status: "loading", error: "" });
      try {
        const formData = new FormData();
        const details = Object.fromEntries(
          [...new Set([...PUBLICATION_DETAIL_FIELDS, ...FEATURED_PUBLICATION_EXTRA_FIELDS])]
            .map((key) => [
              key,
              typeof f[key] === "string" ? f[key].trim() : f[key]
            ])
            .filter(([, value]) => {
              if (Array.isArray(value)) return value.length > 0;
              if (typeof value === "boolean") return value === true;
              return value !== "" && value != null;
            })
        );
        const contributors = normalizePublicationContributors(f.contributors);
        if (contributors.length) details.contributors = contributors;
        const contributorText =
          formatPublicationContributors(contributors) ||
          String(f.author || "").trim();
        const selectedTitle = (
          details.title ||
          details.content ||
          f.title ||
          f.name
        ).trim();
        const selectedContainer = (details.container_title || "").trim();
        const selectedIssuedDate = details.issued_date || "";
        formData.append("name", generatedRecordName);
        formData.append("title", selectedTitle);
        formData.append("pub_type", pt);
        formData.append("source_type", pt);
        formData.append(
          "citation_format",
          f.citation_format || publicationCitationFormat || "mla"
        );
        formData.append("details", JSON.stringify(details));
        if (f.others) formData.append("others", f.others);
        if (f.file) formData.append("file", f.file);
        const derivedAuthor =
          contributorText ||
          [f.author_first_name, f.author_last_name]
            .map((v) => (v || "").trim())
            .filter(Boolean)
            .join(" ");
        if (derivedAuthor) formData.append("author", derivedAuthor);
        if (contributors.length)
          formData.append("contributors", JSON.stringify(contributors));
        const legacyTitleKeyByType = {
          journal_article: "article_title",
          online_newspaper_article: "article_title",
          online_newspaper: "article_title",
          online_magazine_article: "article_title",
          print_magazine_article: "article_title",
          print_newspaper_article: "article_title",
          book: "book_title",
          report: "report_title",
          video: "video_title",
          webpage: "page_title"
        };
        const legacyContainerKeyByType = {
          journal_article: "journal_name",
          webpage: "website_name",
          online_newspaper_article: "newspaper_name",
          online_newspaper: "newspaper_name",
          online_magazine_article: "website_name",
          print_magazine_article: "website_name",
          print_newspaper_article: "newspaper_name",
          video: "platform"
        };
        const legacyTitleKey = legacyTitleKeyByType[pt];
        const legacyContainerKey = legacyContainerKeyByType[pt];
        if (legacyTitleKey && selectedTitle) formData.append(legacyTitleKey, selectedTitle);
        if (legacyContainerKey && selectedContainer)
          formData.append(legacyContainerKey, selectedContainer);
        if (selectedIssuedDate) {
          formData.append("publication_date", selectedIssuedDate);
          formData.append("year", selectedIssuedDate.slice(0, 4));
        }
        if (contributorText && !formData.has("author"))
          formData.append("author", contributorText);
        if (details.publisher) formData.append("publisher", details.publisher);
        if (details.doi) formData.append("doi", details.doi);
        if (details.url) formData.append("url", details.url);
        if (details.pages) formData.append("pages", details.pages);
        if (details.volume) formData.append("volume", details.volume);
        if (details.issue) formData.append("issue", details.issue);
        if (details.edition) formData.append("edition", details.edition);
        const optionals = [
          "author_first_name",
          "author_last_name",
          "publication_date",
          "url",
          "article_title",
          "journal_name",
          "volume",
          "issue",
          "pages",
          "doi",
          "year",
          "book_title",
          "publisher",
          "edition",
          "page_number",
          "organization",
          "report_title",
          "creator",
          "video_title",
          "platform",
          "newspaper_name",
          "website_name",
          "page_title"
        ];
        optionals.forEach((key) => {
          if (f[key] && !formData.has(key)) formData.append(key, f[key]);
        });
        const res = await apiFetch(`${apiBaseUrl}/publications`, {
          method: "POST",
          body: formData
        });
        if (!res.ok) {
          const data = await res.json().catch(() => null);
          const message = data?.detail || "Unable to submit publication.";
          throw new Error(message);
        }
        onSuccess("Publication submitted.");
        handlePublicationClose();
        loadPublications();
      } catch (err) {
        setPublicationModal({
          open: true,
          status: "error",
          error: err?.message || "Unable to submit publication."
        });
      }
    },
    [
      apiBaseUrl,
      apiFetch,
      handlePublicationClose,
      loadPublications,
      onSuccess,
      publicationCitationFormat
    ]
  );

  // ── Filtered / sorted list ─────────────────────────────────────────────────

  const allPubItems = useMemo(
    () => (Array.isArray(publicationsState.items) ? publicationsState.items : []),
    [publicationsState.items]
  );
  const searchNeedle = publicationSearch.trim().toLowerCase();

  const filteredPubItems = useMemo(() => {
    const sourceMatchesFilter = (item) => {
      if (!publicationTypeFilter) return true;
      return (
        getPublicationSourceKey(item.source_type || item.pub_type) === publicationTypeFilter
      );
    };
    const textMatchesSearch = (item) => {
      if (!searchNeedle) return true;
      const fields = [
        getPublicationDisplayTitle(item),
        getPublicationFieldValue(item, "contributors"),
        getPublicationFieldValue(item, "container_title"),
        getPublicationFieldValue(item, "doi"),
        getPublicationFieldValue(item, "url"),
        item.author,
        item.publisher,
        item.journal_name,
        item.website_name,
        item.newspaper_name
      ];
      return fields
        .filter(Boolean)
        .join(" ")
        .toLowerCase()
        .includes(searchNeedle);
    };
    const citationMatchesFilter = (item) => {
      if (!publicationCitationFilter) return true;
      return (
        String(item.citation_format || "").toLowerCase() === publicationCitationFilter
      );
    };
    const dateMatchesRange = (item) => {
      const dateValue = getPublicationSortDate(item);
      if (publicationDateStart && dateValue < publicationDateStart) return false;
      if (publicationDateEnd && dateValue > publicationDateEnd) return false;
      return true;
    };
    return allPubItems
      .filter(
        (item) =>
          sourceMatchesFilter(item) &&
          citationMatchesFilter(item) &&
          textMatchesSearch(item) &&
          dateMatchesRange(item)
      )
      .sort((a, b) => {
        if (publicationSort.startsWith("title")) {
          const direction = publicationSort.endsWith("desc") ? -1 : 1;
          return (
            getPublicationDisplayTitle(a).localeCompare(
              getPublicationDisplayTitle(b)
            ) * direction
          );
        }
        const direction = publicationSort.endsWith("asc") ? 1 : -1;
        return (
          getPublicationSortDate(a).localeCompare(getPublicationSortDate(b)) *
          direction
        );
      });
  }, [
    allPubItems,
    publicationTypeFilter,
    publicationCitationFilter,
    searchNeedle,
    publicationDateStart,
    publicationDateEnd,
    publicationSort
  ]);

  // ── Search / filter change handlers ───────────────────────────────────────

  const handleSearchChange = useCallback(
    (e) => setPublicationSearch(e.target.value),
    []
  );
  const handleTypeFilterChange = useCallback(
    (e) => setPublicationTypeFilter(e.target.value),
    []
  );
  const handleCitationFilterChange = useCallback(
    (e) => setPublicationCitationFilter(e.target.value),
    []
  );
  const handleSortChange = useCallback((e) => setPublicationSort(e.target.value), []);
  const handleCitationFormatChange = useCallback(
    (e) => setPublicationCitationFormat(e.target.value),
    []
  );
  const handleDateStartChange = useCallback(
    (e) => setPublicationDateStart(e.target.value),
    []
  );
  const handleDateEndChange = useCallback(
    (e) => setPublicationDateEnd(e.target.value),
    []
  );

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div className="primary-column">
      <div className="pub-page-header">
        <div className="pub-page-title-group">
          <h2 className="pub-page-title">Publications</h2>
          {publicationsState.status === "ready" && (
            <span className="pub-page-count">{filteredPubItems.length}</span>
          )}
        </div>
        <div className="pub-page-header-actions">
          <button
            type="button"
            className="primary-action pub-new-btn"
            onClick={handlePublicationOpen}
          >
            <svg
              width="15"
              height="15"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <line x1="12" y1="5" x2="12" y2="19" />
              <line x1="5" y1="12" x2="19" y2="12" />
            </svg>
            New Publication
          </button>
          <div className="pub-filter-group">
            <label className="pub-search-field" aria-label="Search publications">
              <svg
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <circle cx="11" cy="11" r="8" />
                <line x1="21" y1="21" x2="16.65" y2="16.65" />
              </svg>
              <input
                type="search"
                value={publicationSearch}
                onChange={handleSearchChange}
                placeholder="Search title, contributor, DOI, URL"
              />
            </label>

            <div className="pub-select-wrapper">
              <svg
                className="pub-select-icon"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <circle cx="12" cy="12" r="10" />
                <line x1="2" y1="12" x2="22" y2="12" />
                <path d="M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20" />
              </svg>
              <select
                value={publicationTypeFilter}
                onChange={handleTypeFilterChange}
                className="pub-styled-select"
                aria-label="Filter by publication type"
              >
                <option value="">All types</option>
                {SOURCE_TYPE_OPTIONS.map((type) => (
                  <option key={type.key} value={type.key}>
                    {type.label}
                  </option>
                ))}
              </select>
              <svg
                className="pub-select-caret"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <polyline points="6 9 12 15 18 9" />
              </svg>
            </div>

            <div className="pub-select-wrapper">
              <svg
                className="pub-select-icon"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M4 19.5A2.5 2.5 0 016.5 17H20" />
                <path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z" />
              </svg>
              <select
                value={publicationCitationFilter}
                onChange={handleCitationFilterChange}
                className="pub-styled-select"
                aria-label="Filter by saved citation format"
              >
                <option value="">All formats</option>
                {CITATION_FORMAT_OPTIONS.map((item) => (
                  <option key={item.value} value={item.value}>
                    {item.label}
                  </option>
                ))}
              </select>
              <svg
                className="pub-select-caret"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <polyline points="6 9 12 15 18 9" />
              </svg>
            </div>

            <div className="pub-select-wrapper">
              <svg
                className="pub-select-icon"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <line x1="8" y1="6" x2="21" y2="6" />
                <line x1="8" y1="12" x2="21" y2="12" />
                <line x1="8" y1="18" x2="21" y2="18" />
                <line x1="3" y1="6" x2="3.01" y2="6" />
                <line x1="3" y1="12" x2="3.01" y2="12" />
                <line x1="3" y1="18" x2="3.01" y2="18" />
              </svg>
              <select
                value={publicationSort}
                onChange={handleSortChange}
                className="pub-styled-select"
                aria-label="Sort publications"
              >
                <option value="date_desc">Newest first</option>
                <option value="date_asc">Oldest first</option>
                <option value="title_asc">Title (A–Z)</option>
                <option value="title_desc">Title (Z–A)</option>
              </select>
              <svg
                className="pub-select-caret"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <polyline points="6 9 12 15 18 9" />
              </svg>
            </div>

            <div className="pub-select-wrapper">
              <svg
                className="pub-select-icon"
                width="14"
                height="14"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M4 19.5A2.5 2.5 0 016.5 17H20" />
                <path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z" />
              </svg>
              <select
                value={publicationCitationFormat}
                onChange={handleCitationFormatChange}
                className="pub-styled-select"
                aria-label="Citation format"
              >
                {CITATION_FORMAT_OPTIONS.map((item) => (
                  <option key={item.value} value={item.value}>
                    {item.label}
                  </option>
                ))}
              </select>
              <svg
                className="pub-select-caret"
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <polyline points="6 9 12 15 18 9" />
              </svg>
            </div>

            {/* Native date range — zero JS overhead, no portal/rAF */}
            <div className="pub-date-filter">
              <label className="pub-date-range-label">
                <span>From</span>
                <input
                  type="date"
                  className="pub-date-native"
                  value={publicationDateStart}
                  onChange={handleDateStartChange}
                />
              </label>
              <label className="pub-date-range-label">
                <span>To</span>
                <input
                  type="date"
                  className="pub-date-native"
                  value={publicationDateEnd}
                  onChange={handleDateEndChange}
                />
              </label>
            </div>
          </div>
        </div>
      </div>

      {/* Publication list */}
      {publicationsState.status === "loading" ? (
        <ul className="pub-mla-list" aria-label="Loading publications">
          {Array.from({ length: 4 }).map((_, index) => (
            <li key={index} className="pub-mla-list-item pub-skeleton-item">
              <div
                className="skeleton-line"
                style={{ height: "14px", width: "85%", display: "block" }}
              />
              <div
                className="skeleton-line"
                style={{
                  height: "14px",
                  width: "60%",
                  display: "block",
                  marginTop: "6px"
                }}
              />
              <div style={{ display: "flex", gap: "8px", marginTop: "8px" }}>
                <div
                  className="skeleton-line"
                  style={{
                    height: "22px",
                    width: "80px",
                    borderRadius: "999px",
                    display: "block"
                  }}
                />
                <div
                  className="skeleton-line"
                  style={{
                    height: "22px",
                    width: "90px",
                    borderRadius: "8px",
                    display: "block"
                  }}
                />
              </div>
            </li>
          ))}
        </ul>
      ) : publicationsState.status === "error" ? (
        <div className="pub-list-empty">
          <p className="form-error">{publicationsState.error}</p>
        </div>
      ) : publicationsState.status === "ready" && allPubItems.length === 0 ? (
        <div className="pub-list-empty">
          <svg
            width="52"
            height="52"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#c4c9d4"
            strokeWidth="1.4"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M4 19.5A2.5 2.5 0 016.5 17H20" />
            <path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z" />
          </svg>
          <p className="pub-empty-title">No publications yet</p>
          <p className="pub-empty-sub">
            Click <strong>+ New Publication</strong> to add your first one.
          </p>
        </div>
      ) : filteredPubItems.length === 0 && allPubItems.length > 0 ? (
        <div className="pub-list-empty">
          <svg
            width="44"
            height="44"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#c4c9d4"
            strokeWidth="1.4"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <p className="pub-empty-title">No publications of this type</p>
          <p className="pub-empty-sub">
            Try selecting &quot;All types&quot; or another type.
          </p>
        </div>
      ) : (
        <ul className="pub-mla-list" aria-label="Publications">
          {filteredPubItems.map((item) => {
            const sourceKey = getPublicationSourceKey(
              item.source_type || item.pub_type
            );
            const meta =
              PUB_META[item.source_type || item.pub_type] ||
              PUB_META[sourceKey] || { label: item.pub_type || "Unknown", color: "#666" };
            const citation = formatPublicationCitation(
              item,
              publicationCitationFormat
            );
            const detailUrl = getPublicationFieldValue(item, "url");
            const linkUrl = item.web_view_link || detailUrl || item.url;
            const isFile = Boolean(item.web_view_link);
            const linkLabel = item.web_view_link
              ? "View file"
              : linkUrl
              ? "Visit URL"
              : null;
            return (
              <li key={item.id} className="pub-mla-list-item">
                <div className="pub-mla-citation">
                  {renderMlaCitation(citation)}
                </div>
                {item.others?.trim() && (
                  <p className="pub-mla-notes">{item.others}</p>
                )}
                <div className="pub-mla-meta">
                  <span
                    className={`pub-type-badge pub-type-${sourceKey || "unknown"}`}
                  >
                    <span className="pub-badge-icon">
                      <PublicationIcon sourceKey={sourceKey} />
                    </span>
                    {meta.label}
                  </span>
                  {linkLabel && (
                    <button
                      type="button"
                      className={`pub-action-btn ${
                        isFile ? "pub-action-file" : "pub-action-url"
                      }`}
                      onClick={() =>
                        window.open(linkUrl, "_blank", "noopener,noreferrer")
                      }
                    >
                      {isFile ? (
                        <svg
                          width="13"
                          height="13"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        >
                          <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
                          <polyline points="14 2 14 8 20 8" />
                        </svg>
                      ) : (
                        <svg
                          width="13"
                          height="13"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        >
                          <path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6" />
                          <polyline points="15 3 21 3 21 9" />
                          <line x1="10" y1="14" x2="21" y2="3" />
                        </svg>
                      )}
                      {linkLabel}
                    </button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      )}

      {/* Type-selection modal */}
      {publicationTypeModal.open ? (
        <div
          className="modal-overlay pub-type-overlay"
          role="dialog"
          aria-modal="true"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget)
              handlePublicationTypeClose();
          }}
        >
          <div className="modal-card pub-type-modal-card">
            <div className="modal-header">
              <div>
                <h3>Add New Publication</h3>
                <p className="pub-type-subtitle">
                  Select the type of publication you want to add
                </p>
              </div>
              <button
                type="button"
                className="modal-close"
                onClick={handlePublicationTypeClose}
              >
                &times;
              </button>
            </div>
            <div className="pub-type-grid pub-type-grid-featured">
              {FEATURED_SOURCE_TYPE_KEYS.map((key) =>
                SOURCE_TYPE_OPTIONS.find((type) => type.key === key)
              )
                .filter(Boolean)
                .map((type) => (
                  <button
                    key={type.key}
                    type="button"
                    className="pub-type-card pub-type-card-featured"
                    style={{ "--pub-card-color": type.color }}
                    onClick={() => handlePublicationTypeSelect(type.key)}
                  >
                    <span
                      className="pub-type-icon"
                      aria-hidden="true"
                      style={{ color: type.color }}
                    >
                      <PublicationIcon sourceKey={type.key} />
                    </span>
                    <span className="pub-type-card-label">{type.label}</span>
                    <span className="pub-type-card-desc">{type.desc}</span>
                  </button>
                ))}
            </div>
            <div className="pub-type-section-heading">
              <span>More Scribbr source types</span>
              <span>
                {SOURCE_TYPE_OPTIONS.length - FEATURED_SOURCE_TYPE_KEYS.length} more
              </span>
            </div>
            <div className="pub-type-grid pub-type-grid-compact">
              {SOURCE_TYPE_OPTIONS.filter(
                (type) => !FEATURED_SOURCE_TYPE_KEYS.includes(type.key)
              ).map((type) => (
                <button
                  key={type.key}
                  type="button"
                  className="pub-type-card pub-type-card-compact"
                  style={{ "--pub-card-color": type.color }}
                  onClick={() => handlePublicationTypeSelect(type.key)}
                >
                  <span
                    className="pub-type-icon"
                    aria-hidden="true"
                    style={{ color: type.color }}
                  >
                    <PublicationIcon sourceKey={type.key} />
                  </span>
                  <span className="pub-type-card-label">{type.label}</span>
                  <span className="pub-type-card-desc">{type.desc}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      ) : null}

      {/* Form modal */}
      <PublicationFormModal
        modal={publicationModal}
        initialPubType={selectedPublicationType}
        publicationCitationFormat={publicationCitationFormat}
        onClose={handlePublicationClose}
        onBackToTypes={handlePublicationBackToTypes}
        onSubmit={submitPublication}
      />
    </div>
  );
});

export default PublicationsPage;
