/**
 * Global error banner shown for network/server errors.
 * Listens for api:server_error and api:network_error events from the API service.
 */
import { useEffect, useState } from "react";
import api from "../../services/api";

export default function GlobalErrorBanner() {
  const [error, setError] = useState(null);

  useEffect(() => {
    const onServerError = (e) => {
      setError(e.detail?.message || "Server error. Please try again later.");
    };
    const onNetworkError = (e) => {
      setError(e.detail?.message || "Network error. Please check your connection.");
    };
    window.addEventListener(api.API_EVENTS.SERVER_ERROR, onServerError);
    window.addEventListener(api.API_EVENTS.NETWORK_ERROR, onNetworkError);
    return () => {
      window.removeEventListener(api.API_EVENTS.SERVER_ERROR, onServerError);
      window.removeEventListener(api.API_EVENTS.NETWORK_ERROR, onNetworkError);
    };
  }, []);

  if (!error) return null;

  return (
    <div
      className="global-error-banner"
      role="alert"
      aria-live="assertive"
    >
      <span>{error}</span>
      <button
        type="button"
        onClick={() => setError(null)}
        aria-label="Dismiss error"
      >
        ×
      </button>
    </div>
  );
}
