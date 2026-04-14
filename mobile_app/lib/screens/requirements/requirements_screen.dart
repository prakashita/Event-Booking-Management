import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class RequirementsScreen extends StatefulWidget {
  const RequirementsScreen({super.key});

  @override
  State<RequirementsScreen> createState() => _RequirementsScreenState();
}

class _RequirementsScreenState extends State<RequirementsScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;
  late String _role;

  List<dynamic> _inboxItems = [];
  List<dynamic> _myItems = [];
  bool _loadingInbox = true;
  bool _loadingMine = false;
  bool _mineLoaded = false;

  @override
  void initState() {
    super.initState();
    _role = context.read<AuthProvider>().user?.role.name ?? 'faculty';
    _tabController = TabController(length: _showInbox ? 2 : 1, vsync: this);
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

  bool get _showInbox =>
      AppConstants.facilityRoles.contains(_role) ||
      AppConstants.marketingRoles.contains(_role) ||
      AppConstants.itRoles.contains(_role);

  String get _inboxPath {
    if (AppConstants.facilityRoles.contains(_role)) return '/facility/inbox';
    if (AppConstants.marketingRoles.contains(_role)) return '/marketing/inbox';
    if (AppConstants.itRoles.contains(_role)) return '/it/inbox';
    return '/facility/requests/me';
  }

  String get _minePath {
    if (AppConstants.facilityRoles.contains(_role))
      return '/facility/requests/me';
    if (AppConstants.marketingRoles.contains(_role))
      return '/marketing/requests/me';
    if (AppConstants.itRoles.contains(_role)) return '/it/requests/me';
    return '/facility/requests/me';
  }

  String _patchPath(String id) {
    if (AppConstants.facilityRoles.contains(_role))
      return '/facility/requests/$id';
    if (AppConstants.marketingRoles.contains(_role))
      return '/marketing/requests/$id';
    return '/it/requests/$id';
  }

  Future<void> _loadInbox() async {
    setState(() => _loadingInbox = true);
    try {
      final data = await _api.get<Map<String, dynamic>>(_inboxPath);
      final items = (data['items'] as List? ?? []);
      setState(() {
        _inboxItems = _parseItems(items);
        _loadingInbox = false;
      });
    } catch (e) {
      setState(() => _loadingInbox = false);
    }
  }

  Future<void> _loadMine() async {
    setState(() => _loadingMine = true);
    try {
      final data = await _api.get<Map<String, dynamic>>(_minePath);
      setState(() {
        _myItems = _parseItems(data['items'] as List? ?? []);
        _loadingMine = false;
        _mineLoaded = true;
      });
    } catch (e) {
      setState(() => _loadingMine = false);
    }
  }

  List<dynamic> _parseItems(List items) {
    if (AppConstants.facilityRoles.contains(_role)) {
      return items.map((e) => FacilityRequest.fromJson(e)).toList();
    }
    if (AppConstants.marketingRoles.contains(_role)) {
      return items.map((e) => MarketingRequest.fromJson(e)).toList();
    }
    return items.map((e) => ITRequest.fromJson(e)).toList();
  }

  Future<void> _decide(String id, bool accept) async {
    try {
      await _api.patch(
        _patchPath(id),
        data: {'status': accept ? 'accepted' : 'rejected'},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Request accepted!' : 'Request rejected.'),
          backgroundColor: accept ? AppColors.success : AppColors.textSecondary,
        ),
      );
      _inboxItems = [];
      _loadInbox();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabLabels = _showInbox ? ['Inbox', 'My Requests'] : ['My Requests'];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Requirements'),
        bottom: TabBar(
          controller: _tabController,
          tabs: tabLabels.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Inbox (for facility/marketing/IT)
          _loadingInbox
              ? _buildLoading()
              : _inboxItems.isEmpty
              ? const EmptyState(
                  icon: Icons.check_circle_outline,
                  title: 'All caught up',
                  message: 'No pending requests in your inbox.',
                )
              : RefreshIndicator(
                  onRefresh: _loadInbox,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _inboxItems.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RequestCard(
                        item: _inboxItems[i],
                        role: _role,
                        showActions: true,
                        onAccept: () => _decide(_itemId(_inboxItems[i]), true),
                        onReject: () => _decide(_itemId(_inboxItems[i]), false),
                      ),
                    ),
                  ),
                ),

          if (_showInbox)
            _loadingMine
                ? _buildLoading()
                : _myItems.isEmpty
                ? const EmptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No requests',
                    message: 'Requests you submit will appear here.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _myItems.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RequestCard(
                        item: _myItems[i],
                        role: _role,
                        showActions: false,
                      ),
                    ),
                  ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
      ),
    );
  }

  String _itemId(dynamic item) {
    if (item is FacilityRequest) return item.id;
    if (item is MarketingRequest) return item.id;
    if (item is ITRequest) return item.id;
    return '';
  }

  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerBox(width: double.infinity, height: 110, radius: 12),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    if (AppConstants.facilityRoles.contains(_role)) {
      _showFacilityDialog(context);
    } else if (AppConstants.itRoles.contains(_role) || _role == 'faculty') {
      _showITDialog(context);
    } else {
      _showMarketingDialog(context);
    }
  }

  void _showFacilityDialog(BuildContext context) {
    final setupCtrl = TextEditingController();
    final refreshCtrl = TextEditingController();
    final titleCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Facility Request',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Event Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: setupCtrl,
              decoration: const InputDecoration(labelText: 'Setup Details'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refreshCtrl,
              decoration: const InputDecoration(
                labelText: 'Refreshment Details',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await _api.post(
                      '/facility/requests',
                      data: {
                        'event_title': titleCtrl.text,
                        'setup_details': setupCtrl.text,
                        'refreshment_details': refreshCtrl.text,
                      },
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Facility request submitted!'),
                      ),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                },
                child: const Text('Submit Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showITDialog(BuildContext context) {
    String mode = 'offline';
    bool pa = false, projection = false;
    final notesCtrl = TextEditingController();
    final titleCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New IT Request',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Event Title'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Event Mode'),
                items: const [
                  DropdownMenuItem(value: 'offline', child: Text('Offline')),
                  DropdownMenuItem(value: 'online', child: Text('Online')),
                  DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
                ],
                onChanged: (v) => setS(() => mode = v!),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('PA System'),
                value: pa,
                onChanged: (v) => setS(() => pa = v!),
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                title: const Text('Projection'),
                value: projection,
                onChanged: (v) => setS(() => projection = v!),
                contentPadding: EdgeInsets.zero,
              ),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Additional Notes',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await _api.post(
                        '/it/requests',
                        data: {
                          'event_title': titleCtrl.text,
                          'mode': mode,
                          'pa_system': pa,
                          'projection': projection,
                          'notes': notesCtrl.text,
                        },
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('IT request submitted!')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  child: const Text('Submit Request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMarketingDialog(BuildContext context) {
    final List<String> selected = [];
    final notesCtrl = TextEditingController();
    final titleCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Marketing Request',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Event Title'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Items Required:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: AppConstants.marketingItems.map((item) {
                  final sel = selected.contains(item);
                  return FilterChip(
                    label: Text(item),
                    selected: sel,
                    onSelected: (v) {
                      setS(() {
                        if (v)
                          selected.add(item);
                        else
                          selected.remove(item);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          try {
                            await _api.post(
                              '/marketing/requests',
                              data: {
                                'event_title': titleCtrl.text,
                                'items': selected,
                                'notes': notesCtrl.text,
                              },
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Marketing request submitted!'),
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e.toString()),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        },
                  child: const Text('Submit Request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final dynamic item;
  final String role;
  final bool showActions;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _RequestCard({
    required this.item,
    required this.role,
    required this.showActions,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    String title = '';
    String status = '';
    String requestedBy = '';
    String details = '';

    if (item is FacilityRequest) {
      final r = item as FacilityRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      details = [
        if (r.setupDetails != null) 'Setup: ${r.setupDetails}',
        if (r.refreshmentDetails != null)
          'Refreshments: ${r.refreshmentDetails}',
      ].join('\n');
    } else if (item is ITRequest) {
      final r = item as ITRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      details =
          'Mode: ${r.mode.toUpperCase()}${r.paSystem ? ' · PA System' : ''}${r.projection ? ' · Projection' : ''}';
    } else if (item is MarketingRequest) {
      final r = item as MarketingRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      details = r.items.join(', ');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              StatusBadge(status),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow(icon: Icons.person_outline, text: requestedBy),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (showActions && status == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                    ),
                    child: const Text('Accept'),
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
