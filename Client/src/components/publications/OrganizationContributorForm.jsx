/**
 * OrganizationContributorForm — controlled form for an organization contributor's fields.
 *
 * Performance: memo + single stable onChange handler.
 */
import { memo, useCallback } from "react";
import { CONTRIBUTOR_ROLES } from "./contributorUtils";

const OrganizationContributorForm = memo(function OrganizationContributorForm({
  data,
  role,
  onFieldChange,
  onRoleChange,
}) {
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
      {/* Name + Screen name */}
      <div className="contrib-field-row contrib-field-row-split">
        <label className="contrib-split-label">
          <span className="contrib-label-text">
            Name
            <span className="contrib-recommended"> Recommended</span>
          </span>
          <input
            name="name"
            className="contrib-input"
            type="text"
            value={data.name}
            onChange={handleInput}
            autoComplete="off"
            spellCheck={false}
          />
        </label>
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

export default OrganizationContributorForm;
