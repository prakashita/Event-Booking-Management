import { useCallback } from "react";

export default function MessageInput({
  chatInput,
  chatFiles,
  disabled,
  onInputChange,
  onSend,
  onFileChange,
  onRemoveFile,
}) {
  const handleKeyDown = useCallback(
    (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        onSend();
      }
    },
    [onSend]
  );

  return (
    <div className="msger-composer">
      {chatFiles.length > 0 ? (
        <div className="msger-files">
          {chatFiles.map((file, idx) => (
            <div key={`${file.name}-${idx}`} className="msger-file">
              <span>{file.name}</span>
              <button
                type="button"
                className="msger-file-remove"
                onClick={() => onRemoveFile(idx)}
                aria-label={`Remove ${file.name}`}
              >
                &times;
              </button>
            </div>
          ))}
        </div>
      ) : null}
      <div className="msger-input-row">
        <label className="msger-attach" aria-label="Attach file">
          <input
            type="file"
            multiple
            onChange={onFileChange}
            disabled={disabled}
          />
          <svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48" />
          </svg>
        </label>
        <textarea
          value={chatInput}
          onChange={onInputChange}
          placeholder="Type a message..."
          rows={1}
          onKeyDown={handleKeyDown}
          className="msger-textarea"
        />
        <button
          type="button"
          className="msger-send"
          onClick={onSend}
          aria-label="Send message"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
            <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z" />
          </svg>
        </button>
      </div>
    </div>
  );
}
