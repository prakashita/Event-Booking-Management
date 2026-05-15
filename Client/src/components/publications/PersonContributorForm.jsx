/**
 * PersonContributorForm — controlled form for a person contributor's fields.
 *
 * Performance: memo + single stable onChange handler.
 * The parent passes a stable `onFieldChange(fieldName, value)` callback.
 */
import { memo, useCallback } from "react";
import { CONTRIBUTOR_ROLES } from "./contributorUtils";

const PersonContributorForm = memo(function PersonContributorForm({
  data,
  role,
  onFieldChange,
  onRoleChange,
}) {
  // Single event-based handler — stable as long as onFieldChange is stable
  const handleInput = useCallback(
    (e) => {
      onFieldChange(e.target.name, e.target.value);
    },
    [onFieldChange]
  );

  const handleRole = useCallback(
    (e) => {
      onRoleChange(e.target.value);
    },
    [onRoleChange]
  );

  return (
    <div className="contrib-form">
      {/* Title + Initials row */}
      <div className="contrib-field-row contrib-field-row-split">
        <label className="contrib-split-label">
          <span className="contrib-label-text">Title</span>
          <input
            name="title"
            className="contrib-input"
            type="text"
            value={data.title}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
        <label className="contrib-split-label">
          <span className="contrib-label-text">
            Initials
            <span className="contrib-recommended"> Recommended</span>
          </span>
          <input
            name="initials"
            className="contrib-input"
            type="text"
            value={data.initials}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
      </div>

      {/* First name(s) */}
      <div className="contrib-field-row">
        <div className="contrib-field-label">
          <strong>First name(s)</strong>
        </div>
        <div className="contrib-field-control">
          <input
            name="first_names"
            className="contrib-input"
            type="text"
            value={data.first_names}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </div>
      </div>

      {/* Infix */}
      <div className="contrib-field-row">
        <div className="contrib-field-label">
          <strong>Infix</strong>
        </div>
        <div className="contrib-field-control">
          <input
            name="infix"
            className="contrib-input"
            type="text"
            value={data.infix}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </div>
      </div>

      {/* Last name */}
      <div className="contrib-field-row">
        <div className="contrib-field-label">
          <strong>Last name</strong>
          <span className="contrib-recommended">Recommended</span>
        </div>
        <div className="contrib-field-control">
          <input
            name="last_name"
            className="contrib-input"
            type="text"
            value={data.last_name}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </div>
      </div>

      {/* Suffix */}
      <div className="contrib-field-row">
        <div className="contrib-field-label">
          <strong>Suffix</strong>
        </div>
        <div className="contrib-field-control">
          <input
            name="suffix"
            className="contrib-input"
            type="text"
            value={data.suffix}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </div>
      </div>

      {/* Screen name */}
      <div className="contrib-field-row">
        <div className="contrib-field-label">
          <strong>Screen name</strong>
        </div>
        <div className="contrib-field-control">
          <input
            name="screen_name"
            className="contrib-input"
            type="text"
            value={data.screen_name}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </div>
      </div>

      {/* Role */}
      <div className="contrib-field-row contrib-field-row-last">
        <div className="contrib-field-label">
          <strong>Role</strong>
          <span className="contrib-recommended">Recommended</span>
        </div>
        <div className="contrib-field-control">
          <select
            className="contrib-select"
            value={role}
            onChange={handleRole}
          >
            {CONTRIBUTOR_ROLES.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </div>
      </div>
    </div>
  );
});

export default PersonContributorForm;
