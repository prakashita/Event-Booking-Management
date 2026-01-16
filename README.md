# Event Booking Management

This repo contains a React (Vite) frontend and a FastAPI backend. The backend
now uses MongoDB via Beanie/Motor and supports Google sign-in.

## What changed so far

- Merged the upstream repo changes into this project.
- Switched the backend from SQLite/SQLAlchemy to MongoDB/Beanie.
- Added async DB initialization on app startup and clean shutdown on app stop.
- Updated backend auth to load `SECRET_KEY` from `.env`.
- Added Mongo dependencies to `Server/requirements.txt`.
- Added `Server/.env` with `MONGODB_URL`, `SECRET_KEY`, and `DB_NAME`.
- Removed upstream deployment/docs files and cleaned the comparison folder.

## Project structure

- `Client/` - React + Vite frontend
  - `src/App.jsx`, `src/main.jsx`, `src/styles.css`
- `Server/` - FastAPI backend
  - `main.py` - app setup, CORS, and lifespan hooks
  - `database.py` - Mongo connection and Beanie init
  - `models.py` - Beanie document models
  - `routers/auth.py` - Google auth endpoint
  - `auth.py` - JWT helpers and Google token verification

## Requirements

- Python 3.12+
- Node.js 18+
- MongoDB Atlas or local MongoDB instance

## Backend setup

1) Create `Server/.env` (already added locally). It should look like:

```
MONGODB_URL=mongodb+srv://<user>:<password>@<cluster>/<db>
SECRET_KEY=CHANGE_ME_LATER
DB_NAME=eventdb
```

2) Install backend dependencies:

```
cd Server
pip install -r requirements.txt
```

3) Run the API:

```
uvicorn main:app --reload
```

API runs at `http://127.0.0.1:8000`.

## Frontend setup

1) Install frontend dependencies:

```
cd Client
npm install
```

2) Run the dev server:

```
npm run dev
```

Frontend runs at `http://localhost:5173`.

## Environment variables

Frontend (optional):

- `VITE_API_BASE_URL` (default `http://localhost:8000`)
- `VITE_GOOGLE_CLIENT_ID` (fallback is hard-coded in `Client/src/App.jsx`)

Backend:

- `MONGODB_URL` or `DATABASE_URL` (Mongo connection string)
- `SECRET_KEY` (JWT signing key)
- `DB_NAME` (defaults to `eventdb` if not in URL)

## Notes

- The Google auth endpoint is `POST /auth/google` and expects:

```
{ "token": "<google_id_token>" }
```

- Allowed domains are configured in `Server/auth.py`.
- CORS is configured in `Server/main.py`.

