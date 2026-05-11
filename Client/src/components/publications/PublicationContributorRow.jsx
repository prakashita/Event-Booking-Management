/**
 * PublicationContributorRow — isolated contributor card with stable IDs.
 *
 * Performance guarantees:
 *  - Wrapped in React.memo with scalar props; unchanged rows do not re-render.
 *  - Event handlers are stable useCallback instances keyed to client_id.
 *  - Kind switching updates one row object and keeps the modal mounted.
 *  - No portals, layout reads, animated height, backdrop filters, or dynamic SVG work.
 */
import { memo, useCallback } from "react";
import { CONTRIBUTOR_ROLE_OPTIONS } from "./publicationUtils";

const REMOVE_ICON = (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M7 4h10l-1 2h5v2h-2l-1 12a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 8H3V6h5L7 4Zm1 4 1 12h6l1-12H8Zm2 2h2v8h-2v-8Zm4 0h2v8h-2v-8Z" />
  </svg>
);

// ─── Sub-components ───────────────────────────────────────────────────────────

export const PublicationContributorTextInput = memo(function PublicationContributorTextInput({
  contributorId,
  field,
  value,
  className = "",
  label,
  onUpdate
}) {
  const handleChange = useCallback(
    (event) => onUpdate(contributorId, field, event.target.value),
    [contributorId, field, onUpdate]
  );

  return (
    <label className={`form-field ${className}`.trim()}>
      <span>{label}</span>
      <input type="text" value={value || ""} onChange={handleChange} />
    </label>
  );
});

export const PublicationContributorRoleSelect = memo(function PublicationContributorRoleSelect({
  contributorId,
  value,
  className = "",
  onUpdate
}) {
  const handleChange = useCallback(
    (event) => onUpdate(contributorId, "role", event.target.value),
    [contributorId, onUpdate]
  );

  return (
    <label className={`form-field ${className}`.trim()}>
      <span>Role</span>
      <select value={value || "Author"} onChange={handleChange}>
        {CONTRIBUTOR_ROLE_OPTIONS.map((role) => (
          <option key={role} value={role}>
            {role}
          </option>
        ))}
      </select>
    </label>
  );
});

// ─── Lightweight header ───────────────────────────────────────────────────────

const PublicationContributorHeader = memo(function PublicationContributorHeader({
  clientId,
  kind,
  collapsed,
  firstName,
  lastName,
  name,
  role,
  onToggle,
  onRemove
}) {
  const handleToggle = useCallback(() => onToggle(clientId), [clientId, onToggle]);
  const handleRemove = useCallback(() => onRemove(clientId), [clientId, onRemove]);

  const displayLabel =
    kind === "organization"
      ? name || "Organization"
      : [firstName, lastName].filter(Boolean).join(" ") || "Person";

  return (
    <div className="pub-contributor-card-head">
      <button
        type="button"
        className="pub-contributor-collapse"
        onClick={handleToggle}
        aria-expanded={!collapsed}
      >
        <span
          className={`pub-contributor-chevron${collapsed ? " is-collapsed" : ""}`}
          aria-hidden="true"
        />
        <strong>{displayLabel}</strong>
        {collapsed ? <span>{role || "Author"}</span> : null}
      </button>
      <button
        type="button"
        className="pub-icon-btn"
        onClick={handleRemove}
        aria-label="Remove contributor"
      >
        {REMOVE_ICON}
      </button>
    </div>
  );
});

// ─── Expanded controls ───────────────────────────────────────────────────────

const PublicationContributorKindSwitch = memo(function PublicationContributorKindSwitch({
  clientId,
  kind,
  onSwitchKind
}) {
  const handlePerson = useCallback(
    () => onSwitchKind(clientId, "person"),
    [clientId, onSwitchKind]
  );
  const handleOrganization = useCallback(
    () => onSwitchKind(clientId, "organization"),
    [clientId, onSwitchKind]
  );

  return (
    <div className="pub-contributor-tabs" aria-label="Contributor kind">
      <button
        type="button"
        className={kind === "person" ? "active" : ""}
        onClick={handlePerson}
      >
        Person
      </button>
      <button
        type="button"
        className={kind === "organization" ? "active" : ""}
        onClick={handleOrganization}
      >
        Organization
      </button>
    </div>
  );
});

const PersonFields = memo(function PersonFields({
  clientId,
  title,
  initials,
  firstName,
  infix,
  lastName,
  suffix,
  screenName,
  role,
  active,
  onUpdate
}) {
  return (
    <div className="pub-contributor-grid" hidden={!active}>
      <PublicationContributorTextInput
        contributorId={clientId}
        field="title"
        label="Title"
        value={title}
        onUpdate={onUpdate}
      />
      <PublicationContributorTextInput
        contributorId={clientId}
        field="initials"
        label="Initials"
        value={initials}
        onUpdate={onUpdate}
      />
      <PublicationContributorTextInput
        contributorId={clientId}
        field="first_name"
        label="First name(s)"
        value={firstName}
        onUpdate={onUpdate}
      />
      <PublicationContributorTextInput
        contributorId={clientId}
        field="infix"
        label="Infix"
        value={infix}
        onUpdate={onUpdate}
      />
      <PublicationContributorTextInput
        contributorId={clientId}
        field="last_name"
        label="Last name"
        value={lastName}
        onUpdate={onUpdate}
      />
      <PublicationContributorTextInput
        contributorId={clientId}
        field="suffix"
        label="Suffix"
        value={suffix}
        onUpdate={onUpdate}
      />
      <PublicationContributorTextInput
        contributorId={clientId}
        field="screen_name"
        label="Screen name"
        value={screenName}
        onUpdate={onUpdate}
      />
      <PublicationContributorRoleSelect
        contributorId={clientId}
        value={role}
        onUpdate={onUpdate}
      />
    </div>
  );
});

const OrganizationFields = memo(function OrganizationFields({
  clientId,
  name,
  screenName,
  role,
  active,
  onUpdate
}) {
  return (
    <div className="pub-contributor-grid" hidden={!active}>
      <PublicationContributorTextInput
        contributorId={clientId}
        field="name"
        label="Name"
        value={name}
        className="pub-span-2"
        onUpdate={onUpdate}
      />
      <PublicationContributorTextInput
        contributorId={clientId}
        field="screen_name"
        label="Screen name"
        value={screenName}
        className="pub-span-2"
        onUpdate={onUpdate}
      />
      <PublicationContributorRoleSelect
        contributorId={clientId}
        value={role}
        className="pub-span-2"
        onUpdate={onUpdate}
      />
    </div>
  );
});

const PublicationContributorExpandedFields = memo(function PublicationContributorExpandedFields({
  clientId,
  kind,
  name,
  title,
  initials,
  firstName,
  infix,
  lastName,
  suffix,
  screenName,
  role,
  onSwitchKind,
  onUpdate
}) {
  return (
    <>
      <PublicationContributorKindSwitch
        clientId={clientId}
        kind={kind}
        onSwitchKind={onSwitchKind}
      />
      <OrganizationFields
        clientId={clientId}
        name={name}
        screenName={screenName}
        role={role}
        active={kind === "organization"}
        onUpdate={onUpdate}
      />
      <PersonFields
        clientId={clientId}
        title={title}
        initials={initials}
        firstName={firstName}
        infix={infix}
        lastName={lastName}
        suffix={suffix}
        screenName={screenName}
        role={role}
        active={kind !== "organization"}
        onUpdate={onUpdate}
      />
    </>
  );
});

// ─── Main row ─────────────────────────────────────────────────────────────────

const PublicationContributorRow = memo(function PublicationContributorRow({
  clientId,
  kind,
  role,
  collapsed,
  name,
  title,
  initials,
  firstName,
  infix,
  lastName,
  suffix,
  screenName,
  onToggle,
  onRemove,
  onSwitchKind,
  onUpdate
}) {
  return (
    <div className={`pub-contributor-card${collapsed ? " collapsed" : ""}`}>
      <PublicationContributorHeader
        clientId={clientId}
        kind={kind}
        collapsed={collapsed}
        firstName={firstName}
        lastName={lastName}
        name={name}
        role={role}
        onToggle={onToggle}
        onRemove={onRemove}
      />
      {collapsed ? null : (
        <PublicationContributorExpandedFields
          clientId={clientId}
          kind={kind}
          name={name}
          title={title}
          initials={initials}
          firstName={firstName}
          infix={infix}
          lastName={lastName}
          suffix={suffix}
          screenName={screenName}
          role={role}
          onSwitchKind={onSwitchKind}
          onUpdate={onUpdate}
        />
      )}
    </div>
  );
});

export default PublicationContributorRow;
