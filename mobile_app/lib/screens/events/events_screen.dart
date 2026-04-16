import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';
import 'package:intl/intl.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();

  static const _tabs = [
    'All',
    'Pending',
    'Upcoming',
    'Ongoing',
    'Completed',
    'Closed',
  ];

  final Map<String, List<Event>> _eventsByTab = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadEventsForTab(0);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
    if (!_tabController.indexIsChanging) {
      _loadEventsForTab(_tabController.index);
    }
  }

  String _statusForTab(int idx) {
    switch (idx) {
      case 1:
        return 'pending';
      case 2:
        return 'upcoming';
      case 3:
        return 'ongoing';
      case 4:
        return 'completed';
      case 5:
        return 'closed';
      default:
        return '';
    }
  }

  List<Event> _filterEventsForTab(List<Event> all, int idx) {
    final status = _statusForTab(idx);
    if (status.isEmpty) return all;
    if (status == 'pending') {
      return all.where((e) {
        final s = e.status.toLowerCase();
        return s == 'pending' || s == 'clarification_requested';
      }).toList();
    }
    return all.where((e) => (e.status).toLowerCase() == status).toList();
  }

  Future<void> _loadEventsForTab(int idx, {bool force = false}) async {
    final key = _tabs[idx];
    if (_eventsByTab.containsKey(key) && !force) return;

    if (!force) {
      setState(() {
        _loading[key] = true;
        _errors[key] = null;
      });
    }

    try {
      final eventData = await _api.get<Map<String, dynamic>>('/events');
      final approvalData = await _api.get<Map<String, dynamic>>(
        '/approvals/me',
      );

      final events = (eventData['items'] as List? ?? [])
          .map((e) => Event.fromJson(e))
          .toList();

      final approvals = (approvalData['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((a) {
            final status = (a['status'] ?? '').toString().toLowerCase();
            return status == 'pending' || status == 'clarification_requested';
          })
          .map((a) {
            final startDate = (a['start_date'] ?? '').toString();
            final startTime = (a['start_time'] ?? '').toString();
            final endDate = (a['end_date'] ?? '').toString();
            final endTime = (a['end_time'] ?? '').toString();

            final start =
                DateTime.tryParse('${startDate}T$startTime') ?? DateTime.now();
            final end = DateTime.tryParse('${endDate}T$endTime') ?? start;

            return Event(
              id: 'approval-${a['id'] ?? ''}',
              title: (a['event_name'] ?? '').toString(),
              description: a['description']?.toString(),
              venueName: (a['venue_name'] ?? '').toString(),
              startTime: start,
              endTime: end,
              status: (a['status'] ?? 'pending').toString(),
              createdBy: (a['requester_id'] ?? '').toString(),
              createdAt: DateTime.tryParse(
                (a['created_at'] ?? '').toString(),
              )?.toLocal(),
              reportFileId: null,
              audienceCount: null,
              notes: null,
            );
          })
          .toList();

      final allEvents = [...approvals, ...events]
        ..sort((a, b) {
          final aCreated = a.createdAt ?? a.startTime;
          final bCreated = b.createdAt ?? b.startTime;
          final byCreated = bCreated.compareTo(aCreated);
          if (byCreated != 0) return byCreated;
          return b.startTime.compareTo(a.startTime);
        });
      setState(() {
        _eventsByTab[key] = _filterEventsForTab(allEvents, idx);
        _loading[key] = false;
      });
    } catch (e) {
      setState(() {
        _errors[key] = e.toString();
        _loading[key] = false;
      });
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadEventsForTab(_tabController.index, force: true);
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopSection(),
            const SizedBox(height: 12),
            _buildFilterPills(),
            _buildEventsContainer(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
        onPressed: () {
          context.go('/events/create');
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTopSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headingColor = theme.colorScheme.onSurface;
    final refreshFg = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);
    final refreshBg = theme.colorScheme.surface;
    final refreshBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    final currentTabEvents =
        _eventsByTab[_tabs[_tabController.index]]?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'My Events',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: headingColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x4D2563EB),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$currentTabEvents',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => context.go('/events/create'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Event'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 8,
                  shadowColor: const Color(0x332563EB),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _handleRefresh,
                icon: _isRefreshing
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: refreshFg,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: refreshFg,
                  backgroundColor: refreshBg,
                  side: BorderSide(color: refreshBorder),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveBg = theme.colorScheme.surface;
    final inactiveBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final inactiveText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF94A3B8);

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isActive = _tabController.index == index;
          return GestureDetector(
            onTap: () {
              _tabController.animateTo(index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF2563EB) : inactiveBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isActive ? const Color(0xFF2563EB) : inactiveBorder,
                ),
                boxShadow: isActive
                    ? const [
                        BoxShadow(
                          color: Color(0x332563EB),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  _tabs[index],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: isActive ? Colors.white : inactiveText,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventsContainer() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Expanded(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
              blurRadius: 10,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(40),
            topRight: Radius.circular(40),
          ),
          child: TabBarView(
            controller: _tabController,
            children: _tabs.asMap().entries.map((entry) {
              final key = entry.value;
              final isLoading = _loading[key] ?? true;
              final error = _errors[key];
              final events = _eventsByTab[key] ?? [];

              if (isLoading) {
                return _LoadingList();
              }
              if (error != null) {
                return ErrorState(
                  message: error,
                  onRetry: () {
                    _eventsByTab.remove(key);
                    _loadEventsForTab(entry.key);
                  },
                );
              }
              if (events.isEmpty) {
                return EmptyState(
                  icon: Icons.event_busy,
                  title: 'No ${key == 'All' ? '' : key.toLowerCase()} events',
                  message:
                      'Events you create or participate in will appear here.',
                  actionLabel: 'Create Event',
                  onAction: () => context.go('/events/create'),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  _eventsByTab.remove(key);
                  await _loadEventsForTab(entry.key);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: events.length,
                  itemBuilder: (ctx, i) => _EventCard(
                    event: events[i],
                    onTap: () => context.go('/events/${events[i].id}'),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ShimmerBox(width: double.infinity, height: 160, radius: 16),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;

  const _EventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = theme.colorScheme.onSurface;
    final labelColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFFCBD5E1);
    final valueColor = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);
    final rowBorder = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF8FAFC);
    final detailsBg = isDark
        ? const Color(0xFF1E3A5F)
        : const Color(0xFFEFF6FF);
    final detailsFg = isDark
        ? const Color(0xFF93C5FD)
        : const Color(0xFF2563EB);

    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    final statusColor = _getStatusColor(event.status);
    final statusBgColor = _getStatusBgColor(event.status);
    final statusBorderColor = _getStatusBorderColor(event.status);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: rowBorder, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusBorderColor),
                  ),
                  child: Text(
                    event.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DATE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: labelColor,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      df.format(event.startTime),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: valueColor,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIME',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: labelColor,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tf.format(event.startTime),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: valueColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: detailsBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility, size: 16, color: detailsFg),
                  const SizedBox(width: 8),
                  Text(
                    'VIEW DETAILS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: detailsFg,
                      letterSpacing: 1.0,
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFD97706); // amber-600
      case 'upcoming':
        return const Color(0xFF2563EB); // blue-600
      case 'ongoing':
        return const Color(0xFF4F46E5); // indigo-600
      case 'completed':
        return const Color(0xFF059669); // emerald-600
      default:
        return const Color(0xFF475569); // slate-600
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFFFBEB); // amber-50
      case 'upcoming':
        return const Color(0xFFEFF6FF); // blue-50
      case 'ongoing':
        return const Color(0xFFEEF2FF); // indigo-50
      case 'completed':
        return const Color(0xFFECFDF5); // emerald-50
      default:
        return const Color(0xFFF8FAFC); // slate-50
    }
  }

  Color _getStatusBorderColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFEF3C7); // amber-100
      case 'upcoming':
        return const Color(0xFFDBEAFE); // blue-100
      case 'ongoing':
        return const Color(0xFFE0E7FF); // indigo-100
      case 'completed':
        return const Color(0xFFD1FAE5); // emerald-100
      default:
        return const Color(0xFFF1F5F9); // slate-100
    }
  }
}
