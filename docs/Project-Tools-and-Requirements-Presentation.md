# Event Booking Management
## Tools and Requirements Presentation

Audience: Project team, organizational stakeholders, leadership
Purpose: Explain what tools we use, why they are needed, and what requirements they satisfy

---

## Slide 1: Title
### Event Booking Management
### Tools, Requirements, and Organizational Fit

- Prepared by: Project Team
- Date: [Fill before meeting]
- Meeting type: Project review and alignment

Speaker note:
- Set context: this is not just a tech update; this is a readiness and value explanation.

---

## Slide 2: Executive Summary

- We built a full workflow platform for institutional events, from request to closure.
- Tool choices were made to support scale, security, role-based operations, and auditability.
- Requirements are aligned with organizational needs: approvals, compliance (IQAC), transparency, and operational coordination.
- Current system reduces manual follow-up, duplicate tracking, and process delays.

Speaker note:
- Keep this short and outcome-focused.

---

## Slide 3: Problem We Are Solving

Before this system:
- Event workflows were fragmented across email, chat, and spreadsheets.
- Approval visibility was low.
- Support teams (Facility/IT/Marketing/Transport) had no single work queue.
- Report/publication/IQAC evidence tracking was inconsistent.

With this system:
- Unified event lifecycle in one platform.
- Approval and support workflows are traceable.
- Calendar, invites, reports, publications, and IQAC evidence are linked.

---

## Slide 4: Solution Scope (What the Platform Covers)

Core capabilities:
- Google sign-in and role-based access
- Event creation with conflict handling
- Registrar approval pipeline
- Facility/IT/Marketing/Transport requirement workflows
- Calendar integration, invites, chat
- Reports and publications management
- IQAC evidence collection by criterion
- Admin console for users/venues/oversight

Speaker note:
- Emphasize end-to-end coverage, not isolated modules.

---

## Slide 5: High-Level Architecture

- Client (Web): React + Vite
- Mobile app: Flutter
- Backend API: FastAPI
- Database: MongoDB (Beanie/Motor)
- Integrations: Google OAuth, Calendar, Gmail, Drive
- Realtime: WebSocket chat

Why this architecture:
- Fast development and UI agility
- Clear separation of concerns
- Scales independently by layer
- Works for both browser and mobile users

---

## Slide 6: Frontend Tools and Why We Need Them

Web:
- React 18 + Vite
  - Needed for fast UI iteration and modular component design.
- React Router
  - Needed for role-aware navigation and multi-module routing.

Mobile:
- Flutter + Dart
  - Needed for a single cross-platform codebase and consistent UX.
- go_router + Provider
  - Needed for predictable navigation and state management.

UI/UX libraries:
- Material 3 + design tokens/theme
  - Needed for consistency, accessibility, and maintainability.

---

## Slide 7: Backend Tools and Why We Need Them

- FastAPI
  - Needed for high-performance APIs, clear contract definitions, and easier maintenance.
- Pydantic
  - Needed for strict request/response validation.
- Beanie + Motor + MongoDB
  - Needed for flexible document models across events, approvals, and evidence workflows.
- APScheduler
  - Needed for periodic status updates and background operational tasks.
- SlowAPI rate limiting
  - Needed to protect auth and critical endpoints from abuse.

---

## Slide 8: Security and Access Tools

- Google OAuth + JWT
  - Needed for secure authentication and session control.
- Domain allowlist
  - Needed to restrict access to organizational accounts.
- Role-based authorization
  - Needed so each department sees only relevant actions.
- Secure storage and request guards
  - Needed to protect tokens and reduce unauthorized access risk.

Organizational benefit:
- Better control, accountability, and audit trail across teams.

---

## Slide 9: Operational and Collaboration Tools

- Google Calendar integration
  - Needed for schedule visibility and user adoption.
- Gmail integration
  - Needed for official communication and invite flows.
- Google Drive integration
  - Needed for managed file storage (reports, deliverables, publications).
- In-app chat (REST + WebSocket)
  - Needed for contextual communication tied to events.

---

## Slide 10: Functional Requirements (Project)

Must-have requirements implemented:
- Users can sign in with Google and receive role-specific access.
- Event creation supports conflict detection and approval routing.
- Registrar can approve/reject and trigger downstream actions.
- Department requests are created, routed, and tracked by status.
- Reports and publications are uploaded and retrievable.
- IQAC documentation is structured by criterion/sub-item.
- Admin can manage users, venues, and oversight dashboards.

---

## Slide 11: Non-Functional Requirements

- Reliability: background jobs for status refresh and consistent state.
- Performance: responsive API and paginated data flows.
- Security: auth, authorization, token checks, rate limits.
- Traceability: request IDs and action-level logging.
- Maintainability: modular backend routers and layered clients.
- Scalability: architecture supports independent growth per module.

---

## Slide 12: Organizational Requirements Mapping

Institutional needs addressed:
- Governance: registrar-led approval controls
- Operational coordination: department-specific queues
- Documentation and compliance: reports + IQAC evidence
- Transparency: role dashboards and status tracking
- Communication: integrated chat/invites

Key point:
- Tooling is selected to satisfy policy and process requirements, not only engineering preferences.

---

## Slide 13: Why These Tools vs Alternatives

Selection rationale:
- Speed to deliver with maintainable code
- Strong ecosystem and long-term support
- Lower operational friction for common workflows
- Easy onboarding for contributors

Trade-off summary:
- We accept moderate stack complexity to gain stronger workflow coverage and integration capability.

---

## Slide 14: Risks and Mitigation

Key risks:
- Google integration configuration errors
- Role misconfiguration and access confusion
- Data quality inconsistencies from manual fields
- Change management and user adoption

Mitigation:
- Deployment checklist and environment validation
- Admin role governance and clear SOPs
- Input validation and structured forms
- User training and role-based onboarding sessions

---

## Slide 15: Readiness for Upcoming Meeting

What we are ready to present:
- Architecture and tool choices
- Requirement coverage by module
- Security and compliance alignment
- Operational value for each department

What we need from stakeholders:
- Confirm timeline and rollout priorities
- Confirm role ownership matrix
- Confirm policy decisions for reporting and IQAC workflows

---

## Slide 16: Closing

- The platform is designed around institutional workflows, not generic event software.
- The selected tools are justified by security, compliance, and coordination requirements.
- Next step: finalize rollout sequence and governance owners.

Thank you.

---

## Optional Appendix A: Reference Modules

- Authentication and access
- Events and approvals
- Department requirements
- Calendar/invites/chat
- Reports/publications/IQAC
- Admin governance

---

## Optional Appendix B: Talking Points for Q&A

If asked “Why do we need this many tools?”
- Because each tool addresses a distinct risk: security, data integrity, workflow speed, compliance, or user adoption.

If asked “Can we simplify?”
- Yes, by phasing modules, but not by removing core controls like auth, approvals, and evidence management.

If asked “What is immediate value?”
- Faster approvals, fewer coordination gaps, and better documentation readiness for audits/accreditation.
