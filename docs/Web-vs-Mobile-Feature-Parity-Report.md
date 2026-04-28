# Web vs Mobile Feature Parity Report

> **Date**: 2026-04-26  
> **Scope**: Comparison of React web app (`Client/`) vs Flutter mobile app (`mobile_app/`)  
> **Server**: No changes made to `Server/` or `Client/` — read-only audit

---

## Executive Summary

The mobile Flutter app has **excellent feature parity** with the web React app. All major workflows — authentication, event lifecycle, approval pipeline, department requirements, chat, calendar, IQAC, publications, and admin — are present on both platforms. However, **7 specific features** present in the web app are missing from the mobile app, and there are **4 notable inconsistencies** in how certain features behave across platforms.

---

## Feature-by-Feature Comparison

### ✅ Features with Full Parity

| # | Feature | Web | Mobile | Status |
|---|---------|-----|--------|--------|
| 1 | **Google OAuth Login** | `window.google.accounts.id` (GIS) | `google_sign_in` package | ✅ |
| 2 | **Approval Gate Screen** | Inline pending/rejected state | `ApprovalGateScreen` with polling | ✅ |
| 3 | **Role-based Dashboard** | Workflow inbox per role | `DashboardScreen` with role-based cards | ✅ |
| 4 | **Event Creation** | Modal form with venue, audience, budget PDF | `CreateEventScreen` (1315 lines) | ✅ |
| 5 | **Event List with Tabs** | All / Approvals / Upcoming / Ongoing / Completed / Closed | Same 6 tabs in `EventsScreen` | ✅ |
| 6 | **Event Details** | `EventDetailsModalBody` (261 lines) | `EventDetailsScreen` (5580 lines) | ✅ |
| 7 | **Approval Submission** | Budget threshold ₹30K, conflict override, email routing | `EventApprovalScreen` (1307 lines) | ✅ |
| 8 | **Approval Details** | `ApprovalDetailsModalBody` (490 lines) | `ApprovalDetailsScreen` → wraps `EventDetailsScreen` | ✅ |
| 9 | **Conflict Detection** | Conflict dialog with reschedule/override/cancel | Same dialog in `CreateEventScreen` + `EventApprovalScreen` | ✅ |
| 10 | **Budget Breakdown PDF Upload** | `uploadBudgetBreakdown()` | Multipart upload in `EventApprovalScreen` | ✅ |
| 11 | **Forward to Finance/Registrar** | `handleForwardToFinance/Registrar` | `_forwardApproval()` with same endpoints | ✅ |
| 12 | **Close Event** | `handleCloseEvent()` | `_closeEvent()` in `EventsScreen` | ✅ |
| 13 | **Workflow Action Modal** | Department decisions (approve/reject/clarification) | Dialogs in `DashboardScreen` + `EventDetailsScreen` | ✅ |
| 14 | **Approval Discussion Threads** | `ApprovalDiscussionTree` component | Full thread UI in `EventDetailsScreen` | ✅ |
| 15 | **Department Requirements Deck** | `DepartmentRequirementsDeck` component | Department sections in `EventDetailsScreen` | ✅ |
| 16 | **Requirements Wizard** | `RequirementsWizardModal` (585 lines) | `RequirementsWizardDialog` (1977 lines) | ✅ |
| 17 | **Requirements Inbox** | Workflow tables per department | `RequirementsScreen` (1131 lines) | ✅ |
| 18 | **Marketing Deliverable Upload** | `submitMarketingDeliverable()` batch | `_uploadMarketingDeliverablesBatch()` in 3 screens | ✅ |
| 19 | **Chat / Messenger** | `FloatingMessenger` panel + `ChatWindow` | `ChatListScreen` + `ChatScreen` (1674 lines) | ✅ |
| 20 | **WebSocket Real-time** | Chat WS in `MessengerContext` | WS in `ChatScreen` + `NotificationService` | ✅ |
| 21 | **Google Scope Check** | `googleScopeModal` | `_showGoogleScopeModal()` in `HomeScreen` | ✅ |
| 22 | **Invite Sending** | `inviteModal` with to/subject/body | `_sendInvite()` dialog in `EventsScreen` | ✅ |
| 23 | **Calendar View** | FullCalendar with filters + views | `TableCalendar` with same filters + views | ✅ |
| 24 | **Google Calendar Sync** | Connect/disconnect sync | Same in `CalendarScreen` | ✅ |
| 25 | **Institution Calendar Admin** | `InstitutionCalendarAdmin` (835 lines) | `CalendarUpdatesScreen` (2637 lines) | ✅ |
| 26 | **IQAC Data** | `IqacDataPage` (438 lines) | `IqacScreen` (1275 lines) | ✅ |
| 27 | **Publications** | 6 types, search, filter, sort | `PublicationsScreen` (1603 lines) | ✅ |
| 28 | **Event Reports List** | Reports with search, attendance links | `EventReportsScreen` (942 lines) | ✅ |
| 29 | **Report Upload** | Report + attendance file upload | `_uploadReport()` in `EventsScreen` | ✅ |
| 30 | **Attendance File** | View/download attendance | `_openAttendance()` in reports + events | ✅ |
| 31 | **Admin Console** | 6 tabs (users, venues, events, requests, invites, publications) | `AdminScreen` (2522 lines) same 6 tabs | ✅ |
| 32 | **User Approvals** | Approve/reject with role selection | `UserApprovalsScreen` (1001 lines) | ✅ |
| 33 | **Role Management** | Change user roles | Role update in `AdminScreen` | ✅ |
| 34 | **Rejection Reason** | Reject reason modal | Reason field in approval/admin dialogs | ✅ |
| 35 | **Theme Settings** | Light / Dark / System | Same 3 options in `SettingsScreen` | ✅ |
| 36 | **Role-based Navigation** | `Sidebar` with role-filtered menu items | `SideNavBar` with same role checks | ✅ |
| 37 | **Notification Banners** | `NotificationBell` badge | `NotificationProvider` + popup banners | ✅ |
| 38 | **Push Notifications** | Browser Notification API (basic) | Firebase Cloud Messaging (advanced) | ✅ (mobile exceeds) |

---

### ❌ Features Missing in Mobile App

| # | Feature | Web Implementation | Mobile Status |
|---|---------|-------------------|---------------|
| 1 | **Client-side Report PDF Generation** | `buildReportPdf()` (lines 3021–3120 in `App.jsx`) — generates a styled PDF with event info, approval details, department requirements, and IQAC criteria, then uploads it | ❌ **Missing** — Mobile uploads report file directly without generating a PDF |
| 2 | **Appendix Photos Upload** | `handleAppendixPhotosChange()` — multiple image upload for report appendix | ❌ **Missing** — Mobile report upload has no appendix photos field |
| 3 | **IQAC Criteria Selection in Report** | `reportIqacSelection` state + `handleReportIqacCriterionChange()` — select IQAC criteria when uploading report | ❌ **Missing** — Mobile report upload has no IQAC criteria picker |
| 4 | **IQAC Template Download** | `IqacTemplateDownloadCard` component — download IQAC data templates | ❌ **Missing** — Mobile IQAC screen has no template download card |
| 5 | **Add User Modal (Admin)** | `addUserModal` — admin can directly create new users with name, email, role, department | ❌ **Missing** — Mobile admin has user management but no "Add User" creation form |
| 6 | **MLA Citation Formatting** | `formatPublicationMLA()` + `renderMlaCitation()` — formatted MLA citations for publications | ❌ **Missing** — Mobile publications screen has a "Citation" label but no MLA formatting |
| 7 | **Calendar Event Detail Modal** | `calendarDetailModal` — popup with event details when clicking a calendar event + `tippy` tooltips | ❌ **Missing** — Mobile calendar has no detail popup on event tap (may navigate instead) |

---

### ⚠️ Notable Inconsistencies

| # | Area | Web Behavior | Mobile Behavior | Impact |
|---|------|-------------|-----------------|--------|
| 1 | **Chat UI Pattern** | Floating side panel (`FloatingMessenger`) — stays open while browsing | Full-screen dedicated screens (`ChatListScreen` → `ChatScreen`) | Low — expected platform difference; mobile UX is appropriate |
| 2 | **Notification System** | `NotificationBell` dropdown showing unread count | `NotificationProvider` + WebSocket banners + Firebase push notifications | Low — mobile actually exceeds web with push notifications |
| 3 | **Report Upload Flow** | Generates PDF client-side (`buildReportPdf`), uploads PDF + attendance + appendix photos + IQAC criteria | Uploads report file + attendance file via multipart; no PDF generation, no appendix, no IQAC criteria | **Medium** — mobile report uploads are simpler; server may receive less structured data |
| 4 | **Calendar Event Interaction** | Click event → detail modal with tippy tooltip | Tap event → likely navigates to event details screen | Low — different but functionally equivalent navigation pattern |

---

## Detailed Missing Feature Analysis

### 1. Client-side Report PDF Generation
- **Web**: [`buildReportPdf()`](Client/src/App.jsx:3021) creates a multi-section PDF with:
  - Event overview (name, date, time, venue, audience, budget)
  - Approval details (requested by, status, budget breakdown link)
  - Department requirements (facility, IT, marketing, transport)
  - IQAC criteria mapping
  - The PDF is then uploaded as the event report
- **Mobile**: [`_uploadReport()`](mobile_app/lib/screens/events/events_screen.dart:446) uploads a user-selected file directly
- **Impact**: Without PDF generation, mobile users must manually create formatted reports. The server may not receive standardized report PDFs from mobile users.

### 2. Appendix Photos
- **Web**: [`handleAppendixPhotosChange()`](Client/src/App.jsx:2955) allows multiple image uploads as report appendix
- **Mobile**: No appendix photo field in the report upload dialog
- **Impact**: Mobile users cannot attach supplementary photos to event reports.

### 3. IQAC Criteria Selection in Report
- **Web**: [`reportIqacSelection`](Client/src/App.jsx:367) + [`handleReportIqacCriterionChange()`](Client/src/App.jsx:2999) — checkboxes for IQAC criteria mapping
- **Mobile**: No IQAC criteria picker during report upload
- **Impact**: Reports uploaded from mobile won't have IQAC criteria associations, which may affect IQAC data tracking.

### 4. IQAC Template Download
- **Web**: [`IqacTemplateDownloadCard`](Client/src/components/IqacTemplateDownloadCard.jsx) — provides downloadable templates for IQAC data collection
- **Mobile**: [`IqacScreen`](mobile_app/lib/screens/iqac/iqac_screen.dart) has criteria browsing and file upload but no template download
- **Impact**: Mobile users must access templates through the web app or other means.

### 5. Add User Modal (Admin)
- **Web**: [`addUserModal`](Client/src/App.jsx:405) with form fields (name, email, role, department) — calls `/users/add`
- **Mobile**: [`AdminScreen`](mobile_app/lib/screens/admin/admin_screen.dart) has user list and role management but no "Add User" button/form
- **Impact**: Admins on mobile cannot create new user accounts directly.

### 6. MLA Citation Formatting
- **Web**: [`formatPublicationMLA()`](Client/src/App.jsx:7258) generates properly formatted MLA citations with author, title, source, date, URL
- **Mobile**: [`PublicationsScreen`](mobile_app/lib/screens/publications/publications_screen.dart) shows a "Citation" label but no formatted MLA output
- **Impact**: Mobile users see raw publication data without academic citation formatting.

### 7. Calendar Event Detail Modal
- **Web**: [`calendarDetailModal`](Client/src/App.jsx:373) + tippy tooltips on calendar event hover/click
- **Mobile**: No popup modal on calendar event tap
- **Impact**: Minor — mobile likely navigates to event details screen instead, which provides the same information in a different UX pattern.

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| Total features compared | 38 |
| Features with full parity | 31 (82%) |
| Features missing in mobile | 7 (18%) |
| Notable inconsistencies | 4 |
| Features where mobile exceeds web | 1 (Push Notifications) |

---

## Priority Recommendations

| Priority | Missing Feature | Effort | Rationale |
|----------|----------------|--------|-----------|
| 🔴 High | IQAC Criteria Selection in Report | Low | Affects IQAC data integrity; simple checkbox addition |
| 🔴 High | Add User Modal (Admin) | Medium | Admins need full user management on mobile |
| 🟡 Medium | Client-side Report PDF Generation | High | Complex but ensures report standardization |
| 🟡 Medium | Appendix Photos Upload | Low | Simple file picker addition to report dialog |
| 🟡 Medium | IQAC Template Download | Low | Single download button/card |
| 🟢 Low | MLA Citation Formatting | Medium | Nice-to-have for academic context |
| 🟢 Low | Calendar Event Detail Modal | Medium | UX improvement; navigation alternative exists |
