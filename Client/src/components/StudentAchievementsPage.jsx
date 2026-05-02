import { useCallback, useEffect, useMemo, useState } from "react";
import api from "../services/api";

const PLATFORM_OPTIONS = [
  { value: "LinkedIn", label: "LinkedIn" },
  { value: "Instagram", label: "Instagram" },
  { value: "YouTube", label: "YouTube" },
  { value: "VU Website", label: "VU Website" },
];

const emptyStudent = () => ({ student_name: "", batch: "", course: "" });

const emptyForm = () => ({
  students: [emptyStudent()],
  activity_description: "",
  additional_context_objective: "",
  suggested_platforms: [],
  social_media_writeup: "",
  attachments: [],
  iqac_criterion_id: "",
  iqac_subfolder_id: "",
  iqac_item_id: "",
  iqac_description: "",
});

function formatDateTime(value) {
  if (!value) return "--";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return date.toLocaleString("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

function getStudentName(student) {
  return student?.student_name || student?.name || "";
}

function studentLine(item) {
  const students = item?.students || [];
  if (!students.length) return "--";
  return students
    .map((student) => [getStudentName(student), student.batch, student.course].filter(Boolean).join(" - "))
    .join(", ");
}

function itemTitle(item) {
  const firstStudent = getStudentName(item?.students?.[0]);
  if (firstStudent) return `Student Achievement - ${firstStudent}`;
  return item?.achievement_title || "Student Achievement";
}

function toForm(item) {
  const students = (item?.students || [])
    .map((student) => ({
      student_name: getStudentName(student),
      batch: student.batch || "",
      course: student.course || "",
    }))
    .filter((student) => student.student_name || student.batch || student.course);

  return {
    students: students.length ? students : [emptyStudent()],
    activity_description: item?.activity_description || "",
    additional_context_objective: item?.additional_context_objective || "",
    suggested_platforms: Array.isArray(item?.suggested_platforms) ? item.suggested_platforms : [],
    social_media_writeup: item?.social_media_writeup || "",
    attachments: [],
    iqac_criterion_id: item?.iqac_criterion_id || "",
    iqac_subfolder_id: item?.iqac_subfolder_id || "",
    iqac_item_id: item?.iqac_item_id || "",
    iqac_description: item?.iqac_description || "",
  };
}

function buildIqacLabel(criteria, item) {
  if (!item?.iqac_criterion_id) return "--";
  const criterion = criteria.find((row) => String(row.id) === String(item.iqac_criterion_id));
  const sub = criterion?.subFolders?.find((row) => row.id === item.iqac_subfolder_id);
  const evidence = sub?.items?.find((row) => row.id === item.iqac_item_id);
  return [
    criterion ? `${criterion.id}. ${criterion.title}` : item.iqac_criterion_id,
    sub ? `${sub.id} ${sub.title}` : item.iqac_subfolder_id,
    evidence ? `${evidence.id} ${evidence.title}` : item.iqac_item_id,
  ]
    .filter(Boolean)
    .join(" / ");
}

export default function StudentAchievementsPage({ user }) {
  const [itemsState, setItemsState] = useState({ status: "idle", items: [], error: "" });
  const [criteriaState, setCriteriaState] = useState({ status: "idle", items: [], error: "" });
  const [createModal, setCreateModal] = useState({ open: false, status: "idle", error: "" });
  const [detailModal, setDetailModal] = useState({ open: false, mode: "view", item: null, status: "idle", error: "" });
  const [form, setForm] = useState(emptyForm);
  const [editForm, setEditForm] = useState(emptyForm);
  const [filters, setFilters] = useState({ search: "", platform: "", iqac_criterion_id: "" });
  const [actionState, setActionState] = useState({ id: null, error: "" });

  const role = String(user?.role || "").toLowerCase();
  const isAdmin = role === "admin";
  const canViewAll = isAdmin;
  const userId = String(user?.id || user?._id || "");

  const loadItems = useCallback(async () => {
    setItemsState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const params = new URLSearchParams();
      Object.entries(filters).forEach(([key, value]) => {
        if (value) params.set(key, value);
      });
      const suffix = params.toString() ? `?${params.toString()}` : "";
      const res = await api.get(`/student-achievements${suffix}`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.detail || "Unable to load student achievements.");
      setItemsState({ status: "ready", items: data.items || [], error: "" });
    } catch (err) {
      setItemsState({ status: "error", items: [], error: err?.message || "Unable to load student achievements." });
    }
  }, [filters]);

  const loadCriteria = useCallback(async () => {
    setCriteriaState((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await api.get("/student-achievements/iqac-criteria");
      const data = await res.json().catch(() => []);
      if (!res.ok) throw new Error(data?.detail || "Unable to load IQAC criteria.");
      setCriteriaState({ status: "ready", items: Array.isArray(data) ? data : [], error: "" });
    } catch (err) {
      setCriteriaState({ status: "error", items: [], error: err?.message || "Unable to load IQAC criteria." });
    }
  }, []);

  useEffect(() => {
    if (user) {
      loadItems();
      loadCriteria();
    }
  }, [loadItems, loadCriteria, user]);

  const totalCount = useMemo(() => itemsState.items.length, [itemsState.items]);

  const selectedCriterion = useCallback(
    (state) => criteriaState.items.find((row) => String(row.id) === String(state.iqac_criterion_id)),
    [criteriaState.items]
  );

  const selectedSubFolder = useCallback(
    (state) => selectedCriterion(state)?.subFolders?.find((row) => row.id === state.iqac_subfolder_id),
    [selectedCriterion]
  );

  const updateFormField = (setter, field) => (event) => {
    const value = event.target.value;
    setter((prev) => ({ ...prev, [field]: value }));
  };

  const updateFiles = (setter) => (event) => {
    setter((prev) => ({ ...prev, attachments: Array.from(event.target.files || []) }));
  };

  const updateStudent = (setter, index, field, value) => {
    setter((prev) => ({
      ...prev,
      students: prev.students.map((student, i) => (i === index ? { ...student, [field]: value } : student)),
    }));
  };

  const addStudent = (setter) => {
    setter((prev) => ({ ...prev, students: [...prev.students, emptyStudent()] }));
  };

  const removeStudent = (setter, index) => {
    setter((prev) => ({
      ...prev,
      students: prev.students.length > 1 ? prev.students.filter((_, i) => i !== index) : prev.students,
    }));
  };

  const togglePlatform = (setter, platform) => {
    setter((prev) => ({
      ...prev,
      suggested_platforms: prev.suggested_platforms.includes(platform)
        ? prev.suggested_platforms.filter((item) => item !== platform)
        : [...prev.suggested_platforms, platform],
    }));
  };

  const handleCriterionChange = (setter) => (event) => {
    setter((prev) => ({
      ...prev,
      iqac_criterion_id: event.target.value,
      iqac_subfolder_id: "",
      iqac_item_id: "",
    }));
  };

  const handleSubFolderChange = (setter) => (event) => {
    setter((prev) => ({ ...prev, iqac_subfolder_id: event.target.value, iqac_item_id: "" }));
  };

  const cleanedStudents = (state) =>
    state.students
      .map((student) => ({
        student_name: student.student_name.trim(),
        batch: student.batch.trim(),
        course: student.course.trim(),
      }))
      .filter((student) => student.student_name);

  const validateForm = (state) => {
    if (!cleanedStudents(state).length) return "Add at least one student name.";
    if (!state.activity_description.trim()) return "Description of Activity and Achievement is required.";
    return "";
  };

  const openCreateModal = () => {
    setForm(emptyForm());
    setCreateModal({ open: true, status: "idle", error: "" });
  };

  const closeCreateModal = () => {
    setCreateModal({ open: false, status: "idle", error: "" });
  };

  const submitAchievement = async (event) => {
    event.preventDefault();
    const validation = validateForm(form);
    if (validation) {
      setCreateModal((prev) => ({ ...prev, status: "error", error: validation }));
      return;
    }

    const fd = new FormData();
    fd.append("students", JSON.stringify(cleanedStudents(form)));
    fd.append("activity_description", form.activity_description.trim());
    fd.append("additional_context_objective", form.additional_context_objective.trim());
    fd.append("suggested_platforms", JSON.stringify(form.suggested_platforms));
    fd.append("social_media_writeup", form.social_media_writeup.trim());
    fd.append("iqac_criterion_id", form.iqac_criterion_id);
    fd.append("iqac_subfolder_id", form.iqac_subfolder_id);
    fd.append("iqac_item_id", form.iqac_item_id);
    fd.append("iqac_description", form.iqac_description.trim());
    form.attachments.forEach((file) => fd.append("attachments", file));

    setCreateModal((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const res = await api.post("/student-achievements", fd);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.detail || "Unable to submit student achievement.");
      closeCreateModal();
      await loadItems();
    } catch (err) {
      setCreateModal((prev) => ({ ...prev, status: "error", error: err?.message || "Unable to submit student achievement." }));
    }
  };

  const openDetail = async (item) => {
    setDetailModal({ open: true, mode: "view", item, status: "loading", error: "" });
    try {
      const res = await api.get(`/student-achievements/${item.id}`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.detail || "Unable to load submission.");
      setDetailModal({ open: true, mode: "view", item: data, status: "ready", error: "" });
    } catch (err) {
      setDetailModal({ open: true, mode: "view", item, status: "error", error: err?.message || "Unable to load submission." });
    }
  };

  const closeDetail = () => {
    setDetailModal({ open: false, mode: "view", item: null, status: "idle", error: "" });
  };

  const beginEdit = () => {
    setEditForm(toForm(detailModal.item));
    setDetailModal((prev) => ({ ...prev, mode: "edit", error: "" }));
  };

  const cancelEdit = () => {
    setDetailModal((prev) => ({ ...prev, mode: "view", error: "" }));
  };

  const submitEdit = async (event) => {
    event.preventDefault();
    const validation = validateForm(editForm);
    if (validation) {
      setDetailModal((prev) => ({ ...prev, status: "error", error: validation }));
      return;
    }
    setDetailModal((prev) => ({ ...prev, status: "loading", error: "" }));
    try {
      const fd = new FormData();
      fd.append("students", JSON.stringify(cleanedStudents(editForm)));
      fd.append("activity_description", editForm.activity_description.trim());
      fd.append("additional_context_objective", editForm.additional_context_objective.trim());
      fd.append("suggested_platforms", JSON.stringify(editForm.suggested_platforms));
      fd.append("social_media_writeup", editForm.social_media_writeup.trim());
      fd.append("iqac_criterion_id", editForm.iqac_criterion_id);
      fd.append("iqac_subfolder_id", editForm.iqac_subfolder_id);
      fd.append("iqac_item_id", editForm.iqac_item_id);
      fd.append("iqac_description", editForm.iqac_description.trim());
      editForm.attachments.forEach((file) => fd.append("attachments", file));
      const res = await api.patch(`/student-achievements/${detailModal.item.id}`, fd);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.detail || "Unable to update submission.");
      setDetailModal({ open: true, mode: "view", item: data, status: "ready", error: "" });
      setItemsState((prev) => ({ ...prev, items: prev.items.map((row) => (row.id === data.id ? data : row)) }));
    } catch (err) {
      setDetailModal((prev) => ({ ...prev, status: "error", error: err?.message || "Unable to update submission." }));
    }
  };

  const deleteItem = async () => {
    const item = detailModal.item;
    if (!item || !window.confirm("Delete this student achievement submission?")) return;
    setActionState({ id: item.id, error: "" });
    try {
      const res = await api.delete(`/student-achievements/${item.id}`);
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.detail || "Unable to delete submission.");
      setItemsState((prev) => ({ ...prev, items: prev.items.filter((row) => row.id !== item.id) }));
      setActionState({ id: null, error: "" });
      closeDetail();
    } catch (err) {
      setActionState({ id: null, error: err?.message || "Unable to delete submission." });
    }
  };

  const renderForm = (state, setter, onSubmit, submitLabel, options = {}) => {
    const criterion = selectedCriterion(state);
    const subFolder = selectedSubFolder(state);
    return (
      <form className="student-achievement-form" onSubmit={onSubmit}>
        <section className="student-form-block">
          <div className="student-form-section-head">
            <div>
              <h4>Students</h4>
              <p>Add every student who should be credited in the post.</p>
            </div>
            <button type="button" className="secondary-action" onClick={() => addStudent(setter)}>
              Add Student
            </button>
          </div>
          <div className="student-rows">
            {state.students.map((student, index) => (
              <div key={index} className="student-row">
                <label className="form-field">
                  <span>Student Name</span>
                  <input
                    value={student.student_name}
                    onChange={(event) => updateStudent(setter, index, "student_name", event.target.value)}
                    required={index === 0}
                  />
                </label>
                <label className="form-field">
                  <span>Batch</span>
                  <input value={student.batch} onChange={(event) => updateStudent(setter, index, "batch", event.target.value)} />
                </label>
                <label className="form-field">
                  <span>Course</span>
                  <input value={student.course} onChange={(event) => updateStudent(setter, index, "course", event.target.value)} />
                </label>
                <button
                  type="button"
                  className="details-button reject"
                  onClick={() => removeStudent(setter, index)}
                  disabled={state.students.length === 1}
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        </section>

        <label className="form-field">
          <span>Description of Activity and Achievement</span>
          <textarea
            rows="5"
            value={state.activity_description}
            onChange={updateFormField(setter, "activity_description")}
            required
          />
        </label>
        <label className="form-field">
          <span>Additional Details</span>
          <textarea
            rows="5"
            value={state.additional_context_objective}
            onChange={updateFormField(setter, "additional_context_objective")}
            placeholder="Context and objective of the activity"
          />
        </label>
        <div className="student-platforms">
          <span>Suggested Platforms to Post</span>
          <div>
            {PLATFORM_OPTIONS.map((platform) => (
              <label key={platform.value}>
                <input
                  type="checkbox"
                  checked={state.suggested_platforms.includes(platform.value)}
                  onChange={() => togglePlatform(setter, platform.value)}
                />
                <span>{platform.label}</span>
              </label>
            ))}
          </div>
        </div>
        <label className="form-field">
          <span>Social Media Write-up</span>
          <textarea rows="5" value={state.social_media_writeup} onChange={updateFormField(setter, "social_media_writeup")} />
        </label>
        {!options.hideFileUpload ? (
          <label className="form-field student-file-field">
            <span>Images and Attachments/Documents</span>
            <input type="file" multiple accept="image/*,.pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx" onChange={updateFiles(setter)} />
            {state.attachments?.length ? (
              <small>{state.attachments.length} file{state.attachments.length === 1 ? "" : "s"} selected</small>
            ) : null}
          </label>
        ) : null}
        <section className="student-form-block">
          <h4>Relevant IQAC Criterion</h4>
          {criteriaState.status === "error" ? <p className="form-error">{criteriaState.error}</p> : null}
          <div className="student-iqac-grid">
            <label className="form-field">
              <span>Criterion</span>
              <select value={state.iqac_criterion_id} onChange={handleCriterionChange(setter)}>
                <option value="">Select criterion</option>
                {criteriaState.items.map((row) => (
                  <option key={row.id} value={String(row.id)}>
                    {row.id}. {row.title}
                  </option>
                ))}
              </select>
            </label>
            <label className="form-field">
              <span>Subfolder</span>
              <select value={state.iqac_subfolder_id} onChange={handleSubFolderChange(setter)} disabled={!criterion}>
                <option value="">Select subfolder</option>
                {(criterion?.subFolders || []).map((row) => (
                  <option key={row.id} value={row.id}>
                    {row.id} {row.title}
                  </option>
                ))}
              </select>
            </label>
            <label className="form-field">
              <span>Item</span>
              <select
                value={state.iqac_item_id}
                onChange={updateFormField(setter, "iqac_item_id")}
                disabled={!subFolder}
              >
                <option value="">Select item</option>
                {(subFolder?.items || []).map((row) => (
                  <option key={row.id} value={row.id}>
                    {row.id} {row.title}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <label className="form-field">
            <span>IQAC Description</span>
            <input value={state.iqac_description} onChange={updateFormField(setter, "iqac_description")} />
          </label>
        </section>
        {options.error ? <p className="form-error">{options.error}</p> : null}
        <div className="modal-actions">
          {options.onCancel ? (
            <button type="button" className="secondary-action" onClick={options.onCancel}>
              Cancel
            </button>
          ) : null}
          <button type="submit" className="primary-action student-submit-action" disabled={options.loading}>
            {options.loading ? "Saving..." : submitLabel}
          </button>
        </div>
      </form>
    );
  };

  const detailItem = detailModal.item;
  const isOwner = detailItem?.created_by && detailItem.created_by === userId;
  const canEditDetail = Boolean(detailItem && isOwner && !isAdmin);

  return (
    <div className="primary-column student-achievements-page">
      <section className="student-achievements-header">
        <div>
          <p className="student-achievements-kicker">Institutional Communication</p>
          <h2>Students' Achievements</h2>
          <p>Submit student achievement material for institutional website and social media visibility.</p>
        </div>
        <button type="button" className="primary-action student-submit-top" onClick={openCreateModal}>
          Submit Student Achievement
        </button>
      </section>

      <section className="student-achievements-toolbar">
        <input
          type="search"
          value={filters.search}
          onChange={(event) => setFilters((prev) => ({ ...prev, search: event.target.value }))}
          placeholder="Search student, batch, course, description"
        />
        <select value={filters.platform} onChange={(event) => setFilters((prev) => ({ ...prev, platform: event.target.value }))}>
          <option value="">All platforms</option>
          {PLATFORM_OPTIONS.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}
        </select>
        <select
          value={filters.iqac_criterion_id}
          onChange={(event) => setFilters((prev) => ({ ...prev, iqac_criterion_id: event.target.value }))}
        >
          <option value="">All IQAC criteria</option>
          {criteriaState.items.map((item) => (
            <option key={item.id} value={String(item.id)}>{item.id}. {item.title}</option>
          ))}
        </select>
        <button type="button" className="secondary-action" onClick={loadItems}>Refresh</button>
      </section>

      {actionState.error ? <p className="form-error">{actionState.error}</p> : null}

      <section className="student-achievements-list">
        <div className="student-achievements-list-head">
          <h3>{canViewAll ? "All submissions" : "My submissions"}</h3>
          <span>{totalCount} record{totalCount === 1 ? "" : "s"}</span>
        </div>
        {itemsState.status === "loading" ? <p className="table-message">Loading student achievements...</p> : null}
        {itemsState.status === "error" ? <p className="table-message">{itemsState.error}</p> : null}
        {itemsState.status === "ready" && !itemsState.items.length ? (
          <p className="table-message">No student achievements found.</p>
        ) : null}
        {itemsState.items.map((item) => (
          <article key={item.id} className="student-achievement-card">
            <div className="student-achievement-main">
              <div>
                <h3>{itemTitle(item)}</h3>
                <p>{studentLine(item)}</p>
              </div>
              <button type="button" className="details-button" onClick={() => openDetail(item)}>
                View
              </button>
            </div>
            <dl className="student-achievement-meta">
              <div><dt>Platforms</dt><dd>{(item.suggested_platforms || []).join(", ") || "--"}</dd></div>
              <div><dt>IQAC</dt><dd>{buildIqacLabel(criteriaState.items, item)}</dd></div>
              <div><dt>Submitted by</dt><dd>{item.created_by_name || item.created_by_email || "--"}</dd></div>
              <div><dt>Created</dt><dd>{formatDateTime(item.created_at)}</dd></div>
            </dl>
            <p className="student-achievement-caption">{item.activity_description || "No description supplied."}</p>
          </article>
        ))}
      </section>

      {createModal.open ? (
        <div className="modal-overlay" role="dialog" aria-modal="true">
          <div className="modal-card student-achievement-modal">
            <div className="modal-header">
              <div>
                <h3>Submit Student Achievement</h3>
                <p className="form-hint">Use this for non-event institutional publicity inputs.</p>
              </div>
              <button type="button" className="modal-close" onClick={closeCreateModal}>&times;</button>
            </div>
            {renderForm(form, setForm, submitAchievement, "Submit Student Achievement", {
              onCancel: closeCreateModal,
              loading: createModal.status === "loading",
              error: createModal.status === "error" ? createModal.error : "",
            })}
          </div>
        </div>
      ) : null}

      {detailModal.open ? (
        <div className="modal-overlay" role="dialog" aria-modal="true">
          <div className="modal-card student-achievement-modal">
            <div className="modal-header">
              <div>
                <h3>{detailModal.mode === "edit" ? "Edit Student Achievement" : itemTitle(detailItem)}</h3>
                <p className="form-hint">Submitted {formatDateTime(detailItem?.created_at)}</p>
              </div>
              <button type="button" className="modal-close" onClick={closeDetail}>&times;</button>
            </div>
            {detailModal.status === "loading" && detailModal.mode === "view" ? (
              <p className="table-message">Loading submission...</p>
            ) : null}
            {detailModal.mode === "edit" ? (
              renderForm(editForm, setEditForm, submitEdit, "Save Changes", {
                onCancel: cancelEdit,
                loading: detailModal.status === "loading",
                error: detailModal.status === "error" ? detailModal.error : "",
              })
            ) : detailItem ? (
              <div className="student-detail-view">
                {detailModal.status === "error" ? <p className="form-error">{detailModal.error}</p> : null}
                <section>
                  <h4>Students</h4>
                  <div className="student-detail-table">
                    <div className="student-detail-row student-detail-row-head">
                      <span>Student Name</span>
                      <span>Batch</span>
                      <span>Course</span>
                    </div>
                    {(detailItem.students || []).map((student, index) => (
                      <div className="student-detail-row" key={`${getStudentName(student)}-${index}`}>
                        <span>{getStudentName(student) || "--"}</span>
                        <span>{student.batch || "--"}</span>
                        <span>{student.course || "--"}</span>
                      </div>
                    ))}
                  </div>
                </section>
                <section>
                  <h4>Description</h4>
                  <p>{detailItem.activity_description || "--"}</p>
                </section>
                <section>
                  <h4>Additional Details</h4>
                  <p>{detailItem.additional_context_objective || "--"}</p>
                </section>
                <section>
                  <h4>Selected Platforms</h4>
                  <p>{(detailItem.suggested_platforms || []).join(", ") || "--"}</p>
                </section>
                <section>
                  <h4>Social Media Write-up</h4>
                  <p>{detailItem.social_media_writeup || "--"}</p>
                </section>
                <section>
                  <h4>Attachments</h4>
                  <div className="student-achievement-files">
                    {(detailItem.attachments || []).length ? (
                      detailItem.attachments.map((file) => (
                        <button
                          key={file.file_id || file.file_name}
                          type="button"
                          className="pub-action-btn pub-action-file"
                          onClick={() => file.web_view_link && window.open(file.web_view_link, "_blank", "noopener,noreferrer")}
                        >
                          {file.file_name}
                        </button>
                      ))
                    ) : (
                      <span>--</span>
                    )}
                  </div>
                </section>
                <section>
                  <h4>IQAC Criterion</h4>
                  <p>{buildIqacLabel(criteriaState.items, detailItem)}</p>
                  {detailItem.iqac_description ? <p className="student-detail-note">{detailItem.iqac_description}</p> : null}
                </section>
                <dl className="student-achievement-meta student-detail-audit">
                  <div><dt>Created by</dt><dd>{detailItem.created_by_name || detailItem.created_by_email || "--"}</dd></div>
                  <div><dt>Created at</dt><dd>{formatDateTime(detailItem.created_at)}</dd></div>
                  <div><dt>Last updated by</dt><dd>{detailItem.updated_by_name || detailItem.updated_by_email || "--"}</dd></div>
                  <div><dt>Updated at</dt><dd>{formatDateTime(detailItem.updated_at)}</dd></div>
                </dl>
                <div className="modal-actions">
                  <button type="button" className="secondary-action" onClick={closeDetail}>Close</button>
                  {canEditDetail ? (
                    <button type="button" className="primary-action" onClick={beginEdit}>Edit</button>
                  ) : null}
                  {isAdmin ? (
                    <button
                      type="button"
                      className="details-button reject"
                      onClick={deleteItem}
                      disabled={actionState.id === detailItem.id}
                    >
                      Delete
                    </button>
                  ) : null}
                </div>
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  );
}
