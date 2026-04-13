import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();

  List<User> _users = [];
  List<Venue> _venues = [];
  bool _loadingUsers = true;
  bool _loadingVenues = false;
  bool _venuesLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_venuesLoaded) _loadVenues();
    });
    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/users');
      setState(() {
        _users = (data['items'] as List? ?? [])
            .map((u) => User.fromJson(u))
            .toList();
        _loadingUsers = false;
      });
    } catch (e) {
      setState(() => _loadingUsers = false);
    }
  }

  Future<void> _loadVenues() async {
    setState(() => _loadingVenues = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/venues');
      setState(() {
        _venues = (data['items'] as List? ?? data['venues'] as List? ?? [])
            .map((v) => Venue.fromJson(v))
            .toList();
        _loadingVenues = false;
        _venuesLoaded = true;
      });
    } catch (e) {
      setState(() => _loadingVenues = false);
    }
  }

  Future<void> _deleteUser(User user) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete User',
      message: 'Delete ${user.name}? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await _api.delete('/users/${user.id}');
      setState(() => _users.removeWhere((u) => u.id == user.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User deleted.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _deleteVenue(Venue venue) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete Venue',
      message: 'Remove "${venue.name}" from venue list?',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await _api.delete('/venues/${venue.id}');
      setState(() => _venues.removeWhere((v) => v.id == venue.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venue removed.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Admin Console'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Users'), Tab(text: 'Venues')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Users tab
          _loadingUsers
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadUsers,
                  child: _users.isEmpty
                      ? const EmptyState(
                          icon: Icons.people_outline,
                          title: 'No users',
                          message: 'Registered users appear here.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _users.length,
                          itemBuilder: (ctx, i) {
                            final u = _users[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _UserTile(
                                user: u,
                                onChangeRole: () => _showChangeRoleDialog(u),
                                onDelete: () => _deleteUser(u),
                              ),
                            );
                          },
                        ),
                ),

          // Venues tab
          _loadingVenues
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadVenues,
                  child: _venues.isEmpty
                      ? EmptyState(
                          icon: Icons.place_outlined,
                          title: 'No venues',
                          message: 'Add venues to enable event booking.',
                          actionLabel: 'Add Venue',
                          onAction: () => _showAddVenueDialog(context),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _venues.length,
                          itemBuilder: (ctx, i) {
                            final v = _venues[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.place_outlined,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                                title: Text(v.name),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.error,
                                  ),
                                  onPressed: () => _deleteVenue(v),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: AppColors.border),
                                ),
                                tileColor: AppColors.surface,
                              ),
                            );
                          },
                        ),
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _showAddUserDialog(context);
          } else {
            _showAddVenueDialog(context);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tabController.index == 0 ? 'Add User' : 'Add Venue'),
      ),
    );
  }

  void _showChangeRoleDialog(User user) {
    UserRole role = user.role;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Change Role – ${user.name}'),
          content: DropdownButtonFormField<UserRole>(
            value: role,
            items: UserRole.values
                .map((r) => DropdownMenuItem(
                    value: r, child: Text(r.name.toUpperCase())))
                .toList(),
            onChanged: (v) => setS(() => role = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _api.patch('/users/${user.id}/role', data: {'role': role.name});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Role updated!')),
                  );
                  _loadUsers();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddUserDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    String role = 'faculty';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add User by Email'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: ['registrar', 'facility_manager', 'marketing', 'it', 'iqac', 'transport']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase())))
                    .toList(),
                onChanged: (v) => setS(() => role = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _api.post('/auth/pending-role', data: {
                    'email': emailCtrl.text.trim(),
                    'role': role,
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User role registered!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
                  );
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddVenueDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Venue'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Venue Name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _api.post('/venues', data: {'name': nameCtrl.text.trim()});
                _venuesLoaded = false;
                _loadVenues();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Venue added!')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final User user;
  final VoidCallback onChangeRole;
  final VoidCallback onDelete;

  const _UserTile({
    required this.user,
    required this.onChangeRole,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.roleColor(user.role).withOpacity(0.15),
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.roleColor(user.role),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  user.email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.roleColor(user.role).withOpacity(0.12),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              user.role.name.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.roleColor(user.role),
                letterSpacing: 0.3,
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'role') onChangeRole();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'role', child: Text('Change Role')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete', style: TextStyle(color: AppColors.error)),
              ),
            ],
            icon: const Icon(Icons.more_vert, size: 20),
          ),
        ],
      ),
    );
  }
}
