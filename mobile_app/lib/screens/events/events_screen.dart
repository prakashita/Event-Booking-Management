import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../constants/app_colors.dart';
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

  static const _tabs = ['All', 'Upcoming', 'Ongoing', 'Completed', 'Closed'];

  final Map<String, List<Event>> _eventsByTab = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};

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
    if (!_tabController.indexIsChanging) return;
    _loadEventsForTab(_tabController.index);
  }

  String _statusForTab(int idx) {
    switch (idx) {
      case 1: return 'upcoming';
      case 2: return 'ongoing';
      case 3: return 'completed';
      case 4: return 'closed';
      default: return '';
    }
  }

  List<Event> _filterEventsForTab(List<Event> all, int idx) {
    final status = _statusForTab(idx);
    if (status.isEmpty) return all;
    return all
        .where((e) => (e.status).toLowerCase() == status)
        .toList();
  }

  Future<void> _loadEventsForTab(int idx) async {
    final key = _tabs[idx];
    if (_eventsByTab.containsKey(key)) return;

    setState(() {
      _loading[key] = true;
      _errors[key] = null;
    });

    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/events',
      );
      final allEvents = (data['items'] as List? ?? [])
          .map((e) => Event.fromJson(e))
          .toList();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Events'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
          onTap: _loadEventsForTab,
        ),
      ),
      body: TabBarView(
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
              message: 'Events you create or participate in will appear here.',
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: events.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EventCard(
                  event: events[i],
                  onTap: () => context.go('/events/${events[i].id}'),
                ),
              ),
            ),
          );
        }).toList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/events/create'),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerBox(width: double.infinity, height: 100, radius: 12),
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
    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                StatusBadge(event.status),
              ],
            ),
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                event.description!,
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
            Row(
              children: [
                Expanded(
                  child: InfoRow(
                    icon: Icons.location_on_outlined,
                    text: event.venueName,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: InfoRow(
                    icon: Icons.schedule,
                    text:
                        '${df.format(event.startDatetime)} · ${tf.format(event.startDatetime)}',
                  ),
                ),
                if (event.status == 'completed' && event.reportFileId == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_outlined,
                            size: 12, color: AppColors.warning),
                        SizedBox(width: 4),
                        Text(
                          'Report pending',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
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
