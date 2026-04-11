import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();
  List<ApprovalRequest> _inbox = [];
  List<ApprovalRequest> _mySubmissions = [];
  bool _loadingInbox = true;
  bool _loadingMine = false;
  bool _inboxLoaded = false;
  bool _mineLoaded = false;

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
        _inboxLoaded = true;
      });
    } catch (e) {
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
    } catch (e) {
      setState(() => _loadingMine = false);
    }
  }

  Future<void> _decide(ApprovalRequest req, bool approve) async {
    final confirmed = await showConfirmDialog(
      context,
      title: approve ? 'Approve Event' : 'Reject Event',
      message: approve
          ? 'Approve "${req.eventTitle}"? This will create the event and notify the requester.'
          : 'Reject "${req.eventTitle}"? This action cannot be undone.',
      confirmLabel: approve ? 'Approve' : 'Reject',
      isDestructive: !approve,
    );
    if (confirmed != true || !mounted) return;

    try {
      await _api.patch('/approvals/${req.id}', data: {
        'decision': approve ? 'approved' : 'rejected',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve
                ? 'Event approved and created!'
                : 'Request rejected.'),
            backgroundColor:
                approve ? AppColors.success : AppColors.textSecondary,
          ),
        );
        // Reload inbox
        _inbox = [];
        _inboxLoaded = false;
        _loadInbox();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Approvals'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Inbox'),
                  if (_inbox.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${_inbox.where((r) => r.status == 'pending').length}',
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'My Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Inbox
          _loadingInbox
              ? _buildLoadingList()
              : RefreshIndicator(
                  onRefresh: () async {
                    _inbox = [];
                    _inboxLoaded = false;
                    await _loadInbox();
                  },
                  child: _inbox.isEmpty
                      ? const EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'Inbox is empty',
                          message: 'No pending approval requests.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _inbox.length,
                          itemBuilder: (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ApprovalCard(
                              request: _inbox[i],
                              showActions: _inbox[i].status == 'pending',
                              onApprove: () => _decide(_inbox[i], true),
                              onReject: () => _decide(_inbox[i], false),
                            ),
                          ),
                        ),
                ),

          // My submissions
          _loadingMine
              ? _buildLoadingList()
              : RefreshIndicator(
                  onRefresh: () async {
                    _mineLoaded = false;
                    await _loadMine();
                  },
                  child: _mySubmissions.isEmpty
                      ? const EmptyState(
                          icon: Icons.send_outlined,
                          title: 'No submissions',
                          message: 'Your event requests will appear here.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _mySubmissions.length,
                          itemBuilder: (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ApprovalCard(
                              request: _mySubmissions[i],
                              showActions: false,
                            ),
                          ),
                        ),
                ),
        ],
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
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const _ApprovalCard({
    required this.request,
    required this.showActions,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  request.eventTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(request.status),
            ],
          ),
          if (request.description != null && request.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              request.description!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          InfoRow(icon: Icons.person_outline, text: 'By: ${request.requestedBy}'),
          const SizedBox(height: 5),
          InfoRow(icon: Icons.location_on_outlined, text: request.venueName),
          const SizedBox(height: 5),
          InfoRow(
            icon: Icons.schedule,
            text:
                '${df.format(request.startDatetime)} · ${tf.format(request.startDatetime)} → ${tf.format(request.endDatetime)}',
          ),
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                  ),
                ],
              ),
            ),
          ],
          if (showActions) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
