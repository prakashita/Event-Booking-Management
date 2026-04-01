import { createContext, useContext, useState, useMemo, useCallback } from "react";

const MessengerContext = createContext(null);

export function useMessenger() {
  return useContext(MessengerContext);
}

export function MessengerProvider({ children }) {
  const [panelOpen, setPanelOpen] = useState(false);

  const togglePanel = useCallback(() => setPanelOpen((prev) => !prev), []);
  const openPanel = useCallback(() => setPanelOpen(true), []);
  const closePanel = useCallback(() => setPanelOpen(false), []);

  const value = useMemo(
    () => ({ panelOpen, togglePanel, openPanel, closePanel }),
    [panelOpen, togglePanel, openPanel, closePanel]
  );

  return (
    <MessengerContext.Provider value={value}>
      {children}
    </MessengerContext.Provider>
  );
}

export default MessengerContext;
