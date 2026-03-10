/**
 * Display loading or error state for API-driven content.
 */
export default function StatusMessage({ status, error, loadingText = "Loading...", emptyText }) {
  if (status === "loading") {
    return <p className="table-message">{loadingText}</p>;
  }
  if (status === "error" && error) {
    return <p className="table-message form-error">{error}</p>;
  }
  if (status === "ready" && emptyText !== undefined) {
    return <p className="table-message">{emptyText}</p>;
  }
  return null;
}
