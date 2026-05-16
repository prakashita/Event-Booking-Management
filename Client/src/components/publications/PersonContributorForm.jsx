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
      {/* Title + Initials */}
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

      {/* First name(s) + Last name */}
      <div className="contrib-field-row contrib-field-row-split">
        <label className="contrib-split-label">
          <span className="contrib-label-text">First name(s)</span>
          <input
            name="first_names"
            className="contrib-input"
            type="text"
            value={data.first_names}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
        <label className="contrib-split-label">
          <span className="contrib-label-text">
            Last name
            <span className="contrib-recommended"> Recommended</span>
          </span>
          <input
            name="last_name"
            className="contrib-input"
            type="text"
            value={data.last_name}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
      </div>

      {/* Infix + Suffix */}
      <div className="contrib-field-row contrib-field-row-split">
        <label className="contrib-split-label">
          <span className="contrib-label-text">Infix</span>
          <input
            name="infix"
            className="contrib-input"
            type="text"
            value={data.infix}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
        <label className="contrib-split-label">
          <span className="contrib-label-text">Suffix</span>
          <input
            name="suffix"
            className="contrib-input"
            type="text"
            value={data.suffix}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
      </div>

      {/* Screen name + Role */}
      <div className="contrib-field-row contrib-field-row-split contrib-field-row-last">
        <label className="contrib-split-label">
          <span className="contrib-label-text">Screen name</span>
          <input
            name="screen_name"
            className="contrib-input"
            type="text"
            value={data.screen_name}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
        <label className="contrib-split-label">
          <span className="contrib-label-text">
            Role
            <span className="contrib-recommended"> Recommended</span>
          </span>
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
        </label>
      </div>
    </div>
  );
});

export default PersonContributorForm;
