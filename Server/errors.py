"""Shared error response helpers for consistent API error payloads."""

STATUS_TO_CODE = {
    400: "BAD_REQUEST",
    401: "UNAUTHORIZED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    409: "CONFLICT",
    422: "VALIDATION_ERROR",
    429: "RATE_LIMIT_EXCEEDED",
    500: "INTERNAL_ERROR",
    502: "BAD_GATEWAY",
}


def error_payload(detail, code: str, request_id: str, **extra) -> dict:
    """Standard error payload: { detail, code, request_id, ... }."""
    out = {"detail": detail, "code": code, "request_id": request_id}
    out.update(extra)
    return out
