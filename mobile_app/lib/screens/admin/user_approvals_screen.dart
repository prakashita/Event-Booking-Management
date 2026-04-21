import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class UserApprovalsScreen extends StatefulWidget {
  const UserApprovalsScreen({super.key});

  @override
  State<UserApprovalsScreen> createState() => _UserApprovalsScreenState();
}

class _UserApprovalsScreenState extends State<UserApprovalsScreen> {
  final _api = ApiService();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _rejected = [];

  String? _actingUserId;
  String? _actingAction;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  bool get _canAccess {
    final role = (context.read<AuthProvider>().user?.roleKey ?? '')
        .toLowerCase();
    return role == 'admin';
  }

  Future<void> _loadAll({bool forceRefresh = false}) async {
    if (!_canAccess || !mounted) return;

    setState(() {
      if (forceRefresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final pending = await _api.get<List<dynamic>>('/users/pending-approvals');
      final rejected = await _api.get<List<dynamic>>('/users/rejected-users');

      if (!mounted) return;
      setState(() {
        _pending = pending.whereType<Map<String, dynamic>>().toList();
        _rejected = rejected.whereType<Map<String, dynamic>>().toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _extractError(e);
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  String _extractError(Object error) {
    final text = error.toString();
    if (text.isEmpty) return 'Something went wrong.';
    return text;
  }

  String _fmtDate(dynamic value) {
    final raw = value?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '-';
    return DateFormat('yyyy-MM-dd').format(parsed.toLocal());
  }

  Future<void> _submitApprovalAction({
    required String userId,
    required String action,
    String? role,
    String? rejectionReason,
  }) async {
    setState(() {
      _actingUserId = userId;
      _actingAction = action;
    });

    try {
      await _api.post(
        '/users/$userId/approval',
        data: {
          'action': action,
          if (action == 'approve' && role != null) 'role': role,
          if (action == 'reject' && (rejectionReason ?? '').trim().isNotEmpty)
            'rejection_reason': rejectionReason!.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'approve'
                ? 'User approved successfully.'
                : 'User rejected successfully.',
          ),
        ),
      );
      await _loadAll(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractError(e))));
    } finally {
      if (!mounted) return;
      setState(() {
        _actingUserId = null;
        _actingAction = null;
      });
    }
  }

  Future<void> _showApproveDialog(Map<String, dynamic> user) async {
    const roles = [
      'faculty',
      'registrar',
      'vice_chancellor',
      'deputy_registrar',
      'finance_team',
      'facility_manager',
      'marketing',
      'it',
      'transport',
      'iqac',
    ];

    var selected = (user['requested_role'] ?? user['role'] ?? 'faculty')
        .toString()
        .trim()
        .toLowerCase();
    if (!roles.contains(selected)) selected = 'faculty';

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('Approve User'),
              content: DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Assigned Role'),
                items: roles
                    .map(
                      (r) => DropdownMenuItem<String>(
                        value: r,
                        child: Text(r.replaceAll('_', ' ').toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() {
                    selected = v;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final userId = (user['id'] ?? '').toString();
                    if (userId.isEmpty) return;
                    await _submitApprovalAction(
                      userId: userId,
                      action: 'approve',
                      role: selected,
                    );
                  },
                  child: const Text('Confirm Approve'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRejectDialog(Map<String, dynamic> user) async {
    final reasonCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reject User'),
          content: TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Optionally provide a rejection reason',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final userId = (user['id'] ?? '').toString();
                if (userId.isEmpty) return;
                await _submitApprovalAction(
                  userId: userId,
                  action: 'reject',
                  rejectionReason: reasonCtrl.text,
                );
              },
              child: const Text('Confirm Reject'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!_canAccess) {
      return const Scaffold(body: Center(child: Text('Access denied.')));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadAll(forceRefresh: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User Approvals',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Review and approve pending registration requests.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _CountChip(
                      label: 'Pending',
                      value: _pending.length,
                      fg: const Color(0xFFD97706),
                      bg: const Color(0xFFFFFBEB),
                      border: const Color(0xFFFDE68A),
                    ),
                    const SizedBox(width: 8),
                    _CountChip(
                      label: 'Rejected',
                      value: _rejected.length,
                      fg: const Color(0xFFB91C1C),
                      bg: const Color(0xFFFEE2E2),
                      border: const Color(0xFFFCA5A5),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _refreshing
                          ? null
                          : () => _loadAll(forceRefresh: true),
                      icon: _refreshing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  Center(
                    child: Column(
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: _loadAll,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _SectionCard(
                    title: 'Pending Approval',
                    count: _pending.length,
                    countFg: const Color(0xFFD97706),
                    countBg: const Color(0xFFFFFBEB),
                    countBorder: const Color(0xFFFDE68A),
                    child: _pending.isEmpty
                        ? const _EmptySection(
                            message: 'No users pending approval.',
                            subMessage:
                                'All registration requests have been processed.',
                          )
                        : Column(
                            children: _pending.map((item) {
                              final id = (item['id'] ?? '').toString();
                              final name = (item['name'] ?? 'Unnamed')
                                  .toString();
                              final email = (item['email'] ?? '').toString();
                              final role =
                                  (item['requested_role'] ??
                                          item['role'] ??
                                          'faculty')
                                      .toString()
                                      .replaceAll('_', ' ')
                                      .toUpperCase();
                              final requested = _fmtDate(item['created_at']);
                              final acting = _actingUserId == id;

                              return _UserApprovalTile(
                                name: name,
                                email: email,
                                rightTop: role,
                                rightBottom: requested,
                                primaryLabel:
                                    acting && _actingAction == 'approve'
                                    ? '...'
                                    : 'Approve',
                                secondaryLabel:
                                    acting && _actingAction == 'reject'
                                    ? '...'
                                    : 'Reject',
                                onPrimary: acting
                                    ? null
                                    : () => _showApproveDialog(item),
                                onSecondary: acting
                                    ? null
                                    : () => _showRejectDialog(item),
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Rejected Users',
                    count: _rejected.length,
                    countFg: const Color(0xFFB91C1C),
                    countBg: const Color(0xFFFEE2E2),
                    countBorder: const Color(0xFFFCA5A5),
                    child: _rejected.isEmpty
                        ? const _EmptySection(
                            message: 'No rejected users found.',
                          )
                        : Column(
                            children: _rejected.map((item) {
                              final id = (item['id'] ?? '').toString();
                              final name = (item['name'] ?? 'Unnamed')
                                  .toString();
                              final email = (item['email'] ?? '').toString();
                              final reason =
                                  (item['rejection_reason'] ??
                                          'No reason given')
                                      .toString();
                              final rejectedDate = _fmtDate(
                                item['rejected_at'] ?? item['updated_at'],
                              );
                              final acting = _actingUserId == id;

                              return _UserApprovalTile(
                                name: name,
                                email: email,
                                rightTop: reason,
                                rightBottom: rejectedDate,
                                primaryLabel:
                                    acting && _actingAction == 'approve'
                                    ? '...'
                                    : 'Re-approve',
                                onPrimary: acting
                                    ? null
                                    : () => _showApproveDialog(item),
                              );
                            }).toList(),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int value;
  final Color fg;
  final Color bg;
  final Color border;

  const _CountChip({
    required this.label,
    required this.value,
    required this.fg,
    required this.bg,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final int count;
  final Color countFg;
  final Color countBg;
  final Color countBorder;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.count,
    required this.countFg,
    required this.countBg,
    required this.countBorder,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: countBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: countBorder),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: countFg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String message;
  final String? subMessage;

  const _EmptySection({required this.message, this.subMessage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.group_outlined,
                color: isDark
                    ? const Color(0xFF64748B)
                    : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 4),
              Text(
                subMessage!,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserApprovalTile extends StatelessWidget {
  final String name;
  final String email;
  final String rightTop;
  final String rightBottom;
  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;

  const _UserApprovalTile({
    required this.name,
    required this.email,
    required this.rightTop,
    required this.rightBottom,
    required this.primaryLabel,
    this.secondaryLabel,
    this.onPrimary,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            email,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rightTop,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rightBottom,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
