/**
 * PublicationContributorSection — renders the full contributors section
 * inside the publication form.
 *
 * Performance guarantees:
 *  - memo-wrapped; only re-renders when contributor array reference changes.
 *  - Each row uses a stable client_id key so React reconciles cheaply.
 *  - "Add person" / "Add organization" buttons append a new row; existing rows
 *    keep their element identity and do not re-render.
 *  - No network requests triggered here.
 */
import { memo } from "react";
import PublicationContributorRow from "./PublicationContributorRow";

// ─── Add-buttons bar ──────────────────────────────────────────────────────────

const ADD_PERSON_ICON = (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M12 12a4 4 0 1 0-4-4 4 4 0 0 0 4 4Zm0 2c-4.42 0-8 2.24-8 5v1h16v-1c0-2.76-3.58-5-8-5Z" />
  </svg>
);

const ADD_ORGANIZATION_ICON = (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M4 21V3h10v4h6v14h-6v-4H8v4H4Zm4-12h2V7H8v2Zm0 4h2v-2H8v2Zm6 0h2v-2h-2v2Zm0 4h2v-2h-2v2Z" />
  </svg>
);

export const PublicationContributorButtons = memo(function PublicationContributorButtons({
  onAddPerson,
  onAddOrganization
}) {
  return (
    <div className="pub-contributor-actions">
      <button type="button" className="secondary-action" onClick={onAddPerson}>
        {ADD_PERSON_ICON}
        Add person
      </button>
      <button type="button" className="secondary-action" onClick={onAddOrganization}>
        {ADD_ORGANIZATION_ICON}
        Add organization
      </button>
    </div>
  );
});

// ─── Full contributors section ────────────────────────────────────────────────

const PublicationContributorSection = memo(function PublicationContributorSection({
  visible,
  contributors,
  required,
  recommended,
  onAddPerson,
  onAddOrganization,
  onToggleContributor,
  onRemoveContributor,
  onSwitchContributorKind,
  onUpdateContributor
}) {
  if (!visible) return null;

  return (
    <section key="contributors" className="pub-scribbr-row pub-contributor-section">
      <div className="pub-scribbr-label">
        <strong>Contributors</strong>
        <span>{required ? "Required" : recommended ? "Recommended" : ""}</span>
      </div>
      <div className="pub-scribbr-control pub-contributor-control">
        <div className="pub-contributor-list">
          {contributors.map((contributor) => (
            <PublicationContributorRow
              key={contributor.client_id}
              clientId={contributor.client_id}
              kind={contributor.kind}
              role={contributor.role}
              collapsed={contributor.collapsed}
              name={contributor.name}
              title={contributor.title}
              initials={contributor.initials}
              firstName={contributor.first_name}
              infix={contributor.infix}
              lastName={contributor.last_name}
              suffix={contributor.suffix}
              screenName={contributor.screen_name}
              onToggle={onToggleContributor}
              onRemove={onRemoveContributor}
              onSwitchKind={onSwitchContributorKind}
              onUpdate={onUpdateContributor}
            />
          ))}
        </div>
        <PublicationContributorButtons
          onAddPerson={onAddPerson}
          onAddOrganization={onAddOrganization}
        />
      </div>
    </section>
  );
});

export default PublicationContributorSection;
