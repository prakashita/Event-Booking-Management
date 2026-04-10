import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  static const _channels = [
    (label: 'General', inboxPath: '/approvals/inbox', basePath: '/approvals/', idKey: 'approval_id'),
    (label: 'Facility', inboxPath: '/facility/inbox', basePath: '/facility/requests/', idKey: 'id'),
    (label: 'Marketing', inboxPath: '/marketing/inbox', basePath: '/marketing/requests/', idKey: 'id'),
    (label: 'IT', inboxPath: '/it/inbox', basePath: '/it/requests/', idKey: 'id'),
    (label: 'Transport', inboxPath: '/transport/inbox', basePath: '/transport/requests/', idKey: 'id'),
  ];

  int _tab = 0;
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final res = await widget.api.get(_channels[_tab].inboxPath);
    return asList(res);
  }

  Future<void> _act(Map<String, dynamic> item, String status) async {
    final commentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _statusIcon(status),
              color: _statusColor(status),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text('Mark as: ${status.replaceAll('_', ' ')}'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status != 'approved')
                const Text(
                  'A comment is required for non-approval actions.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Comment',
                  hintText: 'Add your notes…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _statusColor(status)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    if (status != 'approved' && commentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment is required for this action.')),
      );
      return;
    }

    final ch = _channels[_tab];
    final id = item[ch.idKey] ?? item['id'];
    if (id == null) return;

    try {
      await widget.api.patch('${ch.basePath}$id', {
        'status': status,
        if (commentCtrl.text.trim().isNotEmpty) 'comment': commentCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action submitted: $status'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'clarification_requested':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle_outline_rounded;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'clarification_requested':
        return Icons.help_outline_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Approvals',
      subtitle: 'Review and act on approval inboxes across all channels.',
      child: Column(
        children: [
          // Channel tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_channels.length, (i) {
                final active = _tab == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_channels[i].label),
                    selected: active,
                    onSelected: (_) => setState(() {
                      _tab = i;
                      _future = _load();
                    }),
                    selectedColor: AppColors.primary.withAlpha(30),
                    checkmarkColor: AppColors.primary,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const ShimmerLoader();
              }
              if (snap.hasError) {
                return ErrorCard(
                  error: snap.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                );
              }

              final data = snap.data ?? [];
              if (data.isEmpty) {
                return const EmptyCard(
                  message: 'No inbox items for this channel.',
                  icon: Icons.inbox_rounded,
                );
              }

              return Column(
                children: data.map((r) {
                  final m = asMap(r);
                  return _ApprovalCard(
                    item: m,
                    onApprove: () => _act(m, 'approved'),
                    onReject: () => _act(m, 'rejected'),
                    onClarify: () => _act(m, 'clarification_requested'),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
    required this.onClarify,
  });

  final Map<String, dynamic> item;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onClarify;

  @override
  Widget build(BuildContext context) {
    final name =
        item['event_name']?.toString() ??
            item['name']?.toString() ??
            'Request';
    final status = item['status']?.toString() ?? 'pending';
    final submittedBy = item['submitted_by']?.toString() ??
        item['faculty_name']?.toString() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withAlpha(22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.approval_rounded,
                    color: Color(0xFFF59E0B),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (submittedBy.isNotEmpty)
                        Text(
                          'By: $submittedBy',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onClarify,
                  icon: const Icon(Icons.help_outline_rounded, size: 16),
                  label: const Text('Clarification'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
