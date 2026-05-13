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
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
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
      if (mounted) {
        setState(() {
          _actingUserId = null;
          _actingAction = null;
        });
      }
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Approve User'),
              content: DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(
                  labelText: 'Assigned Role',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
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
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Reject User'),
          content: TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Optionally provide a rejection reason',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: const Color(0xFFDC2626),
              ),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                          : [const Color(0xFFFFFFFF), const Color(0xFFF8FAFC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.05,
                        ),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
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
                              color: const Color(
                                0xFF4F46E5,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.how_to_reg_rounded,
                              color: Color(0xFF4F46E5),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'ACCESS CONTROL',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: Color(0xFF4F46E5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'User Approvals',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Review and approve pending registration requests.',
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            icon: _refreshing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text(
                              'Refresh',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 48,
                        horizontal: 24,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _loadAll,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  _SectionCard(
                    title: 'Pending Approval',
                    icon: Icons.hourglass_empty_rounded,
                    count: _pending.length,
                    countFg: const Color(0xFFD97706),
                    countBg: const Color(0xFFFFFBEB),
                    countBorder: const Color(0xFFFDE68A),
                    child: _pending.isEmpty
                        ? const _EmptySection(
                            icon: Icons.check_circle_outline_rounded,
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
                  const SizedBox(height: 24),
                  _SectionCard(
                    title: 'Rejected Users',
                    icon: Icons.block_rounded,
                    count: _rejected.length,
                    countFg: const Color(0xFFB91C1C),
                    countBg: const Color(0xFFFEE2E2),
                    countBorder: const Color(0xFFFCA5A5),
                    child: _rejected.isEmpty
                        ? const _EmptySection(
                            icon: Icons.verified_user_outlined,
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
                                    : 'Review & Re-approve',
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: fg,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final int count;
  final Color countFg;
  final Color countBg;
  final Color countBorder;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: countBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: countBorder),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: countFg,
                  ),
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
}

class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subMessage;

  const _EmptySection({
    required this.icon,
    required this.message,
    this.subMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: isDark
                    ? const Color(0xFF475569)
                    : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 6),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
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

    final isPending = secondaryLabel != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isPending
                    ? const Color(0xFFD97706).withValues(alpha: 0.15)
                    : const Color(0xFFDC2626).withValues(alpha: 0.15),
                child: Icon(
                  isPending
                      ? Icons.hourglass_empty_rounded
                      : Icons.block_rounded,
                  color: isPending
                      ? const Color(0xFFD97706)
                      : const Color(0xFFDC2626),
                  size: 20,
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
                      ),
                    ),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isPending
                  ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
                  : const Color(
                      0xFFFEE2E2,
                    ).withValues(alpha: isDark ? 0.05 : 0.5),
              border: Border.all(
                color: isPending
                    ? Colors.transparent
                    : const Color(0xFFFCA5A5).withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isPending
                          ? Icons.badge_outlined
                          : Icons.edit_note_rounded,
                      size: 16,
                      color: isPending
                          ? (isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B))
                          : const Color(0xFFB91C1C),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPending
                            ? 'Requested Role: $rightTop'
                            : 'Rejected on $rightBottom',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isPending
                              ? FontWeight.w500
                              : FontWeight.w600,
                          color: isPending
                              ? theme.colorScheme.onSurface
                              : const Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                    if (isPending)
                      Text(
                        rightBottom,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
                if (!isPending) ...[
                  const SizedBox(height: 4),
                  Text(
                    rightTop, // In rejected state, rightTop is the reason
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFF991B1B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: isPending
                    ? FilledButton.tonal(
                        onPressed: onPrimary,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(
                            0xFF10B981,
                          ).withValues(alpha: 0.15),
                          foregroundColor: const Color(0xFF059669),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(primaryLabel),
                      )
                    : OutlinedButton(
                        onPressed: onPrimary,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(primaryLabel),
                      ),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(secondaryLabel!),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
