import { useCallback, useRef, useState, useEffect } from "react";
import { CHAT_FILE_INPUT_ACCEPT } from "../../constants/uploadConfig";

export default function MessageInput({
  chatInput,
  chatFiles,
  disabled,
  isUploading,
  onInputChange,
  onSend,
  onFileChange,
  onRemoveFile,
}) {
  const [attachOpen, setAttachOpen] = useState(false);
  const wrapRef = useRef(null);
  const fileInputRef = useRef(null);

  const handleKeyDown = useCallback(
    (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        onSend();
      }
    },
    [onSend]
  );

  useEffect(() => {
    if (!attachOpen) return;
    const close = (e) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) {
        setAttachOpen(false);
      }
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [attachOpen]);

  const triggerPick = useCallback(() => {
    setAttachOpen(false);
    fileInputRef.current?.click();
  }, []);

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
        {/* Single file input: images (JPEG, PNG, WebP) and PDF only */}
        <input
          ref={fileInputRef}
          type="file"
          accept={CHAT_FILE_INPUT_ACCEPT}
          multiple
          className="msger-file-input-hidden"
          aria-hidden
          tabIndex={-1}
          onChange={onFileChange}
        />
        <div className="msger-attach-wrap" ref={wrapRef}>
          <button
            type="button"
            className="msger-attach-btn"
            disabled={disabled || isUploading}
            aria-expanded={attachOpen}
            aria-haspopup="true"
            aria-label="Attach file"
            onClick={() => setAttachOpen((v) => !v)}
          >
            {isUploading ? (
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden
                className="msger-spinner"
              >
                <path d="M12 22C6.48 22 2 17.52 2 12S6.48 2 12 2" />
              </svg>
            ) : (
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                aria-hidden
              >
                <path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48" />
              </svg>
            )}
          </button>
          {attachOpen ? (
            <div className="msger-attach-menu" role="menu">
              <button
                type="button"
                role="menuitem"
                className="msger-attach-menu-item"
                onClick={triggerPick}
              >
                Upload image or PDF
              </button>
              <span className="msger-attach-menu-hint">
                JPEG, PNG, WebP, PDF · max 5 MB
              </span>
            </div>
          ) : null}
        </div>
        <textarea
          value={chatInput}
          onChange={onInputChange}
          placeholder={isUploading ? "Uploading…" : "Type a message..."}
          rows={1}
          onKeyDown={handleKeyDown}
          className="msger-textarea"
          disabled={disabled || isUploading}
        />
        <button
          type="button"
          className="msger-send"
          onClick={onSend}
          aria-label={isUploading ? "Uploading…" : "Send message"}
          disabled={disabled || isUploading}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
            <path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z" />
          </svg>
        </button>
      </div>
    </div>
  );
}
