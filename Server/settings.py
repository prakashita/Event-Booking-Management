import os
from dataclasses import dataclass
from typing import List

from dotenv import load_dotenv


load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))


def _csv_to_list(value: str | None) -> List[str]:
    if not value:
        return []
    return [item.strip() for item in value.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    app_env: str
    mongodb_url: str
    db_name: str
    secret_key: str
    log_level: str
    request_id_header: str
    cors_origins: list[str]
    cors_origin_regex: str


def load_settings() -> Settings:
    app_env = (os.getenv("APP_ENV", "development") or "development").strip().lower()
    mongodb_url = (os.getenv("MONGODB_URL") or os.getenv("DATABASE_URL") or "").strip()
    db_name = (os.getenv("DB_NAME") or "eventdb").strip()
    secret_key = (os.getenv("SECRET_KEY") or "").strip()
    log_level = (os.getenv("LOG_LEVEL") or "INFO").strip().upper()
    request_id_header = (os.getenv("REQUEST_ID_HEADER") or "X-Request-ID").strip()
    cors_origin_regex = (
        os.getenv("CORS_ORIGIN_REGEX") or r"^https:\/\/[a-z0-9-]+\.netlify\.app$"
    ).strip()

    default_origins = [
        "http://localhost:5173",
        "https://event-booking-management.netlify.app",
        "https://delicate-rolypoly-9e3ca2.netlify.app",
    ]
    cors_origins = _csv_to_list(os.getenv("CORS_ORIGINS")) or default_origins

    errors: list[str] = []
    if not mongodb_url:
        errors.append("MONGODB_URL or DATABASE_URL is required")
    if not secret_key:
        errors.append("SECRET_KEY is required")
    if app_env in {"staging", "production"} and secret_key == "CHANGE_ME_LATER":
        errors.append("SECRET_KEY must not be default in staging/production")
    if log_level not in {"CRITICAL", "ERROR", "WARNING", "INFO", "DEBUG"}:
        errors.append("LOG_LEVEL must be one of CRITICAL/ERROR/WARNING/INFO/DEBUG")

    if errors:
        raise RuntimeError("Invalid configuration:\n- " + "\n- ".join(errors))

    return Settings(
        app_env=app_env,
        mongodb_url=mongodb_url,
        db_name=db_name,
        secret_key=secret_key,
        log_level=log_level,
        request_id_header=request_id_header,
        cors_origins=cors_origins,
        cors_origin_regex=cors_origin_regex,
    )
