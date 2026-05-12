/**
 * PublicationsPage — self-contained publications route component.
 *
 * All publication state lives here. Nothing bleeds into App.jsx.
 * Network requests: only loadPublications (on mount + sort change) and
 * submitPublication (on explicit submit). No request on date-picker open.
 *
 * Performance marks:
 *   pub-page-render-start / end
 *   pub-modal-open-start
 */
import { memo, useCallback, useEffect, useMemo, useTransition, useState } from "react";
import {
  CITATION_FORMAT_OPTIONS,
  FEATURED_SOURCE_TYPE_KEYS,
  PUBLICATION_FIELD_DEFINITIONS,
  PUB_META,
  SOURCE_TYPE_OPTIONS
} from "../../constants";
import PublicationFormModal, { PublicationIcon } from "./PublicationFormModal";
import PublicationViewModal from "./PublicationViewModal";
import {
  FEATURED_PUBLICATION_EXTRA_FIELDS,
  PUBLICATION_DETAIL_FIELDS,
  getPublicationDisplayTitle,
  getPublicationFieldValue,
  getPublicationSortDate,
  getPublicationSourceConfig,
  getPublicationSourceKey,
  isPublicationFieldEmpty,
  publicationItemToForm
} from "./publicationUtils";

// ─── Citation helpers (no deps, pure render) ─────────────────────────────────

function getCitationPieces(item) {
  const author = item.author || "";
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
  // ── Role helpers ───────────────────────────────────────────────────────────
  const role = String(user?.role || "").toLowerCase();
  const isAdmin = role === "admin";
  const userId = String(user?.id || user?._id || "");

  // ── Create publication modal state ─────────────────────────────────────────
  const [publicationTypeModal, setPublicationTypeModal] = useState({ open: false });
  const [publicationModal, setPublicationModal] = useState({
    open: false,
    status: "idle",
    error: ""
  });
  const [selectedPublicationType, setSelectedPublicationType] = useState("webpage");
  // startTransition marks modal-mount work as a non-urgent transition.
  const [, startTransition] = useTransition();

  // ── View / Edit / Delete state ─────────────────────────────────────────────
  const [viewModal, setViewModal] = useState({ open: false, item: null });
  const [editModal, setEditModal] = useState({ open: false, item: null, status: "idle", error: "" });
  const [deleteConfirm, setDeleteConfirm] = useState({ open: false, item: null, status: "idle", error: "", confirmText: "" });

  // ── List state ─────────────────────────────────────────────────────────────
  const [publicationsState, setPublicationsState] = useState({
    status: "idle",
    items: [],
    error: ""
  });
  const [publicationSort, setPublicationSort] = useState("date_desc");
  const [publicationTypeFilter, setPublicationTypeFilter] = useState("");
  const [publicationCitationFormat, setPublicationCitationFormat] = useState("mla");
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
    // The type-selector grid (~36 SVG cards) is non-urgent; defer so the button
    // click responds instantly and React won't freeze the main thread mounting it.
    startTransition(() => setPublicationTypeModal({ open: true }));
  }, [startTransition]);

  const handlePublicationTypeClose = useCallback(() => {
    setPublicationTypeModal({ open: false });
  }, []);

  const handlePublicationTypeSelect = useCallback((pubType) => {
    // Close the type selector immediately (urgent — user needs visual feedback).
    // Mount the form modal as a non-blocking transition so the heavy form tree
    // (field rows, useCallbacks, useMemos) does not freeze the main thread.
    setPublicationTypeModal({ open: false });
    startTransition(() => {
      setSelectedPublicationType(pubType);
      setPublicationModal({ open: true, status: "idle", error: "" });
    });
  }, [startTransition]);

  const handlePublicationOpen = useCallback(() => {
    handlePublicationTypeOpen();
  }, [handlePublicationTypeOpen]);

  const handlePublicationClose = useCallback(() => {
    setPublicationModal({ open: false, status: "idle", error: "" });
  }, []);

  const handlePublicationBackToTypes = useCallback(() => {
    setPublicationTypeModal({ open: true });
  }, []);

  // ── View / Edit / Delete handlers ──────────────────────────────────────────

  const handleViewOpen = useCallback((item) => {
    startTransition(() => setViewModal({ open: true, item }));
  }, [startTransition]);

  const handleViewClose = useCallback(() => {
    setViewModal({ open: false, item: null });
  }, []);

  const handleEditFromView = useCallback((item) => {
    setViewModal({ open: false, item: null });
    startTransition(() =>
      setEditModal({ open: true, item, status: "idle", error: "" })
    );
  }, [startTransition]);

  const handleEditClose = useCallback(() => {
    setEditModal({ open: false, item: null, status: "idle", error: "" });
  }, []);

  const handleDeleteRequestFromView = useCallback((item) => {
    setViewModal({ open: false, item: null });
    setDeleteConfirm({ open: true, item, status: "idle", error: "", confirmText: "" });
  }, []);

  const handleDeleteRequestFromCard = useCallback((item) => {
    setDeleteConfirm({ open: true, item, status: "idle", error: "", confirmText: "" });
  }, []);

  const handleDeleteConfirmClose = useCallback(() => {
    setDeleteConfirm({ open: false, item: null, status: "idle", error: "", confirmText: "" });
  }, []);

  const handleDeleteConfirm = useCallback(async () => {
    const item = deleteConfirm.item;
    if (!item) return;
    setDeleteConfirm((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await apiFetch(`${apiBaseUrl}/publications/${item.id}`, { method: "DELETE" });
      if (res.status === 204 || res.ok) {
        // Optimistic update — remove from list immediately.
        setPublicationsState((prev) => ({
          ...prev,
          items: prev.items.filter((p) => p.id !== item.id)
        }));
        setDeleteConfirm({ open: false, item: null, status: "idle", error: "", confirmText: "" });
        onSuccess("Publication deleted.");
      } else {
        const data = await res.json().catch(() => null);
        throw new Error(data?.detail || "Unable to delete publication.");
      }
    } catch (err) {
      setDeleteConfirm((prev) => ({
        ...prev,
        status: "error",
        error: err?.message || "Unable to delete publication."
      }));
    }
  }, [deleteConfirm.item, apiBaseUrl, apiFetch, onSuccess]);

  // Escape key for all modals
  useEffect(() => {
    const anyOpen =
      publicationModal.open || publicationTypeModal.open ||
      viewModal.open || editModal.open || deleteConfirm.open;
    if (!anyOpen) return undefined;
    const handleEscape = (event) => {
      if (event.key !== "Escape") return;
      if (deleteConfirm.open) { handleDeleteConfirmClose(); return; }
      if (editModal.open) { handleEditClose(); return; }
      if (viewModal.open) { handleViewClose(); return; }
      if (publicationModal.open) { handlePublicationClose(); return; }
      if (publicationTypeModal.open) { handlePublicationTypeClose(); }
    };
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [
    publicationModal.open, publicationTypeModal.open,
    viewModal.open, editModal.open, deleteConfirm.open,
    handlePublicationClose, handlePublicationTypeClose,
    handleViewClose, handleEditClose, handleDeleteConfirmClose
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
        const authorText = String(f.author || "").trim();
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
          authorText ||
          [f.author_first_name, f.author_last_name]
            .map((v) => (v || "").trim())
            .filter(Boolean)
            .join(" ");
        if (derivedAuthor) formData.append("author", derivedAuthor);
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

  // ── Edit (PATCH) submit ───────────────────────────────────────────────────

  const submitEditPublication = useCallback(
    async (submittedForm) => {
      const f = submittedForm;
      const item = editModal.item;
      if (!item?.id) return;
      setEditModal((prev) => ({ ...prev, status: "loading", error: "" }));
      try {
        const formData = new FormData();
        const details = Object.fromEntries(
          [...new Set([...PUBLICATION_DETAIL_FIELDS, ...FEATURED_PUBLICATION_EXTRA_FIELDS])]
            .map((key) => [key, typeof f[key] === "string" ? f[key].trim() : f[key]])
            .filter(([, value]) => {
              if (Array.isArray(value)) return value.length > 0;
              if (typeof value === "boolean") return value === true;
              return value !== "" && value != null;
            })
        );
        const authorText = String(f.author || "").trim();
        const selectedTitle = (details.title || details.content || f.title || f.name || "").trim();
        const selectedIssuedDate = details.issued_date || "";
        formData.append("name", f.name?.trim() || selectedTitle || item.name);
        formData.append("title", selectedTitle || item.title);
        formData.append("pub_type", getPublicationSourceKey(f.pubType));
        formData.append("source_type", getPublicationSourceKey(f.pubType));
        formData.append("citation_format", f.citation_format || publicationCitationFormat || "mla");
        formData.append("details", JSON.stringify(details));
        if (f.others !== undefined) formData.append("others", f.others || "");
        const derivedAuthor =
          authorText ||
          [f.author_first_name, f.author_last_name]
            .map((v) => (v || "").trim())
            .filter(Boolean)
            .join(" ");
        if (derivedAuthor) formData.append("author", derivedAuthor);
        if (f.author_first_name) formData.append("author_first_name", f.author_first_name);
        if (f.author_last_name) formData.append("author_last_name", f.author_last_name);
        if (selectedIssuedDate) {
          formData.append("publication_date", selectedIssuedDate);
          formData.append("year", selectedIssuedDate.slice(0, 4));
        }
        if (details.container_title) formData.append("container_title", details.container_title);
        if (details.publisher) formData.append("publisher", details.publisher);
        if (details.doi) formData.append("doi", details.doi);
        if (details.url) formData.append("url", details.url);
        if (details.pages) formData.append("pages", details.pages);
        if (details.volume) formData.append("volume", details.volume);
        if (details.issue) formData.append("issue", details.issue);
        if (details.edition) formData.append("edition", details.edition);

        const res = await apiFetch(`${apiBaseUrl}/publications/${item.id}`, {
          method: "PATCH",
          body: formData
        });
        if (!res.ok) {
          const data = await res.json().catch(() => null);
          throw new Error(data?.detail || "Unable to update publication.");
        }
        const updated = await res.json();
        setPublicationsState((prev) => ({
          ...prev,
          items: prev.items.map((p) => (p.id === item.id ? updated : p))
        }));
        onSuccess("Publication updated.");
        handleEditClose();
      } catch (err) {
        setEditModal((prev) => ({
          ...prev,
          status: "error",
          error: err?.message || "Unable to update publication."
        }));
      }
    },
    [
      editModal.item,
      apiBaseUrl,
      apiFetch,
      handleEditClose,
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
        item.author,
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
    const citationMatchesFilter = () => true; // citation format is display-only now
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

  // Date range preset handler
  const handleDatePreset = useCallback((preset) => {
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    if (preset === "today") {
      setPublicationDateStart(today);
      setPublicationDateEnd(today);
    } else if (preset === "7days") {
      const d = new Date(now);
      d.setDate(d.getDate() - 7);
      setPublicationDateStart(d.toISOString().slice(0, 10));
      setPublicationDateEnd(today);
    } else if (preset === "30days") {
      const d = new Date(now);
      d.setDate(d.getDate() - 30);
      setPublicationDateStart(d.toISOString().slice(0, 10));
      setPublicationDateEnd(today);
    } else if (preset === "year") {
      setPublicationDateStart(`${now.getFullYear()}-01-01`);
      setPublicationDateEnd(today);
    } else {
      setPublicationDateStart("");
      setPublicationDateEnd("");
    }
  }, []);

  // ── Render ────────────────────────────────────────────────────────────────

  const hasActiveDateFilter = publicationDateStart || publicationDateEnd;

  return (
    <div className="primary-column">
      {/* ── Page header ── */}
      <div className="pub-page-header">
        <div className="pub-page-title-group">
          <h2 className="pub-page-title">Publications</h2>
          {publicationsState.status === "ready" && (
            <span className="pub-page-count">{filteredPubItems.length}</span>
          )}
        </div>
        <button
          type="button"
          className="primary-action pub-new-btn"
          onClick={handlePublicationOpen}
        >
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <line x1="12" y1="5" x2="12" y2="19" />
            <line x1="5" y1="12" x2="19" y2="12" />
          </svg>
          New Publication
        </button>
      </div>

      {/* ── Filter toolbar ── */}
      <div className="pub-toolbar">
        {/* Row 1: Search + selects in one line */}
        <div className="pub-toolbar-row">
        <label className="pub-search-field" aria-label="Search publications">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <input
            type="search"
            value={publicationSearch}
            onChange={handleSearchChange}
            placeholder="Search title, author, DOI, URL…"
          />
        </label>

        <div className="pub-toolbar-selects">
          {/* Publication type */}
          <div className="pub-select-wrapper">
            <svg className="pub-select-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <circle cx="12" cy="12" r="10" />
              <line x1="2" y1="12" x2="22" y2="12" />
              <path d="M12 2a15.3 15.3 0 010 20M12 2a15.3 15.3 0 000 20" />
            </svg>
            <select value={publicationTypeFilter} onChange={handleTypeFilterChange} className="pub-styled-select" aria-label="Filter by type">
              <option value="">All types</option>
              {SOURCE_TYPE_OPTIONS.map((type) => (
                <option key={type.key} value={type.key}>{type.label}</option>
              ))}
            </select>
            <svg className="pub-select-caret" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9" /></svg>
          </div>

          {/* Citation style — merged display + single format selector */}
          <div className="pub-select-wrapper">
            <svg className="pub-select-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M4 19.5A2.5 2.5 0 016.5 17H20" />
              <path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z" />
            </svg>
            <select value={publicationCitationFormat} onChange={handleCitationFormatChange} className="pub-styled-select" aria-label="Citation style">
              {CITATION_FORMAT_OPTIONS.map((item) => (
                <option key={item.value} value={item.value}>{item.label}</option>
              ))}
            </select>
            <svg className="pub-select-caret" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9" /></svg>
          </div>

          {/* Sort */}
          <div className="pub-select-wrapper">
            <svg className="pub-select-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <line x1="8" y1="6" x2="21" y2="6" /><line x1="8" y1="12" x2="21" y2="12" /><line x1="8" y1="18" x2="21" y2="18" />
              <line x1="3" y1="6" x2="3.01" y2="6" /><line x1="3" y1="12" x2="3.01" y2="12" /><line x1="3" y1="18" x2="3.01" y2="18" />
            </svg>
            <select value={publicationSort} onChange={handleSortChange} className="pub-styled-select" aria-label="Sort publications">
              <option value="date_desc">Newest first</option>
              <option value="date_asc">Oldest first</option>
              <option value="title_asc">Title A–Z</option>
              <option value="title_desc">Title Z–A</option>
            </select>
            <svg className="pub-select-caret" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="6 9 12 15 18 9" /></svg>
          </div>
        </div>
        </div>{/* end pub-toolbar-row */}

        {/* Row 2: Date range */}
        <div className="pub-date-range-group">
          <div className="pub-date-range-inputs">
            <div className="pub-date-range-field">
              <span className="pub-date-range-caption">From</span>
              <input type="date" className="pub-date-native" value={publicationDateStart} onChange={handleDateStartChange} aria-label="Date from" />
            </div>
            <span className="pub-date-range-sep" aria-hidden="true">—</span>
            <div className="pub-date-range-field">
              <span className="pub-date-range-caption">To</span>
              <input type="date" className="pub-date-native" value={publicationDateEnd} onChange={handleDateEndChange} aria-label="Date to" />
            </div>
          </div>
          <div className="pub-date-presets">
            <button type="button" className="pub-date-preset-btn" onClick={() => handleDatePreset("today")}>Today</button>
            <button type="button" className="pub-date-preset-btn" onClick={() => handleDatePreset("7days")}>7d</button>
            <button type="button" className="pub-date-preset-btn" onClick={() => handleDatePreset("30days")}>30d</button>
            <button type="button" className="pub-date-preset-btn" onClick={() => handleDatePreset("year")}>This year</button>
            {hasActiveDateFilter && (
              <button type="button" className="pub-date-preset-btn pub-date-preset-clear" onClick={() => handleDatePreset("")} aria-label="Clear date filter">✕</button>
            )}
          </div>
        </div>
      </div>

      {/* ── Publication list ── */}
      {publicationsState.status === "loading" ? (
        <ul className="pub-mla-list" aria-label="Loading publications">
          {Array.from({ length: 4 }).map((_, index) => (
            <li key={index} className="pub-mla-list-item pub-skeleton-item">
              <div className="skeleton-line" style={{ height: "14px", width: "85%", display: "block" }} />
              <div className="skeleton-line" style={{ height: "14px", width: "60%", display: "block", marginTop: "6px" }} />
              <div style={{ display: "flex", gap: "8px", marginTop: "8px" }}>
                <div className="skeleton-line" style={{ height: "22px", width: "80px", borderRadius: "999px", display: "block" }} />
                <div className="skeleton-line" style={{ height: "22px", width: "90px", borderRadius: "8px", display: "block" }} />
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
          <svg width="52" height="52" viewBox="0 0 24 24" fill="none" stroke="#c4c9d4" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M4 19.5A2.5 2.5 0 016.5 17H20" /><path d="M6.5 2H20v20H6.5A2.5 2.5 0 014 19.5v-15A2.5 2.5 0 016.5 2z" />
          </svg>
          <p className="pub-empty-title">No publications yet</p>
          <p className="pub-empty-sub">Click <strong>+ New Publication</strong> to add your first one.</p>
        </div>
      ) : filteredPubItems.length === 0 && allPubItems.length > 0 ? (
        <div className="pub-list-empty">
          <svg width="44" height="44" viewBox="0 0 24 24" fill="none" stroke="#c4c9d4" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <p className="pub-empty-title">No matching publications</p>
          <p className="pub-empty-sub">Try adjusting your search or filters.</p>
        </div>
      ) : (
        <ul className="pub-mla-list" aria-label="Publications">
          {filteredPubItems.map((item) => {
            const sourceKey = getPublicationSourceKey(item.source_type || item.pub_type);
            const meta = PUB_META[item.source_type || item.pub_type] || PUB_META[sourceKey] || { label: item.pub_type || "Unknown", color: "#666" };
            const citation = formatPublicationCitation(item, publicationCitationFormat);
            const detailUrl = getPublicationFieldValue(item, "url");
            const linkUrl = item.web_view_link || detailUrl || item.url;
            const isFile = Boolean(item.web_view_link);
            const title = getPublicationDisplayTitle(item);
            const submitter = item.created_by_name || item.submitted_by_name || item.user_name
              || item.owner_name || item.creator_name
              || item.created_by_email || item.submitted_by_email || item.user_email
              || "Unknown user";
            const pubDate = getPublicationFieldValue(item, "issued_date") || item.publication_date || item.year || null;
            const createdDate = item.created_at
              ? new Date(item.created_at).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })
              : null;
            const isOwner = item.created_by && item.created_by === userId;
            const canEdit = isOwner && !isAdmin; // creator only; admin cannot edit
            const canDelete = isAdmin || isOwner;
            return (
              <li key={item.id} className="pub-mla-list-item">
                {/* Card top: type badge + title */}
                <div className="pub-card-header">
                  <span className={`pub-type-badge pub-type-${sourceKey || "unknown"}`}>
                    <span className="pub-badge-icon"><PublicationIcon sourceKey={sourceKey} /></span>
                    {meta.label}
                  </span>
                  {title && <h4 className="pub-card-title">{title}</h4>}
                </div>

                {/* Citation preview */}
                <div className="pub-mla-citation">{renderMlaCitation(citation)}</div>

                {/* Submitter + date metadata row — always shown */}
                <div className="pub-card-meta-row">
                    <span className="pub-card-meta-item pub-card-submitter-item">
                      <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                      <span className="pub-card-submitter-label">Submitted by</span>
                      {submitter}
                    </span>
                    {pubDate && (
                      <span className="pub-card-meta-item">
                        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                        {pubDate}
                      </span>
                    )}
                    {!pubDate && createdDate && (
                      <span className="pub-card-meta-item">
                        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
                        Added {createdDate}
                      </span>
                    )}
                </div>

                {/* Annotation */}
                {item.others?.trim() && (
                  <p className="pub-mla-notes">{item.others}</p>
                )}

                {/* Action row */}
                <div className="pub-card-actions">
                  <div className="pub-card-actions-left">
                    {/* View */}
                    <button type="button" className="pub-card-action-btn pub-card-action-view" onClick={() => handleViewOpen(item)} aria-label="View publication details">
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                      View
                    </button>
                    {/* Edit */}
                    {canEdit && (
                      <button type="button" className="pub-card-action-btn pub-card-action-edit" onClick={() => handleEditFromView(item)} aria-label="Edit publication">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                        Edit
                      </button>
                    )}
                    {/* External link */}
                    {linkUrl && (
                      <button
                        type="button"
                        className={`pub-card-action-btn ${isFile ? "pub-card-action-file" : "pub-card-action-url"}`}
                        onClick={() => window.open(linkUrl, "_blank", "noopener,noreferrer")}
                        aria-label={isFile ? "View file" : "Visit URL"}
                      >
                        {isFile ? (
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
                        ) : (
                          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M18 13v6a2 2 0 01-2 2H5a2 2 0 01-2-2V8a2 2 0 012-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>
                        )}
                        {isFile ? "File" : "URL"}
                      </button>
                    )}
                  </div>
                  {/* Delete — subtle, right-aligned */}
                  {canDelete && (
                    <button type="button" className="pub-card-delete-btn" onClick={() => handleDeleteRequestFromCard(item)} aria-label="Delete publication">
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/></svg>
                    </button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      )}

      {/* ── Type-selection modal ── */}
      {publicationTypeModal.open ? (
        <div
          className="modal-overlay pub-type-overlay"
          role="dialog"
          aria-modal="true"
          onMouseDown={(event) => { if (event.target === event.currentTarget) handlePublicationTypeClose(); }}
        >
          <div className="modal-card pub-type-modal-card">
            <div className="modal-header">
              <div>
                <h3>Add New Publication</h3>
                <p className="pub-type-subtitle">Select the type of publication you want to add</p>
              </div>
              <button type="button" className="modal-close" onClick={handlePublicationTypeClose}>&times;</button>
            </div>
            <div className="pub-type-grid pub-type-grid-featured">
              {FEATURED_SOURCE_TYPE_KEYS.map((key) => SOURCE_TYPE_OPTIONS.find((type) => type.key === key))
                .filter(Boolean)
                .map((type) => (
                  <button key={type.key} type="button" className="pub-type-card pub-type-card-featured" style={{ "--pub-card-color": type.color }} onClick={() => handlePublicationTypeSelect(type.key)}>
                    <span className="pub-type-icon" aria-hidden="true" style={{ color: type.color }}><PublicationIcon sourceKey={type.key} /></span>
                    <span className="pub-type-card-label">{type.label}</span>
                    <span className="pub-type-card-desc">{type.desc}</span>
                  </button>
                ))}
            </div>
            <div className="pub-type-section-heading">
              <span>More Scribbr source types</span>
              <span>{SOURCE_TYPE_OPTIONS.length - FEATURED_SOURCE_TYPE_KEYS.length} more</span>
            </div>
            <div className="pub-type-grid pub-type-grid-compact">
              {SOURCE_TYPE_OPTIONS.filter((type) => !FEATURED_SOURCE_TYPE_KEYS.includes(type.key)).map((type) => (
                <button key={type.key} type="button" className="pub-type-card pub-type-card-compact" style={{ "--pub-card-color": type.color }} onClick={() => handlePublicationTypeSelect(type.key)}>
                  <span className="pub-type-icon" aria-hidden="true" style={{ color: type.color }}><PublicationIcon sourceKey={type.key} /></span>
                  <span className="pub-type-card-label">{type.label}</span>
                  <span className="pub-type-card-desc">{type.desc}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      ) : null}

      {/* ── Create form modal ── */}
      {publicationModal.open && (
        <PublicationFormModal
          modal={publicationModal}
          initialPubType={selectedPublicationType}
          publicationCitationFormat={publicationCitationFormat}
          onClose={handlePublicationClose}
          onBackToTypes={handlePublicationBackToTypes}
          onSubmit={submitPublication}
        />
      )}

      {/* ── View modal ── */}
      {viewModal.open && viewModal.item && (
        <PublicationViewModal
          item={viewModal.item}
          citationFormat={publicationCitationFormat}
          onClose={handleViewClose}
          onEdit={handleEditFromView}
          onDeleteRequest={handleDeleteRequestFromView}
          canEdit={!isAdmin && viewModal.item.created_by === userId}
          canDelete={isAdmin || viewModal.item.created_by === userId}
        />
      )}

      {/* ── Edit modal ── */}
      {editModal.open && editModal.item && (
        <PublicationFormModal
          modal={editModal}
          mode="edit"
          initialPubType={getPublicationSourceKey(editModal.item.source_type || editModal.item.pub_type) || "webpage"}
          initialForm={publicationItemToForm(editModal.item)}
          publicationCitationFormat={publicationCitationFormat}
          onClose={handleEditClose}
          onBackToTypes={() => {}}
          onSubmit={submitEditPublication}
        />
      )}

      {/* ── Delete confirmation modal ── */}
      {deleteConfirm.open && deleteConfirm.item && (
        <div className="modal-overlay" role="dialog" aria-modal="true" onMouseDown={(e) => { if (e.target === e.currentTarget) handleDeleteConfirmClose(); }}>
          <div className="modal-card pub-delete-confirm-card">
            <div className="modal-header">
              <div>
                <h3>Delete Publication</h3>
                <p className="form-hint">This action cannot be undone.</p>
              </div>
              <button type="button" className="modal-close" onClick={handleDeleteConfirmClose}>&times;</button>
            </div>
            <div className="pub-delete-confirm-body">
              <div className="pub-delete-confirm-icon" aria-hidden="true">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/><path d="M9 6V4h6v2"/>
                </svg>
              </div>
              <p className="pub-delete-confirm-message">
                Are you sure you want to delete this publication?
              </p>
              <p className="pub-delete-confirm-sub">{getPublicationDisplayTitle(deleteConfirm.item)}</p>
              <label className="pub-delete-confirm-field">
                <span>Type <strong>DELETE</strong> to confirm</span>
                <input
                  type="text"
                  className="pub-delete-confirm-input"
                  value={deleteConfirm.confirmText}
                  onChange={(e) => setDeleteConfirm((prev) => ({ ...prev, confirmText: e.target.value }))}
                  placeholder="DELETE"
                  autoComplete="off"
                  spellCheck={false}
                  autoFocus
                />
              </label>
              {deleteConfirm.status === "error" && (
                <p className="form-error">{deleteConfirm.error}</p>
              )}
            </div>
            <div className="modal-actions">
              <button type="button" className="secondary-action" onClick={handleDeleteConfirmClose} disabled={deleteConfirm.status === "loading"}>
                Cancel
              </button>
              <button
                type="button"
                className="pub-delete-confirm-btn"
                onClick={handleDeleteConfirm}
                disabled={deleteConfirm.status === "loading" || deleteConfirm.confirmText !== "DELETE"}
              >
                {deleteConfirm.status === "loading" ? "Deleting…" : "Delete Publication"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
});

export default PublicationsPage;
