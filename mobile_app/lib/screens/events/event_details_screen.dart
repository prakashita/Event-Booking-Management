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
import '../../widgets/common/marketing_deliverables_upload_dialog.dart';
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
  bool _expandedActionHistory = false;

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
        value.entries.map(
          (entry) => MapEntry(entry.key.toString(), entry.value),
        ),
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

  List<String> _fallbackRequirementLinesForDepartment(String departmentKey) {
    return _stringList(
      _approval['requirements'],
    ).where((line) => _classifyRequirementLine(line) == departmentKey).toList();
  }

  String _transportTypeLabel(String value) {
    switch (value.trim().toLowerCase()) {
      case 'guest_cab':
        return 'Guest cab';
      case 'students_off_campus':
        return 'Student transport';
      case 'both':
        return 'Guest cab and student transport';
      default:
        return '';
    }
  }

  String _normalizeThreadDepartmentKey(String value) {
    switch (value.trim().toLowerCase()) {
      case 'facility_manager':
        return 'facility';
      default:
        return value.trim().toLowerCase();
    }
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
    if (statuses.any(
      (status) =>
          status == 'clarification' || status == 'clarification_requested',
    )) {
      return 'clarification';
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
      return 'Requester action: send to final approver';
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

  String get _currentUserEmail =>
      (context.read<AuthProvider>().user?.email ?? '').trim().toLowerCase();

  bool get _isRequester {
    final requesterId = _s(_approval['requester_id'], fallback: '');
    final eventOwner = _s(_event['created_by'], fallback: '');
    return _currentUserId.isNotEmpty &&
        (_currentUserId == requesterId || _currentUserId == eventOwner);
  }

  bool get _isApprovalActionable {
    if (_approval['is_actionable'] == false) return false;
    final status = _s(_approval['status'], fallback: '').toLowerCase();
    final pipelineStage = _s(
      _approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();
    final requestedTo = _s(
      _approval['requested_to'],
      fallback: '',
    ).trim().toLowerCase();
    return _approvalRequestId.isNotEmpty &&
        (status == 'pending' ||
            status == 'clarification' ||
            status == 'clarification_requested') &&
        pipelineStage != 'after_deputy' &&
        pipelineStage != 'after_finance' &&
        pipelineStage != 'complete' &&
        (requestedTo.isEmpty || requestedTo == _currentUserEmail);
  }

  bool get _isApprovalStageReviewer {
    return _currentRoleKey == 'registrar' ||
        _currentRoleKey == 'vice_chancellor' ||
        _currentRoleKey == 'deputy_registrar' ||
        _currentRoleKey == 'finance_team';
  }

  bool get _showApprovalActions =>
      _isApprovalActionable &&
      _isApprovalStageReviewer &&
      !_isRequester &&
      _isCurrentApprovalReviewer;

  bool get _isCurrentApprovalReviewer {
    final pipelineStage = _s(
      _approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();

    switch (_currentRoleKey) {
      case 'deputy_registrar':
        return pipelineStage == 'deputy';
      case 'finance_team':
        return pipelineStage == 'finance';
      case 'registrar':
      case 'vice_chancellor':
        return pipelineStage == 'registrar' || pipelineStage.isEmpty;
      default:
        return false;
    }
  }

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

  String _workflowStageLabel() {
    final pipelineStage = _s(
      _approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();
    final approvalStatus = _s(_approval['status'], fallback: '').toLowerCase();
    final currentStageLabel = _s(
      _approval['current_stage_label'],
      fallback: '',
    );
    if (currentStageLabel.isNotEmpty) return currentStageLabel;
    if (approvalStatus == 'approved' &&
        (pipelineStage == 'complete' ||
            _s(_approval['event_id'], fallback: '').isNotEmpty)) {
      return 'Completed';
    }
    if (approvalStatus == 'rejected') return 'Rejected';
    if (approvalStatus == 'clarification' ||
        approvalStatus == 'clarification_requested') {
      if (pipelineStage == 'deputy') return 'Deputy Registrar - Clarification';
      if (pipelineStage == 'finance') return 'Finance - Clarification';
      if (pipelineStage == 'registrar') return 'Registrar - Clarification';
      return 'Clarification';
    }
    if (pipelineStage == 'deputy') return 'Awaiting Deputy Registrar';
    if (pipelineStage == 'after_deputy') {
      return 'Deputy Approved - Forward to Finance';
    }
    if (pipelineStage == 'finance') return 'Awaiting Finance';
    if (pipelineStage == 'after_finance') {
      return 'Finance Approved - Forward to Registrar';
    }
    if (pipelineStage == 'registrar') return 'Awaiting Registrar / VC';
    if (pipelineStage == 'complete') return 'Completed';
    if (approvalStatus == 'pending') return 'Awaiting Approval';
    return 'Pending';
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
        return 'Clarification';
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
    required _ApprovalDecisionAction action,
    required String eventTitle,
    required bool requiredComment,
  }) async {
    final controller = TextEditingController();
    final isApprove = action == _ApprovalDecisionAction.approve;
    final isReject = action == _ApprovalDecisionAction.reject;
    final accent = isApprove
        ? const Color(0xFF16A34A)
        : isReject
        ? const Color(0xFFDC2626)
        : const Color(0xFFD97706);
    final soft = isApprove
        ? const Color(0xFFECFDF5)
        : isReject
        ? const Color(0xFFFEF2F2)
        : const Color(0xFFFFFBEB);
    final border = isApprove
        ? const Color(0xFFA7F3D0)
        : isReject
        ? const Color(0xFFFECACA)
        : const Color(0xFFFDE68A);
    final icon = isApprove
        ? LucideIcons.checkCircle2
        : isReject
        ? LucideIcons.xCircle
        : LucideIcons.messageCircle;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Icon(icon, color: accent, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.poppins(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: _onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            eventTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  isApprove
                      ? 'Approve this request and add a message if needed.'
                      : isReject
                      ? 'Add a reason before rejecting this request.'
                      : 'Ask the requester what needs to be clarified.',
                  style: GoogleFonts.inter(
                    color: _muted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: GoogleFonts.inter(color: _muted),
                    filled: true,
                    fillColor: _panel,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: _border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: accent, width: 1.5),
                    ),
                    helperText: requiredComment
                        ? 'A message is required for this action.'
                        : 'Optional message sent with the approval.',
                    helperStyle: GoogleFonts.inter(color: _muted, fontSize: 12),
                  ),
                  style: GoogleFonts.inter(),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _muted,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(
                          dialogContext,
                        ).pop(controller.text.trim()),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: Text(_decisionLabel(action)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    // Give the dialog exit animation time to finish before disposing the
    // controller. The overlay can still reference it briefly after pop.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    return result;
  }

  Future<void> _handleApprovalDecision(_ApprovalDecisionAction action) async {
    if (!_showApprovalActions || _decisionSubmitting) return;

    final isApprove = action == _ApprovalDecisionAction.approve;
    final isReject = action == _ApprovalDecisionAction.reject;
    final requiresComment = !isApprove;
    final eventTitle = _s(
      _approval['event_name'],
      fallback: _s(_event['name'], fallback: 'this event'),
    );

    final comment = await _promptDecisionComment(
      title: isApprove
          ? 'Approve request'
          : (isReject ? 'Reject request' : 'Request clarification'),
      hint: isApprove
          ? 'Add an optional message for the requester'
          : (isReject ? 'Add rejection reason' : 'Ask for clarification'),
      action: action,
      eventTitle: eventTitle,
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
            style: GoogleFonts.inter(),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    // Let the comment dialog's overlay entries unmount before we trigger
    // network work and a full screen rebuild.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

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
          content: Text(message, style: GoogleFonts.inter()),
          backgroundColor: isApprove
              ? const Color(0xFF16A34A)
              : const Color(0xFF475569),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractApiErrorMessage(e), style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                ? 'Request noted.'
                : decision == 'rejected'
                ? 'Request rejected.'
                : 'Clarification requested.',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: decision == 'approved'
              ? const Color(0xFF16A34A)
              : const Color(0xFF475569),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      await _fetchDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractApiErrorMessage(e), style: GoogleFonts.inter()),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _openDepartmentDecisionDialog(
    String key,
    Map<String, dynamic> request, {
    String initialDecision = 'approved',
  }) async {
    final requestId = _s(request['id'], fallback: '');
    if (requestId.isEmpty || !_canDepartmentTakeAction(request)) return;

    String selected = initialDecision;
    final commentCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final screenWidth = MediaQuery.of(ctx).size.width;
          final dialogWidth = screenWidth < 420 ? screenWidth - 32 : 388.0;
          final isApprove = selected == 'approved';
          final isReject = selected == 'rejected';
          final accent = isApprove
              ? const Color(0xFF16A34A)
              : isReject
              ? const Color(0xFFDC2626)
              : const Color(0xFFD97706);
          final title = _s(
            request['event_title'] ?? request['event_name'] ?? request['name'],
            fallback: 'Requirement request',
          );
          final actionLabel = isApprove
              ? 'Noted'
              : isReject
              ? 'Reject'
              : 'Clarification';

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            child: SizedBox(
              width: dialogWidth,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isApprove
                                ? LucideIcons.checkCircle2
                                : isReject
                                ? LucideIcons.xCircle
                                : LucideIcons.helpCircle,
                            color: accent,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Update ${key.toUpperCase()} request',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  color: _onSurface,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  color: _muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildDepartmentDecisionOption(
                      selected: selected == 'approved',
                      icon: LucideIcons.checkCircle2,
                      label: 'Noted',
                      subtitle: 'Mark this request as handled.',
                      foreground: const Color(0xFF166534),
                      background: const Color(0xFFECFDF5),
                      border: const Color(0xFFA7F3D0),
                      onTap: () => setLocal(() => selected = 'approved'),
                    ),
                    const SizedBox(height: 10),
                    _buildDepartmentDecisionOption(
                      selected: selected == 'clarification_requested',
                      icon: LucideIcons.helpCircle,
                      label: 'Clarification',
                      subtitle: 'Ask the requester for more information.',
                      foreground: const Color(0xFFB45309),
                      background: const Color(0xFFFFFBEB),
                      border: const Color(0xFFFDE68A),
                      onTap: () =>
                          setLocal(() => selected = 'clarification_requested'),
                    ),
                    const SizedBox(height: 10),
                    _buildDepartmentDecisionOption(
                      selected: selected == 'rejected',
                      icon: LucideIcons.xCircle,
                      label: 'Reject',
                      subtitle: 'Decline this request with a reason.',
                      foreground: const Color(0xFFB91C1C),
                      background: const Color(0xFFFEF2F2),
                      border: const Color(0xFFFECACA),
                      onTap: () => setLocal(() => selected = 'rejected'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentCtrl,
                      minLines: 4,
                      maxLines: 6,
                      style: GoogleFonts.inter(),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: isApprove
                            ? 'Add an optional message'
                            : isReject
                            ? 'Add rejection reason'
                            : 'Ask for clarification',
                        helperText: isApprove
                            ? 'Optional message sent with the update.'
                            : 'A message is required for this action.',
                        helperStyle: GoogleFonts.inter(
                          color: _muted,
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: _panel,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: accent, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _muted,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final comment = commentCtrl.text.trim();
                              if (selected != 'approved' && comment.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Comment is required for reject/clarification.',
                                      style: GoogleFonts.inter(),
                                    ),
                                    backgroundColor: const Color(0xFFDC2626),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(
                                ctx,
                              ).pop({'decision': selected, 'comment': comment});
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(actionLabel),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    // Do NOT dispose commentCtrl here — the dialog exit animation may still
    // reference it.  It will be garbage-collected once this scope ends.
    if (result == null) return;
    // Wait for the dialog route's exit animation to finish and the overlay
    // entries to be fully removed before triggering
    // _decideDepartmentRequest → _fetchDetails → setState.
    // Without this delay the overlay entries from the closing dialog cause
    // Duplicate GlobalKey errors and "TextEditingController used after
    // being disposed" exceptions.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _decideDepartmentRequest(
      key,
      requestId,
      result['decision'] ?? 'approved',
      result['comment'] ?? '',
    );
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
        SnackBar(
          content: Text(
            'Marketing deliverables submitted.',
            style: GoogleFonts.inter(),
          ),
          backgroundColor: const Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        SnackBar(
          content: Text(
            'This request only includes during-event marketing. No file uploads are required.',
            style: GoogleFonts.inter(),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    final fileNameByType = <String, String>{
      for (final opt in enabledOptions)
        if (existingByType[opt['type']]?.isNa != true &&
            (existingByType[opt['type']]?.link ?? '').isNotEmpty)
          opt['type']!: existingByType[opt['type']]!.link!,
    };
    await showMarketingDeliverablesUploadDialog(
      context: context,
      enabledOptions: enabledOptions,
      initialNaByType: naByType,
      initialFileNameByType: fileNameByType,
      rowLock: (type) => _marketingDeliverableRowLock(type, request),
      onUpload: ({required naByType, required filesByType}) =>
          _uploadMarketingDeliverablesBatch(
            requestId: requestId,
            naByType: naByType,
            filesByType: filesByType,
          ),
      onConnectGoogle: _connectGoogle,
      extractErrorMessage: _extractApiErrorMessage,
      eventTitle: _s(
        request['event_name'],
        fallback: _s(request['event_title'], fallback: _s(_event['name'])),
      ),
    );
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

  Future<void> _openExternalLink(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) return;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open link', style: GoogleFonts.inter()),
        ),
      );
    }
  }

  void _closeDetails() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(_isApprovalOnlyEntry ? '/approvals' : '/events');
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
        return DateFormat('MMM d, yyyy · h:mm a').format(dt);
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

  bool _canDepartmentTakeAction(Map<String, dynamic> request) {
    final status = _s(request['status'], fallback: '').toLowerCase();
    return (status == 'pending' ||
            status == 'clarification' ||
            status == 'clarification_requested') &&
        !_requestHasStarted(request);
  }

  /// Whether the current user can take action on the department request
  /// linked to this discussion thread.
  bool _canTakeActionOnThread(ApprovalThreadInfo thread) {
    final deptKey = _normalizeThreadDepartmentKey(thread.department);
    if (!_isDepartmentInboxRole) return false;
    if (_viewerDepartmentKey != deptKey) return false;
    final requestId = thread.relatedRequestId;
    if (requestId == null || requestId.isEmpty) return false;
    final request = _findDepartmentRequest(deptKey, requestId);
    if (request == null) return false;
    return _canDepartmentTakeAction(request);
  }

  /// Look up a department request map by department key and request ID.
  Map<String, dynamic>? _findDepartmentRequest(
    String deptKey,
    String requestId,
  ) {
    final listKey = deptKey == 'facility'
        ? 'facility_requests'
        : deptKey == 'it'
        ? 'it_requests'
        : deptKey == 'marketing'
        ? 'marketing_requests'
        : deptKey == 'transport'
        ? 'transport_requests'
        : null;
    if (listKey == null) return null;
    final requests = _mapList(listKey);
    try {
      return requests.firstWhere((r) => _s(r['id'], fallback: '') == requestId);
    } catch (_) {
      return null;
    }
  }

  /// Open the department decision dialog from a discussion thread.
  void _openTakeActionFromThread(
    ApprovalThreadInfo thread, {
    String? initialDecision,
  }) {
    final deptKey = _normalizeThreadDepartmentKey(thread.department);
    final requestId = thread.relatedRequestId;
    if (requestId == null || requestId.isEmpty) return;
    final request = _findDepartmentRequest(deptKey, requestId);
    if (request == null) return;
    _openDepartmentDecisionDialog(
      deptKey,
      request,
      initialDecision: initialDecision ?? 'approved',
    );
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
    // Matching website functionality: uploads are never locked by date.
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
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isApprovalOnlyEntry ? 'Approval Details' : 'Event Details',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _onSurface,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              onPressed: _closeDetails,
              icon: Icon(LucideIcons.x, size: 24, color: _muted),
              style: IconButton.styleFrom(
                backgroundColor: _panel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _border.withValues(alpha: 0.5), height: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.alertCircle,
                                color: Color(0xFFDC2626),
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error ?? 'Failed to load event details',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                color: _onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _fetchDetails,
                              icon: const Icon(LucideIcons.refreshCw, size: 16),
                              label: const Text('Try Again'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildEventOverview(),
                          const SizedBox(height: 24),
                          _isApprovalOnlyEntry
                              ? _buildApprovalContext()
                              : _buildEventWorkflow(),
                          if (_showDiscussionSection) ...[
                            const SizedBox(height: 24),
                            _buildDiscussion(),
                          ],
                          const SizedBox(height: 24),
                          _buildRequirements(),
                          if (_isApprovalOnlyEntry) ...[
                            const SizedBox(height: 24),
                            _buildNotesAndDescription(),
                          ],
                          const SizedBox(height: 40), // Bottom padding
                        ],
                      ),
                    ),
            ),

            // Footer Actions
            if (!_isLoading && _error == null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: _surface,
                  border: Border(
                    top: BorderSide(color: _border.withValues(alpha: 0.5)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isDark ? 0.2 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton(
                      onPressed: _closeDetails,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _panel,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: _border),
                      ),
                      child: Text(
                        'Close',
                        style: GoogleFonts.inter(
                          color: _onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!_isApprovalOnlyEntry && _canSendRequirements)
                      FilledButton.icon(
                        onPressed: () {
                          final sendableDepartments =
                              _sendableRequirementDepartments;
                          if (sendableDepartments.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'All requirement requests are already active.',
                                  style: GoogleFonts.inter(),
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
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
                        icon: const Icon(LucideIcons.send, size: 16),
                        label: const Text('Send Requirements'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.04),
            offset: const Offset(0, 4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF2563EB), size: 18),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _onSurface,
                  letterSpacing: -0.3,
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
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: _muted),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
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
      title: 'Event Overview',
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
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _onSurface,
              ),
            ),
          ),
          if (showRequester)
            _buildLabelValue(
              LucideIcons.mail,
              'Requester',
              Text(
                _s(approval['requester_email'], fallback: 'Unknown'),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF2563EB),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          _buildLabelValue(
            LucideIcons.user,
            'Facilitator',
            Text(
              _s(event['facilitator'], fallback: _s(approval['facilitator'])),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _onSurface,
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.mapPin,
            'Venue',
            Text(
              _s(event['venue_name'], fallback: _s(approval['venue_name'])),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _onSurface,
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
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _onSurface,
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
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _onSurface,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: budgetOpenLink.isEmpty
                          ? null
                          : () => _openExternalLink(budgetOpenLink),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: hasBudgetFile
                              ? const Color(0xFFEFF6FF)
                              : _panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasBudgetFile
                                ? const Color(0xFFBFDBFE)
                                : _border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasBudgetFile
                                  ? LucideIcons.fileText
                                  : LucideIcons.fileMinus,
                              size: 14,
                              color: hasBudgetFile
                                  ? const Color(0xFF2563EB)
                                  : _muted,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                hasBudgetFile
                                    ? (budgetFileName.isEmpty
                                          ? 'Budget breakdown (PDF)'
                                          : budgetFileName)
                                    : 'No budget file',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: hasBudgetFile
                                      ? const Color(0xFF2563EB)
                                      : _muted,
                                ),
                              ),
                            ),
                          ],
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
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _displayStatusLabel(approvalStatus).toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFD97706),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '· Event:',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _muted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              status.toUpperCase().replaceAll('_', ' '),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4B5563),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status.toUpperCase().replaceAll('_', ' '),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFD97706),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
          ),
          _buildLabelValue(
            LucideIcons.calendarDays,
            'Duration',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(event['start_date'], event['start_time']),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  width: 2,
                  height: 12,
                  margin: const EdgeInsets.only(left: 3, top: 4, bottom: 4),
                  color: _border,
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateTime(event['end_date'], event['end_time']),
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildLabelValue(
            LucideIcons.alignLeft,
            'Description',
            Text(
              _s(
                event['description'],
                fallback: _s(
                  approval['description'],
                  fallback: 'No description provided.',
                ),
              ),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _onSurface,
                height: 1.5,
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
    final pipelineStage = _s(
      approval['pipeline_stage'],
      fallback: '',
    ).toLowerCase();
    final deputyDone = _s(
      approval['deputy_decided_by'],
      fallback: '',
    ).isNotEmpty;
    final financeDone = _s(
      approval['finance_decided_by'],
      fallback: '',
    ).isNotEmpty;
    final registrarDone =
        status.toLowerCase() == 'approved' &&
        (pipelineStage == 'complete' || pipelineStage.isEmpty);
    final deputyActive =
        !deputyDone &&
        (pipelineStage == 'deputy' || pipelineStage == 'after_deputy');
    final financeActive =
        !financeDone &&
        (pipelineStage == 'finance' || pipelineStage == 'after_finance');
    final registrarActive = !registrarDone && pipelineStage == 'registrar';

    return _buildCard(
      icon: LucideIcons.shieldCheck,
      title: 'Approval Context',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border.withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CURRENT STATUS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusValue.contains('approved')
                              ? const Color(0xFFDCFCE7)
                              : statusValue.contains('reject')
                              ? const Color(0xFFFEE2E2)
                              : statusValue.contains('clarification')
                              ? const Color(0xFFE0E7FF)
                              : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _displayStatusLabel(status),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: statusValue.contains('approved')
                                ? const Color(0xFF166534)
                                : statusValue.contains('reject')
                                ? const Color(0xFF991B1B)
                                : statusValue.contains('clarification')
                                ? const Color(0xFF3730A3)
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: _border,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PIPELINE STAGE',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _workflowStageLabel(),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
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

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildApprovalFlowNode(
                  label: 'Deputy Registrar',
                  subtitle: deputyDone
                      ? _s(approval['deputy_decided_by'], fallback: '')
                      : deputyActive
                      ? 'Awaiting Review'
                      : 'Not started',
                  isDone: deputyDone,
                  isActive: deputyActive,
                  showConnector: true,
                ),
                _buildApprovalFlowNode(
                  label: 'Finance Team',
                  subtitle: financeDone
                      ? _s(approval['finance_decided_by'], fallback: '')
                      : financeActive
                      ? 'Awaiting Review'
                      : 'Not started',
                  isDone: financeDone,
                  isActive: financeActive,
                  showConnector: true,
                ),
                _buildApprovalFlowNode(
                  label: 'Registrar / VC',
                  subtitle: registrarDone
                      ? _s(approval['decided_by'], fallback: 'Approved')
                      : registrarActive
                      ? 'Awaiting Final Review'
                      : 'Not started',
                  isDone: registrarDone,
                  isActive: registrarActive,
                  showConnector: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (discussionStatus.isNotEmpty &&
              (statusValue.contains('clarification') ||
                  discussionStatus.contains('waiting'))) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: discussionStatus.contains('waiting_for_faculty')
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: discussionStatus.contains('waiting_for_faculty')
                      ? const Color(0xFFFED7AA)
                      : const Color(0xFFC7D2FE),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    discussionStatus.contains('waiting_for_faculty')
                        ? LucideIcons.alertCircle
                        : LucideIcons.info,
                    size: 20,
                    color: discussionStatus.contains('waiting_for_faculty')
                        ? const Color(0xFFC2410C)
                        : const Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      discussionStatus.contains('waiting_for_faculty')
                          ? (_isRequester
                                ? 'The reviewer has requested clarification. Please review and reply in the discussion section.'
                                : 'Waiting for the faculty to respond to your clarification request.')
                          : (_isRequester
                                ? 'Your reply has been sent. Waiting for the reviewer to take action.'
                                : 'The faculty has replied. Please review their response.'),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: discussionStatus.contains('waiting_for_faculty')
                            ? const Color(0xFF9A3412)
                            : const Color(0xFF3730A3),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          _buildLabelValue(
            null,
            'Requested To',
            _buildApprovalPersonValue(
              email: _s(approval['requested_to'], fallback: 'None'),
              emailColor: const Color(0xFF2563EB),
            ),
          ),

          if (approval['decided_by'] != null &&
              approval['decided_by'].toString().trim().isNotEmpty)
            _buildLabelValue(
              null,
              'Final Decision By',
              _buildApprovalPersonValue(
                email: _s(approval['decided_by'], fallback: ''),
                role: _getApprovedByRoleLabel(approval),
              ),
            ),

          if (_showApprovalActions) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          LucideIcons.clipboardCheck,
                          color: Color(0xFF2563EB),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your action required',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Choose the next step for this approval.',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      _buildDecisionActionTile(
                        label: 'Approve',
                        subtitle: 'Move this approval to the next stage.',
                        icon: LucideIcons.checkCircle2,
                        foreground: const Color(0xFF166534),
                        background: const Color(0xFFECFDF5),
                        border: const Color(0xFFA7F3D0),
                        onTap: () => _handleApprovalDecision(
                          _ApprovalDecisionAction.approve,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildDecisionActionTile(
                        label: 'Clarification',
                        subtitle: 'Ask the requester for more information.',
                        icon: LucideIcons.messageCircle,
                        foreground: const Color(0xFFD97706),
                        background: const Color(0xFFFFFBEB),
                        border: const Color(0xFFFDE68A),
                        onTap: () => _handleApprovalDecision(
                          _ApprovalDecisionAction.clarify,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildDecisionActionTile(
                        label: 'Reject',
                        subtitle: 'Decline this request with a reason.',
                        icon: LucideIcons.xCircle,
                        foreground: const Color(0xFFDC2626),
                        background: const Color(0xFFFEF2F2),
                        border: const Color(0xFFFECACA),
                        onTap: () => _handleApprovalDecision(
                          _ApprovalDecisionAction.reject,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Approve can include an optional message. Reject and clarification require a comment.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalFlowNode({
    required String label,
    required String subtitle,
    required bool isDone,
    required bool isActive,
    required bool showConnector,
  }) {
    final borderColor = isDone
        ? const Color(0xFF10B981)
        : isActive
        ? const Color(0xFF8B5CF6)
        : _border;
    final subtitleColor = isDone
        ? const Color(0xFF059669)
        : isActive
        ? const Color(0xFF6D28D9)
        : _muted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isDone ? const Color(0xFF10B981) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 2),
              ),
              child: isDone
                  ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                  : isActive
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF8B5CF6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            if (showConnector)
              Container(
                width: 2,
                height: 32,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isDone ? const Color(0xFF6EE7B7) : _border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontStyle: isDone ? FontStyle.normal : FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildApprovalPersonValue({
    required String email,
    String role = '',
    Color? emailColor,
  }) {
    final trimmedRole = role.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: emailColor ?? _onSurface,
          ),
        ),
        if (trimmedRole.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Text(
              trimmedRole,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1D4ED8),
              ),
            ),
          ),
        ],
      ],
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

    final finalApprovalStep = (
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
      finalApprovalStep,
      facilityStep,
      itStep,
      marketingStep,
      iqacStep,
    ];

    return _buildCard(
      icon: LucideIcons.gitBranch,
      title: 'Approval Flow',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 20, color: _muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Registrar through IQAC. Multiple requests for one team are aggregated into a single status.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
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
    final teamWorkflow =
        label == 'Facility' ||
        label == 'Marketing' ||
        label == 'IT' ||
        label == 'Transport';
    final isDone = normalized == 'approved' || normalized == 'accepted';
    final isPending = normalized == 'pending';
    final isClarification =
        normalized == 'clarification' ||
        normalized == 'clarification_requested';
    final showBadge = normalized.isNotEmpty && normalized != 'none';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isDone
                ? const Color(0xFF10B981)
                : isPending || isClarification
                ? const Color(0xFFF59E0B)
                : _panel,
            shape: BoxShape.circle,
            border: Border.all(
              color: isDone
                  ? const Color(0xFF10B981)
                  : isPending || isClarification
                  ? const Color(0xFFF59E0B)
                  : _border,
              width: 2,
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                : null,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          teamWorkflow && normalized == 'approved'
                              ? 'NOTED'
                              : normalized.replaceAll('_', ' ').toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors['fg'] as Color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (assignee.isNotEmpty)
                  Text(
                    assignee,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  )
                else if (normalized == 'none')
                  Text(
                    'No record yet',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: _muted,
                    ),
                  ),
                if (updatedAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    () {
                      try {
                        final dt = DateTime.parse(updatedAt);
                        return DateFormat('MMM d, yyyy · h:mm a').format(dt);
                      } catch (_) {
                        return updatedAt;
                      }
                    }(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
  }

  Widget _buildPipelineConnector() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 2,
            height: 24,
            margin: const EdgeInsets.only(left: 11),
            decoration: BoxDecoration(
              color: _border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _buildDecisionActionTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color foreground,
    required Color background,
    required Color border,
    required VoidCallback onTap,
  }) {
    final disabled = _decisionSubmitting;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: disabled ? _surface : background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: disabled ? _border : border, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _surface.withValues(alpha: _isDark ? 0.16 : 0.82),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: foreground, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      disabled ? 'Working...' : label,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: disabled ? _muted : foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: _muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, color: foreground, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentDecisionOption({
    required bool selected,
    required IconData icon,
    required String label,
    required String subtitle,
    required Color foreground,
    required Color background,
    required Color border,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? background : _panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? border : _border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _surface.withValues(alpha: _isDark ? 0.16 : 0.82),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: foreground, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: _muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.check, color: foreground, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreadDecisionButton({
    required String label,
    required IconData icon,
    required Color foreground,
    required Color background,
    required Color border,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _surface.withValues(alpha: _isDark ? 0.16 : 0.76),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: foreground),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: foreground),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreadDecisionActions(ApprovalThreadInfo thread) {
    final actions = [
      _buildThreadDecisionButton(
        label: 'Noted',
        icon: LucideIcons.checkCircle2,
        foreground: const Color(0xFF16A34A),
        background: const Color(0xFFECFDF5),
        border: const Color(0xFFA7F3D0),
        onPressed: () =>
            _openTakeActionFromThread(thread, initialDecision: 'approved'),
      ),
      _buildThreadDecisionButton(
        label: 'Reject',
        icon: LucideIcons.xCircle,
        foreground: const Color(0xFFDC2626),
        background: const Color(0xFFFEF2F2),
        border: const Color(0xFFFECACA),
        onPressed: () =>
            _openTakeActionFromThread(thread, initialDecision: 'rejected'),
      ),
      _buildThreadDecisionButton(
        label: 'Clarification',
        icon: LucideIcons.helpCircle,
        foreground: const Color(0xFFD97706),
        background: const Color(0xFFFFFBEB),
        border: const Color(0xFFFDE68A),
        onPressed: () => _openTakeActionFromThread(
          thread,
          initialDecision: 'clarification_requested',
        ),
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Update request',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          actions[0],
          const SizedBox(height: 10),
          actions[1],
          const SizedBox(height: 10),
          actions[2],
        ],
      ),
    );
  }

  Widget _buildDiscussion() {
    final approvalThreads = _approvalThreads;
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.messageSquare,
                color: Color(0xFF2563EB),
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
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
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Approval clarification threads and comments.',
                    style: GoogleFonts.inter(fontSize: 13, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (approvalThreads.isEmpty && actionLogs.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 20, color: _muted),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'No approval discussion threads yet.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: _muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (approvalThreads.isNotEmpty)
            ...approvalThreads.map(
              (thread) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildThreadPanel(thread, showRequestStatus: false),
              ),
            ),
          if (actionLogs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildActionHistory(actionLogs),
          ],
        ],
        if (_discussionError != null &&
            _discussionError!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  size: 18,
                  color: Color(0xFFDC2626),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _discussionError!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF991B1B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_isRequester && _approvalRequestId.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildNewDiscussionPanel(availableDepartments),
        ],
      ],
    );
  }

  Widget _buildNewDiscussionPanel(
    List<({String value, String label})> options,
  ) {
    if (options.isEmpty) {
      return Text(
        'You already have active discussion threads for all supported departments.',
        style: GoogleFonts.inter(
          fontSize: 13,
          color: _muted,
          fontWeight: FontWeight.w500,
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
        label: const Text('Start New Discussion'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4F46E5),
          side: const BorderSide(color: Color(0xFF4F46E5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start a discussion with',
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _onSurface,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _newDiscussionDepartment.isEmpty
                ? null
                : _newDiscussionDepartment,
            items: options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.value,
                    child: Text(option.label, style: GoogleFonts.inter()),
                  ),
                )
                .toList(),
            decoration: InputDecoration(
              labelText: 'Department',
              labelStyle: GoogleFonts.inter(color: _muted),
              filled: true,
              fillColor: _panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _newDiscussionDepartment = value ?? '';
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _newDiscussionMessageCtrl,
            minLines: 3,
            maxLines: 5,
            style: GoogleFonts.inter(),
            decoration: InputDecoration(
              labelText: 'Opening message (optional)',
              labelStyle: GoogleFonts.inter(color: _muted),
              filled: true,
              fillColor: _panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
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
                style: TextButton.styleFrom(
                  foregroundColor: _muted,
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed:
                    _creatingDiscussion || _newDiscussionDepartment.isEmpty
                    ? null
                    : _startDiscussion,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                child: Text(
                  _creatingDiscussion ? 'Creating...' : 'Start Discussion',
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
    if (t == 'clarification') return 'Clarification';
    if (t == 'reply' || t == 'discussion_reply') return 'Reply';
    return actionType;
  }

  Widget _buildActionHistory(List<dynamic> actionLogs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _expandedActionHistory = !_expandedActionHistory;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(LucideIcons.history, size: 20, color: _muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Action History',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _onSurface,
                    ),
                  ),
                ),
                Icon(
                  _expandedActionHistory
                      ? LucideIcons.chevronUp
                      : LucideIcons.chevronDown,
                  size: 20,
                  color: _muted,
                ),
              ],
            ),
          ),
        ),
        if (_expandedActionHistory)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border(
                left: BorderSide(color: _border.withValues(alpha: 0.5)),
                right: BorderSide(color: _border.withValues(alpha: 0.5)),
                bottom: BorderSide(color: _border.withValues(alpha: 0.5)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                ...actionLogs.map((log) {
                  final role = _formatWorkflowRoleLabel(
                    log['role']?.toString(),
                  );
                  final rawRole = log['role']?.toString().toLowerCase() ?? '';
                  final rawActionType =
                      log['action_type']?.toString().toLowerCase() ?? '';
                  final actionType =
                      {
                            'facility_manager',
                            'marketing',
                            'it',
                            'transport',
                            'iqac',
                          }.contains(rawRole) &&
                          rawActionType == 'approve'
                      ? 'Noted'
                      : _formatWorkflowActionTypeLabel(rawActionType);
                  final comment = log['comment']?.toString() ?? '';
                  final createdAt = log['created_at']?.toString();
                  final actorName = log['actor_name']?.toString() ?? '';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
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
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                actionType,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: actionType.contains('Approved')
                                      ? const Color(0xFF166534)
                                      : actionType.contains('Rejected')
                                      ? const Color(0xFF991B1B)
                                      : actionType.contains('clarification')
                                      ? const Color(0xFF3730A3)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                role,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: _muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (actorName.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            actorName,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _onSurface,
                            ),
                          ),
                        ],
                        if (comment.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            comment,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: _onSurface,
                              height: 1.5,
                            ),
                          ),
                        ],
                        if (createdAt != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            () {
                              try {
                                final dt = DateTime.parse(createdAt);
                                return DateFormat(
                                  'MMM d, yyyy · h:mm a',
                                ).format(dt);
                              } catch (_) {
                                return createdAt;
                              }
                            }(),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: _muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildThreadPanel(
    ApprovalThreadInfo thread, {
    required bool showRequestStatus,
  }) {
    final isExpanded = _expandedDiscussionThreads[thread.id] ?? true;
    final canReply =
        _userIsThreadParticipant(thread) && !_threadIsLocked(thread);
    final canTakeThreadAction =
        _canTakeActionOnThread(thread) && !_threadIsLocked(thread);
    final replyController = _replyControllerFor(thread.id);
    final replyTarget = _replyTargets[thread.id];
    final statusColor = _threadStatusColor(thread.threadStatus);

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.04),
            offset: const Offset(0, 4),
            blurRadius: 16,
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
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isExpanded ? _panel : Colors.transparent,
                borderRadius: isExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(16))
                    : BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            thread.departmentLabel,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1D4ED8),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Text(
                          '${thread.messages.length} message${thread.messages.length == 1 ? '' : 's'}',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor['bg'] as Color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _threadStatusLabel(thread.threadStatus),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor['fg'] as Color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        isExpanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 20,
                        color: _muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.all(20),
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
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _pageBg,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _border),
                              ),
                              child: Text(
                                '${participant.name}${participant.role.isEmpty ? '' : ' (${participant.role})'}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _muted,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (showRequestStatus &&
                      (thread.deptRequestStatus ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Request status: ${thread.deptRequestStatus!.replaceAll('_', ' ')}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (thread.messages.isEmpty)
                    Text(
                      'No messages yet.',
                      style: GoogleFonts.inter(fontSize: 14, color: _muted),
                    )
                  else
                    ...thread.messages.map(
                      (message) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildThreadMessage(thread, message),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => context.push('/chat/${thread.id}'),
                        icon: const Icon(LucideIcons.externalLink, size: 14),
                        label: const Text('Open in Full Chat'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          textStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_threadIsLocked(thread))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          thread.closedAt != null
                              ? 'This discussion has been ${_threadStatusLabel(thread.threadStatus).toLowerCase()} since ${DateFormat('MMM d, yyyy').format(thread.closedAt!)}.'
                              : 'This discussion is ${_threadStatusLabel(thread.threadStatus).toLowerCase()}.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  if (canReply) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(),
                    ),
                    if (replyTarget != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _pageBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 30,
                              color: const Color(0xFF2563EB),
                              margin: const EdgeInsets.only(right: 12),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Replying to ${replyTarget.senderName}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF2563EB),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    replyTarget.content.isEmpty
                                        ? 'Message'
                                        : replyTarget.content,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _replyTargets.remove(thread.id);
                                });
                              },
                              icon: const Icon(LucideIcons.x, size: 16),
                              style: IconButton.styleFrom(
                                backgroundColor: _surface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: replyController,
                      minLines: 2,
                      maxLines: 4,
                      style: GoogleFonts.inter(),
                      decoration: InputDecoration(
                        hintText: 'Type your reply...',
                        hintStyle: GoogleFonts.inter(color: _muted),
                        filled: true,
                        fillColor: _pageBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (canTakeThreadAction) ...[
                      _buildThreadDecisionActions(thread),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _submittingReplyThreads.contains(thread.id)
                            ? null
                            : () => _submitThreadReply(thread),
                        icon: const Icon(LucideIcons.send, size: 16),
                        label: Text(
                          _submittingReplyThreads.contains(thread.id)
                              ? 'Posting...'
                              : 'Post Reply',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (!canReply && canTakeThreadAction) ...[
                    const SizedBox(height: 12),
                    _buildThreadDecisionActions(thread),
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isOwn ? const Color(0xFFEFF6FF) : _pageBg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isOwn
                  ? const Radius.circular(16)
                  : const Radius.circular(4),
              bottomRight: isOwn
                  ? const Radius.circular(4)
                  : const Radius.circular(16),
            ),
            border: Border.all(
              color: isOwn ? const Color(0xFFBFDBFE) : _border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isOwn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    message.senderName,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ),
              if (message.replyToSnapshot != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: _isDark ? 0.05 : 0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isOwn ? const Color(0xFF93C5FD) : _border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 30,
                        color: isOwn ? const Color(0xFF3B82F6) : _muted,
                        margin: const EdgeInsets.only(right: 10),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.replyToSnapshot!.senderName,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isOwn ? const Color(0xFF1D4ED8) : _muted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              message.replyToSnapshot!.contentPreview.isEmpty
                                  ? 'Message'
                                  : message.replyToSnapshot!.contentPreview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Text(
                message.content.isEmpty ? '—' : message.content,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: _onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat(
                      'MMM d, yyyy · h:mm a',
                    ).format(message.createdAt),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                  if (_userIsThreadParticipant(thread) &&
                      !_threadIsLocked(thread))
                    InkWell(
                      onTap: () {
                        setState(() {
                          _replyTargets[thread.id] = message;
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.reply, size: 12, color: _muted),
                            const SizedBox(width: 4),
                            Text(
                              'Reply',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
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
      final selectedIndex = items.indexWhere(
        (item) => item.key == highlightDept,
      );
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.layers,
                color: Color(0xFF2563EB),
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Requirements',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _onSurface,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Expand to view department-specific tasks.',
                    style: GoogleFonts.inter(fontSize: 13, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
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
          final fallbackLines = item.key == 'iqac'
              ? const <String>[]
              : _fallbackRequirementLinesForDepartment(item.key);
          final deptIcon = _getDepartmentIcon(item.key);
          final isYourDept = _isYourDepartment(item.key);
          final statusColor = _getRequirementStatusColor(item.status);

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                border: Border.all(
                  color: isYourDept
                      ? const Color(0xFF3B82F6)
                      : _border.withValues(alpha: 0.6),
                  width: isYourDept ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.04),
                    offset: const Offset(0, 4),
                    blurRadius: 16,
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
                    borderRadius: BorderRadius.vertical(
                      top: const Radius.circular(16),
                      bottom: isOpen ? Radius.zero : const Radius.circular(16),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isOpen ? _panel : Colors.transparent,
                        borderRadius: BorderRadius.vertical(
                          top: const Radius.circular(16),
                          bottom: isOpen
                              ? Radius.zero
                              : const Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  deptIcon,
                                  size: 16,
                                  color: const Color(0xFF2563EB),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.title,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: _onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (isYourDept)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDBEAFE),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'YOUR DEPT',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF1D4ED8),
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor['bg'] as Color,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        (item.status.replaceAll(
                                          '_',
                                          ' ',
                                        )).toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: statusColor['fg'] as Color,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                isOpen
                                    ? LucideIcons.chevronUp
                                    : LucideIcons.chevronDown,
                                size: 20,
                                color: _muted,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isOpen)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        border: Border(
                          top: BorderSide(color: _border, width: 1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (source.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _panel,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _border),
                              ),
                              child: item.key == 'iqac'
                                  ? _buildRequirementPhases(
                                      item.key,
                                      const <String, dynamic>{},
                                    )
                                  : fallbackLines.isNotEmpty
                                  ? _buildRequirementPhaseSection(
                                      'General tasks',
                                      fallbackLines,
                                    )
                                  : Row(
                                      children: [
                                        Icon(
                                          LucideIcons.info,
                                          size: 18,
                                          color: _muted,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            'No requests created yet.',
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              color: _muted,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            )
                          else ...[
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
                                        ? DateFormat('MMM d, yyyy').format(
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
                              final relevantMarketingOptions =
                                  item.key == 'marketing'
                                  ? _marketingDeliverableOptions
                                        .where(
                                          (opt) =>
                                              uploadFlags[opt['key']] == true,
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
                              final uploadHint =
                                  canUploadMarketing &&
                                      relevantMarketingOptions.isNotEmpty &&
                                      !uploadEnabled
                                  ? _marketingDeliverableRowLock(
                                      relevantMarketingOptions.first['type']!,
                                      req,
                                    ).hint
                                  : '';
                              final deliverables =
                                  (req['deliverables'] as List? ?? [])
                                      .whereType<Map<String, dynamic>>()
                                      .toList();
                              final requesterAttachments =
                                  (req['requester_attachments'] as List? ?? [])
                                      .whereType<Map<String, dynamic>>()
                                      .toList();
                              final reportLink = item.key == 'iqac'
                                  ? _s(
                                      _event['report_web_view_link'],
                                      fallback: '',
                                    )
                                  : '';
                              final reportName = item.key == 'iqac'
                                  ? _s(_event['report_file_name'], fallback: '')
                                  : '';

                              return Container(
                                margin: EdgeInsets.only(
                                  top: index > 0 ? 20 : 0,
                                ),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _panel,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                reqStatusColor['bg'] as Color,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            _formatRequirementStatusText(
                                              reqStatus,
                                            ),
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  reqStatusColor['fg'] as Color,
                                            ),
                                          ),
                                        ),
                                        if (requestedTo != 'Unassigned')
                                          _buildRequirementMetaChip(
                                            'ASSIGNED TO',
                                            requestedTo,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    if (decidedBy != '—' || decidedAt != '—')
                                      Text(
                                        [
                                          if (decidedBy != '—')
                                            'Decided by $decidedBy',
                                          if (decidedAt != '—') decidedAt,
                                        ].join(' • '),
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: _muted,
                                        ),
                                      ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Divider(),
                                    ),
                                    _buildRequirementPhases(
                                      item.key,
                                      req,
                                      requesterAttachments:
                                          requesterAttachments,
                                      deliverables: deliverables,
                                      reportLink: reportLink,
                                      reportName: reportName,
                                    ),
                                    if (reqStatus.toLowerCase() ==
                                            'clarification' ||
                                        reqStatus.toLowerCase() ==
                                            'clarification_requested') ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFFBEB),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFDE68A),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              LucideIcons.alertTriangle,
                                              size: 16,
                                              color: Color(0xFFD97706),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                'Clarification requested. See the Discussion section above to respond.',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(
                                                    0xFFB45309,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if ((canTakeAction || canUploadMarketing) &&
                                        reqId.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          if (canTakeAction)
                                            FilledButton.icon(
                                              onPressed: () =>
                                                  _openDepartmentDecisionDialog(
                                                    item.key,
                                                    req,
                                                  ),
                                              icon: const Icon(
                                                LucideIcons.checkSquare,
                                                size: 16,
                                              ),
                                              label: const Text('Take Action'),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: const Color(
                                                  0xFF2563EB,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                textStyle: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          if (canUploadMarketing)
                                            OutlinedButton.icon(
                                              onPressed: uploadEnabled
                                                  ? () =>
                                                        _openMarketingUploadDialog(
                                                          req,
                                                        )
                                                  : null,
                                              icon: const Icon(
                                                LucideIcons.uploadCloud,
                                                size: 16,
                                              ),
                                              label: const Text(
                                                'Upload Assets',
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                textStyle: GoogleFonts.inter(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                foregroundColor: const Color(
                                                  0xFF2563EB,
                                                ),
                                                side: const BorderSide(
                                                  color: Color(0xFF2563EB),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (canUploadMarketing &&
                                          !uploadEnabled &&
                                          uploadHint.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          uploadHint,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: _muted,
                                            fontWeight: FontWeight.w500,
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
        return {'bg': const Color(0xFFDCFCE7), 'fg': const Color(0xFF166534)};
      case 'rejected':
      case 'declined':
        return {'bg': const Color(0xFFFEE2E2), 'fg': const Color(0xFF991B1B)};
      case 'clarification':
      case 'clarification_requested':
      case 'clarification_needed':
        return {'bg': const Color(0xFFFEF3C7), 'fg': const Color(0xFFB45309)};
      case 'pending':
      default:
        return {'bg': const Color(0xFFF1F5F9), 'fg': const Color(0xFF475569)};
    }
  }

  String _formatRequirementStatusText(String status) {
    final value = status.trim();
    if (value.isEmpty) return 'Pending';
    final normalized = value.toLowerCase();
    if (normalized == 'clarification' ||
        normalized == 'clarification_requested' ||
        normalized == 'clarification_needed') {
      return 'Clarification';
    }
    return value
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _displayStatusLabel(String status) {
    final normalized = status.trim().toLowerCase();
    if (normalized.isEmpty) return 'Pending';
    if (normalized == 'clarification' ||
        normalized == 'clarification_requested' ||
        normalized == 'clarification_needed') {
      return 'Clarification';
    }
    return status.replaceAll('_', ' ');
  }

  Widget _buildRequirementMetaChip(String label, String value) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 12,
          color: _muted,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: '$label  '),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Color(0xFF2563EB),
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementPhases(
    String departmentKey,
    Map<String, dynamic> request, {
    List<Map<String, dynamic>> requesterAttachments = const [],
    List<Map<String, dynamic>> deliverables = const [],
    String reportLink = '',
    String reportName = '',
  }) {
    final preEvent = _buildRequirementPhaseItems(departmentKey, request, 'pre');
    final duringEvent = _buildRequirementPhaseItems(
      departmentKey,
      request,
      'during',
    );
    final postEvent = _buildRequirementPhaseItems(
      departmentKey,
      request,
      'post',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preEvent.isNotEmpty)
          _buildRequirementPhaseSection('Pre-Event', preEvent),
        if (duringEvent.isNotEmpty) ...[
          if (preEvent.isNotEmpty) const SizedBox(height: 20),
          _buildRequirementPhaseSection('During Event', duringEvent),
        ],
        if (postEvent.isNotEmpty) ...[
          if (preEvent.isNotEmpty || duringEvent.isNotEmpty)
            const SizedBox(height: 20),
          _buildRequirementPhaseSection('Post-Event', postEvent),
        ],
        if (departmentKey == 'marketing') ...[
          if (preEvent.isNotEmpty ||
              duringEvent.isNotEmpty ||
              postEvent.isNotEmpty)
            const SizedBox(height: 24),
          if (requesterAttachments.isNotEmpty)
            _buildRequirementLinkSection(
              'Requester Reference Documents',
              requesterAttachments.map((attachment) {
                return (
                  label: _s(attachment['file_name'], fallback: 'Document'),
                  link: _s(attachment['web_view_link'], fallback: ''),
                );
              }).toList(),
            ),
          if (requesterAttachments.isNotEmpty) const SizedBox(height: 20),
          _buildMarketingDeliverablesSection(deliverables),
        ],
        if (departmentKey == 'iqac') ...[
          if (reportLink.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildRequirementLinkSection('Uploaded Deliverables', [
              (
                label: reportName.isEmpty ? 'View Event Report' : reportName,
                link: reportLink,
              ),
            ]),
          ],
        ],
      ],
    );
  }

  List<String> _buildRequirementPhaseItems(
    String departmentKey,
    Map<String, dynamic> request,
    String phase,
  ) {
    switch (departmentKey) {
      case 'facility':
        if (phase != 'pre') return const [];
        final items = <String>[];
        if (request['venue_required'] == true) {
          items.add('Hall / venue booking');
        }
        if (request['refreshments'] == true) {
          items.add('Refreshments');
        }
        final notes = _s(request['other_notes'], fallback: '');
        if (notes.isNotEmpty) items.add('Notes: $notes');
        if (items.isEmpty) items.add('General facility coordination');
        return items;
      case 'it':
        if (phase != 'pre') return const [];
        final items = <String>[];
        final mode = _s(request['event_mode'], fallback: '');
        if (mode.isNotEmpty) items.add('Event mode: $mode');
        if (request['pa_system'] == true) items.add('PA system');
        if (request['projection'] == true) items.add('Projection / display');
        final notes = _s(request['other_notes'], fallback: '');
        if (notes.isNotEmpty) items.add('Notes: $notes');
        if (items.isEmpty) items.add('General IT support');
        return items;
      case 'marketing':
        final normalized = _normalizeMarketingRequirementsFromMap(request);
        final pre = normalized['pre_event'] as Map<String, dynamic>;
        final during = normalized['during_event'] as Map<String, dynamic>;
        final post = normalized['post_event'] as Map<String, dynamic>;
        if (phase == 'pre') {
          final items = <String>[];
          if (pre['poster'] == true) items.add('Poster');
          if (pre['social_media'] == true) items.add('Social Media Post');
          final notes = _s(request['other_notes'], fallback: '');
          if (notes.isNotEmpty) items.add(notes);
          return items;
        }
        if (phase == 'during') {
          final items = <String>[];
          if (during['photo'] == true) items.add('Photoshoot');
          if (during['video'] == true) items.add('Videoshoot');
          return items;
        }
        if (phase == 'post') {
          final items = <String>[];
          if (post['social_media'] == true) items.add('Social Media Upload');
          if (post['photo_upload'] == true) items.add('Photo Upload');
          if (post['video'] == true) items.add('Video Upload');
          return items;
        }
        return const [];
      case 'transport':
        if (phase != 'pre') return const [];
        final items = <String>[];
        final transportType = _s(
          request['transport_type'],
          fallback: '',
        ).toLowerCase();
        final hasGuestTransport =
            transportType == 'guest_cab' ||
            transportType == 'both' ||
            _s(request['guest_pickup_location'], fallback: '').isNotEmpty ||
            _s(request['guest_dropoff_location'], fallback: '').isNotEmpty;
        final hasStudentTransport =
            transportType == 'students_off_campus' ||
            transportType == 'both' ||
            _s(request['student_count'], fallback: '').isNotEmpty ||
            _s(request['student_transport_kind'], fallback: '').isNotEmpty;

        final typeLabel = _transportTypeLabel(transportType);
        if (typeLabel.isNotEmpty) {
          items.add(typeLabel);
        }
        if (hasGuestTransport) {
          items.add('Guest cab');
          final pickup = [
            _s(request['guest_pickup_location'], fallback: ''),
            _s(request['guest_pickup_date'], fallback: ''),
            _s(request['guest_pickup_time'], fallback: ''),
          ].where((part) => part.isNotEmpty).join(' · ');
          if (pickup.isNotEmpty) {
            items.add('Guest pickup: $pickup');
          }
          final dropoff = [
            _s(request['guest_dropoff_location'], fallback: ''),
            _s(request['guest_dropoff_date'], fallback: ''),
            _s(request['guest_dropoff_time'], fallback: ''),
          ].where((part) => part.isNotEmpty).join(' · ');
          if (dropoff.isNotEmpty) {
            items.add('Guest drop-off: $dropoff');
          }
        }
        if (hasStudentTransport) {
          final count = _s(request['student_count'], fallback: '');
          final kind = _s(request['student_transport_kind'], fallback: '');
          final summary = [
            'Student transport',
            if (count.isNotEmpty) '$count passengers',
            if (kind.isNotEmpty) kind,
          ].join(' · ');
          items.add(summary);
          final studentPickup = [
            _s(request['student_pickup_point'], fallback: ''),
            _s(request['student_date'], fallback: ''),
            _s(request['student_time'], fallback: ''),
          ].where((part) => part.isNotEmpty).join(' · ');
          if (studentPickup.isNotEmpty) {
            items.add('Student pickup: $studentPickup');
          }
        }
        final notes = _s(request['other_notes'], fallback: '');
        if (notes.isNotEmpty) items.add('Notes: $notes');
        if (items.isEmpty) items.add('Transport coordination');
        return items;
      case 'iqac':
        if (phase != 'post') return const [];
        return [
          _s(_event['report_web_view_link'], fallback: '').isNotEmpty
              ? 'Event report uploaded'
              : 'Event report not uploaded yet',
        ];
      default:
        return const [];
    }
  }

  Widget _buildRequirementPhaseSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _muted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 6, color: _muted),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _onSurface,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarketingDeliverablesSection(
    List<Map<String, dynamic>> deliverables,
  ) {
    final links = deliverables.map((deliverable) {
      final type = _s(
        deliverable['deliverable_type'] ?? deliverable['type'],
        fallback: 'File',
      );
      final name = _s(deliverable['file_name'], fallback: type);
      final link = _s(
        deliverable['web_view_link'] ?? deliverable['link'],
        fallback: '',
      );
      final isNa = deliverable['is_na'] == true;
      return (label: isNa ? '$type: N/A' : name, link: isNa ? '' : link);
    }).toList();

    return _buildRequirementLinkSection(
      'Uploaded Deliverables',
      links,
      emptyText: 'No files uploaded yet.',
    );
  }

  Widget _buildRequirementLinkSection(
    String title,
    List<({String label, String link})> items, {
    String emptyText = 'No files uploaded yet.',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _muted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text(
            emptyText,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: _muted,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items
                .map(
                  (item) => InkWell(
                    onTap: item.link.isEmpty
                        ? null
                        : () => _openExternalLink(item.link),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _pageBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.link.isEmpty
                                ? LucideIcons.fileMinus
                                : LucideIcons.fileText,
                            size: 14,
                            color: item.link.isEmpty
                                ? _muted
                                : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: item.link.isEmpty
                                  ? _muted
                                  : const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildNotesAndDescription() {
    final event = _event;
    final approval = _approval;
    return _buildCard(
      icon: LucideIcons.stickyNote,
      title: 'Notes & Description',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabelValue(
            null,
            'Other Notes',
            Text(
              _s(event['other_notes'], fallback: _s(approval['other_notes'])),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _onSurface,
                height: 1.5,
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Description',
            Text(
              _s(event['description'], fallback: 'No description provided.'),
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
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
