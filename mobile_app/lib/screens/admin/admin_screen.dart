import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
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
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
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
    final text = error.toString();
    if (text.isEmpty) return 'Something went wrong.';
    return text;
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
                title: Text('Change Role - ${user.name}'),
                content: DropdownButtonFormField<String>(
                  initialValue: selected,
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
                title: const Text('Add User'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role'),
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
          title: const Text('Add Venue'),
          content: TextField(
            controller: venueCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Venue name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
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
          title: const Text('Reject User'),
          content: TextField(
            controller: reasonCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Provide a reason for rejection',
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
    return DateFormat('yyyy-MM-dd h:mm a').format(parsed.toLocal());
  }

  Widget _buildTabButton(_AdminTab tab, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isActive = _activeTab == tab;

    return GestureDetector(
      onTap: () => _switchTab(tab),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2563EB) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? const Color(0xFF2563EB)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isActive ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildTopSummary() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final stats = [
      (
        'Users',
        _overview['users'] ?? 0,
        Icons.people_alt_outlined,
        const Color(0xFF4F46E5),
      ),
      (
        'Venues',
        _overview['venues'] ?? 0,
        Icons.place_outlined,
        const Color(0xFF2563EB),
      ),
      (
        'Events',
        _overview['events'] ?? 0,
        Icons.event_outlined,
        const Color(0xFF059669),
      ),
      (
        'Approvals',
        _overview['approvals'] ?? 0,
        Icons.verified_outlined,
        const Color(0xFFD97706),
      ),
      (
        'Transport',
        _overview['transport'] ?? 0,
        Icons.directions_bus_outlined,
        const Color(0xFF7C3AED),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    color: const Color(0xFF4F46E5),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'System Control',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Administration Center',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage users, venues, and requests across the platform.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _isRefreshing
                    ? null
                    : () => _loadCurrentSection(forceRefresh: true),
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh Overview'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: stats.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.8,
          ),
          itemBuilder: (context, i) {
            final (label, value, icon, color) = stats[i];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '$value',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: color,
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

  Widget _buildUsersSection() {
    final theme = Theme.of(context);
    final border = theme.brightness == Brightness.dark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final narrow = MediaQuery.of(context).size.width < 420;
    final compactOutlinedStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 10, vertical: 7),
      minimumSize: Size(narrow ? 64 : 72, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontSize: narrow ? 11 : 12,
        fontWeight: FontWeight.w700,
      ),
    );
    final compactFilledStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 10, vertical: 7),
      minimumSize: Size(narrow ? 64 : 78, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontSize: narrow ? 11 : 12,
        fontWeight: FontWeight.w700,
      ),
    );

    return _SectionShell(
      title: 'User Management',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: () => _loadCurrentSection(forceRefresh: true),
            style: compactOutlinedStyle,
            child: const Text('Refresh'),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _showAddUserDialog,
            style: compactFilledStyle,
            child: const Text('Add User'),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InlineCountChip(
                  label: 'Pending',
                  count: _pendingUsers.length,
                  fg: const Color(0xFFD97706),
                  bg: const Color(0xFFFFFBEB),
                  border: const Color(0xFFFDE68A),
                ),
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
                      '$name ($email)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Requested: $requestedRole • $createdAt',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton.tonal(
                          onPressed: () => _showApproveUserDialog(item),
                          child: const Text('Approve'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _showRejectUserDialog(item),
                          child: const Text('Reject'),
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
                      '$name ($email)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rejected: $rejectedAt',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.brightness == Brightness.dark
                            ? const Color(0xFFCBD5E1)
                            : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _showApproveUserDialog(item),
                      child: const Text('Re-approve'),
                    ),
                  ],
                ),
              );
            }),
          if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No users found.'),
            )
          else
            ..._users.map((user) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(
                        0xFF4F46E5,
                      ).withValues(alpha: 0.16),
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.brightness == Brightness.dark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        user.roleLabel,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'role') {
                          _showChangeRoleDialog(user);
                        } else if (v == 'delete') {
                          _deleteUser(user);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'role',
                          child: Text('Change Role'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
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

  Widget _buildVenuesSection() {
    final theme = Theme.of(context);
    final border = theme.brightness == Brightness.dark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final narrow = MediaQuery.of(context).size.width < 420;
    final compactOutlinedStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 10, vertical: 7),
      minimumSize: Size(narrow ? 64 : 72, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontSize: narrow ? 11 : 12,
        fontWeight: FontWeight.w700,
      ),
    );
    final compactFilledStyle = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 10, vertical: 7),
      minimumSize: Size(narrow ? 72 : 84, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontSize: narrow ? 11 : 12,
        fontWeight: FontWeight.w700,
      ),
    );

    return _SectionShell(
      title: 'Venue Management',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            onPressed: () => _loadCurrentSection(forceRefresh: true),
            style: compactOutlinedStyle,
            child: const Text('Refresh'),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _showAddVenueDialog,
            style: compactFilledStyle,
            child: const Text('Add Venue'),
          ),
        ],
      ),
      child: _venues.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No venues found.'),
            )
          : Column(
              children: _venues.map((venue) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.place_outlined,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          venue.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFDC2626),
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
    final theme = Theme.of(context);
    final border = theme.brightness == Brightness.dark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return _SectionShell(
      title: 'All Events',
      trailing: OutlinedButton(
        onPressed: () => _loadCurrentSection(forceRefresh: true),
        child: const Text('Refresh'),
      ),
      child: _events.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No events found.'),
            )
          : Column(
              children: _events.map((event) {
                final id = (event['id'] ?? '').toString();
                final name = (event['name'] ?? '').toString();
                final venue = (event['venue_name'] ?? '-').toString();
                final status = (event['status'] ?? 'pending').toString();
                final createdAt = _fmtDateTime(event['created_at']);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$venue - $createdAt',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusPill(status: status),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFDC2626),
                        ),
                        onPressed: () => _deleteByPath(
                          path: '/admin/events',
                          id: id,
                          success: 'Event deleted.',
                        ),
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
      'Approvals': (_approvals, '/admin/approvals'),
      'Facility': (_facility, '/admin/facility'),
      'Marketing': (_marketing, '/admin/marketing'),
      'IT': (_it, '/admin/it'),
      'Transport': (_transport, '/admin/transport'),
    };

    return _SectionShell(
      title: 'Requests Overview',
      trailing: OutlinedButton(
        onPressed: () => _loadCurrentSection(forceRefresh: true),
        child: const Text('Refresh'),
      ),
      child: Column(
        children: groups.entries.map((entry) {
          final title = entry.key;
          final rows = entry.value.$1;
          final path = entry.value.$2;

          return _RequestGroupCard(
            title: title,
            rows: rows,
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
    final theme = Theme.of(context);
    final border = theme.brightness == Brightness.dark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return _SectionShell(
      title: 'Invites',
      trailing: OutlinedButton(
        onPressed: () => _loadCurrentSection(forceRefresh: true),
        child: const Text('Refresh'),
      ),
      child: _invites.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No invites found.'),
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

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              toEmail,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              sentAt,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusPill(status: status),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFDC2626),
                        ),
                        onPressed: () => _deleteByPath(
                          path: '/admin/invites',
                          id: id,
                          success: 'Invite deleted.',
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildPublicationsSection() {
    final theme = Theme.of(context);
    final border = theme.brightness == Brightness.dark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return _SectionShell(
      title: 'Publications',
      trailing: OutlinedButton(
        onPressed: () => _loadCurrentSection(forceRefresh: true),
        child: const Text('Refresh'),
      ),
      child: _publications.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('No publications found.'),
            )
          : Column(
              children: _publications.map((pub) {
                final id = (pub['id'] ?? '').toString();
                final name = (pub['name'] ?? '').toString();
                final fileName = (pub['file_name'] ?? '-').toString();
                final uploadedAt = _fmtDate(
                  pub['uploaded_at'] ?? pub['created_at'],
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              uploadedAt,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.brightness == Brightness.dark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFDC2626),
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
              }).toList(),
            ),
    );
  }

  Widget _buildSectionBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _loadCurrentSection,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadCurrentSection(forceRefresh: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopSummary(),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTabButton(_AdminTab.users, 'Users'),
                      const SizedBox(width: 8),
                      _buildTabButton(_AdminTab.venues, 'Venues'),
                      const SizedBox(width: 8),
                      _buildTabButton(_AdminTab.events, 'Events'),
                      const SizedBox(width: 8),
                      _buildTabButton(_AdminTab.requests, 'Requests'),
                      const SizedBox(width: 8),
                      _buildTabButton(_AdminTab.invites, 'Invites'),
                      const SizedBox(width: 8),
                      _buildTabButton(_AdminTab.publications, 'Publications'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildSectionBody(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _activeTab == _AdminTab.users
          ? FloatingActionButton.extended(
              onPressed: _showAddUserDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add User'),
            )
          : _activeTab == _AdminTab.venues
          ? FloatingActionButton.extended(
              onPressed: _showAddVenueDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Venue'),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final String title;
  final Widget trailing;
  final Widget child;

  const _SectionShell({
    required this.title,
    required this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 18 : 20,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  FittedBox(fit: BoxFit.scaleDown, child: trailing),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
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
    } else if (normalized == 'clarification_requested') {
      fg = const Color(0xFF7C3AED);
      bg = const Color(0xFFF5F3FF);
      border = const Color(0xFFC4B5FD);
    } else {
      fg = const Color(0xFF475569);
      bg = const Color(0xFFF8FAFC);
      border = const Color(0xFFE2E8F0);
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

class _RequestGroupCard extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onDelete;

  const _RequestGroupCard({
    required this.title,
    required this.rows,
    required this.onDelete,
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${rows.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(
              'No requests found.',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            )
          else
            ...rows.map((row) {
              final id = (row['id'] ?? '').toString();
              final event = (row['event_name'] ?? '').toString();
              final email = (row['requester_email'] ?? '').toString();
              final status = (row['status'] ?? 'pending').toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
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
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(status: status),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFDC2626),
                      ),
                      onPressed: () => onDelete(id),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
