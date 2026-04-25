import { useCallback, useEffect, useMemo, useState } from "react";
import { SimpleIcon } from "./icons";
import api from "../services/api";

const TEMPLATE_ICON_PATH = "M7 2h7l5 5v13a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2Zm6 2H7v16h10V8h-4V4Zm-3 8h4v2h-4v-2Zm0 4h5v2h-5v-2Z";
const DOWNLOAD_ICON_PATH = "M12 3a1 1 0 0 1 1 1v8.59l2.3-2.3 1.4 1.42-4.7 4.7-4.7-4.7 1.4-1.42 2.3 2.3V4a1 1 0 0 1 1-1ZM5 19h14v2H5v-2Z";

function formatBytes(n) {
  if (!n) return "";
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function getFileNameFromResponse(res, fallback) {
  const disposition = res.headers.get("content-disposition") || "";
  const utfMatch = disposition.match(/filename\*=UTF-8''([^;]+)/i);
  if (utfMatch?.[1]) {
    try {
      return decodeURIComponent(utfMatch[1]);
    } catch {
      return utfMatch[1];
    }
  }
  const basicMatch = disposition.match(/filename="?([^";]+)"?/i);
  return basicMatch?.[1] || fallback || "iqac-template";
}

export default function IqacTemplateDownloadCard() {
  const [templates, setTemplates] = useState([]);
  const [status, setStatus] = useState("loading");
  const [error, setError] = useState("");
  const [downloadingId, setDownloadingId] = useState("");

  const primaryTemplate = templates[0] || null;
  const hasMultipleTemplates = templates.length > 1;

  const loadTemplates = useCallback(async () => {
    setStatus("loading");
    setError("");
    try {
      const res = await api.get("/iqac/templates");
      const data = await res.json().catch(() => []);
      if (!res.ok) {
        throw new Error(data?.detail || "Unable to load IQAC templates");
      }
      setTemplates(Array.isArray(data) ? data : []);
      setStatus("ready");
    } catch (e) {
      setTemplates([]);
      setError(e?.message || "Unable to load IQAC templates");
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    loadTemplates();
  }, [loadTemplates]);

  const downloadTemplate = useCallback(async (template) => {
    if (!template?.downloadUrl || downloadingId) return;
    setDownloadingId(template.id || template.name || "template");
    setError("");
    try {
      const path = template.downloadUrl.startsWith("http")
        ? template.downloadUrl
        : `${api.getBaseUrl()}${template.downloadUrl.startsWith("/") ? template.downloadUrl : `/${template.downloadUrl}`}`;
      const res = await fetch(path, {
        headers: { Authorization: `Bearer ${api.getToken()}` },
        credentials: "include",
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data?.detail || "Template file is unavailable");
      }
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = getFileNameFromResponse(res, template.fileName || template.name);
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      setError(e?.message || "Template download failed");
    } finally {
      setDownloadingId("");
    }
  }, [downloadingId]);

  const cardMeta = useMemo(() => {
    if (status === "loading") return "Checking available template documents...";
    if (templates.length === 0) return "No template documents are available yet.";
    if (templates.length === 1) {
      const size = formatBytes(templates[0].size);
      return `${templates[0].type || "DOCX"}${size ? ` · ${size}` : ""}`;
    }
    return `${templates.length} template documents available`;
  }, [status, templates]);

  return (
    <section className="iqac-template-card" aria-labelledby="iqac-template-title">
      <div className="iqac-template-icon" aria-hidden="true">
        <SimpleIcon path={TEMPLATE_ICON_PATH} />
      </div>
      <div className="iqac-template-content">
        <div className="iqac-template-heading">
          <div>
            <h3 id="iqac-template-title">IQAC Data Templates</h3>
            <p>{cardMeta}</p>
          </div>
          <button
            type="button"
            className="primary-action iqac-template-primary"
            disabled={status === "loading" || !primaryTemplate || Boolean(downloadingId)}
            onClick={() => downloadTemplate(primaryTemplate)}
          >
            <SimpleIcon path={DOWNLOAD_ICON_PATH} />
            {downloadingId ? "Downloading..." : "Download Templates"}
          </button>
        </div>

        {error ? (
          <div className="iqac-template-message iqac-template-message--error" role="alert">
            <span>{error}</span>
            <button type="button" className="secondary-action" onClick={loadTemplates}>
              Retry
            </button>
          </div>
        ) : null}

        {status === "ready" && templates.length === 0 ? (
          <p className="iqac-template-message">Template documents will appear here once uploaded.</p>
        ) : null}

        {hasMultipleTemplates ? (
          <ul className="iqac-template-list">
            {templates.map((template) => {
              const isDownloading = downloadingId === (template.id || template.name);
              return (
                <li key={template.id || template.name} className="iqac-template-row">
                  <div>
                    <span className="iqac-template-name">{template.name}</span>
                    <span className="iqac-template-meta">
                      {template.type || "Document"}{template.size ? ` · ${formatBytes(template.size)}` : ""}
                    </span>
                  </div>
                  <button
                    type="button"
                    className="secondary-action"
                    disabled={Boolean(downloadingId)}
                    onClick={() => downloadTemplate(template)}
                  >
                    {isDownloading ? "Downloading..." : "Download"}
                  </button>
                </li>
              );
            })}
          </ul>
        ) : null}
      </div>
    </section>
  );
}
