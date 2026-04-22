import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../requirements/requirements_wizard_dialog.dart';

const List<({String value, String label})> _discussionDepartmentOptions = [
  (value: 'registrar', label: 'Registrar'),
  (value: 'facility_manager', label: 'Facility'),
  (value: 'it', label: 'IT'),
  (value: 'marketing', label: 'Marketing'),
  (value: 'transport', label: 'Transport'),
  (value: 'iqac', label: 'IQAC'),
];

class EventDetailsScreen extends StatefulWidget {
  final String eventId;

  const EventDetailsScreen({super.key, required this.eventId});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

enum _ApprovalDecisionAction { approve, reject, clarify }

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final _api = ApiService();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _detailsData;
  final Set<String> _expandedDepartments = <String>{};
  List<ApprovalThreadInfo> _approvalThreads = const [];
  bool _decisionSubmitting = false;
  final Map<String, bool> _expandedDiscussionThreads = <String, bool>{};
  final Map<String, TextEditingController> _replyControllers =
      <String, TextEditingController>{};
  final Map<String, ApprovalThreadMessage?> _replyTargets =
      <String, ApprovalThreadMessage?>{};
  final Set<String> _submittingReplyThreads = <String>{};
  final TextEditingController _newDiscussionMessageCtrl =
      TextEditingController();
  bool _newDiscussionOpen = false;
  bool _creatingDiscussion = false;
  String _newDiscussionDepartment = '';
  String? _discussionError;

  bool get _isApprovalOnlyEntry => widget.eventId.startsWith('approval-');

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _onSurface => Theme.of(context).colorScheme.onSurface;
  Color get _muted =>
      _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _border =>
      _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _panel => _isDark
      ? Theme.of(context).colorScheme.surfaceContainerHighest
      : const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  @override
  void dispose() {
    _newDiscussionMessageCtrl.dispose();
    for (final controller in _replyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _replyControllerFor(String threadId) {
    return _replyControllers.putIfAbsent(threadId, TextEditingController.new);
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _discussionError = null;
    });
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '/events/${widget.eventId}/details',
      );
      final approvalRequest = res['approval_request'] is Map<String, dynamic>
          ? res['approval_request'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final approvalRequestId = (approvalRequest['id'] ?? '').toString().trim();
      List<ApprovalThreadInfo> approvalThreads = const [];
      String? discussionError;

      if (approvalRequestId.isNotEmpty) {
        try {
          final threadData = await _api.get<dynamic>(
            '/approvals/$approvalRequestId/threads',
          );
          final items = threadData is List
              ? threadData
              : (threadData is Map<String, dynamic>
                    ? threadData['items']
                    : null);
          approvalThreads = (items as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(ApprovalThreadInfo.fromJson)
              .toList();
        } catch (e) {
          discussionError = e.toString();
        }
      }

      setState(() {
        _detailsData = res;
        _approvalThreads = approvalThreads;
        _discussionError = discussionError;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> get _event {
    final raw = _detailsData?['event'];
    if (raw is Map<String, dynamic>) return raw;
    return const <String, dynamic>{};
  }

  Map<String, dynamic> get _approval {
    final raw = _detailsData?['approval_request'];
    if (raw is Map<String, dynamic>) return raw;
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _mapList(String key) {
    final raw = _detailsData?[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String? _classifyRequirementLine(String line) {
    final s = line.toLowerCase();
    if (s.contains('marketing') ||
        s.contains('poster') ||
        s.contains('social media')) {
      return 'marketing';
    }
    if (s.contains('facility') ||
        s.contains('venue') ||
        s.contains('refreshment') ||
        s.contains('hall')) {
      return 'facility';
    }
    if (s.contains('it') ||
        s.contains('projection') ||
        s.contains('pa system') ||
        s.contains('laptop')) {
      return 'it';
    }
    if (s.contains('transport')) return 'transport';
    if (s.contains('iqac')) return 'iqac';
    return null;
  }

  String _s(dynamic value, {String fallback = '—'}) {
    if (value == null) return fallback;
    final out = value.toString().trim();
    return out.isEmpty ? fallback : out;
  }

  String _buildAudience(Map<String, dynamic> event) {
    final audience = event['intendedAudience'] ?? event['intended_audience'];
    final other = _s(
      event['intendedAudienceOther'] ?? event['intended_audience_other'],
      fallback: '',
    );
    if (audience is List && audience.isNotEmpty) {
      final items = audience
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        if (other.isNotEmpty) {
          return '${items.join(', ')} ($other)';
        }
        return items.join(', ');
      }
    }
    if (audience is String && audience.trim().isNotEmpty) {
      return audience.trim();
    }
    return other.isNotEmpty ? other : 'Unknown';
  }

  String _normalizeRequirementStatus(dynamic status) {
    final normalized = (status ?? '').toString().trim().toLowerCase();
    if (normalized == 'accepted') return 'approved';
    if (normalized.isEmpty) return 'none';
    return normalized;
  }

  String _aggregateRequirementStatus(List<Map<String, dynamic>> requests) {
    if (requests.isEmpty) return 'none';
    final statuses = requests
        .map((request) => _normalizeRequirementStatus(request['status']))
        .toList();

    if (statuses.any((status) => status == 'rejected')) return 'rejected';
    if (statuses.any((status) => status == 'clarification_requested')) {
      return 'clarification_requested';
    }
    if (statuses.any((status) => status == 'pending')) return 'pending';
    if (statuses.every((status) => status == 'approved')) return 'approved';
    return 'pending';
  }

  String _iqacRequirementStatus() {
    final hasReport =
        _s(_event['report_web_view_link'], fallback: '').isNotEmpty ||
        _s(_event['report_file_id'], fallback: '').isNotEmpty;
    if (hasReport) return 'approved';

    final eventStatus = _s(_event['status'], fallback: '').toLowerCase();
    if (eventStatus == 'draft') return 'none';
    return 'pending';
  }

  String _buildReviewRole(
    Map<String, dynamic> approval,
    Map<String, dynamic> event,
  ) {
    final pipelineStage = _s(
      approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();
    if (pipelineStage == 'deputy') return 'Deputy Registrar review';
    if (pipelineStage == 'after_deputy') {
      return 'Requester action: send to Finance';
    }
    if (pipelineStage == 'finance') return 'Finance Team review';
    if (pipelineStage == 'after_finance') {
      return 'Requester action: send to Registrar';
    }

    final requestedTo = _s(
      approval['requested_to'],
      fallback: '',
    ).toLowerCase();
    if (requestedTo.contains('vice')) return 'Vice Chancellor review';
    if (requestedTo.contains('registrar')) return 'Registrar review';
    final budget = (approval['budget'] ?? event['budget']);
    if (budget is num && budget > 30000) return 'Vice Chancellor review';
    return 'Registrar review';
  }

  String get _approvalRequestId => _s(_approval['id'], fallback: '');

  String get _currentUserId =>
      context.read<AuthProvider>().user?.id.trim() ?? '';

  String get _currentRoleKey =>
      (context.read<AuthProvider>().user?.roleKey ?? '').trim().toLowerCase();

  bool get _isRequester {
    final requesterId = _s(_approval['requester_id'], fallback: '');
    final eventOwner = _s(_event['created_by'], fallback: '');
    return _currentUserId.isNotEmpty &&
        (_currentUserId == requesterId || _currentUserId == eventOwner);
  }

  bool get _isApprovalActionable {
    final status = _s(_approval['status'], fallback: '').toLowerCase();
    return _approvalRequestId.isNotEmpty &&
        (status == 'pending' || status == 'clarification_requested');
  }

  bool get _isApprovalStageReviewer {
    return _currentRoleKey == 'registrar' ||
        _currentRoleKey == 'vice_chancellor' ||
        _currentRoleKey == 'deputy_registrar' ||
        _currentRoleKey == 'finance_team';
  }

  bool get _showApprovalActions =>
      _isApprovalActionable && _isApprovalStageReviewer && !_isRequester;

  List<Map<String, String?>> _buildApprovalWorkflowSteps() {
    final approval = _approval;
    final status = _s(approval['status'], fallback: '').toLowerCase();
    final stage = _s(approval['pipeline_stage'], fallback: '').toLowerCase();
    final budgetRaw = approval['budget'] ?? _event['budget'];
    final budget = budgetRaw is num
        ? budgetRaw.toDouble()
        : double.tryParse('$budgetRaw') ?? 0;
    final finalStageLabel = budget > 30000
        ? 'Registrar / VC'
        : 'Registrar';

    String deputyStatus = 'none';
    String financeStatus = 'none';
    String finalStatus = 'none';

    if (stage == 'deputy') {
      deputyStatus = status == 'clarification_requested'
          ? 'clarification_requested'
          : status == 'rejected'
          ? 'rejected'
          : 'pending';
    } else if (stage == 'after_deputy' || stage == 'finance') {
      deputyStatus = 'approved';
      financeStatus = status == 'clarification_requested'
          ? 'clarification_requested'
          : status == 'rejected'
          ? 'rejected'
          : 'pending';
    } else if (stage == 'after_finance') {
      deputyStatus = 'approved';
      financeStatus = 'approved';
      finalStatus = 'pending';
    } else if (stage == 'registrar') {
      deputyStatus = _s(approval['deputy_decided_by'], fallback: '').isNotEmpty
          ? 'approved'
          : 'none';
      financeStatus = _s(approval['finance_decided_by'], fallback: '').isNotEmpty
          ? 'approved'
          : 'none';
      finalStatus = status == 'clarification_requested'
          ? 'clarification_requested'
          : status == 'rejected'
          ? 'rejected'
          : 'pending';
    } else if (stage == 'complete' || status == 'approved') {
      deputyStatus = _s(approval['deputy_decided_by'], fallback: '').isNotEmpty
          ? 'approved'
          : 'none';
      financeStatus = _s(approval['finance_decided_by'], fallback: '').isNotEmpty
          ? 'approved'
          : 'none';
      finalStatus = 'approved';
      if (stage == 'after_deputy') {
        deputyStatus = 'approved';
      }
      if (stage == 'after_finance') {
        deputyStatus = 'approved';
        financeStatus = 'approved';
      }
      if (stage.isEmpty && deputyStatus == 'none' && financeStatus == 'none') {
        finalStatus = 'approved';
      }
    } else if (status == 'rejected') {
      if (stage == 'finance') {
        deputyStatus = 'approved';
        financeStatus = 'rejected';
      } else if (stage == 'registrar') {
        deputyStatus = _s(approval['deputy_decided_by'], fallback: '').isNotEmpty
            ? 'approved'
            : 'none';
        financeStatus = _s(approval['finance_decided_by'], fallback: '').isNotEmpty
            ? 'approved'
            : 'none';
        finalStatus = 'rejected';
      } else {
        deputyStatus = 'rejected';
      }
    } else if (status == 'pending' && stage.isEmpty) {
      finalStatus = 'pending';
    }

    return [
      {
        'label': 'Deputy Registrar',
        'status': deputyStatus,
        'assignee': _s(approval['deputy_decided_by'], fallback: ''),
        'updated_at': _s(approval['deputy_decided_at'], fallback: ''),
      },
      {
        'label': 'Finance Team',
        'status': financeStatus,
        'assignee': _s(approval['finance_decided_by'], fallback: ''),
        'updated_at': _s(approval['finance_decided_at'], fallback: ''),
      },
      {
        'label': finalStageLabel,
        'status': finalStatus,
        'assignee': _s(
          approval['decided_by'] ?? approval['requested_to'],
          fallback: '',
        ),
        'updated_at': _s(approval['decided_at'], fallback: ''),
      },
    ];
  }

  String _workflowBadgeLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approved';
      case 'pending':
        return 'Pending';
      case 'clarification_requested':
        return 'Clarification';
      case 'rejected':
        return 'Rejected';
      default:
        return '—';
    }
  }

  Color _workflowBadgeBg(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFFDCFCE7);
      case 'pending':
        return const Color(0xFFFEF3C7);
      case 'clarification_requested':
        return const Color(0xFFE0E7FF);
      case 'rejected':
        return const Color(0xFFFEE2E2);
      default:
        return _panel;
    }
  }

  Color _workflowBadgeFg(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF166534);
      case 'pending':
        return const Color(0xFFB45309);
      case 'clarification_requested':
        return const Color(0xFF4338CA);
      case 'rejected':
        return const Color(0xFFB91C1C);
      default:
        return _muted;
    }
  }

  List<ApprovalThreadInfo> get _deptRequestThreads => _mapList(
    'dept_request_threads',
  ).map(ApprovalThreadInfo.fromJson).toList();

  String _workflowStageLabel() {
    final pipelineStage = _s(
      _approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();
    final approvalStatus = _s(_approval['status'], fallback: '').toLowerCase();
    if (pipelineStage == 'deputy') return 'Deputy Registrar review';
    if (pipelineStage == 'after_deputy') return 'Waiting for requester';
    if (pipelineStage == 'finance') return 'Finance Team review';
    if (pipelineStage == 'after_finance') return 'Waiting for requester';
    if (approvalStatus == 'approved') {
      final reviewRole = _buildReviewRole(_approval, _event);
      return reviewRole.contains('Vice Chancellor')
          ? 'Vice Chancellor approved'
          : 'Registrar approved';
    }
    if (approvalStatus == 'rejected') return 'Rejected';
    if (approvalStatus == 'clarification_requested') {
      return 'Clarification requested';
    }
    return _buildReviewRole(_approval, _event);
  }

  String _requesterActionLabel() {
    final pipelineStage = _s(
      _approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();
    if (pipelineStage == 'after_deputy') {
      return 'Send this request to Finance from My Events.';
    }
    if (pipelineStage == 'after_finance') {
      return 'Send this request to Registrar from My Events.';
    }
    if (_canSendRequirements) {
      return 'Final approval is complete. You can now send department requirements.';
    }
    return 'No requester action pending.';
  }

  bool _threadIsLocked(ApprovalThreadInfo thread) {
    final status = thread.threadStatus.trim().toLowerCase();
    return status == 'resolved' || status == 'closed';
  }

  bool _userIsThreadParticipant(ApprovalThreadInfo thread) {
    if (_currentUserId.isEmpty) return false;
    return thread.participants.any(
      (participant) => participant.id.trim() == _currentUserId,
    );
  }

  String _threadStatusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'waiting_for_faculty') return 'Waiting for faculty';
    if (normalized == 'waiting_for_department') return 'Waiting for department';
    if (normalized == 'resolved') return 'Resolved';
    if (normalized == 'closed') return 'Closed';
    return normalized.isEmpty ? 'Active' : normalized.replaceAll('_', ' ');
  }

  String _decisionStatus(_ApprovalDecisionAction action) {
    switch (action) {
      case _ApprovalDecisionAction.approve:
        return 'approved';
      case _ApprovalDecisionAction.reject:
        return 'rejected';
      case _ApprovalDecisionAction.clarify:
        return 'clarification_requested';
    }
  }

  String _decisionLabel(_ApprovalDecisionAction action) {
    switch (action) {
      case _ApprovalDecisionAction.approve:
        return 'Approve';
      case _ApprovalDecisionAction.reject:
        return 'Reject';
      case _ApprovalDecisionAction.clarify:
        return 'Need clarification';
    }
  }

  String _extractApiErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        if (detail is List && detail.isNotEmpty) {
          final joined = detail
              .map((e) {
                if (e is Map<String, dynamic>) {
                  return (e['msg'] ?? e.toString()).toString();
                }
                return e.toString();
              })
              .where((e) => e.trim().isNotEmpty)
              .join(' ')
              .trim();
          if (joined.isNotEmpty) return joined;
        }
      }
      return error.message ?? 'Request failed. Please try again.';
    }
    return error.toString();
  }

  Future<String?> _promptDecisionComment({
    required String title,
    required String hint,
    required bool requiredComment,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              helperText: requiredComment
                  ? 'Comment is required for this action.'
                  : 'Comment is optional.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _handleApprovalDecision(_ApprovalDecisionAction action) async {
    if (!_showApprovalActions || _decisionSubmitting) return;

    final isApprove = action == _ApprovalDecisionAction.approve;
    final isReject = action == _ApprovalDecisionAction.reject;
    final requiresComment = !isApprove;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${_decisionLabel(action)} Event'),
          content: Text(
            isApprove
                ? 'Do you want to approve "${_s(_approval['event_name'], fallback: _s(_event['name'], fallback: 'this event'))}"?'
                : 'Do you want to ${_decisionLabel(action).toLowerCase()} "${_s(_approval['event_name'], fallback: _s(_event['name'], fallback: 'this event'))}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_decisionLabel(action)),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final comment = await _promptDecisionComment(
      title: isApprove
          ? 'Optional approval message'
          : (isReject ? 'Reject request' : 'Request clarification'),
      hint: isApprove
          ? 'Add an optional message for the requester'
          : (isReject ? 'Add rejection reason' : 'Ask for clarification'),
      requiredComment: requiresComment,
    );

    if (!mounted || comment == null) return;
    if (requiresComment && comment.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isReject
                ? 'Comment is required when rejecting a request.'
                : 'Comment is required when requesting clarification.',
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    setState(() {
      _decisionSubmitting = true;
    });

    try {
      final updated = await _api.patch<Map<String, dynamic>>(
        '/approvals/$_approvalRequestId',
        data: {
          'status': _decisionStatus(action),
          if (comment.trim().isNotEmpty) 'comment': comment.trim(),
        },
      );

      final status = (updated['status'] ?? '').toString().toLowerCase();
      final stage = (updated['pipeline_stage'] ?? '').toString().toLowerCase();
      String message;
      if (action == _ApprovalDecisionAction.approve && stage == 'after_deputy') {
        message =
            'Approved at Deputy stage. Requester can now send to Finance.';
      } else if (action == _ApprovalDecisionAction.approve &&
          stage == 'after_finance') {
        message =
            'Approved at Finance stage. Requester can now send to Registrar.';
      } else if (action == _ApprovalDecisionAction.approve &&
          status == 'approved') {
        message = 'Final approval completed.';
      } else if (action == _ApprovalDecisionAction.clarify) {
        message = 'Clarification requested from requester.';
      } else {
        message = isApprove ? 'Request approved.' : 'Request rejected.';
      }

      await _fetchDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isApprove
              ? const Color(0xFF16A34A)
              : const Color(0xFF475569),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractApiErrorMessage(e)),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _decisionSubmitting = false;
        });
      }
    }
  }

  Color _threadStatusBg(String status) {
    switch (status.trim().toLowerCase()) {
      case 'waiting_for_faculty':
        return const Color(0xFFFFF7ED);
      case 'waiting_for_department':
        return const Color(0xFFEEF2FF);
      case 'resolved':
      case 'closed':
        return const Color(0xFFF1F5F9);
      default:
        return const Color(0xFFECFDF5);
    }
  }

  Color _threadStatusFg(String status) {
    switch (status.trim().toLowerCase()) {
      case 'waiting_for_faculty':
        return const Color(0xFFC2410C);
      case 'waiting_for_department':
        return const Color(0xFF4338CA);
      case 'resolved':
      case 'closed':
        return const Color(0xFF475569);
      default:
        return const Color(0xFF047857);
    }
  }

  Future<void> _startDiscussion() async {
    final approvalRequestId = _approvalRequestId;
    if (approvalRequestId.isEmpty || _newDiscussionDepartment.isEmpty) return;

    setState(() {
      _creatingDiscussion = true;
      _discussionError = null;
    });
    try {
      await _api.post<Map<String, dynamic>>(
        '/approvals/$approvalRequestId/threads/ensure',
        data: {
          'department': _newDiscussionDepartment,
          if (_newDiscussionMessageCtrl.text.trim().isNotEmpty)
            'message': _newDiscussionMessageCtrl.text.trim(),
        },
      );
      _newDiscussionMessageCtrl.clear();
      setState(() {
        _newDiscussionOpen = false;
        _newDiscussionDepartment = '';
      });
      await _fetchDetails();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discussionError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _creatingDiscussion = false;
        });
      }
    }
  }

  Future<void> _submitThreadReply(ApprovalThreadInfo thread) async {
    final approvalRequestId = _approvalRequestId;
    final controller = _replyControllerFor(thread.id);
    final message = controller.text.trim();
    if (approvalRequestId.isEmpty || message.isEmpty) return;

    setState(() {
      _submittingReplyThreads.add(thread.id);
      _discussionError = null;
    });
    try {
      await _api.post<Map<String, dynamic>>(
        '/approvals/$approvalRequestId/reply',
        data: {
          'thread_id': thread.id,
          'message': message,
          if (_replyTargets[thread.id]?.id != null)
            'reply_to_message_id': _replyTargets[thread.id]!.id,
        },
      );
      controller.clear();
      setState(() {
        _replyTargets.remove(thread.id);
      });
      await _fetchDetails();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discussionError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _submittingReplyThreads.remove(thread.id);
        });
      }
    }
  }

  Future<void> _openExternalLink(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) return;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  void _closeDetails() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/events');
  }

  String _formatBudget(dynamic budgetValue) {
    if (budgetValue == null) return 'Rs 0';
    final parsed = budgetValue is num
        ? budgetValue.toDouble()
        : double.tryParse(budgetValue.toString());
    if (parsed == null) return 'Rs 0';
    if (parsed % 1 == 0) {
      return 'Rs ${NumberFormat('#,##0').format(parsed)}';
    }
    return 'Rs ${NumberFormat('#,##0.##').format(parsed)}';
  }

  String _formatDateTime(String? dateStr, String? timeStr) {
    if ((dateStr == null || dateStr.trim().isEmpty) &&
        (timeStr == null || timeStr.trim().isEmpty)) {
      return 'N/A';
    }

    final cleanDate = (dateStr ?? '').trim();
    final cleanTime = (timeStr ?? '').trim();

    try {
      final dt = DateTime.tryParse(
        '$cleanDate ${cleanTime.isEmpty ? '00:00' : cleanTime}',
      );
      if (dt != null) {
        return DateFormat('yyyy-MM-dd · h:mm a').format(dt);
      }
    } catch (_) {
      // Keep fallback rendering when parsing fails.
    }
    final combined = [
      cleanDate,
      cleanTime,
    ].where((e) => e.isNotEmpty).join(' · ');
    return combined.isEmpty ? 'N/A' : combined;
  }

  bool _isRequirementResolved(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'approved' || normalized == 'accepted';
  }

  bool _eventHasStarted() {
    final startDate = _s(_event['start_date'], fallback: '');
    final startTime = _s(_event['start_time'], fallback: '');
    if (startDate.isEmpty) return false;
    final parsed = DateTime.tryParse(
      '$startDate ${startTime.isEmpty ? '00:00' : startTime}',
    );
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now());
  }

  bool get _canSendRequirements {
    final approvalStatus = _s(_approval['status'], fallback: '').toLowerCase();
    final eventStatus = _s(_event['status'], fallback: '').toLowerCase();
    if (approvalStatus != 'approved') return false;
    if (_eventHasStarted()) return false;
    if (eventStatus == 'completed' || eventStatus == 'closed') return false;

    final facility = _mapList('facility_requests');
    final marketing = _mapList('marketing_requests');
    final it = _mapList('it_requests');
    final transport = _mapList('transport_requests');

    final statuses = <String?>[
      facility.isNotEmpty ? _aggregateRequirementStatus(facility) : null,
      marketing.isNotEmpty ? _aggregateRequirementStatus(marketing) : null,
      it.isNotEmpty ? _aggregateRequirementStatus(it) : null,
      transport.isNotEmpty ? _aggregateRequirementStatus(transport) : null,
    ];

    return statuses.any(
      (status) => status == null || !_isRequirementResolved(status),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: _surface,
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isApprovalOnlyEntry ? 'Approval details' : 'Event details',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  InkWell(
                    onTap: _closeDetails,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(LucideIcons.x, size: 20, color: _muted),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.alertCircle,
                              color: Color(0xFFDC2626),
                              size: 28,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error ?? 'Failed to load event details',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFB91C1C)),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _fetchDetails,
                              icon: const Icon(LucideIcons.refreshCw, size: 16),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A73E8),
                                foregroundColor: Colors.white,
                                textStyle: GoogleFonts.roboto(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildEventOverview(),
                          const SizedBox(height: 24),
                          _buildApprovalWorkflow(),
                          const SizedBox(height: 24),
                          _buildApprovalContext(),
                          const SizedBox(height: 24),
                          _buildDiscussion(),
                          const SizedBox(height: 24),
                          _buildRequirements(),
                          const SizedBox(height: 24),
                          _buildNotesAndDescription(),
                        ],
                      ),
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: _surface,
                border: Border(top: BorderSide(color: _border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed: _closeDetails,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _isDark
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: _isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFDADCE0),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: GoogleFonts.roboto(
                        color: _muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_canSendRequirements)
                    ElevatedButton(
                      onPressed: () {
                        final event = Event.fromJson(
                          _detailsData?['event'] ?? {},
                        );
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => RequirementsWizardDialog(
                            event: event,
                            requesterEmail: _s(
                              _approval['requester_email'],
                              fallback: '',
                            ),
                            onSuccess: () {
                              _fetchDetails();
                              setState(() {});
                            },
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Send Requirements',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required Widget child,
    double topPadding = 0,
  }) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: 24,
        top: topPadding > 0 ? topPadding : 24,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.24 : 0.03),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF2563EB), size: 20),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildLabelValue(IconData? icon, String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: _muted),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: _muted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                valueWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventOverview() {
    final event = _event;
    final approval = _approval;

    final status = _s(event['status'], fallback: 'pending');
    final approvalStatus = _s(approval['status'], fallback: 'pending');
    final budgetValue = approval['budget'] ?? event['budget'];
    final budgetWebLink = _s(
      event['budget_breakdown_web_view_link'] ??
          approval['budget_breakdown_web_view_link'],
      fallback: '',
    );
    final budgetFileId = _s(
      event['budget_breakdown_file_id'] ?? approval['budget_breakdown_file_id'],
      fallback: '',
    );
    final budgetFileName = _s(
      event['budget_breakdown_file_name'] ??
          approval['budget_breakdown_file_name'],
      fallback: '',
    );
    final hasBudgetFile =
        budgetWebLink.isNotEmpty ||
        budgetFileId.isNotEmpty ||
        budgetFileName.isNotEmpty;
    final budgetOpenLink = budgetWebLink.isNotEmpty
        ? budgetWebLink
        : (budgetFileId.isNotEmpty
              ? 'https://drive.google.com/file/d/$budgetFileId/view'
              : '');

    return _buildCard(
      icon: LucideIcons.fileText,
      title: 'Event overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabelValue(
            LucideIcons.flag,
            'Event Name',
            Text(
              _s(
                event['name'],
                fallback: _s(approval['event_name'], fallback: 'Untitled'),
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.mail,
            'Requester',
            Text(
              _s(approval['requester_email'], fallback: 'Unknown'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2563EB),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.user,
            'Facilitator',
            Text(
              _s(event['facilitator'], fallback: _s(approval['facilitator'])),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.mapPin,
            'Venue',
            Text(
              _s(event['venue_name'], fallback: _s(approval['venue_name'])),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.users,
            'Intended Audience',
            Text(
              _buildAudience(event).trim().toLowerCase() == 'unknown'
                  ? _s(approval['intendedAudience'], fallback: 'Unknown')
                  : _buildAudience(event),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.creditCard,
            'Budget',
            Row(
              children: [
                Text(
                  _formatBudget(budgetValue),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: budgetOpenLink.isEmpty
                          ? null
                          : () => _openExternalLink(budgetOpenLink),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Text(
                          hasBudgetFile
                              ? (budgetFileName.isEmpty
                                    ? 'Budget breakdown (PDF)'
                                    : budgetFileName)
                              : 'No budget file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: hasBudgetFile
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildLabelValue(
            LucideIcons.disc,
            'Status',
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF0D5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    approvalStatus.toUpperCase().replaceAll('_', ' '),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB47B1E),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '· Event:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF0D5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase().replaceAll('_', ' '),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB47B1E),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildLabelValue(
            LucideIcons.calendar,
            'Start',
            Text(
              _formatDateTime(event['start_date'], event['start_time']),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.calendar,
            'End',
            Text(
              _formatDateTime(event['end_date'], event['end_time']),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.alignLeft,
            'Description',
            Text(
              _s(event['description'], fallback: 'No description'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalContext() {
    final approval = _approval;
    final status = _s(approval['status'], fallback: 'Pending');
    final statusValue = status.toLowerCase().replaceAll('_', ' ');

    return _buildCard(
      icon: LucideIcons.shieldCheck,
      title: 'Approval context',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabelValue(
            null,
            'Requested To',
            Text(
              _s(approval['requested_to'], fallback: 'None'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2563EB),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Current Status',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: statusValue.contains('approved')
                    ? const Color(0xFFDCFCE7)
                    : statusValue.contains('reject')
                    ? const Color(0xFFFEE2E2)
                    : statusValue.contains('clarification')
                    ? const Color(0xFFE0E7FF)
                    : const Color(0xFFFDF0D5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: statusValue.contains('approved')
                      ? const Color(0xFF166534)
                      : statusValue.contains('reject')
                      ? const Color(0xFFB91C1C)
                      : statusValue.contains('clarification')
                      ? const Color(0xFF4338CA)
                      : const Color(0xFFB47B1E),
                ),
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Workflow Stage',
            Text(
              _workflowStageLabel(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Requester Action',
            Text(
              _requesterActionLabel(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          if (_showApprovalActions) ...[
            const SizedBox(height: 4),
            Text(
              'Take action',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _muted,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildDecisionButton(
                  label: 'Approve',
                  background: const Color(0xFFDCFCE7),
                  foreground: const Color(0xFF166534),
                  border: const Color(0xFF86EFAC),
                  onTap: () => _handleApprovalDecision(
                    _ApprovalDecisionAction.approve,
                  ),
                ),
                _buildDecisionButton(
                  label: 'Need clarification',
                  background: const Color(0xFFE0E7FF),
                  foreground: const Color(0xFF4338CA),
                  border: const Color(0xFFC7D2FE),
                  onTap: () => _handleApprovalDecision(
                    _ApprovalDecisionAction.clarify,
                  ),
                ),
                _buildDecisionButton(
                  label: 'Reject',
                  background: const Color(0xFFFEE2E2),
                  foreground: const Color(0xFFB91C1C),
                  border: const Color(0xFFFECACA),
                  onTap: () => _handleApprovalDecision(
                    _ApprovalDecisionAction.reject,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Approve can include an optional message. Reject and clarification require a comment, matching the website workflow.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _muted,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalWorkflow() {
    final steps = _buildApprovalWorkflowSteps();
    final currentStageLabel = _s(
      _approval['current_stage_label'],
      fallback: _workflowStageLabel(),
    );

    return _buildCard(
      icon: LucideIcons.gitBranch,
      title: 'Approval flow',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deputy Registrar → Finance Team → Registrar / VC',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Current stage: $currentStageLabel',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _onSurface,
            ),
          ),
          const SizedBox(height: 18),
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final status = (step['status'] ?? 'none').trim().toLowerCase();
            final isLast = index == steps.length - 1;
            final assignee = (step['assignee'] ?? '').trim();
            final updatedAt = (step['updated_at'] ?? '').trim();
            final parsedUpdatedAt = updatedAt.isEmpty
                ? null
                : DateTime.tryParse(updatedAt)?.toLocal();

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: status == 'none'
                            ? _panel
                            : _workflowBadgeBg(status),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: status == 'none'
                              ? _border
                              : _workflowBadgeFg(status),
                          width: 1.5,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 58,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        color: _border,
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                step['label'] ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _onSurface,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: _workflowBadgeBg(status),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _workflowBadgeLabel(status),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _workflowBadgeFg(status),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (assignee.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Assigned / decided by: $assignee',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ],
                        if (parsedUpdatedAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Updated: ${DateFormat('yyyy-MM-dd · h:mm a').format(parsedUpdatedAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDecisionButton({
    required String label,
    required Color background,
    required Color foreground,
    required Color border,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _decisionSubmitting ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          _decisionSubmitting ? 'Working...' : label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: foreground,
          ),
        ),
      ),
    );
  }

  Widget _buildDiscussion() {
    final approvalThreads = _approvalThreads;
    final deptThreads = _deptRequestThreads;
    final existingDepartments = approvalThreads
        .map((thread) => thread.department.trim().toLowerCase())
        .toSet();
    final availableDepartments = _discussionDepartmentOptions
        .where((option) => !existingDepartments.contains(option.value))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(LucideIcons.messageCircle, color: Color(0xFF2563EB), size: 20),
            SizedBox(width: 12),
            Text(
              'Discussion',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (approvalThreads.isEmpty && deptThreads.isEmpty)
          Text(
            _isRequester
                ? 'No department discussions yet. Start a conversation with a department from here, like on the web workflow.'
                : 'No department discussions yet. A discussion will appear here when a department or approver sends a message.',
            style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
          )
        else
          ...approvalThreads.map(
            (thread) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildThreadPanel(thread, showRequestStatus: false),
            ),
          ),
        if (deptThreads.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Department request discussions',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          ...deptThreads.map(
            (thread) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildThreadPanel(thread, showRequestStatus: true),
            ),
          ),
        ],
        if (_discussionError != null &&
            _discussionError!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _discussionError!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFB91C1C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_isRequester && _approvalRequestId.isNotEmpty)
          _buildNewDiscussionPanel(availableDepartments),
      ],
    );
  }

  Widget _buildNewDiscussionPanel(
    List<({String value, String label})> options,
  ) {
    if (options.isEmpty) {
      return Text(
        'You already have active discussion threads for all supported departments.',
        style: TextStyle(
          fontSize: 12,
          color: _muted,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (!_newDiscussionOpen) {
      return OutlinedButton.icon(
        onPressed: () {
          setState(() {
            _newDiscussionOpen = true;
            _newDiscussionDepartment = '';
          });
        },
        icon: const Icon(LucideIcons.plus, size: 16),
        label: const Text('Start new discussion'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF8B5CF6),
          side: const BorderSide(
            color: Color(0xFF8B5CF6),
            width: 1,
            style: BorderStyle.solid,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start a discussion with',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _onSurface,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _newDiscussionDepartment.isEmpty
                ? null
                : _newDiscussionDepartment,
            items: options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.value,
                    child: Text(option.label),
                  ),
                )
                .toList(),
            decoration: const InputDecoration(
              labelText: 'Department',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() {
                _newDiscussionDepartment = value ?? '';
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newDiscussionMessageCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Opening message (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: _creatingDiscussion
                    ? null
                    : () {
                        _newDiscussionMessageCtrl.clear();
                        setState(() {
                          _newDiscussionOpen = false;
                          _newDiscussionDepartment = '';
                        });
                      },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed:
                    _creatingDiscussion || _newDiscussionDepartment.isEmpty
                    ? null
                    : _startDiscussion,
                child: Text(
                  _creatingDiscussion ? 'Creating...' : 'Start discussion',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThreadPanel(
    ApprovalThreadInfo thread, {
    required bool showRequestStatus,
  }) {
    final isExpanded = _expandedDiscussionThreads[thread.id] ?? true;
    final canReply =
        _userIsThreadParticipant(thread) && !_threadIsLocked(thread);
    final replyController = _replyControllerFor(thread.id);
    final replyTarget = _replyTargets[thread.id];

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedDiscussionThreads[thread.id] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      thread.departmentLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${thread.messages.length} message${thread.messages.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _threadStatusBg(thread.threadStatus),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _threadStatusLabel(thread.threadStatus),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _threadStatusFg(thread.threadStatus),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 18,
                    color: _muted,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (thread.participants.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: thread.participants
                          .map(
                            (participant) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _panel,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: _border),
                              ),
                              child: Text(
                                '${participant.name}${participant.role.isEmpty ? '' : ' (${participant.role})'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _muted,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (showRequestStatus &&
                      (thread.deptRequestStatus ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Request status: ${thread.deptRequestStatus!.replaceAll('_', ' ')}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (thread.messages.isEmpty)
                    Text(
                      'No messages yet.',
                      style: TextStyle(fontSize: 13, color: _muted),
                    )
                  else
                    ...thread.messages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildThreadMessage(thread, message),
                      ),
                    ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => context.push('/chat/${thread.id}'),
                    icon: const Icon(LucideIcons.externalLink, size: 14),
                    label: const Text('Open in chat'),
                  ),
                  if (_threadIsLocked(thread))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        thread.closedAt != null
                            ? 'This discussion is ${_threadStatusLabel(thread.threadStatus).toLowerCase()} since ${DateFormat('yyyy-MM-dd · h:mm a').format(thread.closedAt!)}.'
                            : 'This discussion is ${_threadStatusLabel(thread.threadStatus).toLowerCase()}.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (canReply) ...[
                    if (replyTarget != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Replying to ${replyTarget.senderName}: ${replyTarget.content}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _muted,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _replyTargets.remove(thread.id);
                                });
                              },
                              icon: const Icon(Icons.close, size: 16),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: replyController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Reply to this discussion',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: _submittingReplyThreads.contains(thread.id)
                              ? null
                              : () => _submitThreadReply(thread),
                          child: Text(
                            _submittingReplyThreads.contains(thread.id)
                                ? 'Posting...'
                                : 'Post reply',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThreadMessage(
    ApprovalThreadInfo thread,
    ApprovalThreadMessage message,
  ) {
    final isOwn = message.senderId.trim() == _currentUserId;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.72,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isOwn ? const Color(0xFFDBEAFE) : _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOwn)
              Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _onSurface,
                ),
              ),
            if (message.replyToSnapshot != null) ...[
              if (!isOwn) const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _isDark ? 0.05 : 0.7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.replyToSnapshot!.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message.replyToSnapshot!.contentPreview.isEmpty
                          ? 'Message'
                          : message.replyToSnapshot!.contentPreview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else if (!isOwn)
              const SizedBox(height: 8),
            Text(
              message.content.isEmpty ? '—' : message.content,
              style: TextStyle(fontSize: 13, height: 1.45, color: _onSurface),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('yyyy-MM-dd · h:mm a').format(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
                if (_userIsThreadParticipant(thread) &&
                    !_threadIsLocked(thread))
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _replyTargets[thread.id] = message;
                      });
                    },
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Reply'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequirements() {
    final items = <({String key, String title, String status, int count})>[];
    final facility = _mapList('facility_requests');
    final marketing = _mapList('marketing_requests');
    final it = _mapList('it_requests');
    final transport = _mapList('transport_requests');
    final approval = _approval;

    if (facility.isNotEmpty) {
      items.add((
        key: 'facility',
        title: 'Facility',
        status: _aggregateRequirementStatus(facility),
        count: facility.length,
      ));
    }
    if (it.isNotEmpty) {
      items.add((
        key: 'it',
        title: 'IT',
        status: _aggregateRequirementStatus(it),
        count: it.length,
      ));
    }
    if (marketing.isNotEmpty) {
      items.add((
        key: 'marketing',
        title: 'Marketing',
        status: _aggregateRequirementStatus(marketing),
        count: marketing.length,
      ));
    }
    if (transport.isNotEmpty) {
      items.add((
        key: 'transport',
        title: 'Transport',
        status: _aggregateRequirementStatus(transport),
        count: transport.length,
      ));
    }

    if (items.isEmpty) {
      final requirements = _stringList(approval['requirements']);
      final bucketCounts = <String, int>{
        'facility': 0,
        'it': 0,
        'marketing': 0,
        'transport': 0,
        'iqac': 0,
      };

      for (final line in requirements) {
        final key = _classifyRequirementLine(line);
        if (key != null) {
          bucketCounts[key] = (bucketCounts[key] ?? 0) + 1;
        }
      }

      if ((bucketCounts['facility'] ?? 0) > 0) {
        items.add((
          key: 'facility',
          title: 'Facility',
          status: 'pending',
          count: bucketCounts['facility']!,
        ));
      }
      if ((bucketCounts['it'] ?? 0) > 0) {
        items.add((
          key: 'it',
          title: 'IT',
          status: 'pending',
          count: bucketCounts['it']!,
        ));
      }
      if ((bucketCounts['marketing'] ?? 0) > 0) {
        items.add((
          key: 'marketing',
          title: 'Marketing',
          status: 'pending',
          count: bucketCounts['marketing']!,
        ));
      }
      if ((bucketCounts['transport'] ?? 0) > 0) {
        items.add((
          key: 'transport',
          title: 'Transport',
          status: 'pending',
          count: bucketCounts['transport']!,
        ));
      }
      if ((bucketCounts['iqac'] ?? 0) > 0) {
        items.add((
          key: 'iqac',
          title: 'IQAC',
          status: 'pending',
          count: bucketCounts['iqac']!,
        ));
      }

      if (items.isEmpty) {
        items.add((
          key: 'iqac',
          title: 'IQAC',
          status: _iqacRequirementStatus(),
          count: 0,
        ));
      }
    }

    if (!items.any((item) => item.key == 'iqac')) {
      items.add((
        key: 'iqac',
        title: 'IQAC',
        status: _iqacRequirementStatus(),
        count: 0,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(LucideIcons.layers, color: Color(0xFF2563EB), size: 20),
            SizedBox(width: 12),
            Text(
              'Requirements by department',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Department requirement statuses for your event.',
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        ...items.map((item) {
          final isOpen = _expandedDepartments.contains(item.key);
          final source = item.key == 'facility'
              ? facility
              : item.key == 'it'
              ? it
              : item.key == 'marketing'
              ? marketing
              : item.key == 'transport'
              ? transport
              : const <Map<String, dynamic>>[];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isOpen) {
                    _expandedDepartments.remove(item.key);
                  } else {
                    _expandedDepartments.add(item.key);
                  }
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: _isDark ? 0.22 : 0.04),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.checkSquare,
                              size: 18,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _onSurface,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _panel,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: _border),
                              ),
                              child: Text(
                                item.status.replaceAll('_', ' '),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isOpen
                                  ? LucideIcons.chevronUp
                                  : LucideIcons.chevronDown,
                              size: 18,
                              color: const Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isOpen) ...[
                      const SizedBox(height: 10),
                      Text(
                        item.count == 0
                            ? 'No requests created yet.'
                            : '${item.count} request${item.count == 1 ? '' : 's'} linked to this event.',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                      if (source.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...source.take(3).map((req) {
                          final requestedTo = _s(
                            req['requested_to'],
                            fallback: 'Unassigned',
                          );
                          final decidedBy = _s(
                            req['decided_by'],
                            fallback: '—',
                          );
                          final rawDecidedAt = _s(
                            req['decided_at'],
                            fallback: '',
                          );
                          final decidedAt = rawDecidedAt.isEmpty
                              ? '—'
                              : (DateTime.tryParse(rawDecidedAt) != null
                                    ? DateFormat('yyyy-MM-dd · h:mm a').format(
                                        DateTime.parse(rawDecidedAt).toLocal(),
                                      )
                                    : rawDecidedAt);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              'Assigned: $requestedTo · By: $decidedBy · Updated: $decidedAt',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                          );
                        }),
                        if (source.length > 3)
                          Text(
                            '+${source.length - 3} more',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _muted,
                            ),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNotesAndDescription() {
    final event = _event;
    final approval = _approval;
    return _buildCard(
      icon: LucideIcons.fileText,
      title: 'Notes and description',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabelValue(
            null,
            'Other Notes',
            Text(
              _s(event['other_notes'], fallback: _s(approval['other_notes'])),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _onSurface,
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Description',
            Text(
              _s(event['description'], fallback: 'No description'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
