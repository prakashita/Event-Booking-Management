/**
 * ContributorCard — a single collapsible contributor entry.
 *
 * Performance guarantees:
 *  - Memoized with a custom equality check: only re-renders when THIS card's
 *    `contributor` object changes (not when other cards change).
 *  - All callbacks are stable across renders (no inline functions in JSX).
 *  - PersonContributorForm and OrganizationContributorForm are individually
 *    memoized — only re-render when their own data props change.
 */
import { memo, useCallback } from "react";
import { getContributorSummary } from "./contributorUtils";
import PersonContributorForm from "./PersonContributorForm";
import OrganizationContributorForm from "./OrganizationContributorForm";

// ─── Icons ────────────────────────────────────────────────────────────────────

function ChevronDownIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M6 9l6 6 6-6"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}

function ChevronUpIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M18 15l-6-6-6 6"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}

function ArrowUpIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M12 19V5M5 12l7-7 7 7"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}

function ArrowDownIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M12 5v14M19 12l-7 7-7-7"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}

// ─── Custom equality for memo ─────────────────────────────────────────────────

function cardPropsEqual(prev, next) {
  return (
    prev.contributor === next.contributor &&
    prev.index === next.index &&
    prev.total === next.total &&
    prev.onUpdateField === next.onUpdateField &&
    prev.onDelete === next.onDelete &&
    prev.onMove === next.onMove &&
    prev.onToggleExpand === next.onToggleExpand &&
    prev.onSwitchType === next.onSwitchType
  );
}

// ─── ContributorCard ──────────────────────────────────────────────────────────

const ContributorCard = memo(function ContributorCard({
  contributor,
  index,
  total,
  onUpdateField,
  onDelete,
  onMove,
  onToggleExpand,
  onSwitchType,
}) {
  const { id, type, role, expanded, person, organization } = contributor;

  // --- Stable handlers (deps: id + stable parent callbacks) ---

  const handleToggle = useCallback(() => {
    onToggleExpand(id);
  }, [id, onToggleExpand]);

  const handleDelete = useCallback(() => {
    onDelete(id);
  }, [id, onDelete]);

  const handleMoveUp = useCallback(() => {
    onMove(id, "up");
  }, [id, onMove]);

  const handleMoveDown = useCallback(() => {
    onMove(id, "down");
  }, [id, onMove]);

  const handleSwitchToPerson = useCallback(() => {
    onSwitchType(id, "person");
  }, [id, onSwitchType]);

  const handleSwitchToOrg = useCallback(() => {
    onSwitchType(id, "organization");
  }, [id, onSwitchType]);

  // Person field change: (fieldName, value)
  const handlePersonField = useCallback(
    (fieldName, value) => {
      onUpdateField(id, ["person", fieldName], value);
    },
    [id, onUpdateField]
  );

  // Org field change: (fieldName, value)
  const handleOrgField = useCallback(
    (fieldName, value) => {
      onUpdateField(id, ["organization", fieldName], value);
    },
    [id, onUpdateField]
  );

  const handleRoleChange = useCallback(
    (value) => {
      onUpdateField(id, ["role"], value);
    },
    [id, onUpdateField]
  );

  // --- Derived display values ---
  const summary = getContributorSummary(contributor);
  const typeLabel = type === "organization" ? "Organization" : "Person";

  return (
    <div className={`contrib-card${expanded ? " contrib-card-open" : ""}`}>
      {/* Card header — always visible */}
      <div
        className="contrib-card-header"
        role="button"
        aria-expanded={expanded}
        tabIndex={0}
        onClick={handleToggle}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            handleToggle();
          }
        }}
      >
        <div className="contrib-card-summary">
          <span className="contrib-type-badge contrib-type-badge-sm">
            {typeLabel}
          </span>
          {summary ? (
            <span className="contrib-summary-name">{summary}</span>
          ) : (
            <span className="contrib-summary-empty">No name entered</span>
          )}
          <span className="contrib-summary-role">{role}</span>
        </div>

        <div className="contrib-card-controls">
          {/* Move up */}
          {index > 0 && (
            <button
              type="button"
              className="contrib-icon-btn"
              aria-label="Move contributor up"
              title="Move up"
              onClick={(e) => {
                e.stopPropagation();
                handleMoveUp();
              }}
            >
              <ArrowUpIcon />
            </button>
          )}
          {/* Move down */}
          {index < total - 1 && (
            <button
              type="button"
              className="contrib-icon-btn"
              aria-label="Move contributor down"
              title="Move down"
              onClick={(e) => {
                e.stopPropagation();
                handleMoveDown();
              }}
            >
              <ArrowDownIcon />
            </button>
          )}
          {/* Delete */}
          <button
            type="button"
            className="contrib-icon-btn contrib-delete-btn"
            aria-label="Remove contributor"
            title="Remove"
            onClick={(e) => {
              e.stopPropagation();
              handleDelete();
            }}
          >
            <TrashIcon />
          </button>
          {/* Expand/collapse chevron */}
          <span className="contrib-chevron" aria-hidden="true">
            {expanded ? <ChevronUpIcon /> : <ChevronDownIcon />}
          </span>
        </div>
      </div>

      {/* Expandable body */}
      {expanded && (
        <div className="contrib-card-body">
          {/* Person / Organization type tabs */}
          <div className="contrib-type-tabs">
            <button
              type="button"
              className={`contrib-type-tab${type === "person" ? " active" : ""}`}
              onClick={handleSwitchToPerson}
              aria-pressed={type === "person"}
            >
              Person
            </button>
            <button
              type="button"
              className={`contrib-type-tab${type === "organization" ? " active" : ""}`}
              onClick={handleSwitchToOrg}
              aria-pressed={type === "organization"}
            >
              Organization
            </button>
          </div>

          {/* Fields */}
          {type === "person" ? (
            <PersonContributorForm
              data={person}
              role={role}
              onFieldChange={handlePersonField}
              onRoleChange={handleRoleChange}
            />
          ) : (
            <OrganizationContributorForm
              data={organization}
              role={role}
              onFieldChange={handleOrgField}
              onRoleChange={handleRoleChange}
            />
          )}
        </div>
      )}
    </div>
  );
}, cardPropsEqual);

export default ContributorCard;
