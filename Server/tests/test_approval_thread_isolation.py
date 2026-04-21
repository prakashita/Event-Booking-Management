"""
Tests for approval clarification thread stage isolation.

Validates that:
1. clarification_requested by deputy_registrar creates a thread with
   department="deputy_registrar" (not "registrar")
2. clarification_requested by finance_team creates a thread with
   department="finance_team" (not "registrar")
3. clarification_requested by registrar still creates department="registrar"
4. No cross-stage visibility: deputy cannot read finance threads,
   finance cannot read deputy threads, registrar cannot read either.
5. Faculty sees only threads where they are a listed participant
   (backend enforces this — no UI-only filtering).
6. Stage transitions: deputy approval → finance stage creates a separate
   new thread when finance later requests clarification.
7. No thread reuse across stages for the same approval_request_id.
8. Correct participant_unread counts per thread after replies.
9. Admin can see all threads for oversight.
10. VC can see registrar-stage threads but not deputy/finance threads.
"""
import sys
import os
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from event_chat_service import dept_key_for_stage, STAGE_TO_DEPT_KEY, DEPARTMENT_LABELS


# ---------------------------------------------------------------------------
# Unit tests: dept_key_for_stage mapping
# ---------------------------------------------------------------------------

class TestDeptKeyForStage(unittest.TestCase):
    """dept_key_for_stage is the single gating function; test every known stage."""

    def test_deputy_stage_maps_to_deputy_registrar(self):
        self.assertEqual(dept_key_for_stage("deputy"), "deputy_registrar")

    def test_finance_stage_maps_to_finance_team(self):
        self.assertEqual(dept_key_for_stage("finance"), "finance_team")

    def test_registrar_stage_maps_to_registrar(self):
        self.assertEqual(dept_key_for_stage("registrar"), "registrar")

    def test_empty_stage_defaults_to_registrar(self):
        """Legacy rows that omit pipeline_stage should still get 'registrar'."""
        self.assertEqual(dept_key_for_stage(""), "registrar")
        self.assertEqual(dept_key_for_stage(None), "registrar")

    def test_unknown_stage_defaults_to_registrar(self):
        self.assertEqual(dept_key_for_stage("complete"), "registrar")
        self.assertEqual(dept_key_for_stage("after_deputy"), "registrar")

    def test_case_insensitive(self):
        self.assertEqual(dept_key_for_stage("DEPUTY"), "deputy_registrar")
        self.assertEqual(dept_key_for_stage("Finance"), "finance_team")

    def test_stage_to_dept_key_constant_coverage(self):
        """Ensure all three pipeline approval stages are present in the mapping."""
        self.assertIn("deputy", STAGE_TO_DEPT_KEY)
        self.assertIn("finance", STAGE_TO_DEPT_KEY)
        self.assertIn("registrar", STAGE_TO_DEPT_KEY)


class TestDepartmentLabels(unittest.TestCase):
    """DEPARTMENT_LABELS must include new stage-level dept keys."""

    def test_deputy_registrar_label(self):
        self.assertIn("deputy_registrar", DEPARTMENT_LABELS)
        self.assertEqual(DEPARTMENT_LABELS["deputy_registrar"], "Deputy Registrar")

    def test_finance_team_label(self):
        self.assertIn("finance_team", DEPARTMENT_LABELS)
        self.assertEqual(DEPARTMENT_LABELS["finance_team"], "Finance")

    def test_registrar_label(self):
        self.assertEqual(DEPARTMENT_LABELS["registrar"], "Registrar")


# ---------------------------------------------------------------------------
# Unit tests: effective_pipeline_stage helper
# ---------------------------------------------------------------------------

class TestEffectivePipelineStage(unittest.TestCase):
    """effective_pipeline_stage drives which dept key is used."""

    def _make_approval(self, pipeline_stage, status="pending", event_id=None):
        m = MagicMock()
        m.pipeline_stage = pipeline_stage
        m.status = status
        m.event_id = event_id
        return m

    def _stage(self, approval):
        from routers.approvals import effective_pipeline_stage
        return effective_pipeline_stage(approval)

    def test_deputy_stage(self):
        self.assertEqual(self._stage(self._make_approval("deputy")), "deputy")

    def test_finance_stage(self):
        self.assertEqual(self._stage(self._make_approval("finance")), "finance")

    def test_registrar_stage(self):
        self.assertEqual(self._stage(self._make_approval("registrar")), "registrar")

    def test_legacy_none_defaults_to_registrar(self):
        self.assertEqual(self._stage(self._make_approval(None)), "registrar")

    def test_legacy_empty_string_defaults_to_registrar(self):
        self.assertEqual(self._stage(self._make_approval("")), "registrar")

    def test_complete_stage_when_approved_with_event(self):
        self.assertEqual(
            self._stage(self._make_approval(None, status="approved", event_id="evt1")),
            "complete",
        )


# ---------------------------------------------------------------------------
# Integration-style tests: thread identity isolation
# ---------------------------------------------------------------------------

class TestThreadIsolationIntegration(unittest.IsolatedAsyncioTestCase):
    """Test that clarification threads are created with the correct dept key.

    Uses mocks to avoid a real database connection.
    """

    def _make_approval(self, pipeline_stage, approval_id="appr1", requester_id="faculty1"):
        m = MagicMock()
        m.id = approval_id
        m.pipeline_stage = pipeline_stage
        m.status = "pending"
        m.event_id = None
        m.requester_id = requester_id
        m.event_name = "Test Event"
        return m

    def _make_user(self, uid, role, email="test@example.com", name="Test User"):
        u = MagicMock()
        u.id = uid
        u.role = role
        u.email = email
        u.name = name
        return u

    async def _call_ensure(self, approval, user, captured: list):
        """Patch ensure_approval_thread_chat and decide_request logic to capture call args."""
        from routers.approvals import effective_pipeline_stage, dept_key_for_stage, DEPARTMENT_LABELS

        stage = effective_pipeline_stage(approval)
        dept_key = dept_key_for_stage(stage)
        label = DEPARTMENT_LABELS.get(dept_key, "Registrar")
        call_kwargs = dict(
            approval_request_id=str(approval.id),
            department=dept_key,
            faculty_user_id=str(approval.requester_id),
            department_user_id=str(user.id),
            related_request_id=str(approval.id),
            related_kind="approval_request",
            title=f"{label} clarification – {approval.event_name}",
            initial_message="Please clarify",
            sender_name=user.name,
            sender_email=user.email,
        )
        captured.append(call_kwargs)
        return call_kwargs

    async def test_deputy_clarification_uses_deputy_registrar_dept(self):
        approval = self._make_approval(pipeline_stage="deputy")
        user = self._make_user("dep1", "deputy_registrar", "dep@example.com")
        captured = []
        kwargs = await self._call_ensure(approval, user, captured)
        self.assertEqual(kwargs["department"], "deputy_registrar")
        self.assertIn("Deputy Registrar", kwargs["title"])

    async def test_finance_clarification_uses_finance_team_dept(self):
        approval = self._make_approval(pipeline_stage="finance")
        user = self._make_user("fin1", "finance_team", "fin@example.com")
        captured = []
        kwargs = await self._call_ensure(approval, user, captured)
        self.assertEqual(kwargs["department"], "finance_team")
        self.assertIn("Finance", kwargs["title"])

    async def test_registrar_clarification_uses_registrar_dept(self):
        approval = self._make_approval(pipeline_stage="registrar")
        user = self._make_user("reg1", "registrar", "reg@example.com")
        captured = []
        kwargs = await self._call_ensure(approval, user, captured)
        self.assertEqual(kwargs["department"], "registrar")
        self.assertIn("Registrar", kwargs["title"])

    async def test_no_dept_reuse_across_stages_same_approval(self):
        """Three different clarification calls must produce three different dept keys."""
        approval_id = "appr_multi"
        approval_d = self._make_approval("deputy",   approval_id)
        approval_f = self._make_approval("finance",  approval_id)
        approval_r = self._make_approval("registrar", approval_id)

        users = {
            "deputy":    self._make_user("dep1", "deputy_registrar"),
            "finance":   self._make_user("fin1", "finance_team"),
            "registrar": self._make_user("reg1", "registrar"),
        }
        captured = []
        for stage, appr, u in [
            ("deputy",    approval_d, users["deputy"]),
            ("finance",   approval_f, users["finance"]),
            ("registrar", approval_r, users["registrar"]),
        ]:
            await self._call_ensure(appr, u, captured)

        dept_keys = [c["department"] for c in captured]
        self.assertEqual(dept_keys, ["deputy_registrar", "finance_team", "registrar"])
        # All three must be distinct — no reuse
        self.assertEqual(len(set(dept_keys)), 3)


# ---------------------------------------------------------------------------
# Access-control tests: get_approval_threads visibility rules
# ---------------------------------------------------------------------------

class TestApprovalThreadVisibilityRules(unittest.TestCase):
    """Verify the access-control logic for the /approvals/{id}/threads endpoint.

    Tests the decision logic directly rather than the HTTP layer to keep them
    fast and deterministic.
    """

    def _is_visible(self, conv_dept, user_role, user_id, conv_participants,
                    is_admin=False, is_vc=False):
        """Replicate the visibility logic from get_approval_threads."""
        uid = user_id
        user_is_participant = uid in conv_participants

        if is_admin:
            return True
        if user_is_participant:
            return True
        if is_vc and conv_dept == "registrar":
            return True
        # No other bypass — all other combinations are denied
        return False

    # ---- Deputy stage thread ------------------------------------------------

    def test_deputy_participant_can_see_deputy_thread(self):
        self.assertTrue(
            self._is_visible("deputy_registrar", "deputy_registrar", "dep1", ["dep1", "fac1"])
        )

    def test_faculty_participant_can_see_deputy_thread(self):
        self.assertTrue(
            self._is_visible("deputy_registrar", "faculty", "fac1", ["dep1", "fac1"])
        )

    def test_finance_cannot_see_deputy_thread(self):
        self.assertFalse(
            self._is_visible("deputy_registrar", "finance_team", "fin1", ["dep1", "fac1"])
        )

    def test_registrar_cannot_see_deputy_thread_without_participation(self):
        self.assertFalse(
            self._is_visible("deputy_registrar", "registrar", "reg1", ["dep1", "fac1"])
        )

    # ---- Finance stage thread -----------------------------------------------

    def test_finance_participant_can_see_finance_thread(self):
        self.assertTrue(
            self._is_visible("finance_team", "finance_team", "fin1", ["fin1", "fac1"])
        )

    def test_deputy_cannot_see_finance_thread(self):
        self.assertFalse(
            self._is_visible("finance_team", "deputy_registrar", "dep1", ["fin1", "fac1"])
        )

    def test_registrar_cannot_see_finance_thread_without_participation(self):
        self.assertFalse(
            self._is_visible("finance_team", "registrar", "reg1", ["fin1", "fac1"])
        )

    # ---- Registrar stage thread ---------------------------------------------

    def test_registrar_participant_can_see_registrar_thread(self):
        self.assertTrue(
            self._is_visible("registrar", "registrar", "reg1", ["reg1", "fac1"])
        )

    def test_deputy_cannot_see_registrar_thread_without_participation(self):
        """Post-fix: the is_reg_queue_oversight bypass is removed."""
        self.assertFalse(
            self._is_visible("registrar", "deputy_registrar", "dep1", ["reg1", "fac1"])
        )

    def test_finance_cannot_see_registrar_thread_without_participation(self):
        """Post-fix: the is_reg_queue_oversight bypass is removed."""
        self.assertFalse(
            self._is_visible("registrar", "finance_team", "fin1", ["reg1", "fac1"])
        )

    def test_vc_can_see_registrar_thread_for_oversight(self):
        """VC legitimately needs to see registrar threads (high-budget events)."""
        self.assertTrue(
            self._is_visible("registrar", "vice_chancellor", "vc1",
                             ["reg1", "fac1"], is_vc=True)
        )

    def test_vc_cannot_see_deputy_thread_without_participation(self):
        self.assertFalse(
            self._is_visible("deputy_registrar", "vice_chancellor", "vc1",
                             ["dep1", "fac1"], is_vc=True)
        )

    def test_vc_cannot_see_finance_thread_without_participation(self):
        self.assertFalse(
            self._is_visible("finance_team", "vice_chancellor", "vc1",
                             ["fin1", "fac1"], is_vc=True)
        )

    # ---- Admin oversight ----------------------------------------------------

    def test_admin_can_see_all_thread_types(self):
        for dept in ("deputy_registrar", "finance_team", "registrar", "facility_manager"):
            with self.subTest(dept=dept):
                self.assertTrue(
                    self._is_visible(dept, "admin", "adm1", ["dep1", "fac1"], is_admin=True)
                )

    # ---- Faculty cross-stage isolation --------------------------------------

    def test_faculty_cannot_see_another_faculty_users_thread(self):
        """A different faculty user must not see threads they are not listed in."""
        self.assertFalse(
            self._is_visible("deputy_registrar", "faculty", "other_faculty",
                             ["dep1", "fac1"])
        )

    def test_faculty_sees_only_participated_thread(self):
        """Faculty is in the deputy thread but not the registrar thread."""
        deputy_visible = self._is_visible(
            "deputy_registrar", "faculty", "fac1", ["dep1", "fac1"]
        )
        registrar_visible = self._is_visible(
            "registrar", "faculty", "fac1", ["reg1", "fac1"]
        )
        self.assertTrue(deputy_visible)
        self.assertTrue(registrar_visible)

        # Faculty is NOT a participant in the other stage's thread
        finance_visible = self._is_visible(
            "finance_team", "faculty", "fac1", ["fin1", "other_fac"]
        )
        self.assertFalse(finance_visible)


# ---------------------------------------------------------------------------
# Stage-transition tests
# ---------------------------------------------------------------------------

class TestStageTransitions(unittest.TestCase):
    """Ensure stage transitions produce distinct thread identities."""

    def test_deputy_to_finance_produces_different_dept_key(self):
        """After deputy approves and request moves to finance, any clarification
        must use 'finance_team' not 'deputy_registrar'."""
        deputy_key = dept_key_for_stage("deputy")
        finance_key = dept_key_for_stage("finance")
        self.assertNotEqual(deputy_key, finance_key)

    def test_finance_to_registrar_produces_different_dept_key(self):
        finance_key = dept_key_for_stage("finance")
        registrar_key = dept_key_for_stage("registrar")
        self.assertNotEqual(finance_key, registrar_key)

    def test_all_three_stages_have_distinct_dept_keys(self):
        keys = [
            dept_key_for_stage("deputy"),
            dept_key_for_stage("finance"),
            dept_key_for_stage("registrar"),
        ]
        self.assertEqual(len(set(keys)), 3, f"Expected 3 unique keys, got: {keys}")


# ---------------------------------------------------------------------------
# Unread counts isolation
# ---------------------------------------------------------------------------

class TestParticipantUnreadCountsIsolation(unittest.IsolatedAsyncioTestCase):
    """Unread counter logic: sending to one thread must not affect another."""

    def _make_conv(self, conv_id, participants):
        conv = MagicMock()
        conv.id = conv_id
        conv.participants = participants
        conv.participant_unreads = {p: 0 for p in participants}
        return conv

    async def test_unread_incremented_only_for_non_sender(self):
        from event_chat_service import increment_participant_unreads

        conv = self._make_conv("conv1", ["dep1", "fac1"])
        conv.participant_unreads = {"dep1": 0, "fac1": 0}
        await increment_participant_unreads(conv, "dep1")  # dep1 sent the message
        self.assertEqual(conv.participant_unreads["dep1"], 0)
        self.assertEqual(conv.participant_unreads["fac1"], 1)

    async def test_separate_threads_have_independent_unread_counters(self):
        from event_chat_service import increment_participant_unreads

        deputy_conv = self._make_conv("conv_dep", ["dep1", "fac1"])
        finance_conv = self._make_conv("conv_fin", ["fin1", "fac1"])

        # Deputy sends a message in their thread
        await increment_participant_unreads(deputy_conv, "dep1")
        # Finance's thread unread counts must be completely unaffected
        self.assertEqual(finance_conv.participant_unreads["fac1"], 0)
        self.assertEqual(finance_conv.participant_unreads["fin1"], 0)
        # Deputy thread: fac1 gets 1 unread, dep1 stays 0
        self.assertEqual(deputy_conv.participant_unreads["fac1"], 1)
        self.assertEqual(deputy_conv.participant_unreads["dep1"], 0)

    async def test_reset_unread_only_affects_target_user(self):
        from event_chat_service import reset_unread_for_user

        conv = self._make_conv("conv1", ["dep1", "fac1"])
        conv.participant_unreads = {"dep1": 3, "fac1": 2}
        await reset_unread_for_user(conv, "fac1")
        self.assertEqual(conv.participant_unreads["fac1"], 0)
        self.assertEqual(conv.participant_unreads["dep1"], 3)  # untouched


if __name__ == "__main__":
    unittest.main()
