/**
 * ContributorsSection — the full Contributors UI section.
 *
 * Design:
 *  - Manages its OWN internal contributors state.
 *  - Calls `onChange` on every mutation so the parent can keep a ref
 *    without triggering a full parent re-render.
 *  - Each ContributorCard is memoized; only the mutated card re-renders.
 *
 * Props:
 *  - initialContributors: array loaded from the publication form
 *  - onChange: (contributors) => void  ← parent stores in a ref, NOT state
 */
import { memo, useCallback, useState } from "react";
import ContributorCard from "./ContributorCard";
import {
  createOrganizationContributor,
  createPersonContributor,
  normalizeContributors,
} from "./contributorUtils";

// ─── Add icons ────────────────────────────────────────────────────────────────

function PersonIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}

function OrgIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M3 21h18M9 8h1m-1 4h1m-1 4h1m4-8h1m-1 4h1m-1 4h1M5 21V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
        fill="none"
      />
    </svg>
  );
}

// ─── ContributorsSection ──────────────────────────────────────────────────────

const ContributorsSection = memo(function ContributorsSection({
  initialContributors,
  onChange,
}) {
  const [contributors, setContributors] = useState(() =>
    normalizeContributors(initialContributors || [])
  );

  // Single internal updater — calls onChange after every mutation
  const commit = useCallback(
    (updater) => {
      setContributors((prev) => {
        const next = typeof updater === "function" ? updater(prev) : updater;
        onChange(next);
        return next;
      });
    },
    [onChange]
  );

  // ── Stable mutation handlers ──────────────────────────────────────────────

  /**
   * Update a deeply-nested field by path array, e.g.
   *   ['person', 'last_name'], 'Smith'
   *   ['role'], 'Editor'
   */
  const handleUpdateField = useCallback(
    (id, path, value) => {
      commit((prev) =>
        prev.map((c) => {
          if (c.id !== id) return c;
          if (path.length === 1) {
            return { ...c, [path[0]]: value };
          }
          // Two-level: ['person'|'organization', fieldName]
          const [topKey, fieldKey] = path;
          return {
            ...c,
            [topKey]: { ...c[topKey], [fieldKey]: value },
          };
        })
      );
    },
    [commit]
  );

  const handleToggleExpand = useCallback(
    (id) => {
      commit((prev) =>
        prev.map((c) =>
          c.id === id ? { ...c, expanded: !c.expanded } : c
        )
      );
    },
    [commit]
  );

  const handleDelete = useCallback(
    (id) => {
      commit((prev) => prev.filter((c) => c.id !== id));
    },
    [commit]
  );

  const handleMove = useCallback(
    (id, direction) => {
      commit((prev) => {
        const idx = prev.findIndex((c) => c.id === id);
        if (idx === -1) return prev;
        const targetIdx = direction === "up" ? idx - 1 : idx + 1;
        if (targetIdx < 0 || targetIdx >= prev.length) return prev;
        const next = [...prev];
        [next[idx], next[targetIdx]] = [next[targetIdx], next[idx]];
        return next;
      });
    },
    [commit]
  );

  const handleSwitchType = useCallback(
    (id, newType) => {
      commit((prev) =>
        prev.map((c) =>
          c.id === id ? { ...c, type: newType } : c
        )
      );
    },
    [commit]
  );

  const handleAddPerson = useCallback(() => {
    commit((prev) => [...prev, createPersonContributor()]);
  }, [commit]);

  const handleAddOrg = useCallback(() => {
    commit((prev) => [...prev, createOrganizationContributor()]);
  }, [commit]);

  // ─────────────────────────────────────────────────────────────────────────

  return (
    <section className="contrib-section pub-scribbr-row">
      {/* Label column */}
      <div className="pub-scribbr-label contrib-section-label">
        <strong>Contributors</strong>
        <span>Recommended</span>
      </div>

      {/* Control column */}
      <div className="contrib-section-body">
        {contributors.length > 0 && (
          <div className="contrib-list" role="list">
            {contributors.map((contributor, index) => (
              <div key={contributor.id} role="listitem">
                <ContributorCard
                  contributor={contributor}
                  index={index}
                  total={contributors.length}
                  onUpdateField={handleUpdateField}
                  onDelete={handleDelete}
                  onMove={handleMove}
                  onToggleExpand={handleToggleExpand}
                  onSwitchType={handleSwitchType}
                />
              </div>
            ))}
          </div>
        )}

        {/* Add buttons */}
        <div className="contrib-add-row">
          <button
            type="button"
            className="contrib-add-btn"
            onClick={handleAddPerson}
          >
            <PersonIcon />
            Add person
          </button>
          <button
            type="button"
            className="contrib-add-btn"
            onClick={handleAddOrg}
          >
            <OrgIcon />
            Add organization
          </button>
        </div>
      </div>
    </section>
  );
});

export default ContributorsSection;
