# Event Booking Management

Full-stack event booking workflow with a React + Vite client and a FastAPI +
MongoDB backend. Users sign in with Google, create events, request approvals,
and route marketing/IT support requests, with optional Google Calendar sync.

## Features
- Google Sign-In with domain allowlist and JWT sessions
- Event scheduling with conflict detection + override
- Approval workflow with inbox/decision endpoints
- Marketing + IT request pipelines with decision tracking
- Venue management + seeding
  - Google OAuth connect for Calendar + Gmail send + Drive uploads
- Invite sending (Gmail API) with sent status tracking
- Single-page dashboard UI (React + FullCalendar)

## Tech Stack
- Client: React, Vite, FullCalendar
- Server: FastAPI, Beanie, Motor
- Auth: Google token validation + JWT
- Database: MongoDB

## Project Structure
```
Client/   # React + Vite frontend
Server/   # FastAPI backend
```

## Data Model (MongoDB Collections)
- `users`
  - `name`, `email`, `google_id`, `role`
  - `google_refresh_token`, `google_access_token`, `google_token_expiry`
- `venues`
  - `name`
- `events`
  - `name`, `facilitator`, `description`
  - `venue_name`, `start_date`, `start_time`, `end_date`, `end_time`
  - `created_by` (user id), `created_at`
- `approval_requests`
  - `requester_id` (user id), `requester_email`
  - `requested_to` (approver email)
  - event details + `requirements`, `other_notes`
  - `status`, `event_id`, `decided_at`, `decided_by`
- `marketing_requests`
  - `requester_id` (user id), `requester_email`
  - `requested_to` (marketing email)
  - event details + asset needs + `other_notes`
  - `status`, `decided_at`, `decided_by`
- `it_requests`
  - `requester_id` (user id), `requester_email`
  - `requested_to` (IT email)
  - event details + IT needs + `other_notes`
  - `status`, `decided_at`, `decided_by`
- `invites`
  - `event_id`, `created_by` (user id)
  - `to_email`, `subject`, `body`
  - `status`, `sent_at`, `created_at`

Notes:
- `created_by`, `requester_id`, and `event_id` are stored as string ids.
- Date/time values are stored as ISO strings in the database.
- Report uploads use the user's OAuth token; users must complete Google OAuth and have access to the Drive folder.

## Key Flows
- Sign-in:
  - Client uses Google Sign-In -> `POST /auth/google`
  - Server verifies token + allowed domain, upserts user, returns JWT
- Event creation:
  - Client checks conflicts via `POST /events/conflicts`
  - If no conflicts, creates event via `POST /events`
  - If conflicts, user can reschedule or override
- Approval workflow:
  - Client submits event with `submit_for_approval` -> `POST /events`
  - Server creates `approval_requests` entry (status `pending`)
  - Approver checks `GET /approvals/inbox` and decides via `PATCH /approvals/{id}`
  - On approval, server creates an `events` entry and links it via `event_id`
- Marketing/IT requests:
  - Client sends requests to `POST /marketing/requests` and `POST /it/requests`
  - Teams review via `GET /marketing/inbox` and `GET /it/inbox`
  - Decisions via `PATCH /marketing/requests/{id}` and `PATCH /it/requests/{id}`
- Google Calendar + Gmail:
  - Client calls `GET /calendar/connect-url` to start OAuth
  - OAuth scope includes Calendar create, Gmail send, and Drive file upload
  - Callback stores refresh/access tokens on the user
  - Client fetches `GET /calendar/events` for the calendar view
  - Client sends invites via `POST /invites`

## API Overview
Auth
- `POST /auth/google`

Venues
- `GET /venues`
- `POST /venues`
- `POST /venues/seed`

Events
- `GET /events`
- `POST /events`
- `POST /events/conflicts`

Approvals
- `GET /approvals/me`
- `GET /approvals/inbox`
- `PATCH /approvals/{request_id}`

Marketing
- `POST /marketing/requests`
- `GET /marketing/inbox`
- `PATCH /marketing/requests/{request_id}`

IT
- `POST /it/requests`
- `GET /it/inbox`
- `PATCH /it/requests/{request_id}`

Calendar
- `GET /calendar/connect-url`
- `GET /calendar/oauth/callback`
- `GET /calendar/events`

Invites
- `POST /invites`
- `GET /invites/me`

## Prerequisites
- Node.js 18+
- Python 3.10+
- MongoDB instance (local or cloud)
- Google OAuth Client ID
- Google OAuth Client Secret
- Gmail API enabled in the Google Cloud project

## Environment Variables

Server (.env in `Server/`):
```
MONGODB_URL=mongodb://localhost:27017/eventdb
DB_NAME=eventdb
SECRET_KEY=replace_me
GOOGLE_CLIENT_ID=your_google_client_id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your_google_client_secret
GOOGLE_REDIRECT_URI=http://localhost:8000/calendar/oauth/callback
```

Client (`Client/.env`):
```
VITE_API_BASE_URL=http://localhost:8000
VITE_GOOGLE_CLIENT_ID=your_google_client_id.apps.googleusercontent.com
```

Notes:
- The backend also accepts `DATABASE_URL` as an alternative to `MONGODB_URL`.
- Allowed email domains are hard-coded in `Server/auth.py` (default:
  `@srmap.edu.in`, `@vidyashilp.edu.in`). Update as needed.
- CORS origins are configured in `Server/main.py`.
- Reconnect Google OAuth after adding Calendar/Gmail/Drive scopes (new refresh token required).
- Enable Gmail API in Google Cloud Console for your project.

## Run Locally

Server:
```
cd Server
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

Client:
```
cd Client
npm install
npm run dev
```

Open `http://localhost:5173` in your browser.
