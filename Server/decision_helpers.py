"""Shared validation for structured approval decisions (status + mandatory comment)."""

from fastapi import HTTPException, status

VALID_REQUIREMENT_DECISION_STATUSES = frozenset({"approved", "rejected", "clarification_requested"})
VALID_REGISTRAR_DECISION_STATUSES = frozenset({"approved", "rejected", "clarification_requested"})


def parse_requirement_decision_status(raw: str) -> str:
    s = (raw or "").strip().lower()
    if s not in VALID_REQUIREMENT_DECISION_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Status must be approved, rejected, or clarification_requested",
        )
    return s


def parse_registrar_decision_status(raw: str) -> str:
    s = (raw or "").strip().lower()
    if s not in VALID_REGISTRAR_DECISION_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Status must be approved, rejected, or clarification_requested",
        )
    return s


def require_decision_comment(comment_val: str | None) -> str:
    c = (comment_val or "").strip()
    if not c:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Comment is required.",
        )
    if len(c) > 4000:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Comment must be at most 4000 characters.",
        )
    return c


def action_type_for_status(status_norm: str) -> str:
    if status_norm == "approved":
        return "approve"
    if status_norm == "rejected":
        return "reject"
    return "clarification"
