import { useTheme } from "../contexts/ThemeContext";
import { SimpleIcon } from "./icons";

const THEME_OPTIONS = [
  {
    value: "light",
    label: "Light",
    desc: "Clean, bright interface",
    icon: "M12 7a5 5 0 1 0 0 10 5 5 0 0 0 0-10Zm0-3a1 1 0 0 0 1-1V1a1 1 0 1 0-2 0v2a1 1 0 0 0 1 1Zm0 18a1 1 0 0 0-1 1v2a1 1 0 1 0 2 0v-2a1 1 0 0 0-1-1ZM5.64 7.05 4.22 5.64a1 1 0 0 1 1.41-1.41L7.05 5.64a1 1 0 0 1-1.41 1.41Zm12.73 9.9a1 1 0 0 0-1.41 1.41l1.41 1.42a1 1 0 0 0 1.42-1.42l-1.42-1.41ZM4 12a1 1 0 0 0-1-1H1a1 1 0 1 0 0 2h2a1 1 0 0 0 1-1Zm18-1h-2a1 1 0 1 0 0 2h2a1 1 0 1 0 0-2ZM7.05 18.36a1 1 0 0 0-1.41 0l-1.42 1.42a1 1 0 1 0 1.41 1.41l1.42-1.42a1 1 0 0 0 0-1.41ZM18.36 7.05a1 1 0 0 0 .7-.29l1.42-1.42a1 1 0 1 0-1.42-1.41l-1.41 1.41a1 1 0 0 0 .71 1.71Z",
  },
  {
    value: "dark",
    label: "Dark",
    desc: "Easy on the eyes",
    icon: "M21.64 13a1 1 0 0 0-1.05-.14 8.05 8.05 0 0 1-3.37.73 8.15 8.15 0 0 1-8.14-8.1 8.6 8.6 0 0 1 .25-2A1 1 0 0 0 8.35 2.2 10.14 10.14 0 1 0 22 13.05a1 1 0 0 0-.36-.05Z",
  },
  {
    value: "system",
    label: "System",
    desc: "Match your OS setting",
    icon: "M4 6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6Zm2 0v8h12V6H6Zm-1 12a1 1 0 1 0 0 2h14a1 1 0 1 0 0-2H5Z",
  },
];

export default function SettingsModal({ open, onClose }) {
  const { theme, setTheme } = useTheme();

  if (!open) return null;

  return (
    <div className="settings-overlay" onClick={onClose}>
      <div
        className="settings-card"
        role="dialog"
        aria-modal="true"
        aria-label="Settings"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="settings-header">
          <h2 className="settings-title">Settings</h2>
          <button
            type="button"
            className="settings-close"
            onClick={onClose}
            aria-label="Close settings"
          >
            <SimpleIcon path="M18 6 6 18M6 6l12 12" />
          </button>
        </div>

        {/* Body */}
        <div className="settings-body">
          <fieldset className="settings-section">
            <legend className="settings-section-label">Appearance</legend>
            <div className="settings-theme-grid">
              {THEME_OPTIONS.map((opt) => (
                <button
                  key={opt.value}
                  type="button"
                  className={`settings-theme-card${theme === opt.value ? " active" : ""}`}
                  onClick={() => setTheme(opt.value)}
                  aria-pressed={theme === opt.value}
                >
                  <span className="settings-theme-icon" aria-hidden="true">
                    <SimpleIcon path={opt.icon} />
                  </span>
                  <span className="settings-theme-label">{opt.label}</span>
                  <span className="settings-theme-desc">{opt.desc}</span>
                  {theme === opt.value && (
                    <span className="settings-theme-check" aria-hidden="true">
                      <SimpleIcon path="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41L9 16.17Z" />
                    </span>
                  )}
                </button>
              ))}
            </div>
          </fieldset>
        </div>
      </div>
    </div>
  );
}
