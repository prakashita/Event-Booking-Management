export default function MessengerHeader({ onClose, onRefresh }) {
  return (
    <div className="msger-header">
      <div className="msger-header-left">
        <h3 className="msger-title">Messages</h3>
        <p className="msger-subtitle">Chats &amp; Conversations</p>
      </div>
      <div className="msger-header-actions">
        <button
          type="button"
          className="msger-header-btn"
          onClick={onRefresh}
          aria-label="Refresh conversations"
        >
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M23 4v6h-6M1 20v-6h6" />
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
          </svg>
        </button>
        <button
          type="button"
          className="msger-header-btn"
          onClick={onClose}
          aria-label="Close messenger"
        >
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M18 6L6 18M6 6l12 12" />
          </svg>
        </button>
      </div>
    </div>
  );
}
