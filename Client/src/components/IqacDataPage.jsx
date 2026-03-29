/**
 * IQAC Data Collection: criteria cards with sub-folder list and file counts;
 * drill-down via Open → modal (sub-folders → item tiles → file list/upload).
 */
import { useCallback, useEffect, useState } from "react";
import { SimpleIcon } from "./icons";
import { Modal } from "./ui";
import api from "../services/api";

const SUBFOLDERS_VISIBLE = 3; // show first N, then "... +M more sub-folders"

function formatBytes(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(iso) {
  if (!iso) return "—";
  try {
    const d = new Date(iso);
    return d.toLocaleDateString(undefined, { dateStyle: "short", timeStyle: "short" });
  } catch {
    return iso;
  }
}

// Folder icon (large for card header)
const FOLDER_PATH = "M4 5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5zm2 0v4h12V5H6zm0 6v8h12v-8H6z";
// Document icon for item tiles
const DOC_PATH = "M7 2h6l4 4v12a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2zm0 2v14h10V8h-4V4H7zm2 2h4v2H9V6z";

export default function IqacDataPage({ canDeleteIqacFiles = false }) {
  const [criteria, setCriteria] = useState([]);
  const [counts, setCounts] = useState({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [panel, setPanel] = useState(null);
  const [files, setFiles] = useState([]);
  const [filesLoading, setFilesLoading] = useState(false);
  const [uploadFile, setUploadFile] = useState(null);
  const [uploadDesc, setUploadDesc] = useState("");
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState("");

  const loadCriteria = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [critRes, countRes] = await Promise.all([
        api.get("/iqac/criteria"),
        api.get("/iqac/counts"),
      ]);
      if (!critRes.ok) throw new Error("Failed to load criteria");
      const data = await critRes.json();
      setCriteria(Array.isArray(data) ? data : []);
      setCounts((await countRes.json()) || {});
    } catch (e) {
      setError(e?.message || "Failed to load criteria");
      setCriteria([]);
      setCounts({});
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadCriteria();
  }, [loadCriteria]);

  const loadFiles = useCallback(async (criterion, subFolder, item) => {
    setFilesLoading(true);
    try {
      const res = await api.get(`/iqac/folders/${criterion}/${encodeURIComponent(subFolder)}/${encodeURIComponent(item)}/files`);
      if (!res.ok) throw new Error("Failed to load files");
      const data = await res.json();
      setFiles(Array.isArray(data) ? data : []);
    } catch {
      setFiles([]);
    } finally {
      setFilesLoading(false);
    }
  }, []);

  const getSubfolderCount = (criterionId, subId) => {
    const c = counts[String(criterionId)];
    if (!c || !c[subId]) return 0;
    return Object.values(c[subId]).reduce((a, n) => a + n, 0);
  };

  const getItemCount = (criterionId, subId, itemId) => {
    const c = counts[String(criterionId)];
    if (!c || !c[subId]) return 0;
    return c[subId][itemId] ?? 0;
  };

  const openCriterion = (c, action) => {
    const readOnly = action === "view";
    setPanel({
      step: "subfolders",
      criterion: c.id,
      title: c.title,
      subFolders: c.subFolders || [],
      readOnly,
    });
  };

  const openSubfolder = (sub) => {
    setPanel((prev) => ({
      ...prev,
      step: "items",
      subFolder: sub.id,
      subFolderTitle: sub.title,
      items: sub.items || [],
    }));
  };

  const openItem = (itemIdOrObj) => {
    const itemId = typeof itemIdOrObj === "string" ? itemIdOrObj : itemIdOrObj?.id;
    const itemTitle = typeof itemIdOrObj === "object" && itemIdOrObj?.title ? itemIdOrObj.title : itemId;
    setPanel((prev) => ({
      ...prev,
      step: "files",
      item: itemId,
      itemTitle,
    }));
    loadFiles(panel.criterion, panel.subFolder, itemId);
    setUploadFile(null);
    setUploadDesc("");
    setUploadError("");
  };

  const closePanel = () => {
    setPanel(null);
    setFiles([]);
  };

  const handleUpload = async (e) => {
    e.preventDefault();
    if (!uploadFile?.files?.[0] || !panel) return;
    setUploading(true);
    setUploadError("");
    const file = uploadFile.files[0];
    const form = new FormData();
    form.append("file", file);
    form.append("description", uploadDesc);
    try {
      const res = await api.post(
        `/iqac/folders/${panel.criterion}/${encodeURIComponent(panel.subFolder)}/${encodeURIComponent(panel.item)}/files`,
        form
      );
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || "Upload failed");
      }
      const added = await res.json();
      setFiles((prev) => [added, ...prev]);
      setUploadFile(null);
      setUploadDesc("");
      if (uploadFile.value) uploadFile.value = "";
      loadCriteria();
    } catch (e) {
      setUploadError(e?.message || "Upload failed");
    } finally {
      setUploading(false);
    }
  };

  const handleDelete = async (fileId) => {
    if (!canDeleteIqacFiles) return;
    if (!window.confirm("Delete this file?")) return;
    try {
      const res = await api.delete(`/iqac/files/${fileId}`);
      if (!res.ok) throw new Error("Delete failed");
      setFiles((prev) => prev.filter((f) => f.id !== fileId));
      loadCriteria();
    } catch {}
  };

  const getMimeType = (fileName) => {
    const ext = (fileName || "").toLowerCase().split(".").pop();
    if (ext === "pdf") return "application/pdf";
    if (ext === "doc") return "application/msword";
    if (ext === "docx") return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    return "application/octet-stream";
  };

  const handleView = (fileId, fileName) => {
    const token = api.getToken();
    const url = `${api.getBaseUrl()}/iqac/files/${fileId}/download`;
    if (!token) return;
    fetch(url, { headers: { Authorization: `Bearer ${token}` } })
      .then((r) => (r.ok ? r.blob() : null))
      .then(async (blob) => {
        if (!blob) return;
        const type = getMimeType(fileName);
        const viewBlob = type !== "application/octet-stream" ? new Blob([await blob.arrayBuffer()], { type }) : blob;
        const u = URL.createObjectURL(viewBlob);
        const w = window.open(u, "_blank", "noopener,noreferrer");
        if (w) setTimeout(() => URL.revokeObjectURL(u), 5000);
        else URL.revokeObjectURL(u);
      })
      .catch(() => {});
  };

  const handleDownload = (fileId, fileName) => {
    const token = api.getToken();
    const url = `${api.getBaseUrl()}/iqac/files/${fileId}/download`;
    if (token) {
      fetch(url, { headers: { Authorization: `Bearer ${token}` } })
        .then((r) => (r.ok ? r.blob() : null))
        .then((blob) => {
          if (!blob) return;
          const u = URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = u;
          a.download = fileName || "file";
          a.click();
          URL.revokeObjectURL(u);
        })
        .catch(() => {});
    } else {
      const a = document.createElement("a");
      a.href = url;
      a.download = fileName || "file";
      a.click();
    }
  };

  return (
    <div className="primary-column iqac-page">
      <header className="iqac-header">
        <div>
          <h2 className="iqac-title">IQAC Data Collection</h2>
          <p className="iqac-subtitle">Manage IQAC criteria folders and sub-folders (IQAC Committee Only)</p>
        </div>
      </header>

      {loading ? (
        <div className="iqac-loading">
          <p>Loading…</p>
        </div>
      ) : error ? (
        <div className="iqac-error">
          <p>{error}</p>
        </div>
      ) : (
        <section className="iqac-structure-section">
          <div className="iqac-structure-head">
            <h3 className="iqac-structure-title">IQAC Criteria Structure</h3>
            <span className="iqac-badge">🔒 IQAC Committee Only</span>
          </div>

          <div className="iqac-cards-grid">
            {criteria.map((c) => {
              const subFolders = c.subFolders || [];
              const visible = subFolders.slice(0, SUBFOLDERS_VISIBLE);
              const rest = subFolders.length - SUBFOLDERS_VISIBLE;
              return (
                <article key={c.id} className="iqac-criterion-card">
                  <div className="iqac-card-header">
                    <span className="iqac-card-folder-icon" aria-hidden="true">
                      <SimpleIcon path={FOLDER_PATH} />
                    </span>
                    <h4 className="iqac-card-title">Criterion {c.id}: {c.title}</h4>
                  </div>
                  <ul className="iqac-card-sub-list">
                    {visible.map((sub) => (
                      <li key={sub.id} className="iqac-card-sub-row">
                        <span className="iqac-card-sub-icon" aria-hidden="true">
                          <SimpleIcon path={FOLDER_PATH} />
                        </span>
                        <span className="iqac-card-sub-code">{sub.id}</span>
                        <span className="iqac-card-sub-name">{sub.title}</span>
                        <span className="iqac-card-sub-count">{getSubfolderCount(c.id, sub.id)}</span>
                      </li>
                    ))}
                    {rest > 0 && (
                      <li className="iqac-card-sub-more">... +{rest} more sub-folders</li>
                    )}
                  </ul>
                  <div className="iqac-card-actions">
                    <button
                      type="button"
                      className="iqac-btn iqac-btn-view"
                      onClick={() => openCriterion(c, "view")}
                      aria-label="View criterion"
                    >
                      <SimpleIcon path="M10.5 12a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0ZM12 3c4.97 0 9 3.134 9 7 0 2.5-1.5 4.75-3.8 6.2L15 18l-2.2-1.8C10.5 14.75 9 12.5 9 10c0-3.866 4.03-7 9-7Z" />
                      View
                    </button>
                    <button
                      type="button"
                      className="iqac-btn iqac-btn-open"
                      onClick={() => openCriterion(c, "open")}
                      aria-label="Open criterion"
                    >
                      <SimpleIcon path={FOLDER_PATH} />
                      Open
                    </button>
                  </div>
                </article>
              );
            })}
          </div>
        </section>
      )}

      {panel && (
        <Modal
          title={
            (panel.step === "subfolders"
              ? `Criterion ${panel.criterion}: ${panel.title}`
              : panel.step === "items"
                ? `${panel.subFolder}: ${panel.subFolderTitle}`
                : `${panel.subFolder} → ${panel.itemTitle ?? panel.item}`) +
            (panel.readOnly ? " (View only)" : "")
          }
          onClose={closePanel}
        >
          <div className="iqac-panel-body">
            {panel.step === "subfolders" && (
              <div className="iqac-subfolders">
                {(panel.subFolders || []).map((sub) => (
                  <button
                    key={sub.id}
                    type="button"
                    className="iqac-subfolder-btn"
                    onClick={() => openSubfolder(sub)}
                  >
                    <SimpleIcon path={FOLDER_PATH} />
                    {sub.id} — {sub.title}
                  </button>
                ))}
              </div>
            )}

            {panel.step === "items" && (
              <div className="iqac-items-tiles">
                {(panel.items || []).map((it) => {
                  const id = typeof it === "string" ? it : it?.id;
                  const title = typeof it === "object" && it?.title ? it.title : id;
                  const n = getItemCount(panel.criterion, panel.subFolder, id);
                  return (
                    <button
                      key={id}
                      type="button"
                      className="iqac-item-tile"
                      onClick={() => openItem(it)}
                    >
                      <span className="iqac-item-tile-icon">
                        <SimpleIcon path={DOC_PATH} />
                      </span>
                      <span className="iqac-item-tile-label">{id} {title}</span>
                      <span className="iqac-item-tile-count">{n} file{n !== 1 ? "s" : ""}</span>
                    </button>
                  );
                })}
              </div>
            )}

            {panel.step === "files" && (
              <div className="iqac-files-view">
                {panel.readOnly && (
                  <p className="iqac-readonly-hint">
                    You are viewing in read-only mode. Use <strong>Open</strong> on the card to upload files.
                    {canDeleteIqacFiles ? " You can delete files from there." : ""}
                  </p>
                )}
                {!panel.readOnly && (
                  <form className="iqac-upload-form" onSubmit={handleUpload}>
                    <div className="iqac-upload-row">
                      <input
                        type="file"
                        accept=".pdf,.doc,.docx"
                        ref={(el) => setUploadFile(el)}
                        onChange={() => setUploadError("")}
                      />
                      <input
                        type="text"
                        placeholder="Description (optional)"
                        value={uploadDesc}
                        onChange={(e) => setUploadDesc(e.target.value)}
                        className="iqac-upload-desc"
                      />
                      <button type="submit" className="primary-action" disabled={uploading || !uploadFile?.files?.[0]}>
                        {uploading ? "Uploading…" : "Upload"}
                      </button>
                    </div>
                    {uploadError && <p className="form-error iqac-upload-err">{uploadError}</p>}
                    <p className="form-hint">Max 10 MB. PDF, DOC, DOCX only.</p>
                  </form>
                )}

                {filesLoading ? (
                  <p className="iqac-files-loading">Loading…</p>
                ) : files.length === 0 ? (
                  <p className="iqac-files-empty">No documents uploaded yet.</p>
                ) : (
                  <ul className="iqac-file-list">
                    {files.map((f) => (
                      <li key={f.id} className="iqac-file-row">
                        <div className="iqac-file-info">
                          <span className="iqac-file-name">{f.fileName}</span>
                          <span className="iqac-file-meta">
                            {formatBytes(f.size)} · {formatDate(f.uploadedAt)}
                            {f.description ? ` · ${f.description}` : ""}
                          </span>
                        </div>
                        <div className="iqac-file-actions">
                          <button type="button" className="details-button iqac-btn-view-file" onClick={() => handleView(f.id, f.fileName)} title="Open in new tab">
                            View
                          </button>
                          <button type="button" className="details-button" onClick={() => handleDownload(f.id, f.fileName)}>
                            Download
                          </button>
                          {!panel.readOnly && canDeleteIqacFiles && (
                            <button type="button" className="details-button reject" onClick={() => handleDelete(f.id)}>
                              Delete
                            </button>
                          )}
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}
