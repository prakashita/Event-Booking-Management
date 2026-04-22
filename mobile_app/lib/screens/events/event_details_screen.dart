import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../requirements/requirements_wizard_dialog.dart';

const List<({String value, String label})> _discussionDepartmentOptions = [
  (value: 'registrar', label: 'Registrar'),
  (value: 'deputy_registrar', label: 'Deputy Registrar'),
  (value: 'finance_team', label: 'Finance'),
  (value: 'facility_manager', label: 'Facility'),
  (value: 'it', label: 'IT'),
  (value: 'marketing', label: 'Marketing'),
  (value: 'transport', label: 'Transport'),
  (value: 'iqac', label: 'IQAC'),
];

class EventDetailsScreen extends StatefulWidget {
  final String eventId;
  final EventDetailsViewMode viewMode;

  const EventDetailsScreen({
    super.key,
    required this.eventId,
    this.viewMode = EventDetailsViewMode.event,
  });

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

enum EventDetailsViewMode { event, approval }

enum _ApprovalDecisionAction { approve, reject, clarify }

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final _api = ApiService();
  static const List<Map<String, String>> _marketingDeliverableOptions = [
    {'key': 'poster_required', 'type': 'poster', 'label': 'Poster'},
    {'key': 'video_required', 'type': 'video', 'label': 'Videoshoot'},
    {'key': 'linkedin_post', 'type': 'linkedin', 'label': 'Social Media Post'},
    {
      'key': 'photography',
      'type': 'photography',
      'label': 'Photoshoot / Photo upload',
    },
    {'key': 'recording', 'type': 'recording', 'label': 'Video Upload'},
  ];
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

  bool get _isApprovalOnlyEntry =>
      widget.viewMode == EventDetailsViewMode.approval ||
      widget.eventId.startsWith('approval-');

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

  Map<String, dynamic> _stringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map((entry) => MapEntry(entry.key.toString(), entry.value)),
      );
    }
    return <String, dynamic>{};
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

  bool get _showDiscussionSection => _approvalRequestId.isNotEmpty;

  String? get _viewerDepartmentKey {
    switch (_currentRoleKey) {
      case 'marketing':
        return 'marketing';
      case 'facility_manager':
        return 'facility';
      case 'it':
        return 'it';
      case 'transport':
        return 'transport';
      case 'iqac':
        return 'iqac';
      default:
        return null;
    }
  }

  bool get _isDepartmentInboxRole =>
      _viewerDepartmentKey == 'facility' ||
      _viewerDepartmentKey == 'it' ||
      _viewerDepartmentKey == 'marketing' ||
      _viewerDepartmentKey == 'transport';

  String? _patchPathForDepartment(String key, String id) {
    switch (key) {
      case 'facility':
        return '/facility/requests/$id';
      case 'it':
        return '/it/requests/$id';
      case 'marketing':
        return '/marketing/requests/$id';
      case 'transport':
        return '/transport/requests/$id';
      default:
        return null;
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

  ApprovalThreadInfo? _threadForRequestId(String requestId) {
    if (requestId.trim().isEmpty) return null;
    for (final thread in _deptRequestThreads) {
      if ((thread.relatedRequestId ?? '').trim() == requestId.trim()) {
        return thread;
      }
    }
    return null;
  }

  String _threadStatusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'waiting_for_faculty') return 'Waiting for faculty';
    if (normalized == 'waiting_for_department') return 'Waiting for department';
    if (normalized == 'resolved') return 'Resolved';
    if (normalized == 'closed') return 'Closed';
    return normalized.isEmpty ? 'Active' : normalized.replaceAll('_', ' ');
  }

  String _getApprovedByRoleLabel(Map<String, dynamic> approval) {
    final reviewRole = _buildReviewRole(approval, _event);
    if (reviewRole.contains('Vice Chancellor')) return 'Vice Chancellor';
    if (reviewRole.contains('Registrar')) return 'Registrar';
    if (reviewRole.contains('Finance')) return 'Finance Team';
    if (reviewRole.contains('Deputy')) return 'Deputy Registrar';
    return '';
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

  Future<void> _connectGoogle() async {
    final res = await _api.get<Map<String, dynamic>>('/calendar/connect-url');
    final url = res['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw Exception('Failed to obtain Google connect URL.');
    }
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      final fallback = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!fallback) {
        throw Exception('Could not open the Google consent page.');
      }
    }
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
      if (action == _ApprovalDecisionAction.approve &&
          stage == 'after_deputy') {
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

  Map<String, Color> _threadStatusColor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'waiting_for_faculty':
        return {'bg': const Color(0xFFFFF7ED), 'fg': const Color(0xFFC2410C)};
      case 'waiting_for_department':
        return {'bg': const Color(0xFFEEF2FF), 'fg': const Color(0xFF4338CA)};
      case 'resolved':
      case 'closed':
        return {'bg': const Color(0xFFF1F5F9), 'fg': const Color(0xFF475569)};
      default:
        return {'bg': const Color(0xFFECFDF5), 'fg': const Color(0xFF047857)};
    }
  }

  Future<void> _decideDepartmentRequest(
    String key,
    String id,
    String decision,
    String comment,
  ) async {
    final path = _patchPathForDepartment(key, id);
    if (path == null) return;
    try {
      await _api.patch(path, data: {'status': decision, 'comment': comment});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approved'
                ? 'Request approved.'
                : decision == 'rejected'
                ? 'Request rejected.'
                : 'Clarification requested.',
          ),
          backgroundColor: decision == 'approved'
              ? const Color(0xFF16A34A)
              : const Color(0xFF475569),
        ),
      );
      await _fetchDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractApiErrorMessage(e)),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _openDepartmentDecisionDialog(
    String key,
    Map<String, dynamic> request,
  ) async {
    final requestId = _s(request['id'], fallback: '');
    if (requestId.isEmpty || !_canDepartmentTakeAction(request)) return;

    String selected = 'approved';
    final commentCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Update ${key.toUpperCase()} request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Decision',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'approved', child: Text('Approve')),
                    DropdownMenuItem(value: 'rejected', child: Text('Reject')),
                    DropdownMenuItem(
                      value: 'clarification_requested',
                      child: Text('Need clarification'),
                    ),
                  ],
                  onChanged: (value) {
                    setLocal(() => selected = value ?? 'approved');
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: selected == 'approved'
                        ? 'Comment (optional)'
                        : 'Comment (required)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final comment = commentCtrl.text.trim();
                if (selected != 'approved' && comment.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Comment is required for reject/clarification.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                await _decideDepartmentRequest(key, requestId, selected, comment);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    commentCtrl.dispose();
  }

  Future<String?> _uploadMarketingDeliverablesBatch({
    required String requestId,
    required Map<String, bool> naByType,
    required Map<String, MultipartFile?> filesByType,
  }) async {
    try {
      final payload = <String, dynamic>{};
      for (final entry in naByType.entries) {
        if (entry.value) payload['na_${entry.key}'] = '1';
      }
      for (final entry in filesByType.entries) {
        final file = entry.value;
        if (file != null) {
          payload['file_${entry.key}'] = file;
        }
      }
      if (payload.isEmpty) {
        return 'Choose at least one file or mark an item as N/A.';
      }
      await _api.postMultipart<Map<String, dynamic>>(
        '/marketing/requests/$requestId/deliverables/batch',
        FormData.fromMap(payload),
      );
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marketing deliverables submitted.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      await _fetchDetails();
      return null;
    } catch (e) {
      return _extractApiErrorMessage(e);
    }
  }

  Future<void> _openMarketingUploadDialog(Map<String, dynamic> request) async {
    final requestId = _s(request['id'], fallback: '');
    if (requestId.isEmpty) return;

    final uploadFlags = _marketingDeliverableUploadFlagsFromMap(request);
    final enabledOptions = _marketingDeliverableOptions
        .where((opt) => uploadFlags[opt['key']] == true)
        .toList();

    if (enabledOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This request only includes during-event marketing. No file uploads are required.',
          ),
        ),
      );
      return;
    }

    final deliverables = (request['deliverables'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MarketingDeliverable.fromJson)
        .toList();
    final existingByType = <String, MarketingDeliverable>{
      for (final d in deliverables) d.type: d,
    };
    final naByType = <String, bool>{
      for (final opt in enabledOptions)
        opt['type']!: existingByType[opt['type']]?.isNa ?? false,
    };
    final filesByType = <String, MultipartFile?>{
      for (final opt in enabledOptions) opt['type']!: null,
    };
    final fileNameByType = <String, String>{
      for (final opt in enabledOptions)
        if (existingByType[opt['type']]?.isNa != true &&
            (existingByType[opt['type']]?.link ?? '').isNotEmpty)
          opt['type']!: existingByType[opt['type']]!.link!,
    };
    var submitStatus = 'idle';
    var submitError = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final hasSelection = enabledOptions.any((opt) {
            final type = opt['type']!;
            final lock = _marketingDeliverableRowLock(type, request);
            if (lock.locked) return false;
            return naByType[type] == true ||
                filesByType[type] != null;
          });

          return AlertDialog(
            title: const Text('Upload Marketing Deliverables'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final opt in enabledOptions) ...[
                    Builder(
                      builder: (_) {
                        final type = opt['type']!;
                        final lock = _marketingDeliverableRowLock(type, request);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: _border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt['label']!,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _onSurface,
                                ),
                              ),
                              if (lock.locked) ...[
                                const SizedBox(height: 4),
                                Text(
                                  lock.hint,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _muted,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: naByType[type] == true
                                          ? null
                                          : () async {
                                              final result =
                                                  await FilePicker.platform
                                                      .pickFiles(
                                                        withData: kIsWeb,
                                                        withReadStream: !kIsWeb,
                                                        type: FileType.custom,
                                                        allowedExtensions: [
                                                          'pdf',
                                                          'png',
                                                          'jpg',
                                                          'jpeg',
                                                          'webp',
                                                        ],
                                                      );
                                              final picked = result
                                                  ?.files
                                                  .single;
                                              if (picked == null) return;
                                              MultipartFile? multipart;
                                              if (picked.path != null &&
                                                  picked.path!
                                                      .trim()
                                                      .isNotEmpty) {
                                                multipart =
                                                    await MultipartFile.fromFile(
                                                      picked.path!,
                                                      filename: picked.name,
                                                    );
                                              } else if (picked.bytes != null) {
                                                multipart =
                                                    MultipartFile.fromBytes(
                                                      picked.bytes!,
                                                      filename: picked.name,
                                                    );
                                              } else if (picked.readStream !=
                                                  null) {
                                                multipart =
                                                    MultipartFile.fromStream(
                                                  () => picked.readStream!,
                                                  picked.size,
                                                  filename: picked.name,
                                                );
                                              }
                                              if (multipart == null) {
                                                if (!ctx.mounted) return;
                                                ScaffoldMessenger.of(
                                                  ctx,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Unable to read selected file.',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              setLocal(() {
                                                filesByType[type] = multipart;
                                                fileNameByType[type] =
                                                    picked.name;
                                              });
                                            },
                                      icon: const Icon(Icons.upload_file),
                                      label: Text(
                                        fileNameByType[type]?.isNotEmpty == true
                                            ? 'Replace file'
                                            : 'Choose file',
                                      ),
                                    ),
                                    FilterChip(
                                      label: const Text('Mark N/A'),
                                      selected: naByType[type] == true,
                                      onSelected: (value) {
                                        setLocal(() {
                                          naByType[type] = value;
                                          if (value) {
                                            filesByType[type] = null;
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                if ((fileNameByType[type] ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    fileNameByType[type]!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  if (submitStatus == 'error') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            submitError,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (submitError == 'Google not connected') ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () async {
                              try {
                                await _connectGoogle();
                              } catch (e) {
                                if (!ctx.mounted) return;
                                setLocal(() {
                                  submitError = _extractApiErrorMessage(e);
                                });
                              }
                            },
                            child: const Text('Connect Google'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: submitStatus == 'loading' || !hasSelection
                    ? null
                    : () async {
                        setLocal(() {
                          submitStatus = 'loading';
                          submitError = '';
                        });
                        final error = await _uploadMarketingDeliverablesBatch(
                          requestId: requestId,
                          naByType: naByType,
                          filesByType: filesByType,
                        );
                        if (!ctx.mounted) return;
                        if (error == null) {
                          Navigator.of(ctx).pop();
                          return;
                        }
                        setLocal(() {
                          submitStatus = 'error';
                          submitError = error;
                        });
                      },
                child: Text(
                  submitStatus == 'loading' ? 'Saving...' : 'Save',
                ),
              ),
            ],
          );
        },
      ),
    );
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

  bool _requestHasStarted(Map<String, dynamic> request) {
    final startDate = _s(request['start_date'], fallback: '');
    final startTime = _s(request['start_time'], fallback: '');
    if (startDate.isEmpty) return false;
    final parsed = DateTime.tryParse(
      '$startDate ${startTime.isEmpty ? '00:00' : startTime}',
    );
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now());
  }

  bool _requestHasEnded(Map<String, dynamic> request) {
    final endDate = _s(request['end_date'], fallback: '');
    final endTime = _s(request['end_time'], fallback: '');
    if (endDate.isEmpty) return false;
    final parsed = DateTime.tryParse(
      '$endDate ${endTime.isEmpty ? '23:59' : endTime}',
    );
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now());
  }

  bool _canDepartmentTakeAction(Map<String, dynamic> request) {
    final status = _s(request['status'], fallback: '').toLowerCase();
    return (status == 'pending' || status == 'clarification_requested') &&
        !_requestHasStarted(request);
  }

  Map<String, dynamic> _normalizeMarketingRequirementsFromMap(
    Map<String, dynamic> request,
  ) {
    final req = _stringDynamicMap(request['marketing_requirements']);
    final pre = req['pre_event'] is Map
        ? Map<String, dynamic>.from(req['pre_event'] as Map)
        : const <String, dynamic>{};
    final during = req['during_event'] is Map
        ? Map<String, dynamic>.from(req['during_event'] as Map)
        : const <String, dynamic>{};
    final post = req['post_event'] is Map
        ? Map<String, dynamic>.from(req['post_event'] as Map)
        : const <String, dynamic>{};

    return {
      'pre_event': {
        'poster': pre['poster'] ?? request['poster_required'] == true,
        'social_media': pre['social_media'] ?? request['linkedin_post'] == true,
      },
      'during_event': {
        'photo': during['photo'] ?? request['photography'] == true,
        'video': during['video'] ?? request['video_required'] == true,
      },
      'post_event': {
        'social_media': post['social_media'] ?? false,
        'photo_upload': post['photo_upload'] ?? false,
        'video': post['video'] ?? request['recording'] == true,
      },
    };
  }

  Map<String, bool> _marketingDeliverableUploadFlagsFromMap(
    Map<String, dynamic> request,
  ) {
    final normalized = _normalizeMarketingRequirementsFromMap(request);
    final pre = normalized['pre_event'] as Map<String, dynamic>;
    final post = normalized['post_event'] as Map<String, dynamic>;
    return {
      'poster_required': pre['poster'] == true,
      'video_required': false,
      'linkedin_post':
          pre['social_media'] == true || post['social_media'] == true,
      'photography': post['photo_upload'] == true,
      'recording': post['video'] == true,
    };
  }

  ({bool locked, String hint}) _marketingDeliverableRowLock(
    String type,
    Map<String, dynamic> request,
  ) {
    final started = _requestHasStarted(request);
    final ended = _requestHasEnded(request);
    if (type == 'poster' || type == 'linkedin') {
      return started
          ? (
              locked: true,
              hint: 'Pre-event social posts: upload before the event starts.',
            )
          : (locked: false, hint: '');
    }
    if (type == 'recording') {
      return !ended
          ? (
              locked: true,
              hint: 'Post-event video: upload after the event has ended.',
            )
          : (locked: false, hint: '');
    }
    if (type == 'photography') {
      return !ended
          ? (
              locked: true,
              hint: 'Post-event photo: upload after the event has ended.',
            )
          : (locked: false, hint: '');
    }
    return (locked: false, hint: '');
  }

  bool _canSendRequirementForStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'none' || normalized == 'rejected';
  }

  List<String> get _sendableRequirementDepartments {
    final facility = _mapList('facility_requests');
    final marketing = _mapList('marketing_requests');
    final it = _mapList('it_requests');
    final transport = _mapList('transport_requests');

    final statuses = <String, String>{
      'facility': _aggregateRequirementStatus(facility),
      'it': _aggregateRequirementStatus(it),
      'marketing': _aggregateRequirementStatus(marketing),
      'transport': _aggregateRequirementStatus(transport),
    };

    return statuses.entries
        .where((entry) => _canSendRequirementForStatus(entry.value))
        .map((entry) => entry.key)
        .toList();
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

    return _sendableRequirementDepartments.isNotEmpty;
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
                          _isApprovalOnlyEntry
                              ? _buildApprovalWorkflow()
                              : _buildEventWorkflow(),
                          if (_showDiscussionSection) ...[
                            const SizedBox(height: 24),
                            _buildDiscussion(),
                          ],
                          if (_isApprovalOnlyEntry) ...[
                            const SizedBox(height: 24),
                            _buildApprovalContext(),
                          ],
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
                  if (!_isApprovalOnlyEntry && _canSendRequirements)
                    ElevatedButton(
                      onPressed: () {
                        final sendableDepartments =
                            _sendableRequirementDepartments;
                        if (sendableDepartments.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'All requirement requests are already active.',
                              ),
                            ),
                          );
                          return;
                        }
                        final event = Event.fromJson(
                          _detailsData?['event'] ?? {},
                        );
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => RequirementsWizardDialog(
                            event: event,
                            departments: sendableDepartments,
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
    final showRequester = _isApprovalOnlyEntry;
    final showCombinedStatus = _isApprovalOnlyEntry;

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
          if (showRequester)
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
            showCombinedStatus
                ? Row(
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
                  )
                : Container(
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
              _s(
                event['description'],
                fallback: _s(approval['description'], fallback: 'No description'),
              ),
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
    final discussionStatus = _s(approval['discussion_status'], fallback: '');

    return _buildCard(
      icon: LucideIcons.shieldCheck,
      title: 'Approval context',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status + Stage: side-by-side prominent row (matching website)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current status',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _muted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusValue.contains('approved')
                              ? const Color(0xFFDCFCE7)
                              : statusValue.contains('reject')
                              ? const Color(0xFFFEE2E2)
                              : statusValue.contains('clarification')
                              ? const Color(0xFFE0E7FF)
                              : const Color(0xFFFDF0D5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
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
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stage',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _muted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _workflowStageLabel(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Discussion status banner (matching website)
          if (discussionStatus.isNotEmpty &&
              (statusValue.contains('clarification') ||
                  discussionStatus.contains('waiting'))) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: discussionStatus.contains('waiting_for_faculty')
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: discussionStatus.contains('waiting_for_faculty')
                      ? const Color(0xFFFED7AA)
                      : const Color(0xFFC7D2FE),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    discussionStatus.contains('waiting_for_faculty')
                        ? LucideIcons.alertCircle
                        : LucideIcons.info,
                    size: 18,
                    color: discussionStatus.contains('waiting_for_faculty')
                        ? const Color(0xFFC2410C)
                        : const Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      discussionStatus.contains('waiting_for_faculty')
                          ? (_isRequester
                                ? 'The reviewer has requested clarification. Please review and reply.'
                                : 'Waiting for the faculty to respond to your clarification request.')
                          : (_isRequester
                                ? 'Your reply has been sent. Waiting for the reviewer.'
                                : 'The faculty has replied. Please review their response.'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: discussionStatus.contains('waiting_for_faculty')
                            ? const Color(0xFFC2410C)
                            : const Color(0xFF4338CA),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Requested To field
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

          // Final decision by with role label (matching website)
          if (approval['decided_by'] != null &&
              approval['decided_by'].toString().trim().isNotEmpty)
            _buildLabelValue(
              null,
              'Final decision by',
              Row(
                children: [
                  Text(
                    _s(approval['decided_by'], fallback: ''),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (_getApprovedByRoleLabel(approval).isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      ' (${_getApprovedByRoleLabel(approval)})',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Requester action label
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

          // Approval action buttons
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
                  onTap: () =>
                      _handleApprovalDecision(_ApprovalDecisionAction.approve),
                ),
                _buildDecisionButton(
                  label: 'Need clarification',
                  background: const Color(0xFFE0E7FF),
                  foreground: const Color(0xFF4338CA),
                  border: const Color(0xFFC7D2FE),
                  onTap: () =>
                      _handleApprovalDecision(_ApprovalDecisionAction.clarify),
                ),
                _buildDecisionButton(
                  label: 'Reject',
                  background: const Color(0xFFFEE2E2),
                  foreground: const Color(0xFFB91C1C),
                  border: const Color(0xFFFECACA),
                  onTap: () =>
                      _handleApprovalDecision(_ApprovalDecisionAction.reject),
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
    final approval = _approval;
    final pipelineStage = _s(
      approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();
    final currentStageLabel = _s(
      approval['current_stage_label'],
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

          // Pipeline stage timeline: deputy → finance → registrar (matching website)
          _buildPipelineStep(
            label: 'Deputy Registrar',
            decidedBy: _s(approval['deputy_decided_by'], fallback: ''),
            isDone:
                approval['deputy_decided_by'] != null &&
                approval['deputy_decided_by'].toString().trim().isNotEmpty,
            isActive:
                approval['deputy_decided_by'] == null &&
                (pipelineStage == 'deputy' || pipelineStage == 'after_deputy'),
            isLast: false,
          ),
          _buildPipelineConnector(),
          _buildPipelineStep(
            label: 'Finance',
            decidedBy: _s(approval['finance_decided_by'], fallback: ''),
            isDone:
                approval['finance_decided_by'] != null &&
                approval['finance_decided_by'].toString().trim().isNotEmpty,
            isActive:
                approval['finance_decided_by'] == null &&
                (pipelineStage == 'finance' ||
                    pipelineStage == 'after_finance'),
            isLast: false,
          ),
          _buildPipelineConnector(),
          _buildPipelineStep(
            label: 'Registrar / VC',
            decidedBy: _s(approval['decided_by'], fallback: ''),
            isDone:
                approval['status'] == 'approved' &&
                (pipelineStage == 'complete' || pipelineStage.isEmpty),
            isActive:
                approval['status'] != 'approved' &&
                pipelineStage == 'registrar',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildEventWorkflow() {
    final approval = _approval;
    final event = _event;
    final facility = _mapList('facility_requests');
    final it = _mapList('it_requests');
    final marketing = _mapList('marketing_requests');
    final eventStatus = _s(event['status'], fallback: '').toLowerCase();
    final approvalStatus = _s(approval['status'], fallback: '').toLowerCase();

    final registrarStep = (
      label: 'Registrar',
      status: approvalStatus.isEmpty ? 'none' : approvalStatus,
      assignee: _s(
        approval['requested_to'] ?? approval['decided_by'],
        fallback: '',
      ),
      updatedAt: _s(approval['decided_at'], fallback: ''),
    );
    final facilityStep = (
      label: 'Facility',
      status: _aggregateRequirementStatus(facility),
      assignee: facility
          .map((req) => _s(req['requested_to'], fallback: ''))
          .where((value) => value.isNotEmpty)
          .toSet()
          .join(', '),
      updatedAt: facility
          .map((req) => _s(req['decided_at'], fallback: ''))
          .where((value) => value.isNotEmpty)
          .fold<String>('', (latest, value) {
            if (latest.isEmpty) return value;
            final latestDt = DateTime.tryParse(latest);
            final nextDt = DateTime.tryParse(value);
            if (latestDt == null || nextDt == null) return value;
            return nextDt.isAfter(latestDt) ? value : latest;
          }),
    );
    final itStep = (
      label: 'IT',
      status: _aggregateRequirementStatus(it),
      assignee: it
          .map((req) => _s(req['requested_to'], fallback: ''))
          .where((value) => value.isNotEmpty)
          .toSet()
          .join(', '),
      updatedAt: it
          .map((req) => _s(req['decided_at'], fallback: ''))
          .where((value) => value.isNotEmpty)
          .fold<String>('', (latest, value) {
            if (latest.isEmpty) return value;
            final latestDt = DateTime.tryParse(latest);
            final nextDt = DateTime.tryParse(value);
            if (latestDt == null || nextDt == null) return value;
            return nextDt.isAfter(latestDt) ? value : latest;
          }),
    );
    final marketingStep = (
      label: 'Marketing',
      status: _aggregateRequirementStatus(marketing),
      assignee: marketing
          .map((req) => _s(req['requested_to'], fallback: ''))
          .where((value) => value.isNotEmpty)
          .toSet()
          .join(', '),
      updatedAt: marketing
          .map((req) => _s(req['decided_at'], fallback: ''))
          .where((value) => value.isNotEmpty)
          .fold<String>('', (latest, value) {
            if (latest.isEmpty) return value;
            final latestDt = DateTime.tryParse(latest);
            final nextDt = DateTime.tryParse(value);
            if (latestDt == null || nextDt == null) return value;
            return nextDt.isAfter(latestDt) ? value : latest;
          }),
    );
    final iqacHasReport =
        _s(event['report_web_view_link'], fallback: '').isNotEmpty ||
        _s(event['report_file_id'], fallback: '').isNotEmpty;
    final iqacStep = (
      label: 'IQAC',
      status: iqacHasReport
          ? 'approved'
          : eventStatus.isNotEmpty && eventStatus != 'draft'
          ? 'pending'
          : 'none',
      assignee: iqacHasReport ? 'Report on file' : '',
      updatedAt: _s(event['report_uploaded_at'], fallback: ''),
    );

    final steps = [
      registrarStep,
      facilityStep,
      itStep,
      marketingStep,
      iqacStep,
    ];

    return _buildCard(
      icon: LucideIcons.gitBranch,
      title: 'Approval flow',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registrar through IQAC. Multiple requests for one team are aggregated into a single status.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ...steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            return Column(
              children: [
                _buildEventWorkflowStep(
                  label: step.label,
                  status: step.status,
                  assignee: step.assignee,
                  updatedAt: step.updatedAt,
                ),
                if (index != steps.length - 1) _buildPipelineConnector(),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEventWorkflowStep({
    required String label,
    required String status,
    required String assignee,
    required String updatedAt,
  }) {
    final colors = _getRequirementStatusColor(status);
    final normalized = status.trim().toLowerCase();
    final isDone = normalized == 'approved' || normalized == 'accepted';
    final isPending = normalized == 'pending';
    final isClarification = normalized == 'clarification_requested';
    final showBadge = normalized.isNotEmpty && normalized != 'none';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isDone
                ? const Color(0xFFDCFCE7)
                : isPending || isClarification
                ? const Color(0xFFFEF3C7)
                : _panel,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDone
                  ? const Color(0xFF16A34A)
                  : isPending || isClarification
                  ? const Color(0xFFB45309)
                  : _border,
              width: 2,
            ),
          ),
          child: Center(
            child: isDone
                ? Icon(
                    LucideIcons.check,
                    size: 10,
                    color: const Color(0xFF16A34A),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _onSurface,
                      ),
                    ),
                  ),
                  if (showBadge)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors['bg'] as Color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        normalized.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: colors['fg'] as Color,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (assignee.isNotEmpty)
                Text(
                  assignee,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                )
              else if (normalized == 'none')
                Text(
                  'No record yet',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
              if (updatedAt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(updatedAt, ''),
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
      ],
    );
  }

  Widget _buildPipelineStep({
    required String label,
    required String decidedBy,
    required bool isDone,
    required bool isActive,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pipeline dot with checkmark (matching website)
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: isDone
                ? const Color(0xFFDCFCE7)
                : isActive
                ? const Color(0xFFFEF3C7)
                : _panel,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDone
                  ? const Color(0xFF16A34A)
                  : isActive
                  ? const Color(0xFFB45309)
                  : _border,
              width: 2,
            ),
          ),
          child: Center(
            child: isDone
                ? Icon(
                    LucideIcons.check,
                    size: 10,
                    color: const Color(0xFF16A34A),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                if (decidedBy.isNotEmpty)
                  Text(
                    decidedBy,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  )
                else if (isActive)
                  Text(
                    'Awaiting',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFB45309),
                    ),
                  )
                else
                  Text(
                    'Not started',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPipelineConnector() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 2, height: 24, color: _border),
          const SizedBox(width: 14),
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
    final actionLogs = _mapList('workflow_action_logs');
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
          children: [
            Icon(
              LucideIcons.messageCircle,
              color: const Color(0xFF2563EB),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discussion',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Department conversations and clarification threads.',
                    style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (approvalThreads.isEmpty &&
            deptThreads.isEmpty &&
            actionLogs.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 18, color: _muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isRequester
                        ? 'No department discussions yet. Start a conversation with a department from here, like on the web workflow.'
                        : 'No department discussions yet. A discussion will appear here when a department or approver sends a message.',
                    style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
                  ),
                ),
              ],
            ),
          )
        else if (approvalThreads.isEmpty &&
            deptThreads.isEmpty &&
            actionLogs.isNotEmpty)
          _buildActionHistory(actionLogs)
        else
          ...approvalThreads.map(
            (thread) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildThreadPanel(thread, showRequestStatus: false),
            ),
          ),
        if (deptThreads.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Department request discussions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
                letterSpacing: 0.4,
              ),
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
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.alertCircle,
                  size: 16,
                  color: const Color(0xFFDC2626),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _discussionError!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
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

  String _formatWorkflowRoleLabel(String? role) {
    if (role == null) return '—';
    final r = role.toLowerCase();
    if (r == 'registrar') return 'Registrar';
    if (r == 'requester') return 'Requester';
    if (r == 'faculty') return 'Faculty';
    if (r == 'facility_manager') return 'Facility';
    if (r == 'marketing') return 'Marketing';
    if (r == 'it') return 'IT';
    if (r == 'transport') return 'Transport';
    if (r == 'iqac') return 'IQAC';
    if (r == 'deputy_registrar') return 'Deputy Registrar';
    if (r == 'finance_team') return 'Finance';
    if (r == 'vice_chancellor') return 'Vice Chancellor';
    return role;
  }

  String _formatWorkflowActionTypeLabel(String? actionType) {
    if (actionType == null) return '—';
    final t = actionType.toLowerCase();
    if (t == 'approve') return 'Approved';
    if (t == 'reject') return 'Rejected';
    if (t == 'clarification') return 'Need clarification';
    if (t == 'reply' || t == 'discussion_reply') return 'Reply';
    return actionType;
  }

  Widget _buildActionHistory(List<dynamic> actionLogs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.history, size: 18, color: _muted),
              const SizedBox(width: 8),
              Text(
                'Action history',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...actionLogs.map((log) {
            final role = _formatWorkflowRoleLabel(log['role']?.toString());
            final actionType = _formatWorkflowActionTypeLabel(
              log['action_type']?.toString(),
            );
            final comment = log['comment']?.toString() ?? '';
            final createdAt = log['created_at']?.toString();
            final actorName = log['actor_name']?.toString() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: actionType.contains('Approved')
                              ? const Color(0xFFDCFCE7)
                              : actionType.contains('Rejected')
                              ? const Color(0xFFFEE2E2)
                              : actionType.contains('clarification')
                              ? const Color(0xFFE0E7FF)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          actionType,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: actionType.contains('Approved')
                                ? const Color(0xFF166534)
                                : actionType.contains('Rejected')
                                ? const Color(0xFFB91C1C)
                                : actionType.contains('clarification')
                                ? const Color(0xFF4338CA)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          role,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (actorName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      actorName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _onSurface,
                      ),
                    ),
                  ],
                  if (comment.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      comment,
                      style: TextStyle(
                        fontSize: 13,
                        color: _onSurface,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(() {
                      try {
                        final dt = DateTime.parse(createdAt);
                        return DateFormat('yyyy-MM-dd · h:mm a').format(dt);
                      } catch (_) {
                        return createdAt;
                      }
                    }(), style: TextStyle(fontSize: 11, color: _muted)),
                  ],
                ],
              ),
            );
          }),
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
    final isLocked = _threadIsLocked(thread);
    final statusColor = _threadStatusColor(thread.threadStatus);

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked ? _border.withValues(alpha: 0.5) : _border,
          width: isLocked ? 1 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.24 : 0.03),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedDiscussionThreads[thread.id] = !isExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
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
                  if (isLocked)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor['bg'] as Color,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _threadStatusLabel(thread.threadStatus),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor['fg'] as Color,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _threadStatusLabel(thread.threadStatus),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF16A34A),
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

    final highlightDept = _viewerDepartmentKey;
    if (highlightDept != null) {
      final selectedIndex = items.indexWhere((item) => item.key == highlightDept);
      if (selectedIndex > 0) {
        final selected = items.removeAt(selectedIndex);
        items.insert(0, selected);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.layers, color: const Color(0xFF2563EB), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Requirements by department',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expand each card for phased requirements. Your department is listed first when applicable.',
                    style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
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
          final deptIcon = _getDepartmentIcon(item.key);
          final isYourDept = _isYourDepartment(item.key);
          final statusColor = _getRequirementStatusColor(item.status);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                border: Border.all(
                  color: isYourDept
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.45)
                      : _border,
                  width: isYourDept ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _isDark ? 0.24 : 0.03,
                    ),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        if (isOpen) {
                          _expandedDepartments.remove(item.key);
                        } else {
                          _expandedDepartments.add(item.key);
                        }
                      });
                    },
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              deptIcon,
                              size: 18,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.title,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _onSurface,
                              ),
                            ),
                          ),
                          if (isYourDept)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF3B82F6,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(
                                    0xFF3B82F6,
                                  ).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                'YOUR RESPONSIBILITY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF2563EB),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor['bg'] as Color,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              (item.status.replaceAll('_', ' ')).toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: statusColor['fg'] as Color,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isOpen
                                ? LucideIcons.chevronDown
                                : LucideIcons.chevronRight,
                            size: 18,
                            color: _muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isOpen)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _surface,
                        border: Border(
                          top: BorderSide(color: _border, width: 1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.count == 0)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _panel,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _border),
                              ),
                              child: item.key == 'iqac'
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              LucideIcons.info,
                                              size: 16,
                                              color: _muted,
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                _s(
                                                      _event['report_web_view_link'],
                                                      fallback: '',
                                                    )
                                                    .isNotEmpty
                                                    ? 'Event report submitted.'
                                                    : 'Report expected after the event is finalized.',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: _muted,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_s(
                                              _event['report_web_view_link'],
                                              fallback: '',
                                            )
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          InkWell(
                                            onTap: () => _openExternalLink(
                                              _s(
                                                _event['report_web_view_link'],
                                                fallback: '',
                                              ),
                                            ),
                                            child: Text(
                                              _s(
                                                _event['report_file_name'],
                                                fallback: 'View event report',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF2563EB),
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Icon(
                                          LucideIcons.info,
                                          size: 16,
                                          color: _muted,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'No requests created yet.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: _muted,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            )
                          else ...[
                            Text(
                              '${item.count} request${item.count == 1 ? '' : 's'} linked to this event.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ...source.asMap().entries.map((entry) {
                              final req = entry.value;
                              final index = entry.key;
                              final reqId = _s(req['id'], fallback: '');
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
                                        ? DateFormat(
                                            'yyyy-MM-dd · h:mm a',
                                          ).format(
                                            DateTime.parse(
                                              rawDecidedAt,
                                            ).toLocal(),
                                          )
                                        : rawDecidedAt);
                              final reqStatus = _s(
                                req['status'],
                                fallback: 'pending',
                              );
                              final reqStatusColor = _getRequirementStatusColor(
                                reqStatus,
                              );
                              final canTakeAction =
                                  isYourDept &&
                                  _isDepartmentInboxRole &&
                                  _canDepartmentTakeAction(req);
                              final canUploadMarketing =
                                  isYourDept &&
                                  item.key == 'marketing' &&
                                  _currentRoleKey == 'marketing';
                              final uploadFlags = item.key == 'marketing'
                                  ? _marketingDeliverableUploadFlagsFromMap(req)
                                  : const <String, bool>{};
                              final relevantMarketingOptions = item.key == 'marketing'
                                  ? _marketingDeliverableOptions
                                        .where(
                                          (opt) => uploadFlags[opt['key']] == true,
                                        )
                                        .toList()
                                  : const <Map<String, String>>[];
                              final unlockedMarketingOptions =
                                  relevantMarketingOptions
                                      .where(
                                        (opt) => !_marketingDeliverableRowLock(
                                          opt['type']!,
                                          req,
                                        ).locked,
                                      )
                                      .toList();
                              final uploadEnabled =
                                  canUploadMarketing &&
                                  unlockedMarketingOptions.isNotEmpty;
                              final uploadHint = canUploadMarketing &&
                                      relevantMarketingOptions.isNotEmpty &&
                                      !uploadEnabled
                                  ? _marketingDeliverableRowLock(
                                      relevantMarketingOptions.first['type']!,
                                      req,
                                    ).hint
                                  : '';
                              final deliverables = (req['deliverables'] as List? ?? [])
                                  .whereType<Map<String, dynamic>>()
                                  .toList();
                              final requesterAttachments =
                                  (req['requester_attachments'] as List? ?? [])
                                      .whereType<Map<String, dynamic>>()
                                      .toList();
                              final thread = _threadForRequestId(reqId);
                              final reportLink = item.key == 'iqac'
                                  ? _s(_event['report_web_view_link'], fallback: '')
                                  : '';
                              final reportName = item.key == 'iqac'
                                  ? _s(_event['report_file_name'], fallback: '')
                                  : '';

                              return Container(
                                margin: EdgeInsets.only(
                                  top: index > 0 ? 14 : 0,
                                ),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: _panel,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                reqStatusColor['bg'] as Color,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            (reqStatus.replaceAll(
                                              '_',
                                              ' ',
                                            )).toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  reqStatusColor['fg'] as Color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildReqPersonInfo(
                                            'Assigned',
                                            requestedTo,
                                          ),
                                        ),
                                        if (decidedBy != '—') ...[
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: _buildReqPersonInfo(
                                              'By',
                                              decidedBy,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (decidedAt != '—') ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Updated: $decidedAt',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _muted,
                                        ),
                                      ),
                                    ],
                                    if (thread != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Discussion status: ${_threadStatusLabel(thread.threadStatus)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _muted,
                                        ),
                                      ),
                                    ],
                                    if (item.key == 'marketing' &&
                                        requesterAttachments.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      Text(
                                        'Requester reference documents',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: _onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...requesterAttachments.map((attachment) {
                                        final name = _s(
                                          attachment['file_name'],
                                          fallback: 'Document',
                                        );
                                        final link = _s(
                                          attachment['web_view_link'],
                                          fallback: '',
                                        );
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 6),
                                          child: InkWell(
                                            onTap: link.isEmpty
                                                ? null
                                                : () => _openExternalLink(link),
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: link.isEmpty
                                                    ? _muted
                                                    : const Color(0xFF2563EB),
                                                decoration: link.isEmpty
                                                    ? TextDecoration.none
                                                    : TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                    if (item.key == 'marketing') ...[
                                      const SizedBox(height: 14),
                                      Text(
                                        'Uploaded deliverables',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: _onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (deliverables.isEmpty)
                                        Text(
                                          'No files uploaded yet.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        )
                                      else
                                        ...deliverables.map((deliverable) {
                                          final type = _s(
                                            deliverable['deliverable_type'] ??
                                                deliverable['type'],
                                            fallback: 'File',
                                          );
                                          final name = _s(
                                            deliverable['file_name'],
                                            fallback: type,
                                          );
                                          final link = _s(
                                            deliverable['web_view_link'] ??
                                                deliverable['link'],
                                            fallback: '',
                                          );
                                          final isNa =
                                              deliverable['is_na'] == true;
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 6),
                                            child: isNa
                                                ? Text(
                                                    '$type: N/A',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: _muted,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  )
                                                : InkWell(
                                                    onTap: link.isEmpty
                                                        ? null
                                                        : () => _openExternalLink(link),
                                                    child: Text(
                                                      name,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                        color: link.isEmpty
                                                            ? _muted
                                                            : const Color(0xFF2563EB),
                                                        decoration: link.isEmpty
                                                            ? TextDecoration.none
                                                            : TextDecoration.underline,
                                                      ),
                                                    ),
                                                  ),
                                          );
                                        }),
                                    ],
                                    if (item.key == 'iqac' && reportLink.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      InkWell(
                                        onTap: () => _openExternalLink(reportLink),
                                        child: Text(
                                          reportName.isEmpty
                                              ? 'View event report'
                                              : reportName,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF2563EB),
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (reqStatus.toLowerCase() ==
                                        'clarification_requested') ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        'Clarification requested. See the Discussion section above to respond.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFD97706),
                                        ),
                                      ),
                                    ],
                                    if ((canTakeAction || canUploadMarketing) &&
                                        reqId.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (canTakeAction)
                                            ElevatedButton(
                                              onPressed: () =>
                                                  _openDepartmentDecisionDialog(
                                                    item.key,
                                                    req,
                                                  ),
                                              child: const Text('Take action'),
                                            ),
                                          if (canUploadMarketing)
                                            OutlinedButton(
                                              onPressed: uploadEnabled
                                                  ? () => _openMarketingUploadDialog(
                                                        req,
                                                      )
                                                  : null,
                                              child: const Text('Upload'),
                                            ),
                                          OutlinedButton(
                                            onPressed: thread == null
                                                ? null
                                                : () => context.push(
                                                      '/chat/${thread.id}',
                                                    ),
                                            child: const Text('Open discussion'),
                                          ),
                                        ],
                                      ),
                                      if (canUploadMarketing &&
                                          !uploadEnabled &&
                                          uploadHint.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          uploadHint,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  IconData _getDepartmentIcon(String key) {
    switch (key.toLowerCase()) {
      case 'marketing':
        return LucideIcons.megaphone;
      case 'facility':
        return LucideIcons.building2;
      case 'it':
        return LucideIcons.monitor;
      case 'transport':
        return LucideIcons.car;
      case 'iqac':
        return LucideIcons.clipboardCheck;
      default:
        return LucideIcons.layers;
    }
  }

  bool _isYourDepartment(String key) {
    return _viewerDepartmentKey == key.toLowerCase();
  }

  Map<String, Color> _getRequirementStatusColor(String status) {
    final normalized = status.trim().toLowerCase();
    switch (normalized) {
      case 'approved':
      case 'accepted':
        return {'bg': const Color(0xFFDCFCE7), 'fg': const Color(0xFF16A34A)};
      case 'rejected':
      case 'declined':
        return {'bg': const Color(0xFFFEE2E2), 'fg': const Color(0xFFDC2626)};
      case 'clarification':
      case 'clarification_needed':
        return {'bg': const Color(0xFFFEF3C7), 'fg': const Color(0xFFD97706)};
      case 'pending':
      default:
        return {'bg': const Color(0xFFF1F5F9), 'fg': const Color(0xFF64748B)};
    }
  }

  Widget _buildReqPersonInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: _muted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _onSurface,
          ),
        ),
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
