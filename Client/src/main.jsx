import React from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App.jsx";
import { ErrorBoundary, GlobalErrorBanner } from "./components/ui";
import "./styles.css";

const root = createRoot(document.getElementById("root"));
root.render(
  <React.StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <GlobalErrorBanner />
        <App />
      </BrowserRouter>
    </ErrorBoundary>
  </React.StrictMode>
);
