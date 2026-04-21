"""Migration: reclassify approval-thread conversations that were incorrectly
stored with department="registrar" when the clarification was actually
triggered by a deputy_registrar or finance_team approver.

Root cause fixed in this migration:
  PATCH /approvals/{id} always called ensure_approval_thread_chat with
  department="registrar" even when pipeline_stage was "deputy" or "finance".
  This caused all three stage threads to share the same conversation record,
  leaking history across stages.

Strategy (migration-safe):
  1. Find all ChatConversation docs with thread_kind="approval_thread" and
     department="registrar".
  2. For each, look up the WorkflowActionLog entries where
       action_type="clarification_requested"
       approval_request_id = conversation.approval_request_id
       role IN ("deputy_registrar", "finance_team")
     and created_at <= conversation.created_at + 60s  (allow clock skew).
  3. If exactly one such log exists and it predates or matches the thread
     creation timestamp, re-label the conversation's department to the role
     value ("deputy_registrar" or "finance_team") and update its title.
  4. If zero such logs exist → the thread was correctly created at the
     registrar stage; leave it alone.
  5. If more than one such log matches → ambiguous; log a warning and skip
     (operator can resolve manually via admin API).

Run with:
    python -m migrations.migrate_approval_thread_departments

or from the Server/ directory:
    python migrations/migrate_approval_thread_departments.py
"""

import asyncio
import logging
from datetime import datetime, timedelta, timezone

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("migration.approval_thread_dept")

# ---- Stage-to-dept-key mapping (mirrors event_chat_service.STAGE_TO_DEPT_KEY) ----
STAGE_ROLES_TO_DEPT = {
    "deputy_registrar": "deputy_registrar",
    "finance_team": "finance_team",
}

DEPT_LABELS = {
    "deputy_registrar": "Deputy Registrar",
    "finance_team": "Finance",
    "registrar": "Registrar",
}

CLOCK_SKEW_SECONDS = 120  # allow threads created up to 2 min before the audit log


async def run_migration(dry_run: bool = False) -> None:
    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

    from database import init_db
    await init_db()

    from models import ChatConversation, WorkflowActionLog

    # 1. Fetch all approval_thread conversations with department="registrar"
    candidates = await ChatConversation.find(
        {
            "thread_kind": "approval_thread",
            "department": "registrar",
        }
    ).to_list()

    logger.info("Found %d approval_thread conversations with department='registrar'", len(candidates))

    reclassified = 0
    skipped_ambiguous = 0
    skipped_correct = 0

    for conv in candidates:
        ar_id = conv.approval_request_id
        if not ar_id:
            logger.warning("  Conversation %s has no approval_request_id — skipping", conv.id)
            continue

        # 2. Find clarification logs for this approval from a sub-registrar stage
        logs = await WorkflowActionLog.find(
            {
                "approval_request_id": ar_id,
                "action_type": "clarification_requested",
                "role": {"$in": list(STAGE_ROLES_TO_DEPT.keys())},
            }
        ).sort("created_at").to_list()

        if not logs:
            skipped_correct += 1
            logger.debug(
                "  Conv %s (approval %s): no sub-stage clarification log found — correctly "
                "labelled as registrar thread, skipping.",
                conv.id, ar_id,
            )
            continue

        # Only consider logs that happened at or before the thread was created
        # (plus clock-skew allowance) to avoid matching future logs from a later
        # re-clarification that would correctly use the new dept key.
        conv_ts = conv.created_at
        if conv_ts and conv_ts.tzinfo is None:
            conv_ts = conv_ts.replace(tzinfo=timezone.utc)
        cutoff = (conv_ts or datetime.now(timezone.utc)) + timedelta(seconds=CLOCK_SKEW_SECONDS)

        matching = [
            lg for lg in logs
            if lg.created_at and (
                lg.created_at.replace(tzinfo=timezone.utc)
                if lg.created_at.tzinfo is None
                else lg.created_at
            ) <= cutoff
        ]

        if not matching:
            skipped_correct += 1
            logger.debug(
                "  Conv %s: clarification logs exist but are all newer than thread creation — "
                "thread may have been manually created at registrar stage.",
                conv.id,
            )
            continue

        if len(matching) > 1:
            skipped_ambiguous += 1
            logger.warning(
                "  AMBIGUOUS — Conv %s (approval %s): %d sub-stage clarification logs match. "
                "Roles: %s. Manual review required.",
                conv.id, ar_id, len(matching), [lg.role for lg in matching],
            )
            continue

        # Exactly one match — safe to reclassify
        log = matching[0]
        new_dept = STAGE_ROLES_TO_DEPT[log.role]
        new_label = DEPT_LABELS[new_dept]

        # Reconstruct a sensible title if current title says "Registrar clarification"
        old_title = conv.title or ""
        if "registrar clarification" in old_title.lower():
            new_title = old_title.lower().replace(
                "registrar clarification",
                f"{new_label} clarification",
            ).capitalize()
            # Preserve original capitalisation
            new_title = old_title.replace(
                old_title.split("–")[0].strip(),
                f"{new_label} clarification",
            )
        else:
            new_title = old_title  # keep custom titles unchanged

        logger.info(
            "  [%s] Conv %s (approval %s): department 'registrar' → '%s' (log role=%s, log_id=%s)",
            "DRY-RUN" if dry_run else "RECLASSIFY",
            conv.id, ar_id, new_dept, log.role, log.id,
        )

        if not dry_run:
            conv.department = new_dept
            if new_title != old_title:
                conv.title = new_title
            # Tag for audit trail
            conv.migrated_from_dept = "registrar"
            conv.migrated_at = datetime.now(timezone.utc)
            await conv.save()

        reclassified += 1

    logger.info(
        "\nMigration complete (dry_run=%s):\n"
        "  Reclassified : %d\n"
        "  Skipped (correct registrar threads): %d\n"
        "  Skipped (ambiguous, manual review needed): %d",
        dry_run, reclassified, skipped_correct, skipped_ambiguous,
    )


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Reclassify misidentified approval thread departments")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be changed without saving to the database",
    )
    args = parser.parse_args()
    asyncio.run(run_migration(dry_run=args.dry_run))
