/**
 * Reusable modal shell with header, body, and optional actions.
 */
export default function Modal({ title, onClose, children, actions, className = "" }) {
  return (
    <div className="modal-overlay" role="dialog" aria-modal="true">
      <div className={`modal-card ${className}`.trim()}>
        <div className="modal-header">
          <h3>{title}</h3>
          <button type="button" className="modal-close" onClick={onClose} aria-label="Close">
            &times;
          </button>
        </div>
        {children}
        {actions ? <div className="modal-actions">{actions}</div> : null}
      </div>
    </div>
  );
}
