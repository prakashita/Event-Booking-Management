/**
 * Pure JS utilities for the Contributors system.
 * No React imports — safe to use anywhere.
 */

// ─── Role options ─────────────────────────────────────────────────────────────

export const CONTRIBUTOR_ROLES = [
  "Author",
  "Editor",
  "Contributor",
  "Reviewer",
  "Translator",
  "Advisor",
  "Compiler",
  "Director",
  "Producer",
  "Illustrator",
  "Narrator",
  "Performer",
  "Series Editor",
  "Guest",
];

// ─── ID generation ────────────────────────────────────────────────────────────

let _seq = 0;
function generateContributorId() {
  _seq = (_seq + 1) % 1_000_000;
  return `c_${Date.now()}_${_seq}`;
}

// ─── Factory functions ────────────────────────────────────────────────────────

export function createPersonContributor(overrides = {}) {
  return {
    id: generateContributorId(),
    type: "person",
    role: "Author",
    expanded: true,
    person: {
      title: "",
      initials: "",
      first_names: "",
      infix: "",
      last_name: "",
      suffix: "",
      screen_name: "",
      ...(overrides.person || {}),
    },
    organization: {
      name: "",
      screen_name: "",
    },
    ...overrides,
    // Ensure id and type are not overridden accidentally
    id: overrides.id || generateContributorId(),
    type: "person",
  };
}

export function createOrganizationContributor(overrides = {}) {
  return {
    id: generateContributorId(),
    type: "organization",
    role: "Author",
    expanded: true,
    person: {
      title: "",
      initials: "",
      first_names: "",
      infix: "",
      last_name: "",
      suffix: "",
      screen_name: "",
    },
    organization: {
      name: "",
      screen_name: "",
      ...(overrides.organization || {}),
    },
    ...overrides,
    id: overrides.id || generateContributorId(),
    type: "organization",
  };
}

// ─── Summary ──────────────────────────────────────────────────────────────────

export function getContributorSummary(contributor) {
  if (!contributor) return "";
  const org = contributor.organization || {};
  const orgName = (org.name || org.screen_name || "").trim();
  const p = contributor.person || {};
  const nameParts = [
    p.title,
    p.first_names || p.initials,
    p.infix,
    p.last_name,
    p.suffix,
  ].filter((s) => s && String(s).trim());
  const personName = nameParts.join(" ").trim() || (p.screen_name || "").trim();
  if (contributor.type === "organization") {
    return orgName || personName;
  }
  return personName || orgName;
}

// ─── Normalization ────────────────────────────────────────────────────────────

/**
 * Normalize a raw contributor object from storage / API into the canonical shape.
 * Handles legacy formats where keys may differ.
 */
export function normalizeContributor(raw) {
  if (!raw || typeof raw !== "object") return createPersonContributor();

  const type = raw.type === "organization" ? "organization" : "person";
  const id = raw.id || generateContributorId();
  const role = raw.role || "Author";
  // UI-only; default collapsed for loaded contributors so the list stays tidy
  const expanded = typeof raw.expanded === "boolean" ? raw.expanded : false;

  const personSrc = raw.person || {};
  const orgSrc = raw.organization || {};

  return {
    id,
    type,
    role,
    expanded,
    person: {
      title: String(personSrc.title || ""),
      initials: String(personSrc.initials || ""),
      first_names: String(personSrc.first_names || personSrc.firstName || personSrc.first_name || ""),
      infix: String(personSrc.infix || ""),
      last_name: String(personSrc.last_name || personSrc.lastName || ""),
      suffix: String(personSrc.suffix || ""),
      screen_name: String(personSrc.screen_name || personSrc.screenName || ""),
    },
    organization: {
      name: String(orgSrc.name || ""),
      screen_name: String(orgSrc.screen_name || orgSrc.screenName || ""),
    },
  };
}

/**
 * Normalize an array of contributors from storage.
 */
export function normalizeContributors(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map(normalizeContributor);
}

/**
 * Serialize contributors for API submission — strips the UI-only `expanded` flag.
 * IMPORTANT: Always include BOTH `person` and `organization` sub-objects so that
 * switching a contributor's type tab and saving never permanently discards the
 * data entered for the other type.
 */
export function serializeContributors(contributors) {
  if (!Array.isArray(contributors)) return [];
  return contributors.map(({ id, type, role, person, organization }) => ({
    id,
    type,
    role,
    person: person ?? {
      title: "", initials: "", first_names: "", infix: "",
      last_name: "", suffix: "", screen_name: "",
    },
    organization: organization ?? { name: "", screen_name: "" },
  }));
}
