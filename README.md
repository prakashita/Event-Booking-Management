# Event Booking Management

A full-stack event booking login experience with a React + Vite client and a
FastAPI + MongoDB backend. The app uses Google Sign-In to authenticate users,
stores user profiles in MongoDB, and returns a JWT for session use.

## Features
- Google Sign-In with domain allowlist
- JWT issuance on successful login
- MongoDB persistence via Beanie (Motor)
- Polished landing + login UI (React + Vite)

## Tech Stack
- Client: React, Vite
- Server: FastAPI, Beanie, Motor
- Auth: Google OAuth token validation + JWT
- Database: MongoDB

## Project Structure
```
Client/   # React + Vite frontend
Server/   # FastAPI backend
```

## Prerequisites
- Node.js 18+
- Python 3.10+
- MongoDB instance (local or cloud)
- Google OAuth Client ID

## Environment Variables

Server (.env in `Server/`):
```
MONGODB_URL=mongodb://localhost:27017/eventdb
DB_NAME=eventdb
SECRET_KEY=replace_me
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

## API

POST `/auth/google`
```
{ "token": "<google_id_token>" }
```
Returns:
```
{
  "access_token": "<jwt>",
  "user": { "id": "...", "name": "...", "email": "..." }
}
```
