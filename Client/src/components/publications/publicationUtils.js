/**
 * Publication utility functions and constants.
 * Extracted from App.jsx for isolation and performance.
 * No React imports — pure JS only.
 */
import {
  PUBLICATION_FIELD_DEFINITIONS,
  SOURCE_TYPE_CONFIG,
  SOURCE_TYPE_OPTIONS
} from "../../constants";

// ─── Field sets ─────────────────────────────────────────────────────────────
export const PUBLICATION_DETAIL_FIELDS = Object.keys(PUBLICATION_FIELD_DEFINITIONS);

export const PUBLICATION_DATE_FIELDS = new Set([
  "issued_date",
  "accessed_date",
  "composed_date",
  "submitted_date",
  "original_publication_date"
]);
export const PUBLICATION_CONTAINER_FIELDS = new Set(["container_title", "collection_title"]);
export const PUBLICATION_TITLE_FIELDS = new Set(["title", "content"]);
export const PUBLICATION_NOTE_FIELDS = new Set(["note"]);

export const FEATURED_PUBLICATION_EXTRA_FIELDS = [
  "subtitle",
  "description",
  "volume_is_range",
  "pages_is_range",
  "show_description",
  "show_subtitle",
  "show_original_publication_date",
  "show_publisher_place"
];

const PUBLICATION_FIELD_GROUP_CACHE = new Map();

export const LEGACY_PUBLICATION_FIELD_MAP = {
  article_title: "title",
  book_title: "title",
  report_title: "title",
  video_title: "title",
  page_title: "title",
  journal_name: "container_title",
  website_name: "container_title",
  newspaper_name: "container_title",
  platform: "container_title",
  publication_date: "issued_date",
  year: "issued_date",
  pages: "pages",
  doi: "doi",
  url: "url",
  publisher: "publisher",
  edition: "edition",
  volume: "volume",
  issue: "issue"
};

export const PUBLICATION_SOURCE_ICON_PATHS = {
  webpage:
    "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 0c2.1 2.15 3.1 5.03 3.1 9s-1 6.85-3.1 9M12 3C9.9 5.15 8.9 8.03 8.9 12s1 6.85 3.1 9M4.2 9h15.6M4.2 15h15.6",
  journal_article:
    "M7 3h7.5L19 7.5V21H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm7 0v5h5M8.5 12h7M8.5 15.5h7M8.5 19h4.5",
  book: "M6 4.5A2.5 2.5 0 0 1 8.5 2H19v17H8.5A2.5 2.5 0 0 0 6 21.5v-17Zm0 0v17M9.5 6.5h6M9.5 10h6M9.5 13.5H14",
  report:
    "M5 3h14v18H5V3Zm3 4h8M8 10.5h8M8 14h4M14.5 14H16M14.5 17.5H16M8 17.5h4",
  video:
    "M5.5 5h13A2.5 2.5 0 0 1 21 7.5v9a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 3 16.5v-9A2.5 2.5 0 0 1 5.5 5Zm5 4v6l5-3-5-3Z",
  online_newspaper_article:
    "M4 5h12.5A3.5 3.5 0 0 1 20 8.5V19H6a2 2 0 0 1-2-2V5Zm12 3h4M7 8.5h6M7 12h5M14.5 12H17M7 15.5h5M14.5 15.5H17",
  default:
    "M7 3h7.5L19 7.5V21H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm7 0v5h5M8.5 13h7M8.5 17h5"
};

export const FEATURED_PUBLICATION_FORM_FIELDS = {
  artwork: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_description",
      field: "description",
      toggleLabel: "Show description",
      fieldLabel: "Description"
    },
    { type: "date", field: "composed_date", label: "Composed date" },
    { type: "field", field: "medium", label: "Medium" },
    {
      type: "archiveGroup",
      label: "Archive / Library / Museum",
      subFields: [
        { field: "archive_collection", label: "Name" },
        { field: "place_country", label: "Country" },
        { field: "place_region", label: "Region" },
        { field: "place_locality", label: "City" }
      ]
    },
    { type: "annotation" }
  ],
  blog_post: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_description",
      field: "description",
      toggleLabel: "Show description",
      fieldLabel: "Description"
    },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Blog name", required: true },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  book_chapter: [
    { type: "field", field: "title", label: "Chapter title", required: true },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Book title", required: true },
    { type: "field", field: "edition", label: "Edition", placeholder: "e.g. 2" },
    { type: "range", field: "volume", flag: "volume_is_range", label: "Volume number" },
    { type: "field", field: "medium", label: "Medium" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    { type: "field", field: "publisher", label: "Publisher", placeholder: "e.g. Grove Press" },
    {
      type: "toggleField",
      flag: "show_publisher_place",
      field: "publisher_place",
      toggleLabel: "Show place of publication",
      fieldLabel: "Place of publication"
    },
    { type: "range", field: "pages", flag: "pages_is_range", label: "Page" },
    { type: "field", field: "doi", label: "DOI", placeholder: "e.g. 10.1037/a0040251" },
    { type: "field", field: "pdf_url", label: "PDF", inputType: "url", placeholder: "Link to PDF" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  comment: [
    { type: "field", field: "content", label: "Content", required: true },
    { type: "field", field: "container_title", label: "Comment on" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "source", label: "Website name" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  webpage: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Website name" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  journal_article: [
    { type: "field", field: "title", label: "Article title", required: true },
    { type: "field", field: "container_title", label: "Journal name", required: true },
    { type: "range", field: "volume", flag: "volume_is_range", label: "Volume number" },
    { type: "field", field: "issue", label: "Issue number" },
    { type: "field", field: "number", label: "Article number or eLocator", placeholder: "e.g. e0209899" },
    { type: "radio", field: "status", label: "Publication status", options: ["Published", "In press"] },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "source", label: "Library database", placeholder: "e.g. JSTOR, ProQuest, or EBSCO" },
    { type: "range", field: "pages", flag: "pages_is_range", label: "Page" },
    { type: "field", field: "doi", label: "DOI", placeholder: "e.g. 10.1037/a0040251" },
    { type: "field", field: "pdf_url", label: "PDF", inputType: "url", placeholder: "Link to PDF" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  book: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "edition", label: "Edition", placeholder: "e.g. 2" },
    { type: "range", field: "volume", flag: "volume_is_range", label: "Volume number" },
    { type: "field", field: "medium", label: "Medium" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    { type: "field", field: "publisher", label: "Publisher" },
    {
      type: "toggleField",
      flag: "show_publisher_place",
      field: "publisher_place",
      label: "Show place of publication",
      fieldLabel: "Place of publication"
    },
    { type: "field", field: "doi", label: "DOI", placeholder: "e.g. 10.1037/a0040251" },
    { type: "field", field: "pdf_url", label: "PDF", inputType: "url", placeholder: "Link to PDF" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  report: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      label: "Subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Website or database name" },
    { type: "field", field: "number", label: "Identifying number", placeholder: "e.g. WA-RD 896.4" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    {
      type: "field",
      field: "publisher",
      label: "Publisher",
      placeholder: "e.g. Washington State Department of Transportation"
    },
    {
      type: "toggleField",
      flag: "show_publisher_place",
      field: "publisher_place",
      label: "Show place of publication",
      fieldLabel: "Place of publication"
    },
    { type: "field", field: "doi", label: "DOI", placeholder: "e.g. 10.1037/a0040251" },
    { type: "field", field: "pdf_url", label: "PDF", inputType: "url", placeholder: "Link to PDF" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  video: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Website name", placeholder: "e.g. YouTube or Vimeo" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  online_newspaper_article: [
    { type: "field", field: "title", label: "Article title", required: true },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      label: "Subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Newspaper name", required: true },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "publisher", label: "Publisher" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  conference_proceeding: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Container title" },
    { type: "field", field: "edition", label: "Edition", placeholder: "e.g. 2" },
    { type: "range", field: "volume", flag: "volume_is_range", label: "Volume number" },
    { type: "field", field: "medium", label: "Medium" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "publisher", label: "Publisher" },
    {
      type: "toggleField",
      flag: "show_publisher_place",
      field: "publisher_place",
      toggleLabel: "Show place of publication",
      fieldLabel: "Place of publication"
    },
    { type: "field", field: "doi", label: "DOI", placeholder: "e.g. 10.1037/a0040251" },
    { type: "field", field: "pdf_url", label: "PDF", inputType: "url", placeholder: "Link to PDF" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  conference_session: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "medium", label: "Type of contribution" },
    {
      type: "archiveGroup",
      label: "Event",
      subFields: [
        { field: "event", label: "Name" },
        { field: "place_country", label: "Country" },
        { field: "place_region", label: "Region" },
        { field: "place_locality", label: "City" }
      ]
    },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  dataset: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_description",
      field: "description",
      toggleLabel: "Show description",
      fieldLabel: "Description"
    },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "version", label: "Version", placeholder: "e.g. V2, 1.1.67" },
    { type: "field", field: "medium", label: "Medium" },
    { type: "radio", field: "status", label: "Publication status", options: ["Published", "Unpublished"] },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "publisher", label: "Publisher" },
    { type: "field", field: "doi", label: "DOI", placeholder: "e.g. 10.1037/a0040251" },
    { type: "field", field: "pdf_url", label: "PDF", inputType: "url", placeholder: "Link to PDF" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  film: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "medium", label: "Medium", placeholder: "e.g. four-disc special extended ed. on DVDs" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "publisher", label: "Production company" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  forum_post: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Website name" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  image: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_description",
      field: "description",
      toggleLabel: "Show description",
      fieldLabel: "Description"
    },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Website name" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],
  print_newspaper_article: [
    { type: "field", field: "title", label: "Article title", required: true },
    {
      type: "toggleField",
      flag: "show_description",
      field: "description",
      toggleLabel: "Show description",
      fieldLabel: "Description"
    },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Newspaper name", required: true },
    { type: "field", field: "edition", label: "Edition", placeholder: "e.g. New York" },
    { type: "field", field: "section", label: "Section", placeholder: "e.g. Sports" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    { type: "field", field: "publisher", label: "Publisher" },
    {
      type: "toggleField",
      flag: "show_publisher_place",
      field: "publisher_place",
      toggleLabel: "Show place of publication",
      fieldLabel: "Place of publication"
    },
    { type: "range", field: "pages", flag: "pages_is_range", label: "Page" },
    { type: "annotation" }
  ],

  // ── Online dictionary entry ─────────────────────────────────────────────
  online_dictionary_entry: [
    { type: "field", field: "title", label: "Entry title", required: true },
    { type: "field", field: "container_title", label: "Website name" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Online encyclopedia entry ───────────────────────────────────────────
  online_encyclopedia_entry: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Online magazine article ─────────────────────────────────────────────
  online_magazine_article: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Website name" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "publisher", label: "Publisher" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Patent ──────────────────────────────────────────────────────────────
  patent: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Container title" },
    { type: "field", field: "jurisdiction", label: "Jurisdiction", required: true },
    {
      type: "field",
      field: "authority",
      label: "Issuing body",
      required: true,
      placeholder: "e.g., U.S. Patent and Trademark Office"
    },
    { type: "date", field: "issued_date", label: "Publication date", required: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Podcast (whole series) ───────────────────────────────────────────────
  podcast: [
    { type: "field", field: "title", label: "Name", required: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Podcast episode ─────────────────────────────────────────────────────
  podcast_episode: [
    { type: "field", field: "title", label: "Title" },
    { type: "field", field: "collection_title", label: "Podcast name", required: true },
    { type: "field", field: "season", label: "Season number" },
    { type: "field", field: "episode", label: "Episode number" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "publisher", label: "Production company" },
    {
      type: "field",
      field: "source",
      label: "Platform name",
      placeholder: "e.g. Apple Podcasts"
    },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Presentation slides ──────────────────────────────────────────────────
  presentation_slides: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Website name" },
    { type: "field", field: "medium", label: "Medium" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    {
      type: "archiveGroup",
      label: "Event",
      subFields: [
        { field: "event", label: "Name" },
        { field: "place_country", label: "Country" },
        { field: "place_region", label: "Region" },
        { field: "place_locality", label: "City" }
      ]
    },
    { type: "range", field: "pages", flag: "pages_is_range", label: "Slide number" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Press release ────────────────────────────────────────────────────────
  press_release: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Print dictionary entry ───────────────────────────────────────────────
  print_dictionary_entry: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Dictionary name", required: true },
    { type: "range", field: "volume", flag: "volume_is_range", label: "Volume number" },
    { type: "field", field: "number", label: "Identifying number" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    { type: "field", field: "publisher", label: "Publisher" },
    {
      type: "toggleField",
      flag: "show_publisher_place",
      field: "publisher_place",
      toggleLabel: "Show place of publication",
      fieldLabel: "Place of publication"
    },
    { type: "range", field: "pages", flag: "pages_is_range", label: "Page" },
    { type: "annotation" }
  ],

  // ── Print encyclopedia entry ─────────────────────────────────────────────
  print_encyclopedia_entry: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Encyclopedia name", required: true },
    { type: "range", field: "volume", flag: "volume_is_range", label: "Volume number" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    { type: "field", field: "publisher", label: "Publisher" },
    {
      type: "toggleField",
      flag: "show_publisher_place",
      field: "publisher_place",
      toggleLabel: "Show place of publication",
      fieldLabel: "Place of publication"
    },
    { type: "annotation" }
  ],

  // ── Print magazine article ───────────────────────────────────────────────
  print_magazine_article: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Magazine name", required: true },
    { type: "field", field: "issue", label: "Issue number" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "toggleDate",
      flag: "show_original_publication_date",
      field: "original_publication_date",
      label: "Show original publication date"
    },
    { type: "field", field: "source", label: "Source" },
    { type: "range", field: "pages", flag: "pages_is_range", label: "Page" },
    { type: "annotation" }
  ],

  // ── Social media post ────────────────────────────────────────────────────
  social_media_post: [
    { type: "field", field: "content", label: "Content", required: true },
    { type: "field", field: "container_title", label: "Website name" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Software ─────────────────────────────────────────────────────────────
  software: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "field", field: "container_title", label: "Container title" },
    { type: "field", field: "version", label: "Version", placeholder: "e.g. V3, 1.1.6.7" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "publisher", label: "Publisher" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Speech / Lecture ─────────────────────────────────────────────────────
  speech: [
    { type: "field", field: "title", label: "Title", required: true },
    {
      type: "toggleField",
      flag: "show_description",
      field: "description",
      toggleLabel: "Show description",
      fieldLabel: "Description"
    },
    {
      type: "toggleField",
      flag: "show_subtitle",
      field: "subtitle",
      toggleLabel: "Show subtitle",
      fieldLabel: "Subtitle"
    },
    { type: "field", field: "container_title", label: "Container title" },
    { type: "date", field: "issued_date", label: "Publication date" },
    {
      type: "archiveGroup",
      label: "Event",
      subFields: [
        { field: "event", label: "Name" },
        { field: "place_country", label: "Country" },
        { field: "place_region", label: "Region" },
        { field: "place_locality", label: "City" }
      ]
    },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Thesis / Dissertation ────────────────────────────────────────────────
  thesis: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "date", field: "submitted_date", label: "Year of submission" },
    {
      type: "field",
      field: "publisher",
      label: "University",
      placeholder: "e.g. University of Chicago"
    },
    { type: "field", field: "doi", label: "DOI", placeholder: "e.g. 10.1037/a0040251" },
    { type: "field", field: "pdf_url", label: "PDF", inputType: "url", placeholder: "Link to PDF" },
    { type: "annotation" }
  ],

  // ── TV show (whole series) ───────────────────────────────────────────────
  tv_show: [
    { type: "field", field: "title", label: "Title", required: true },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "field", field: "publisher", label: "Production company" },
    {
      type: "field",
      field: "source",
      label: "Platform name",
      placeholder: "e.g. Netflix"
    },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── TV show episode ──────────────────────────────────────────────────────
  tv_show_episode: [
    { type: "field", field: "title", label: "Title" },
    { type: "field", field: "collection_title", label: "TV show name", required: true },
    { type: "field", field: "season", label: "Season number" },
    { type: "field", field: "episode", label: "Episode number" },
    {
      type: "field",
      field: "medium",
      label: "Medium",
      placeholder: "e.g. Blu-ray edition"
    },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "publisher", label: "Production company" },
    {
      type: "field",
      field: "source",
      label: "Platform name",
      placeholder: "e.g. Netflix"
    },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Website (whole site) ─────────────────────────────────────────────────
  website: [
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "publisher", label: "Publisher" },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ],

  // ── Wiki entry (Wikipedia article) ──────────────────────────────────────
  wiki_entry: [
    { type: "field", field: "title", label: "Title" },
    { type: "field", field: "container_title", label: "Wiki title" },
    { type: "date", field: "issued_date", label: "Publication date" },
    { type: "date", field: "accessed_date", label: "Access date", todayShortcut: true },
    { type: "field", field: "url", label: "URL", inputType: "url" },
    { type: "annotation" }
  ]
};

// ─── Source helpers ───────────────────────────────────────────────────────────
export function getPublicationSourceKey(pubType) {
  const raw = String(pubType || "").trim();
  if (!raw) return "webpage";
  if (SOURCE_TYPE_CONFIG[raw]) return raw;
  const found = SOURCE_TYPE_OPTIONS.find((type) => (type.aliases || []).includes(raw));
  return found?.key || raw;
}

export function getPublicationSourceConfig(pubType) {
  const key = getPublicationSourceKey(pubType);
  return (
    SOURCE_TYPE_CONFIG[key] || {
      label: pubType || "Publication",
      sourceType: pubType || "Publication",
      requiredFields: ["title"],
      recommendedFields: [],
      optionalFields: [],
      icon: "📋",
      color: "#64748b"
    }
  );
}

// ─── Default form ─────────────────────────────────────────────────────────────
// Pre-compute the static parts of getDefaultPublicationForm once at module load.
// PUBLICATION_DETAIL_FIELDS (37 fields) and FEATURED_PUBLICATION_EXTRA_FIELDS (6 fields)
// never change at runtime, so there is no reason to call Object.fromEntries+map on every
// modal open. Spreading two already-built plain objects is essentially free.
const _STATIC_DETAIL_DEFAULTS = Object.fromEntries(
  PUBLICATION_DETAIL_FIELDS.map((field) => [field, ""])
);
const _STATIC_EXTRA_DEFAULTS = Object.fromEntries(
  FEATURED_PUBLICATION_EXTRA_FIELDS.map((field) => [
    field,
    field.startsWith("show_") || field.endsWith("_is_range") ? false : ""
  ])
);

export function getDefaultPublicationForm(pubType = "webpage") {
  return {
    name: "",
    title: "",
    pubType,
    citation_format: "mla",
    file: null,
    others: "",
    author: "",
    author_first_name: "",
    author_last_name: "",
    publication_date: "",
    url: "",
    article_title: "",
    journal_name: "",
    volume: "",
    issue: "",
    pages: "",
    doi: "",
    year: "",
    book_title: "",
    publisher: "",
    edition: "",
    page_number: "",
    organization: "",
    report_title: "",
    creator: "",
    video_title: "",
    platform: "",
    newspaper_name: "",
    website_name: "",
    page_title: "",
    contributors: [],
    ..._STATIC_DETAIL_DEFAULTS,
    ..._STATIC_EXTRA_DEFAULTS
  };
}

// ─── Publication data helpers ─────────────────────────────────────────────────
export function getPublicationDetails(item) {
  const raw = item?.details || item?.metadata || {};
  if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
  return {};
}

export function isPublicationFieldEmpty(form, field) {
  const value = form[field];
  if (Array.isArray(value)) return value.length === 0;
  return !String(value || "").trim();
}

export function getPublicationFieldValue(item, field) {
  const details = getPublicationDetails(item);
  const direct = details[field] ?? item?.[field];
  if (Array.isArray(direct))
    return direct
      .map((value) => String(value || "").trim())
      .filter(Boolean)
      .join(", ");
  if (direct) return String(direct);
  const legacyKeys = Object.entries(LEGACY_PUBLICATION_FIELD_MAP)
    .filter(([, mapped]) => mapped === field)
    .map(([legacyKey]) => legacyKey);
  for (const legacyKey of legacyKeys) {
    if (item?.[legacyKey]) return String(item[legacyKey]);
  }
  if (field === "title") return item?.title || item?.name || "";
  if (field === "note") return item?.others || "";
  return "";
}

export function getPublicationDisplayTitle(item) {
  return (
    getPublicationFieldValue(item, "title") ||
    item?.article_title ||
    item?.book_title ||
    item?.report_title ||
    item?.video_title ||
    item?.page_title ||
    item?.title ||
    item?.name ||
    "Untitled"
  );
}

export function normalizePublicationDate(value) {
  if (!value) return "";
  const raw = String(value).trim();
  if (/^\d{4}$/.test(raw)) return `${raw}-01-01`;
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return "";
  return parsed.toISOString().slice(0, 10);
}

export function getPublicationSortDate(item) {
  const value =
    getPublicationFieldValue(item, "issued_date") ||
    item?.publication_date ||
    item?.year ||
    item?.created_at;
  return normalizePublicationDate(value) || "0000-01-01";
}

export function getPublicationFieldGroups(pubType) {
  const cacheKey = getPublicationSourceKey(pubType);
  const cached = PUBLICATION_FIELD_GROUP_CACHE.get(cacheKey);
  if (cached) return cached;

  const selectedSourceConfig = getPublicationSourceConfig(pubType);
  const selectedSourceKey = cacheKey;
  const featuredFormRows = FEATURED_PUBLICATION_FORM_FIELDS[selectedSourceKey] || null;
  const selectedFieldSet = [
    ...(selectedSourceConfig.requiredFields || []),
    ...(selectedSourceConfig.recommendedFields || []),
    ...(selectedSourceConfig.optionalFields || [])
  ];
  const uniqueSelectedFieldSet = [...new Set(selectedFieldSet)];
  const requiredFieldSet = new Set(selectedSourceConfig.requiredFields || []);
  const recommendedFieldSet = new Set(selectedSourceConfig.recommendedFields || []);
  const getFieldGroup = (predicate) => uniqueSelectedFieldSet.filter((fieldKey) => predicate(fieldKey));

  const groups = {
    selectedSourceConfig,
    selectedSourceKey,
    featuredFormRows,
    selectedFieldSet: uniqueSelectedFieldSet,
    requiredFieldSet,
    recommendedFieldSet,
    titleFields: getFieldGroup((fieldKey) => PUBLICATION_TITLE_FIELDS.has(fieldKey)),
    containerFields: getFieldGroup((fieldKey) => PUBLICATION_CONTAINER_FIELDS.has(fieldKey)),
    dateFields: getFieldGroup((fieldKey) => PUBLICATION_DATE_FIELDS.has(fieldKey)),
    noteFields: getFieldGroup((fieldKey) => PUBLICATION_NOTE_FIELDS.has(fieldKey)),
    metadataFields: getFieldGroup(
      (fieldKey) =>
        !PUBLICATION_TITLE_FIELDS.has(fieldKey) &&
        !PUBLICATION_CONTAINER_FIELDS.has(fieldKey) &&
        !PUBLICATION_DATE_FIELDS.has(fieldKey) &&
        !PUBLICATION_NOTE_FIELDS.has(fieldKey)
    )
  };
  PUBLICATION_FIELD_GROUP_CACHE.set(cacheKey, groups);
  return groups;
}

/**
 * Convert a publication API response item → the form shape used by PublicationFormModal.
 * Used to pre-populate the edit form.
 */
export function publicationItemToForm(item) {
  const details = getPublicationDetails(item);
  const pubType = getPublicationSourceKey(item.source_type || item.pub_type) || "webpage";
  const base = getDefaultPublicationForm(pubType);

  // Overlay all detail fields
  const merged = { ...base };
  for (const key of Object.keys(base)) {
    const detailVal = details[key];
    const itemVal = item[key];
    if (detailVal !== undefined && detailVal !== null && detailVal !== "") {
      merged[key] = typeof detailVal === "boolean" ? detailVal : String(detailVal);
    } else if (itemVal !== undefined && itemVal !== null && itemVal !== "") {
      merged[key] = typeof itemVal === "boolean" ? itemVal : String(itemVal);
    }
  }

  // Boolean toggle flags
  for (const flag of ["show_subtitle", "show_description", "show_publisher_place", "show_original_publication_date"]) {
    if (details[flag] === true) merged[flag] = true;
  }
  for (const flag of ["volume_is_range", "pages_is_range"]) {
    if (details[flag] === true) merged[flag] = true;
  }

  // Contributors — restore the structured array from details (never from the display string)
  const rawContributors = details?.contributors;
  merged.contributors = Array.isArray(rawContributors) ? rawContributors : [];

  merged.pubType = pubType;
  merged.citation_format = item.citation_format || "mla";
  merged.name = item.name || "";
  merged.others = item.others || item.note || details.note || "";
  merged.author = item.author || "";
  merged.author_first_name = item.author_first_name || "";
  merged.author_last_name = item.author_last_name || "";
  merged.file = null; // files cannot be pre-filled
  return merged;
}

