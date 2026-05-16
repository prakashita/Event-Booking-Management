import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/common/app_widgets.dart';
import '../home_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

enum _AdminTab { users, venues, events, requests, invites, publications }

class _AdminScreenState extends State<AdminScreen> {
  final _api = ApiService();
  ValueNotifier<bool>? _chatFabVisibility;

  bool get _canAccess {
    final role = (context.read<AuthProvider>().user?.roleKey ?? '')
        .toLowerCase()
        .trim();
    return role == 'admin';
  }

  void _setChatFabVisible(bool visible) {
    _chatFabVisibility?.value = visible;
  }

  Future<T?> _runWithFormFabHidden<T>(Future<T?> Function() action) async {
    _setChatFabVisible(false);
    try {
      return await action();
    } finally {
      _setChatFabVisible(true);
    }
  }

  _AdminTab _activeTab = _AdminTab.users;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;

  Map<String, int> _overview = {};
  List<User> _users = [];
  List<Map<String, dynamic>> _pendingUsers = [];
  List<Map<String, dynamic>> _rejectedUsers = [];
  List<Venue> _venues = [];
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _approvals = [];
  List<Map<String, dynamic>> _facility = [];
  List<Map<String, dynamic>> _marketing = [];
  List<Map<String, dynamic>> _it = [];
  List<Map<String, dynamic>> _transport = [];
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _publications = [];

  @override
  void initState() {
    super.initState();
    if (_canAccess) {
      _loadCurrentSection();
    } else {
      _isLoading = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = ChatFabVisibilityScope.maybeOf(context);
    if (_chatFabVisibility != notifier) {
      _chatFabVisibility = notifier;
      _setChatFabVisible(true);
    }
  }

  @override
  void dispose() {
    _setChatFabVisible(true);
    super.dispose();
  }

  Future<void> _loadCurrentSection({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      if (!forceRefresh) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
      _error = null;
    });

    try {
      await _loadOverview();
      switch (_activeTab) {
        case _AdminTab.users:
          await _loadUsers();
        case _AdminTab.venues:
          await _loadVenues();
        case _AdminTab.events:
          await _loadEvents();
        case _AdminTab.requests:
          await _loadRequests();
        case _AdminTab.invites:
          await _loadInvites();
        case _AdminTab.publications:
          await _loadPublications();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _extractError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadOverview() async {
    final data = await _api.get<Map<String, dynamic>>('/admin/overview');
    _overview = data.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
  }

  Future<void> _loadUsers() async {
    final data = await _api.get<List<dynamic>>('/users');
    _users = data.whereType<Map<String, dynamic>>().map(User.fromJson).toList();

    final pendingData = await _api.get<List<dynamic>>(
      '/users/pending-approvals',
    );
    _pendingUsers = pendingData.whereType<Map<String, dynamic>>().toList();

    final rejectedData = await _api.get<List<dynamic>>('/users/rejected-users');
    _rejectedUsers = rejectedData.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> _loadVenues() async {
    final data = await _api.get<List<dynamic>>('/admin/venues');
    _venues = data
        .whereType<Map<String, dynamic>>()
        .map(Venue.fromJson)
        .toList();
  }

  Future<void> _loadEvents() async {
    final data = await _api.get<Map<String, dynamic>>('/admin/events');
    _events = _listItems(data);
  }

  Future<void> _loadRequests() async {
    final approvalsData = await _api.get<Map<String, dynamic>>(
      '/admin/approvals',
    );
    final facilityData = await _api.get<Map<String, dynamic>>(
      '/admin/facility',
    );
    final marketingData = await _api.get<Map<String, dynamic>>(
      '/admin/marketing',
    );
    final itData = await _api.get<Map<String, dynamic>>('/admin/it');
    final transportData = await _api.get<Map<String, dynamic>>(
      '/admin/transport',
    );

    _approvals = _listItems(approvalsData);
    _facility = _listItems(facilityData);
    _marketing = _listItems(marketingData);
    _it = _listItems(itData);
    _transport = _listItems(transportData);
  }

  Future<void> _loadInvites() async {
    final data = await _api.get<Map<String, dynamic>>('/admin/invites');
    _invites = _listItems(data);
  }

  Future<void> _loadPublications() async {
    final data = await _api.get<Map<String, dynamic>>('/admin/publications');
    _publications = _listItems(data);
  }

  List<Map<String, dynamic>> _listItems(Map<String, dynamic> data) {
    final raw = data['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  String _extractError(Object error) {
    return friendlyErrorMessage(error);
  }

  Future<void> _switchTab(_AdminTab tab) async {
    if (_activeTab == tab) return;
    setState(() {
      _activeTab = tab;
    });
    await _loadCurrentSection();
  }

  Future<void> _deleteUser(User user) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete User',
      message: 'Delete ${user.name}? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (ok != true) return;

    try {
      await _api.delete('/users/${user.id}');
      if (!mounted) return;
      setState(() {
        _users.removeWhere((u) => u.id == user.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User deleted.')));
      await _loadOverview();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractError(e))));
    }
  }

  Future<void> _deleteRejectedUser(Map<String, dynamic> user) async {
    final id = (user['id'] ?? '').toString();
    if (id.isEmpty) return;

    final name = (user['name'] ?? 'this rejected user').toString();
    final ok = await showConfirmDialog(
      context,
      title: 'Delete Rejected User',
      message: 'Delete $name? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (ok != true) return;

    try {
      await _api.delete('/users/$id');
      if (!mounted) return;
      setState(() {
        _rejectedUsers.removeWhere(
          (item) => (item['id'] ?? '').toString() == id,
        );
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rejected user deleted.')));
      await _loadOverview();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractError(e))));
    }
  }

  Future<void> _deleteVenue(Venue venue) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete Venue',
      message: 'Delete ${venue.name}?',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (ok != true) return;

    try {
      await _api.delete('/venues/${venue.id}');
      if (!mounted) return;
      setState(() {
        _venues.removeWhere((v) => v.id == venue.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Venue deleted.')));
      await _loadOverview();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractError(e))));
    }
  }

  Future<void> _deleteByPath({
    required String path,
    required String id,
    required String success,
  }) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete Item',
      message: 'This action cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (ok != true) return;

    try {
      await _api.delete('$path/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _loadCurrentSection(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractError(e))));
    }
  }

  Future<void> _showChangeRoleDialog(User user) async {
    const allowedRoles = [
      'admin',
      'registrar',
      'vice_chancellor',
      'deputy_registrar',
      'finance_team',
      'faculty',
      'facility_manager',
      'marketing',
      'it',
      'iqac',
      'transport',
    ];

    var selected = (user.roleKey).trim().toLowerCase();
    if (!allowedRoles.contains(selected)) {
      selected = 'faculty';
    }
    await _runWithFormFabHidden<void>(
      () => showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text('Change Role - ${user.name}'),
                content: DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  items: allowedRoles
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
                      try {
                        await _api.patch(
                          '/users/${user.id}/role',
                          data: {'role': selected},
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Role updated.')),
                        );
                        await _loadCurrentSection(forceRefresh: true);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_extractError(e))),
                        );
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddUserDialog() async {
    final emailCtrl = TextEditingController();
    var role = 'facility_manager';
    const addRoles = [
      'registrar',
      'vice_chancellor',
      'deputy_registrar',
      'finance_team',
      'facility_manager',
      'marketing',
      'it',
      'transport',
    ];

    await _runWithFormFabHidden<void>(
      () => showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text('Add User'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: addRoles
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
                          role = v;
                        });
                      },
                    ),
                  ],
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
                      try {
                        await _api.post(
                          '/users/add',
                          data: {'email': emailCtrl.text.trim(), 'role': role},
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User added.')),
                        );
                        await _loadCurrentSection(forceRefresh: true);
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(_extractError(e))),
                        );
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showAddVenueDialog() async {
    final venueCtrl = TextEditingController();
    await _runWithFormFabHidden<void>(
      () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Add Venue'),
          content: TextField(
            controller: venueCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Venue name',
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
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await _api.post(
                    '/venues',
                    data: {'name': venueCtrl.text.trim()},
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Venue added.')));
                  await _loadCurrentSection(forceRefresh: true);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(_extractError(e))));
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approvePendingUser(
    Map<String, dynamic> user,
    String role,
  ) async {
    final id = (user['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await _api.post(
        '/users/$id/approval',
        data: {'action': 'approve', 'role': role},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User approved successfully.')),
      );
      await _loadCurrentSection(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractError(e))));
    }
  }

  Future<void> _rejectPendingUser(
    Map<String, dynamic> user,
    String reason,
  ) async {
    final id = (user['id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      await _api.post(
        '/users/$id/approval',
        data: {
          'action': 'reject',
          if (reason.trim().isNotEmpty) 'rejection_reason': reason.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User rejected successfully.')),
      );
      await _loadCurrentSection(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_extractError(e))));
    }
  }

  Future<void> _showApproveUserDialog(Map<String, dynamic> user) async {
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

    await _runWithFormFabHidden<void>(
      () => showDialog<void>(
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
                      await _approvePendingUser(user, selected);
                    },
                    child: const Text('Approve'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showRejectUserDialog(Map<String, dynamic> user) async {
    final reasonCtrl = TextEditingController();
    await _runWithFormFabHidden<void>(
      () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Reject User'),
          content: TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Provide a reason for rejection',
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
                await _rejectPendingUser(user, reasonCtrl.text);
              },
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(dynamic value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return DateFormat('yyyy-MM-dd').format(parsed.toLocal());
  }

  String _fmtDateTime(dynamic value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return DateFormat('MMM d, yyyy • h:mm a').format(parsed.toLocal());
  }

  Widget _buildTabButton(_AdminTab tab, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isActive = _activeTab == tab;
    final compact = MediaQuery.sizeOf(context).width < 430;

    return GestureDetector(
      onTap: () => _switchTab(tab),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 20,
          vertical: compact ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primary
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
            color: isActive
                ? theme.colorScheme.onPrimary
                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _buildTopSummary() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 430;

    final stats = [
      (
        'Users',
        _overview['users'] ?? 0,
        Icons.people_alt_rounded,
        const Color(0xFF4F46E5),
      ),
      (
        'Venues',
        _overview['venues'] ?? 0,
        Icons.domain_rounded,
        const Color(0xFF2563EB),
      ),
      (
        'Events',
        _overview['events'] ?? 0,
        Icons.event_note_rounded,
        const Color(0xFF059669),
      ),
      (
        'Approvals',
        _overview['approvals'] ?? 0,
        Icons.fact_check_rounded,
        const Color(0xFFD97706),
      ),
      (
        'Transport',
        _overview['transport'] ?? 0,
        Icons.directions_bus_rounded,
        const Color(0xFF7C3AED),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 18 : 24),
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
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
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
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Color(0xFF4F46E5),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'SYSTEM CONTROL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 10 : 12),
              Text(
                'Administration Center',
                style: TextStyle(
                  fontSize: compact ? 18 : 20,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage users, venues, and requests across the platform.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              SizedBox(height: compact ? 14 : 16),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isRefreshing
                    ? null
                    : () => _loadCurrentSection(forceRefresh: true),
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                label: const Text(
                  'Refresh Overview',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: compact ? 10 : 12,
            crossAxisSpacing: compact ? 10 : 12,
            childAspectRatio: compact ? 2.28 : 2.2,
          ),
          itemBuilder: (context, i) {
            final (label, value, icon, color) = stats[i];
            return Container(
              padding: EdgeInsets.all(compact ? 12 : 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: compact ? 30 : 32,
                    height: compact ? 30 : 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  SizedBox(width: compact ? 7 : 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: compact ? 11.5 : 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$value',
                          style: TextStyle(
                            fontSize: compact ? 16 : 17,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 48,
              color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionRefreshButton() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final foregroundColor = isDark
        ? const Color(0xFF93C5FD)
        : const Color(0xFF2563EB);

    return Tooltip(
      message: 'Refresh',
      child: SizedBox.square(
        dimension: 44,
        child: Material(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          elevation: isDark ? 0 : 2,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          child: InkWell(
            onTap: _isRefreshing
                ? null
                : () => _loadCurrentSection(forceRefresh: true),
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: _isRefreshing
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foregroundColor,
                      ),
                    )
                  : Icon(
                      Icons.refresh_rounded,
                      size: 21,
                      color: foregroundColor,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsersSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final narrow = MediaQuery.of(context).size.width < 420;

    final actionButtonStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 16, vertical: 8),
      textStyle: TextStyle(
        fontSize: narrow ? 12 : 13,
        fontWeight: FontWeight.w600,
      ),
    );

    return _SectionShell(
      title: 'User Management',
      icon: Icons.people_outline_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSectionRefreshButton(),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _showAddUserDialog,
            style: actionButtonStyle,
            icon: const Icon(Icons.person_add_rounded, size: 16),
            label: const Text('Add User'),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_pendingUsers.isNotEmpty || _rejectedUsers.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Action Required',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_pendingUsers.isNotEmpty)
                    _InlineCountChip(
                      label: 'Pending',
                      count: _pendingUsers.length,
                      fg: const Color(0xFFD97706),
                      bg: const Color(0xFFFFFBEB),
                      border: const Color(0xFFFDE68A),
                    ),
                  if (_pendingUsers.isNotEmpty && _rejectedUsers.isNotEmpty)
                    const SizedBox(width: 8),
                  if (_rejectedUsers.isNotEmpty)
                    _InlineCountChip(
                      label: 'Rejected',
                      count: _rejectedUsers.length,
                      fg: const Color(0xFFB91C1C),
                      bg: const Color(0xFFFEE2E2),
                      border: const Color(0xFFFCA5A5),
                    ),
                ],
              ),
            ),
          if (_pendingUsers.isNotEmpty)
            ..._pendingUsers.map((item) {
              final name = (item['name'] ?? 'Unnamed').toString();
              final email = (item['email'] ?? '').toString();
              final requestedRole =
                  (item['requested_role'] ?? item['role'] ?? 'faculty')
                      .toString()
                      .replaceAll('_', ' ')
                      .toUpperCase();
              final createdAt = _fmtDate(item['created_at']);

              return _buildListCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(
                            0xFFD97706,
                          ).withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.hourglass_empty_rounded,
                            color: Color(0xFFD97706),
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
                                  fontSize: 13,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.badge_outlined,
                            size: 16,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Requested Role: $requestedRole',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            createdAt,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => _showApproveUserDialog(item),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF10B981,
                              ).withValues(alpha: 0.15),
                              foregroundColor: const Color(0xFF059669),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _showRejectUserDialog(item),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFFCA5A5)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Reject'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          if (_rejectedUsers.isNotEmpty)
            ..._rejectedUsers.map((item) {
              final name = (item['name'] ?? 'Unnamed').toString();
              final email = (item['email'] ?? '').toString();
              final reason = (item['rejection_reason'] ?? 'No reason given')
                  .toString();
              final rejectedAt = _fmtDate(
                item['rejected_at'] ?? item['updated_at'],
              );

              return _buildListCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(
                            0xFFDC2626,
                          ).withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.block_rounded,
                            color: Color(0xFFDC2626),
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
                                  fontSize: 13,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFFEE2E2,
                        ).withValues(alpha: isDark ? 0.05 : 0.5),
                        border: Border.all(
                          color: const Color(0xFFFCA5A5).withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.edit_note_rounded,
                                size: 16,
                                color: Color(0xFFB91C1C),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Rejected on $rejectedAt',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            reason,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? const Color(0xFFFCA5A5)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () => _showApproveUserDialog(item),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF2563EB,
                              ).withValues(alpha: 0.12),
                              foregroundColor: const Color(0xFF2563EB),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Re-approve',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: 'Delete rejected user',
                          child: SizedBox.square(
                            dimension: 48,
                            child: OutlinedButton(
                              onPressed: () => _deleteRejectedUser(item),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                padding: EdgeInsets.zero,
                                side: const BorderSide(
                                  color: Color(0xFFFCA5A5),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          if (_users.isEmpty && _pendingUsers.isEmpty && _rejectedUsers.isEmpty)
            _buildEmptyState(
              'No users have registered yet.',
              Icons.group_off_outlined,
            )
          else
            ..._users.map((user) {
              return _buildListCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(
                        0xFF4F46E5,
                      ).withValues(alpha: 0.12),
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.roleLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4338CA),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      onSelected: (v) {
                        if (v == 'role') {
                          _showChangeRoleDialog(user);
                        } else if (v == 'delete') {
                          _deleteUser(user);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'role',
                          child: Row(
                            children: [
                              Icon(Icons.manage_accounts_rounded, size: 18),
                              SizedBox(width: 12),
                              Text('Change Role'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Color(0xFFDC2626),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Delete User',
                                style: TextStyle(color: Color(0xFFDC2626)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildListCard({required Widget child}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 430;

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 10 : 12),
      padding: EdgeInsets.all(compact ? 14 : 16),
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
      child: child,
    );
  }

  Widget _buildVenuesSection() {
    return _SectionShell(
      title: 'Venue Management',
      icon: Icons.domain_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSectionRefreshButton(),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _showAddVenueDialog,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.add_location_alt_rounded, size: 16),
            label: const Text('Add Venue'),
          ),
        ],
      ),
      child: _venues.isEmpty
          ? _buildEmptyState(
              'No venues have been added yet.',
              Icons.location_off_outlined,
            )
          : Column(
              children: _venues.map((venue) {
                return _buildListCard(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.place_rounded,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          venue.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: const Color(0xFFDC2626),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(
                            0xFFDC2626,
                          ).withValues(alpha: 0.1),
                        ),
                        onPressed: () => _deleteVenue(venue),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildEventsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SectionShell(
      title: 'All Events',
      icon: Icons.event_note_rounded,
      trailing: _buildSectionRefreshButton(),
      child: _events.isEmpty
          ? _buildEmptyState(
              'There are no events in the system.',
              Icons.event_busy_outlined,
            )
          : Column(
              children: _events.map((event) {
                final id = (event['id'] ?? '').toString();
                final name = (event['name'] ?? '').toString();
                final venue = (event['venue_name'] ?? '-').toString();
                final status = (event['status'] ?? 'pending').toString();
                final createdAt = _fmtDateTime(event['created_at']);

                return _buildListCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 14,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    venue,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  createdAt,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _StatusPill(status: status),
                          const SizedBox(height: 12),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                            color: const Color(0xFFDC2626),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(
                                0xFFDC2626,
                              ).withValues(alpha: 0.1),
                            ),
                            onPressed: () => _deleteByPath(
                              path: '/admin/events',
                              id: id,
                              success: 'Event deleted.',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildRequestsSection() {
    final groups = {
      'Approvals': (
        _approvals,
        '/admin/approvals',
        Icons.verified_user_outlined,
      ),
      'Facility': (_facility, '/admin/facility', Icons.handyman_outlined),
      'Marketing': (_marketing, '/admin/marketing', Icons.campaign_outlined),
      'IT': (_it, '/admin/it', Icons.computer_outlined),
      'Transport': (
        _transport,
        '/admin/transport',
        Icons.directions_bus_outlined,
      ),
    };

    return _SectionShell(
      title: 'Requests Overview',
      icon: Icons.assignment_outlined,
      trailing: _buildSectionRefreshButton(),
      child: Column(
        children: groups.entries.map((entry) {
          final title = entry.key;
          final rows = entry.value.$1;
          final path = entry.value.$2;
          final icon = entry.value.$3;

          return _RequestGroupCard(
            title: title,
            rows: rows,
            icon: icon,
            onDelete: (id) => _deleteByPath(
              path: path,
              id: id,
              success: '$title request deleted.',
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInvitesSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _SectionShell(
      title: 'Invites',
      icon: Icons.forward_to_inbox_rounded,
      trailing: _buildSectionRefreshButton(),
      child: _invites.isEmpty
          ? _buildEmptyState(
              'No invites have been sent.',
              Icons.mark_email_unread_outlined,
            )
          : Column(
              children: _invites.map((invite) {
                final id = (invite['id'] ?? '').toString();
                final toEmail = (invite['to_email'] ?? '-').toString();
                final subject = (invite['subject'] ?? '').toString();
                final sentAt = _fmtDate(
                  invite['sent_at'] ?? invite['created_at'],
                );
                final status = (invite['status'] ?? 'sent').toString();

                return _buildListCard(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.mail_outline_rounded,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              toEmail,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sent: $sentAt',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _StatusPill(status: status),
                          const SizedBox(height: 8),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                            color: const Color(0xFFDC2626),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(
                                0xFFDC2626,
                              ).withValues(alpha: 0.1),
                            ),
                            onPressed: () => _deleteByPath(
                              path: '/admin/invites',
                              id: id,
                              success: 'Invite deleted.',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildPublicationsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 430;

    return _SectionShell(
      title: 'Publications',
      icon: Icons.article_outlined,
      trailing: _buildSectionRefreshButton(),
      child: _publications.isEmpty
          ? _buildEmptyState('No publications found.', Icons.note_alt_outlined)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 14,
                    vertical: 10,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.library_books_outlined,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_publications.length} publication${_publications.length == 1 ? '' : 's'} on record',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ..._publications.map((pub) {
                  final id = (pub['id'] ?? '').toString();
                  final rawName = (pub['name'] ?? '').toString().trim();
                  final name = rawName.isEmpty
                      ? 'Untitled publication'
                      : rawName;
                  final rawFileName = (pub['file_name'] ?? '')
                      .toString()
                      .trim();
                  final rawUrl = (pub['url'] ?? '').toString().trim();
                  final rawWebViewLink = (pub['web_view_link'] ?? '')
                      .toString()
                      .trim();
                  final fileName = rawFileName.isEmpty || rawFileName == '-'
                      ? ''
                      : rawFileName;
                  final publicationLink = rawUrl.isNotEmpty
                      ? rawUrl
                      : rawWebViewLink;
                  final detailText = fileName.isNotEmpty
                      ? fileName
                      : publicationLink;
                  final uploadedAt = _fmtDate(
                    pub['uploaded_at'] ?? pub['created_at'],
                  );

                  return _buildListCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: compact ? 42 : 46,
                          height: compact ? 42 : 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Color(0xFF0284C7),
                            size: 22,
                          ),
                        ),
                        SizedBox(width: compact ? 12 : 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 14.5 : 15.5,
                                  color: isDark
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              if (detailText.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        detailText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? const Color(0xFFCBD5E1)
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    size: 14,
                                    color: isDark
                                        ? const Color(0xFF64748B)
                                        : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Uploaded $uploadedAt',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Delete publication',
                          constraints: const BoxConstraints(
                            minWidth: 42,
                            minHeight: 42,
                          ),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 22,
                          ),
                          color: const Color(0xFFDC2626),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFFEE2E2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => _deleteByPath(
                            path: '/admin/publications',
                            id: id,
                            success: 'Publication deleted.',
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildSectionBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadCurrentSection,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    switch (_activeTab) {
      case _AdminTab.users:
        return _buildUsersSection();
      case _AdminTab.venues:
        return _buildVenuesSection();
      case _AdminTab.events:
        return _buildEventsSection();
      case _AdminTab.requests:
        return _buildRequestsSection();
      case _AdminTab.invites:
        return _buildInvitesSection();
      case _AdminTab.publications:
        return _buildPublicationsSection();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccess) {
      return const Scaffold(
        body: Center(
          child: Text('Access denied. This page is available to Admin only.'),
        ),
      );
    }

    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 430;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadCurrentSection(forceRefresh: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 12,
              compact ? 8 : 12,
              compact ? 10 : 12,
              116,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopSummary(),
                SizedBox(height: compact ? 14 : 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  clipBehavior: Clip.none,
                  child: Row(
                    children: [
                      _buildTabButton(_AdminTab.users, 'Users'),
                      SizedBox(width: compact ? 8 : 10),
                      _buildTabButton(_AdminTab.venues, 'Venues'),
                      SizedBox(width: compact ? 8 : 10),
                      _buildTabButton(_AdminTab.events, 'Events'),
                      SizedBox(width: compact ? 8 : 10),
                      _buildTabButton(_AdminTab.requests, 'Requests'),
                      SizedBox(width: compact ? 8 : 10),
                      _buildTabButton(_AdminTab.invites, 'Invites'),
                      SizedBox(width: compact ? 8 : 10),
                      _buildTabButton(_AdminTab.publications, 'Publications'),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 14 : 16),
                _buildSectionBody(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _activeTab == _AdminTab.users
          ? FloatingActionButton.extended(
              onPressed: _showAddUserDialog,
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('Add User'),
              elevation: 4,
            )
          : _activeTab == _AdminTab.venues
          ? FloatingActionButton.extended(
              onPressed: _showAddVenueDialog,
              icon: const Icon(Icons.add_location_alt_rounded),
              label: const Text('Add Venue'),
              elevation: 4,
            )
          : null,
    );
  }
}

class _InlineCountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color fg;
  final Color bg;
  final Color border;

  const _InlineCountChip({
    required this.label,
    required this.count,
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
              '$count',
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

class _SectionShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget trailing;
  final Widget child;

  const _SectionShell({
    required this.title,
    required this.icon,
    required this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              return Row(
                children: [
                  Icon(
                    icon,
                    size: compact ? 18 : 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 15 : 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 12),
                  FittedBox(fit: BoxFit.scaleDown, child: trailing),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();

    Color fg;
    Color bg;
    Color border;

    if (normalized == 'approved' ||
        normalized == 'completed' ||
        normalized == 'sent') {
      fg = const Color(0xFF059669);
      bg = const Color(0xFFECFDF5);
      border = const Color(0xFFA7F3D0);
    } else if (normalized == 'pending') {
      fg = const Color(0xFFD97706);
      bg = const Color(0xFFFFFBEB);
      border = const Color(0xFFFDE68A);
    } else if (normalized == 'clarification' ||
        normalized == 'clarification_requested') {
      fg = const Color(0xFF7C3AED);
      bg = const Color(0xFFF5F3FF);
      border = const Color(0xFFC4B5FD);
    } else {
      fg = const Color(0xFF475569);
      bg = const Color(0xFFF8FAFC);
      border = const Color(0xFFE2E8F0);
    }

    final displayText =
        (normalized == 'clarification' ||
            normalized == 'clarification_requested')
        ? 'CLARIFICATION'
        : status.replaceAll('_', ' ').toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }
}

class _RequestGroupCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onDelete;

  const _RequestGroupCard({
    required this.title,
    required this.icon,
    required this.rows,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                  : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${rows.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text(
                        'No requests pending.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: rows.map((row) {
                      final id = (row['id'] ?? '').toString();
                      final event = (row['event_name'] ?? '').toString();
                      final email = (row['requester_email'] ?? '').toString();
                      final status = (row['status'] ?? 'pending').toString();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFF1F5F9),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    event,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(status: status),
                            const SizedBox(width: 8),
                            IconButton(
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.all(8),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                              ),
                              color: const Color(0xFFDC2626),
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(
                                  0xFFDC2626,
                                ).withValues(alpha: 0.1),
                              ),
                              onPressed: () => onDelete(id),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
