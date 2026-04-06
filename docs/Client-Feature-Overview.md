# Event Booking Management — Feature Overview for Clients

This document explains what the **Event Booking Management** system does, in plain language. It is meant for stakeholders who will use or oversee the product, not for IT staff installing it.

---

## 1. What this system is for

The product is a **single place** to plan and run events at your institution. It helps you:

- Propose events and get them **officially approved**
- Coordinate **venue, IT, marketing, and transport** needs
- Keep a **calendar view** of what is happening
- Store **reports, budgets, and publications**
- Support **quality assurance (IQAC)** document collection
- **Message** the right people without leaving the application

Everything runs in a web browser. Users sign in with their **Vidyashilp account** (the same kind of login many people already use for email).

---

## 2. How people sign in and get access

| What happens | In simple terms |
|--------------|-----------------|
| **Sign-in** | The user clicks to log in with Google. No separate password is created for this system. |
| **First visit** | If someone is new, an account is created when they first sign in. |
| **Who can do what** | **Administrators** can assign each person a **role** (for example Faculty, Registrar, Facility Manager). That role controls which menus and actions they see. |
| **Planned access** | An admin can **add someone by email** before they ever log in. When that person signs in with Google, they automatically receive the role you chose. |

Certain email addresses can also be treated as **admin** automatically (configured in the system). That is useful for IT or leadership accounts.

---

## 3. User roles (who does what)

Below is a practical summary. Exact labels on screen may use slightly different wording (for example with underscores removed).

| Role (typical) | Main purpose |
|----------------|--------------|
| **Faculty** (and similar) | Create event requests, manage **my events**, connect calendar, use publications and IQAC uploads (where allowed), chat with others. |
| **Registrar** | **Approves or rejects** event requests, sees **approvals inbox**, uses **admin-style tools** with the admin role (user list, venues, reports across the institution). |
| **Admin** | Full **admin console**: users, venues, and visibility across events and related requests. |
| **Facility Manager** | Sees **requirements** meant for facilities (venue setup, refreshments, etc.) and can **accept or decline** those requests. |
| **Marketing** | Sees **marketing** requirements (posters, social media, photos, video, etc.) and can upload **deliverables** or mark items not applicable. |
| **IT** | Sees **IT** requirements (for example online/offline mode, PA system, projection) and can respond to requests. |
| **Transport** | Sees **transport** requests (guest transport, student transport, or both) and can process them. |
| **IQAC** | Focused access for **IQAC data collection**, including ability to manage uploads where policy allows. |

**Note:** Menu items such as **Approvals**, **Event Reports**, **Requirements**, **Admin Console**, and **IQAC Data Collection** only appear when that person’s role allows it. This avoids clutter and protects sensitive areas.

---

## 4. Main screens (the left-hand menu)

### 4.1 Dashboard

A **home** view when you open the application after login. It gives an at-a-glance picture of activity (statistics and summaries shown there are part of the product experience).

### 4.2 My Events

Where **event owners** work day to day:

- **Create** new events (after approval workflow where applicable).
- See **status** of each event. The system can show events as **upcoming**, **ongoing**, or **completed** based on date and time, and can treat some events as **closed** when that applies.
- **Attach or replace** important documents such as **budget breakdown** and **post-event report** (stored in a structured way, often linked to Google Drive for your organization).
- **Request services** from Facility, IT, Marketing, and Transport when the event is approved and the flow allows it.
- **Detect scheduling conflicts** when another event already uses the same venue and overlapping time (so double-booking is harder).


### 4.3 Event Reports

A **reporting-oriented** view of events and documentation. In the product, access is limited to roles that need institution-wide oversight (for example **admin** and **registrar**), not every faculty member.

### 4.4 Calendar View

Shows events in **calendar** form so you can see **when** things happen, not only lists. Users can **connect their Google Calendar** so approved events can be reflected in their own calendar (depending on how your organization configured Google).

### 4.5 Approvals

Used by the **Registrar** (or equivalent approver):

- See **incoming event requests** with full details: name, facilitator, venue, audience, dates, times, budget notes, attached budget file if provided, and any extra notes.
- **Approve** or **reject** requests.
- If the schedule **conflicts** with another event in the same venue, the system can **block approval** unless the situation is explicitly overridden—reducing accidental double bookings.

### 4.6 Requirements

Used by **Facility**, **Marketing**, **IT**, and **Transport** staff:

- Each team sees an **inbox** of requests assigned to them (or to their role’s email, depending on setup).
- They can **approve or decline** (or otherwise complete) their part of the workflow.
- **Marketing** can attach **deliverables** (files) or mark certain items as **not applicable**.

This screen is the operational “**work queue**” for support teams around events.

### 4.7 Publications

A dedicated area to **register and file publications** (for example web pages, journal articles, books, reports, videos, online newspapers). Users can:

- Enter **metadata** (titles, authors, dates, URLs, journal details, and so on—depending on publication type).
- **Upload** supporting files where needed.

This supports **research and visibility** reporting separate from a single event’s logistics.

### 4.8 IQAC Data Collection

For **accreditation and quality** documentation (structured around standard **NAAC-style criteria**—seven main areas with numbered sub-items):

- Browse a **tree** of criteria → sub-criteria → items.
- **Upload** evidence files (for example PDF or Word documents, within size limits set in the system).
- **List, download**, and (for authorized roles) **delete** files.

**Faculty** can typically **upload and view**; **IQAC, admin, and registrar** roles often have **broader** rights, including deletion where policy allows.

### 4.9 Admin Console

For **admin** and **registrar** (as implemented in the product):

- **User management**: list users, **add** users by email with a role, **change roles**.
- **Venue management**: maintain the list of **venues** that can be chosen when booking events.
- **Oversight** of events and related requests (approvals, facility, marketing, IT, transport, invites, publications) for operational and compliance visibility.

### 4.10 Preferences (sidebar)

The sidebar may show **Preferences** such as **User Management** and **Settings**. In the current product, some of these entries are **placeholders** for future or organizational customization—your implementation team can confirm what is active in your deployment.

### 4.11 Logout

Ends the session so the next person using the same device must sign in again.

---

## 5. The typical life of an event (step by step)

1. **Request** — A faculty member (or other authorized user) submits an **approval request** with event details, venue, schedule, audience, budget information, and optional files.
2. **Review** — The **Registrar** reviews the request in **Approvals**.
3. **Decision** — The request is **approved** or **rejected**. If there is a **venue/time conflict**, the system may require resolution before approval.
4. **Notification** — On approval, the requester may get an **email** explaining next steps.
5. **Requirements** — The event owner submits **facility, IT, marketing, and transport** needs. Each team works from its **Requirements** inbox.
6. **Execution** — Event runs; status moves from **upcoming** to **ongoing** to **completed** automatically based on dates/times (unless the event is marked **closed**).
7. **Closure** — **Reports** and any final uploads (for example post-event report) can be attached to the event record for audit and reporting.

Transport requests are typically created **after** registrar approval, aligned with the event record.

---

## 6. Built-in messaging (chat)

The application includes **in-app messaging**:

- **Direct** conversations between users.
- **Event-related** group-style threads involving the registrar, event creator, and relevant staff when appropriate.

Messages can include **file attachments** (within limits). This reduces reliance on scattered email threads for coordination **inside** the platform.

---

## 7. Connections to Google (Calendar, Gmail, Drive)

When your organization completes Google integration, users may:

- **Link Google Calendar** so events can appear on their calendar.
- **Send email** (invites, notifications) via **Gmail** on behalf of the signed-in user, where permissions allow.
- Store certain **files** (reports, budgets, publication uploads, marketing deliverables) in **Google Drive** using your institution’s folders and policies.

If calendar or Gmail is not connected, some actions will ask the user to **connect** or may be limited until an administrator fixes configuration.

---

## 8. Reliability and safety (non-technical summary)

- **Automatic status updates**: The system periodically **refreshes** event statuses (upcoming / ongoing / completed) so lists stay current without manual editing.
- **Rate limiting**: Login and some sensitive actions are **throttled** to reduce abuse (for example repeated automated attempts).
- **Secure headers**: The application uses standard **web security** settings to reduce common browser risks.
- **Request tracking**: Each server request can carry an **identifier** so support staff can trace issues if something goes wrong.

Your IT team holds details such as **where data is hosted**, **backup policy**, and **password / token** handling.

---

## 9. What we recommend you tell end users

1. Use **Chrome or another supported browser** and keep it updated.
2. Sign in with the **Google account** your institution expects (usually official email).
3. If a menu or button is **missing**, it is usually because of **role**—ask an admin to confirm your role.
4. For **IQAC** uploads, use **allowed file types** (typically PDF and Word) and stay within **size limits**.
5. For **reports and budgets**, follow any **naming rules** your registrar or admin communicates—the system may expect filenames tied to event name and date for consistency.

---

## 10. Glossary (short)

| Term | Meaning |
|------|---------|
| **Approval request** | A formal proposal for an event that needs registrar (or approver) sign-off before it becomes a full event. |
| **Requirement** | A sub-request to Facility, IT, Marketing, or Transport tied to an approved event. |
| **Venue** | A bookable location from the master list maintained in admin. |
| **Role** | The permission profile that decides which features a user sees. |
| **IQAC** | Internal Quality Assurance Cell—evidence collection for accreditation and quality review. |

---

## Document control

- **Purpose**: Client-facing description of product capabilities.  
- **Scope**: Reflects the application structure as implemented (web client + API).  
- **Updates**: When new features ship, this document should be revised in the same release cycle.

If you need a **one-page executive summary** or a **training checklist** by role, that can be derived from the sections above.
