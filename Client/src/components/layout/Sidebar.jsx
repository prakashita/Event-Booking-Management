import { NavLink, useNavigate } from "react-router-dom";
import { preferenceItems, VIEW_TO_PATH } from "../../constants";
import { SimpleIcon } from "../icons";

export default function Sidebar({
  visibleMenuItems,
  onLogout,
  className = "",
  onNavigate
}) {
  const navigate = useNavigate();

  return (
    <aside className={`sidebar ${className}`.trim()}>
      <div className="brand">
        <div className="brand-icon">
          <SimpleIcon path="M6 12a6 6 0 1 1 6 6H6v-6Z" />
        </div>
        <span>FACULTY</span>
      </div>

      <div className="menu-block">
        <p className="menu-title">Menu</p>
        <nav className="menu-list">
          {visibleMenuItems.map((item) => {
            const path = VIEW_TO_PATH[item.id] ?? "/";
            const iconPath = item.icon || "M3 10.5 12 3l9 7.5v9.5H3z";
            return (
              <NavLink
                key={item.id}
                to={path}
                className={({ isActive }) => `menu-item ${isActive ? "active" : ""}`}
                onClick={() => onNavigate?.()}
              >
                <span className="menu-icon">
                  <SimpleIcon path={iconPath} />
                </span>
                {item.label}
              </NavLink>
            );
          })}
        </nav>
      </div>

      <div className="menu-block">
        <p className="menu-title">Preferences</p>
        <nav className="menu-list">
          {preferenceItems.map((item) => (
            <button key={item.id} type="button" className="menu-item">
              <span className="menu-icon">
                <SimpleIcon path="M12 2a6 6 0 1 1 0 12 6 6 0 0 1 0-12Zm0 14c4.4 0 8 2 8 4v2H4v-2c0-2 3.6-4 8-4Z" />
              </span>
              {item.label}
            </button>
          ))}
        </nav>
      </div>

      <button
        type="button"
        className="menu-item logout"
        onClick={() => {
          onLogout();
          onNavigate?.();
          navigate("/");
        }}
      >
        <span className="menu-icon">
          <SimpleIcon path="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4M10 17l-4-4 4-4M6 13h12" />
        </span>
        Logout
      </button>
    </aside>
  );
}
