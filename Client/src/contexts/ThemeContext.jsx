import { createContext, useContext, useEffect, useMemo, useState } from "react";

const STORAGE_KEY = "ebm-theme";
const VALID = ["light", "dark", "system"];

const ThemeContext = createContext({ theme: "system", resolvedTheme: "light", setTheme: () => {} });

function getSystemPref() {
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function resolve(theme) {
  return theme === "system" ? getSystemPref() : theme;
}

export function ThemeProvider({ children }) {
  const [theme, setThemeRaw] = useState(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (VALID.includes(stored)) return stored;
    } catch { /* ignore */ }
    return "system";
  });

  const setTheme = (t) => {
    const v = VALID.includes(t) ? t : "system";
    setThemeRaw(v);
    try { localStorage.setItem(STORAGE_KEY, v); } catch { /* ignore */ }
  };

  const [resolvedTheme, setResolved] = useState(() => resolve(theme));

  useEffect(() => {
    if (theme !== "system") {
      setResolved(theme);
      document.documentElement.setAttribute("data-theme", theme);
      return;
    }
    const update = () => {
      const r = getSystemPref();
      setResolved(r);
      document.documentElement.setAttribute("data-theme", r);
    };
    update();
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, [theme]);

  const value = useMemo(() => ({ theme, resolvedTheme, setTheme }), [theme, resolvedTheme]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  return useContext(ThemeContext);
}
