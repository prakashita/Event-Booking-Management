import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

enum _DecisionAction { approve, reject, clarify }

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<ApprovalRequest> _inbox = [];
  List<ApprovalRequest> _mySubmissions = [];
  bool _loadingInbox = true;
  bool _loadingMine = false;
  bool _mineLoaded = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_mineLoaded) _loadMine();
    });
    _loadInbox();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInbox() async {
    setState(() => _loadingInbox = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/approvals/inbox');
      setState(() {
        _inbox = (data['items'] as List? ?? [])
            .map((e) => ApprovalRequest.fromJson(e))
            .toList();
        _loadingInbox = false;
      });
    } catch (_) {
      setState(() => _loadingInbox = false);
    }
  }

  Future<void> _loadMine() async {
    setState(() => _loadingMine = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/approvals/me');
      setState(() {
        _mySubmissions = (data['items'] as List? ?? [])
            .map((e) => ApprovalRequest.fromJson(e))
            .toList();
        _loadingMine = false;
        _mineLoaded = true;
      });
    } catch (_) {
      setState(() => _loadingMine = false);
    }
  }

  bool _isActionable(ApprovalRequest req) {
    final status = req.status.trim().toLowerCase();
    return status == 'pending' || status == 'clarification_requested';
  }

  String _decisionStatus(_DecisionAction action) {
    switch (action) {
      case _DecisionAction.approve:
        return 'approved';
      case _DecisionAction.reject:
        return 'rejected';
      case _DecisionAction.clarify:
        return 'clarification_requested';
    }
  }

  String _decisionLabel(_DecisionAction action) {
    switch (action) {
      case _DecisionAction.approve:
        return 'Approve';
      case _DecisionAction.reject:
        return 'Reject';
      case _DecisionAction.clarify:
        return 'Need clarification';
    }
  }

  Future<void> _handleDecision(
    ApprovalRequest req,
    _DecisionAction action,
  ) async {
    final isApprove = action == _DecisionAction.approve;
    final isReject = action == _DecisionAction.reject;

    final confirmed = await showConfirmDialog(
      context,
      title: '${_decisionLabel(action)} Event',
      message: isApprove
          ? '${_decisionLabel(action)} "${req.eventTitle}"?'
          : '${_decisionLabel(action)} "${req.eventTitle}"? Please provide a comment for the requester.',
      confirmLabel: _decisionLabel(action),
      isDestructive: isReject,
    );
    if (confirmed != true || !mounted) return;

    String? comment;
    if (!isApprove) {
      comment = await _promptDecisionComment(
        title: action == _DecisionAction.reject
            ? 'Reject request'
            : 'Request clarification',
        hint: action == _DecisionAction.reject
            ? 'Add rejection reason'
            : 'Ask for clarification',
      );
      if (!mounted || comment == null) return;
      if (comment.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _DecisionAction.reject
                  ? 'Comment is required when rejecting a request.'
                  : 'Comment is required when requesting clarification.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    try {
      final updated = await _api.patch<Map<String, dynamic>>(
        '/approvals/${req.id}',
        data: {
          'status': _decisionStatus(action),
          if ((comment ?? '').trim().isNotEmpty) 'comment': comment!.trim(),
        },
      );

      final status = (updated['status'] ?? '').toString().toLowerCase();
      final stage = (updated['pipeline_stage'] ?? '').toString().toLowerCase();
      String message;
      if (action == _DecisionAction.approve && stage == 'after_deputy') {
        message =
            'Approved at Deputy stage. Requester can now send to Finance.';
      } else if (action == _DecisionAction.approve &&
          stage == 'after_finance') {
        message =
            'Approved at Finance stage. Requester can now send to Registrar.';
      } else if (action == _DecisionAction.approve && status == 'approved') {
        message = 'Final approval completed.';
      } else if (action == _DecisionAction.clarify) {
        message = 'Clarification requested from requester.';
      } else {
        message = isApprove ? 'Request approved.' : 'Request rejected.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isApprove
                ? AppColors.success
                : AppColors.textSecondary,
          ),
        );
        _inbox = [];
        _loadInbox();
      }
    } catch (e) {
      if (mounted) {
        final message = _extractApiErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
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

  Future<void> _refreshActiveTab() async {
    setState(() => _refreshing = true);
    try {
      if (_tabController.index == 0) {
        await _loadInbox();
      } else {
        await _loadMine();
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  List<ApprovalRequest> _applySearch(List<ApprovalRequest> source) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((item) {
      return item.eventTitle.toLowerCase().contains(query) ||
          item.requestedBy.toLowerCase().contains(query) ||
          item.requestedTo.toLowerCase().contains(query) ||
          (item.description ?? '').toLowerCase().contains(query);
    }).toList();
  }

  Future<String?> _promptDecisionComment({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
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

  @override
  Widget build(BuildContext context) {
    final pendingCount = _inbox.where((r) => _isActionable(r)).length;
    final tabIndex = _tabController.index;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Approvals',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _refreshing ? null : _refreshActiveTab,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        icon: AnimatedRotation(
                          turns: _refreshing ? 0.35 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: const Icon(Icons.refresh),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search events, requester, email...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF4F46E5),
                    labelColor: const Color(0xFF4F46E5),
                    unselectedLabelColor: const Color(0xFF64748B),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Approval Requests'),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF43F5E),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$pendingCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Tab(text: 'My Requests'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRequestList(
                    loading: _loadingInbox,
                    source: _inbox,
                    emptyIcon: Icons.inbox_outlined,
                    emptyTitle: 'Inbox is empty',
                    emptyMessage: 'No pending approval requests.',
                    showActions: true,
                  ),
                  _buildRequestList(
                    loading: _loadingMine,
                    source: _mySubmissions,
                    emptyIcon: Icons.send_outlined,
                    emptyTitle: 'No submissions',
                    emptyMessage: 'Your event requests will appear here.',
                    showActions: false,
                  ),
                ],
              ),
            ),
            if (tabIndex == 0) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestList({
    required bool loading,
    required List<ApprovalRequest> source,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
    required bool showActions,
  }) {
    final requests = _applySearch(source);
    if (loading) return _buildLoadingList();

    return RefreshIndicator(
      onRefresh: _refreshActiveTab,
      child: requests.isEmpty
          ? EmptyState(
              icon: emptyIcon,
              title: emptyTitle,
              message: emptyMessage,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              itemCount: requests.length,
              itemBuilder: (ctx, i) {
                final req = requests[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ApprovalCard(
                    request: req,
                    showActions: showActions && _isActionable(req),
                    onDetails: () => context.go('/events/approval-${req.id}'),
                    onDecision: (action) => _handleDecision(req, action),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildLoadingList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerBox(width: double.infinity, height: 130, radius: 12),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final ApprovalRequest request;
  final bool showActions;
  final VoidCallback? onDetails;
  final Future<void> Function(_DecisionAction action)? onDecision;

  const _ApprovalCard({
    required this.request,
    required this.showActions,
    this.onDetails,
    this.onDecision,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  request.eventTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(request.status),
            ],
          ),
          if (request.description != null &&
              request.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              request.description!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          InfoRow(
            icon: Icons.person_outline,
            text: 'By: ${request.requestedBy}',
          ),
          const SizedBox(height: 5),
          InfoRow(
            icon: Icons.alternate_email_rounded,
            text: request.requestedBy,
          ),
          const SizedBox(height: 5),
          InfoRow(
            icon: Icons.schedule,
            text:
                '${df.format(request.startDatetime)} · ${tf.format(request.startDatetime)} → ${tf.format(request.endDatetime)}',
          ),
          if ((request.pipelineStage ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            InfoRow(
              icon: Icons.route_outlined,
              text: _pipelineStageLabel(request.pipelineStage),
            ),
          ],
          if (request.overrideConflict) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, size: 14, color: AppColors.warning),
                  SizedBox(width: 6),
                  Text(
                    'Conflict override requested',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton(
                onPressed: onDetails,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  side: const BorderSide(color: Color(0xFFC7D2FE)),
                  backgroundColor: const Color(0xFFEEF2FF),
                ),
                child: const Text('Details'),
              ),
              const Spacer(),
              if (showActions) _ActionDropdown(onSelected: onDecision),
            ],
          ),
        ],
      ),
    );
  }

  String _pipelineStageLabel(String? stage) {
    final s = (stage ?? '').trim().toLowerCase();
    switch (s) {
      case 'deputy':
        return 'Stage: Awaiting Deputy Registrar';
      case 'after_deputy':
        return 'Stage: Deputy approved - waiting requester action';
      case 'finance':
        return 'Stage: Awaiting Finance Team';
      case 'after_finance':
        return 'Stage: Finance approved - waiting requester action';
      case 'registrar':
        return 'Stage: Awaiting Registrar / Vice Chancellor';
      case 'complete':
        return 'Stage: Final approval completed';
      default:
        return 'Stage: Awaiting approval';
    }
  }
}

class _ActionDropdown extends StatelessWidget {
  final Future<void> Function(_DecisionAction action)? onSelected;

  const _ActionDropdown({this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DecisionAction>(
      onSelected: (action) {
        onSelected?.call(action);
      },
      itemBuilder: (context) => const [
        PopupMenuItem<_DecisionAction>(
          value: _DecisionAction.approve,
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: Color(0xFF059669),
                size: 18,
              ),
              SizedBox(width: 8),
              Text('Approve'),
            ],
          ),
        ),
        PopupMenuItem<_DecisionAction>(
          value: _DecisionAction.reject,
          child: Row(
            children: [
              Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 18),
              SizedBox(width: 8),
              Text('Reject'),
            ],
          ),
        ),
        PopupMenuItem<_DecisionAction>(
          value: _DecisionAction.clarify,
          child: Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                color: Color(0xFFD97706),
                size: 18,
              ),
              SizedBox(width: 8),
              Text('Need clarification'),
            ],
          ),
        ),
      ].toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'Action',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.expand_more_rounded, size: 18, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}
