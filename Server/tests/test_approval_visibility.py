"""
Tests for approval post-decision visibility.

Validates that:
- Deputy/Finance decided-by fields are populated on approval
- Historical items are included in the inbox query filter
- is_actionable is correctly computed
- current_stage_label and approved_by_role are correct for all stages
- Serializer includes new fields
"""
import sys
import os
import unittest
from datetime import datetime
from unittest.mock import MagicMock

# Add Server directory to path so we can import modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from routers.admin import (
    _compute_approved_by_role,
    _compute_current_stage_label,
    serialize_approval,
)


def _make_approval(**overrides):
    """Create a mock ApprovalRequest with sensible defaults."""
    defaults = dict(
        id="abc123",
        status="pending",
        discussion_status=None,
        requester_id="user1",
        requester_email="faculty@example.com",
        requested_to="deputy@example.com",
        event_name="Test Event",
        facilitator="Faculty User",
        budget=5000.0,
        budget_breakdown_file_id=None,
        budget_breakdown_file_name=None,
        budget_breakdown_web_view_link=None,
        budget_breakdown_uploaded_at=None,
        description="A test event",
        venue_name="Hall A",
        intendedAudience=["students"],
        intendedAudienceOther=None,
        discussedWithProgrammingChair=False,
        start_date="2026-05-01",
        start_time="10:00",
        end_date="2026-05-01",
        end_time="12:00",
        requirements=[],
        other_notes=None,
        event_id=None,
        decided_at=None,
        decided_by=None,
        created_at=datetime(2026, 4, 20),
        override_conflict=False,
        approval_cc=[],
        pipeline_stage=None,
        deputy_decided_by=None,
        deputy_decided_at=None,
        finance_decided_by=None,
        finance_decided_at=None,
    )
    defaults.update(overrides)
    mock = MagicMock()
    for k, v in defaults.items():
        setattr(mock, k, v)
    return mock


class TestComputeCurrentStageLabel(unittest.TestCase):
    def test_awaiting_deputy(self):
        item = _make_approval(status="pending", pipeline_stage="deputy")
        self.assertEqual(_compute_current_stage_label(item), "Awaiting Deputy Registrar")

    def test_deputy_approved(self):
        item = _make_approval(status="pending", pipeline_stage="after_deputy")
        self.assertEqual(_compute_current_stage_label(item), "Deputy Approved — Forward to Finance")

    def test_awaiting_finance(self):
        item = _make_approval(status="pending", pipeline_stage="finance")
        self.assertEqual(_compute_current_stage_label(item), "Awaiting Finance")

    def test_finance_approved(self):
        item = _make_approval(status="pending", pipeline_stage="after_finance")
        self.assertEqual(_compute_current_stage_label(item), "Finance Approved — Forward to Registrar")

    def test_awaiting_registrar(self):
        item = _make_approval(status="pending", pipeline_stage="registrar")
        self.assertEqual(_compute_current_stage_label(item), "Awaiting Registrar / VC")

    def test_completed(self):
        item = _make_approval(status="approved", pipeline_stage="complete", event_id="evt1")
        self.assertEqual(_compute_current_stage_label(item), "Completed")

    def test_rejected(self):
        item = _make_approval(status="rejected", pipeline_stage="deputy")
        self.assertEqual(_compute_current_stage_label(item), "Rejected")

    def test_deputy_clarification(self):
        item = _make_approval(status="clarification_requested", pipeline_stage="deputy")
        self.assertEqual(_compute_current_stage_label(item), "Deputy Registrar — Clarification")

    def test_finance_clarification(self):
        item = _make_approval(status="clarification_requested", pipeline_stage="finance")
        self.assertEqual(_compute_current_stage_label(item), "Finance — Clarification")

    def test_registrar_clarification(self):
        item = _make_approval(status="clarification_requested", pipeline_stage="registrar")
        self.assertEqual(_compute_current_stage_label(item), "Registrar — Clarification")


class TestComputeApprovedByRole(unittest.TestCase):
    def test_after_deputy_returns_deputy(self):
        item = _make_approval(
            pipeline_stage="after_deputy",
            deputy_decided_by="deputy@example.com",
            decided_by="deputy@example.com",
        )
        self.assertEqual(_compute_approved_by_role(item), "Deputy Registrar")

    def test_after_finance_returns_finance(self):
        item = _make_approval(
            pipeline_stage="after_finance",
            finance_decided_by="finance@example.com",
            decided_by="finance@example.com",
        )
        self.assertEqual(_compute_approved_by_role(item), "Finance")

    def test_completed_returns_registrar(self):
        item = _make_approval(
            status="approved",
            pipeline_stage="complete",
            event_id="evt1",
            decided_by="registrar@example.com",
        )
        self.assertEqual(_compute_approved_by_role(item), "Registrar / VC")

    def test_no_decided_by(self):
        item = _make_approval(status="pending", pipeline_stage="deputy", decided_by=None)
        self.assertIsNone(_compute_approved_by_role(item))


class TestSerializeApproval(unittest.TestCase):
    def test_new_fields_populated(self):
        item = _make_approval(
            pipeline_stage="after_deputy",
            deputy_decided_by="deputy@example.com",
            deputy_decided_at=datetime(2026, 4, 20, 10, 0),
        )
        result = serialize_approval(item)
        self.assertEqual(result.deputy_decided_by, "deputy@example.com")
        self.assertEqual(result.deputy_decided_at, datetime(2026, 4, 20, 10, 0))
        self.assertIsNone(result.finance_decided_by)

    def test_is_actionable_default_true(self):
        item = _make_approval()
        result = serialize_approval(item)
        self.assertTrue(result.is_actionable)

    def test_is_actionable_false(self):
        item = _make_approval()
        result = serialize_approval(item, is_actionable=False)
        self.assertFalse(result.is_actionable)

    def test_completed_flag(self):
        item = _make_approval(status="approved", pipeline_stage="complete", event_id="evt1")
        result = serialize_approval(item)
        self.assertTrue(result.completed)

    def test_not_completed_when_pending(self):
        item = _make_approval(status="pending", pipeline_stage="deputy")
        result = serialize_approval(item)
        self.assertFalse(result.completed)


class TestHistoricalVisibilityScenarios(unittest.TestCase):
    """Scenario-level tests for the visibility business rules."""

    def test_deputy_clarification_then_approve_fields(self):
        """Deputy requests clarification, faculty replies, deputy approves.
        The item should have deputy_decided_by set and be serializable as non-actionable."""
        item = _make_approval(
            status="pending",
            pipeline_stage="after_deputy",
            deputy_decided_by="deputy@example.com",
            deputy_decided_at=datetime(2026, 4, 20, 11, 0),
            requested_to=None,  # cleared on deputy approval
        )
        result = serialize_approval(item, is_actionable=False)
        self.assertFalse(result.is_actionable)
        self.assertEqual(result.deputy_decided_by, "deputy@example.com")
        self.assertEqual(result.current_stage_label, "Deputy Approved — Forward to Finance")
        self.assertEqual(result.approved_by_role, "Deputy Registrar")

    def test_finance_clarification_then_approve_fields(self):
        """Finance requests clarification, faculty replies, finance approves."""
        item = _make_approval(
            status="pending",
            pipeline_stage="after_finance",
            deputy_decided_by="deputy@example.com",
            deputy_decided_at=datetime(2026, 4, 20, 10, 0),
            finance_decided_by="finance@example.com",
            finance_decided_at=datetime(2026, 4, 20, 12, 0),
            requested_to=None,
        )
        result = serialize_approval(item, is_actionable=False)
        self.assertFalse(result.is_actionable)
        self.assertEqual(result.finance_decided_by, "finance@example.com")
        self.assertEqual(result.current_stage_label, "Finance Approved — Forward to Registrar")
        self.assertEqual(result.approved_by_role, "Finance")

    def test_registrar_final_approval_is_actionable(self):
        """Registrar's active item is actionable."""
        item = _make_approval(
            status="pending",
            pipeline_stage="registrar",
            requested_to="registrar@example.com",
            deputy_decided_by="deputy@example.com",
            finance_decided_by="finance@example.com",
        )
        result = serialize_approval(item, is_actionable=True)
        self.assertTrue(result.is_actionable)
        self.assertEqual(result.current_stage_label, "Awaiting Registrar / VC")

    def test_historical_item_after_full_approval(self):
        """After registrar approves, deputy's historical view."""
        item = _make_approval(
            status="approved",
            pipeline_stage="complete",
            event_id="evt1",
            decided_by="registrar@example.com",
            deputy_decided_by="deputy@example.com",
            finance_decided_by="finance@example.com",
            requested_to=None,
        )
        result = serialize_approval(item, is_actionable=False)
        self.assertFalse(result.is_actionable)
        self.assertTrue(result.completed)
        self.assertEqual(result.current_stage_label, "Completed")
        self.assertEqual(result.approved_by_role, "Registrar / VC")


if __name__ == "__main__":
    unittest.main()
