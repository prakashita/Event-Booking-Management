import { NavLink, useNavigate } from "react-router-dom";
import {
  VIEW_TO_PATH,
  MENU_ICONS,
  SIDEBAR_TOGGLE_ICONS,
} from "../../constants";
import { SimpleIcon } from "../icons";

export default function Sidebar({
  visibleMenuItems,
  onLogout,
  className = "",
  onNavigate,
  user,
  collapsed = false,
  onToggleCollapse,
}) {
  const navigate = useNavigate();

  const roleLabel = (user?.role || "Faculty")
    .replace(/_/g, " ")
    .toUpperCase();

  return (
    <aside
      className={`sidebar ${collapsed ? "collapsed" : ""} ${className}`.trim()}
      aria-label="Main navigation"
    >
      {/* Header: brand + collapse toggle */}
      <div className="sidebar-header">
        <div className="brand">
          <div className="brand-icon" aria-hidden="true">
            <SimpleIcon path="M6 12a6 6 0 1 1 6 6H6v-6Z" />
          </div>
          <span className="brand-label">{roleLabel}</span>
        </div>
        {onToggleCollapse && (
          <button
            type="button"
            className="sidebar-toggle"
            onClick={onToggleCollapse}
            aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          >
            <SimpleIcon
              path={
                collapsed
                  ? SIDEBAR_TOGGLE_ICONS.expand
                  : SIDEBAR_TOGGLE_ICONS.collapse
              }
            />
          </button>
        )}
      </div>

      {/* Main menu */}
      <nav className="sidebar-nav" aria-label="Main menu">
        <p className="menu-title">
          <span className="menu-title-text">Menu</span>
        </p>
        <ul className="menu-list" role="list">
          {visibleMenuItems.map((item) => {
            const path = VIEW_TO_PATH[item.id] ?? "/";
            const iconPath =
              MENU_ICONS[item.id] || "M3 10.5 12 3l9 7.5v9.5H3z";
            return (
              <li key={item.id} role="listitem">
                <NavLink
                  to={path}
                  className={({ isActive }) =>
                    `menu-item ${isActive ? "active" : ""}`
                  }
                  onClick={() => onNavigate?.()}
                  title={collapsed ? item.label : undefined}
                >
                  <span className="menu-icon" aria-hidden="true">
                    <SimpleIcon path={iconPath} />
                  </span>
                  <span className="menu-label">{item.label}</span>
                </NavLink>
              </li>
            );
          })}
        </ul>
      </nav>
    </aside>
  );
}
