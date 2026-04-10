/** Pure helpers for the event details modal (workflow + grouped requirements). */

export function aggregateRequirementStatuses(requests) {
  if (!Array.isArray(requests) || requests.length === 0) return "none";
  const statuses = requests.map((r) => String(r?.status || "").toLowerCase());
  if (statuses.some((s) => s === "rejected")) return "rejected";
  if (statuses.some((s) => s === "clarification_requested")) return "clarification_requested";
  if (statuses.some((s) => s === "pending")) return "pending";
  if (statuses.every((s) => s === "approved" || s === "accepted")) return "approved";
  return "pending";
}

export function formatModalDateTime(iso) {
  if (!iso) return null;
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return null;
    return d.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
  } catch {
    return null;
  }
}

function assigneeLine(requests) {
  if (!requests?.length) return null;
  const tos = [...new Set(requests.map((r) => r?.requested_to).filter(Boolean))];
  if (tos.length) return tos.join(", ");
  return null;
}

function latestDecidedAt(requests) {
  if (!requests?.length) return null;
  const dates = requests.map((r) => r?.decided_at).filter(Boolean);
  if (!dates.length) return null;
  return dates.reduce((a, b) => (new Date(a) > new Date(b) ? a : b));
}

export function buildWorkflowStepperSteps(details) {
  const event = details?.event;
  const ar = details?.approval_request;
  const facility = details?.facility_requests || [];
  const it = details?.it_requests || [];
  const marketing = details?.marketing_requests || [];

  let registrarStatus = "none";
  if (ar) {
    const s = String(ar.status || "").toLowerCase();
    if (s === "rejected") registrarStatus = "rejected";
    else if (s === "pending") registrarStatus = "pending";
    else if (s === "clarification_requested") registrarStatus = "clarification_requested";
    else registrarStatus = "approved";
  }

  let iqacStatus = "none";
  if (event?.report_web_view_link || event?.report_file_id) iqacStatus = "approved";
  else {
    const st = String(event?.status || "").toLowerCase();
    if (st && st !== "draft") iqacStatus = "pending";
  }

  return [
    {
      key: "registrar",
      label: "Registrar",
      status: registrarStatus,
      assignee: ar?.requested_to || ar?.decided_by || null,
      at: ar?.decided_at || null
    },
    {
      key: "facility",
      label: "Facility",
      status: aggregateRequirementStatuses(facility),
      assignee: assigneeLine(facility),
      at: latestDecidedAt(facility)
    },
    {
      key: "it",
      label: "IT",
      status: aggregateRequirementStatuses(it),
      assignee: assigneeLine(it),
      at: latestDecidedAt(it)
    },
    {
      key: "marketing",
      label: "Marketing",
      status: aggregateRequirementStatuses(marketing),
      assignee: assigneeLine(marketing),
      at: latestDecidedAt(marketing)
    },
    {
      key: "iqac",
      label: "IQAC",
      status: iqacStatus,
      assignee: event?.report_web_view_link || event?.report_file_id ? "Report on file" : null,
      at: event?.report_uploaded_at || null
    }
  ];
}

export function wfBadgeClass(status) {
  if (status === "approved") return "wf-badge wf-badge--approved";
  if (status === "pending") return "wf-badge wf-badge--pending";
  if (status === "clarification_requested") return "wf-badge wf-badge--clarification";
  if (status === "rejected") return "wf-badge wf-badge--rejected";
  return "wf-badge wf-badge--neutral";
}

export function wfBadgeLabel(status) {
  if (status === "approved") return "Approved";
  if (status === "pending") return "Pending";
  if (status === "clarification_requested") return "Clarification";
  if (status === "rejected") return "Rejected";
  return "—";
}

export function normalizeDecisionStatusForWf(status) {
  const x = String(status || "").toLowerCase();
  if (x === "none") return "none";
  if (x === "approved" || x === "accepted") return "approved";
  if (x === "rejected") return "rejected";
  if (x === "clarification_requested") return "clarification_requested";
  if (x === "pending") return "pending";
  return "pending";
}

export function formatWorkflowActionTypeLabel(actionType) {
  const t = String(actionType || "").toLowerCase();
  if (t === "approve") return "Approved";
  if (t === "reject") return "Rejected";
  if (t === "clarification") return "Need clarification";
  if (t === "reply" || t === "discussion_reply") return "Reply";
  return actionType || "—";
}

export function formatWorkflowRoleLabel(role) {
  const r = String(role || "").toLowerCase();
  const map = {
    registrar: "Registrar",
    requester: "Requester",
    faculty: "Faculty",
    facility_manager: "Facility",
    marketing: "Marketing",
    it: "IT",
    transport: "Transport",
    iqac: "IQAC"
  };
  return map[r] || role || "—";
}

/** Build nested discussion from flat logs when API threads are empty (backward compat). */
export function nestApprovalDiscussionFromLogs(logs, approvalRequestId) {
  if (!Array.isArray(logs) || !approvalRequestId) return [];
  const aid = String(approvalRequestId);
  const scoped = logs.filter(
    (l) =>
      (l.related_kind || "") === "approval_request" &&
      String(l.approval_request_id || "") === aid &&
      String(l.related_id || "") === aid
  );
  if (!scoped.length) return [];
  const byId = {};
  for (const l of scoped) {
    byId[l.id] = { ...l, replies: [] };
  }
  const roots = [];
  for (const l of scoped) {
    const node = byId[l.id];
    const pid = l.parent_id;
    if (pid && byId[pid]) {
      byId[pid].replies.push(node);
    } else {
      roots.push(node);
    }
  }
  const sortTree = (nodes) => {
    nodes.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
    for (const n of nodes) sortTree(n.replies || []);
  };
  sortTree(roots);
  return roots;
}

export function formatInboxDecisionStatusLabel(status) {
  const s = String(status || "").toLowerCase();
  if (s === "clarification_requested") return "Clarification";
  if (!s) return "—";
  return `${s.charAt(0).toUpperCase()}${s.slice(1)}`;
}

export function buildMarketingPhaseGroups(normalizedReq) {
  const n = normalizedReq;
  const phases = [
    { title: "Pre-Event", items: [] },
    { title: "During Event", items: [] },
    { title: "Post-Event", items: [] }
  ];
  if (n.pre_event.poster) phases[0].items.push("Poster");
  if (n.pre_event.social_media) phases[0].items.push("Social Media Post");
  if (n.during_event.photo) phases[1].items.push("Photoshoot");
  if (n.during_event.video) phases[1].items.push("Videoshoot");
  if (n.post_event.social_media) phases[2].items.push("Social Media Upload");
  if (n.post_event.photo_upload) phases[2].items.push("Photo Upload");
  if (n.post_event.video) phases[2].items.push("Video Upload");
  return phases.filter((p) => p.items.length > 0);
}

export function facilityRequestPhaseGroups(req) {
  const pre = [];
  if (req.venue_required) pre.push("Hall / venue booking");
  if (req.refreshments) pre.push("Refreshments");
  if (req.other_notes && String(req.other_notes).trim()) {
    pre.push(`Notes: ${String(req.other_notes).trim()}`);
  }
  if (!pre.length) pre.push("General facility coordination");
  return [{ title: "Pre-Event", items: pre }];
}

export function itRequestPhaseGroups(req) {
  const pre = [];
  if (req.event_mode) pre.push(`Event mode: ${req.event_mode}`);
  if (req.pa_system) pre.push("PA system");
  if (req.projection) pre.push("Projection / display");
  if (req.other_notes && String(req.other_notes).trim()) {
    pre.push(`Notes: ${String(req.other_notes).trim()}`);
  }
  if (!pre.length) pre.push("General IT support");
  return [{ title: "Pre-Event", items: pre }];
}

export function transportRequestPhaseGroups(req, typeLabel) {
  const pre = [typeLabel(req.transport_type)];
  if (req.other_notes && String(req.other_notes).trim()) {
    pre.push(`Notes: ${String(req.other_notes).trim()}`);
  }
  return [{ title: "Pre-Event", items: pre }];
}

const ROLE_TO_DEPT = {
  marketing: "marketing",
  facility_manager: "facility",
  it: "it",
  transport: "transport",
  iqac: "iqac"
};

export function viewerDepartmentKey(viewerRole) {
  return ROLE_TO_DEPT[String(viewerRole || "").toLowerCase()] || null;
}

export function orderDepartmentSectionsForRole(viewerRole, sections) {
  const first = viewerDepartmentKey(viewerRole);
  if (!first) return sections;
  const ix = sections.findIndex((s) => s.key === first);
  if (ix <= 0) return sections;
  const copy = [...sections];
  const [item] = copy.splice(ix, 1);
  return [item, ...copy];
}

function classifyRequirementLine(line) {
  const s = String(line || "").toLowerCase();
  if (/\bmarketing\b/.test(s) || s.includes("poster") || s.includes("social media")) return "marketing";
  if (/\bfacility\b/.test(s) || s.includes("venue") || s.includes("refreshment") || s.includes("hall")) {
    return "facility";
  }
  if (/\bit\b/.test(s) || s.includes("projection") || s.includes("pa system") || s.includes("laptop")) return "it";
  if (s.includes("transport")) return "transport";
  if (s.includes("iqac")) return "iqac";
  return null;
}

/**
 * When event details are not available, group legacy `requirements: string[]` on the approval record into
 * department-shaped sections for the same UI as the marketing event modal.
 */
export function buildRegistrarFallbackDeptSections(requirements) {
  if (!Array.isArray(requirements) || requirements.length === 0) return [];
  const buckets = { marketing: [], facility: [], it: [], transport: [], iqac: [] };
  const general = [];
  for (const line of requirements) {
    const k = classifyRequirementLine(line);
    if (k && buckets[k]) buckets[k].push(String(line));
    else general.push(String(line));
  }
  const out = [];
  const add = (key, title, iconKey, items) => {
    if (!items.length) return;
    out.push({
      key,
      title,
      iconKey,
      blocks: [
        {
          id: `${key}-fallback`,
          subtitle: null,
          requestedTo: null,
          phases: [{ title: "General", items: [...items] }],
          status: "pending",
          decidedBy: null,
          decidedAt: null,
          deliverables: []
        }
      ]
    });
  };
  add("marketing", "Marketing", "marketing", buckets.marketing);
  add("facility", "Facility", "facility", buckets.facility);
  add("it", "IT", "it", buckets.it);
  add("transport", "Transport", "transport", buckets.transport);
  add("iqac", "IQAC", "iqac", buckets.iqac);
  if (general.length) add("other", "Other", "facility", general);
  return out;
}

export function collectDepartmentRequirementSections(
  details,
  normalizeMarketingRequirements,
  transportTypeLabel
) {
  const sections = [];
  // Index dept_request_threads by related_request_id for O(1) look-up per block.
  const deptThreads = details?.dept_request_threads || [];
  const threadByRequestId = {};
  for (const t of deptThreads) {
    if (t.related_request_id) threadByRequestId[t.related_request_id] = t;
  }

  const marketing = details?.marketing_requests;
  if (marketing?.length) {
    sections.push({
      key: "marketing",
      title: "Marketing",
      iconKey: "marketing",
      blocks: marketing.map((req) => ({
        id: req.id,
        subtitle: marketing.length > 1 ? `To: ${req.requested_to || "Marketing desk"}` : null,
        phases: buildMarketingPhaseGroups(normalizeMarketingRequirements(req)),
        status: req.status,
        requestedTo: req.requested_to || null,
        decidedBy: req.decided_by,
        decidedAt: req.decided_at,
        deliverables: req.deliverables || [],
        requesterAttachments: req.requester_attachments || [],
        marketingRequest: req,
        discussionThread: threadByRequestId[req.id] || null
      }))
    });
  }

  const facility = details?.facility_requests;
  if (facility?.length) {
    sections.push({
      key: "facility",
      title: "Facility",
      iconKey: "facility",
      blocks: facility.map((req) => ({
        id: req.id,
        subtitle: facility.length > 1 ? `To: ${req.requested_to || "Facility"}` : null,
        phases: facilityRequestPhaseGroups(req),
        status: req.status,
        requestedTo: req.requested_to || null,
        decidedBy: req.decided_by,
        decidedAt: req.decided_at,
        deliverables: [],
        discussionThread: threadByRequestId[req.id] || null
      }))
    });
  }

  const it = details?.it_requests;
  if (it?.length) {
    sections.push({
      key: "it",
      title: "IT",
      iconKey: "it",
      blocks: it.map((req) => ({
        id: req.id,
        subtitle: it.length > 1 ? `To: ${req.requested_to || "IT"}` : null,
        phases: itRequestPhaseGroups(req),
        status: req.status,
        requestedTo: req.requested_to || null,
        decidedBy: req.decided_by,
        decidedAt: req.decided_at,
        deliverables: [],
        discussionThread: threadByRequestId[req.id] || null
      }))
    });
  }

  const transport = details?.transport_requests;
  if (transport?.length) {
    sections.push({
      key: "transport",
      title: "Transport",
      iconKey: "transport",
      blocks: transport.map((req) => ({
        id: req.id,
        subtitle: transport.length > 1 ? `To: ${req.requested_to || "Transport"}` : null,
        phases: transportRequestPhaseGroups(req, transportTypeLabel),
        status: req.status,
        requestedTo: req.requested_to || null,
        decidedBy: req.decided_by,
        decidedAt: req.decided_at,
        deliverables: [],
        discussionThread: threadByRequestId[req.id] || null
      }))
    });
  }

  const event = details?.event;
  const hasReport = Boolean(event?.report_web_view_link || event?.report_file_id);
  const eventIsDraft = String(event?.status || "").toLowerCase() === "draft";
  const iqacBlockStatus = hasReport ? "approved" : eventIsDraft ? "none" : "pending";
  sections.push({
    key: "iqac",
    title: "IQAC",
    iconKey: "iqac",
    blocks: [
      {
        id: "iqac-report",
        subtitle: null,
        requestedTo: null,
        phases: [
          {
            title: "Post-Event",
            items: hasReport
              ? ["Event report submitted"]
              : eventIsDraft
                ? ["Report expected after the event is finalized"]
                : ["Event report not uploaded yet"]
          }
        ],
        status: iqacBlockStatus,
        decidedBy: null,
        decidedAt: event?.report_uploaded_at || null,
        deliverables: [],
        reportLink: event?.report_web_view_link || null,
        reportName: event?.report_file_name || null
      }
    ]
  });

  return sections;
}
