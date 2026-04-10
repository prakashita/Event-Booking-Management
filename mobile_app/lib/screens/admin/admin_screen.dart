import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.api, required this.session});

  final ApiClient api;
  final AppSession session;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late Future<_AdminData> _future;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _future = _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<_AdminData> _load() async {
    final results = await Future.wait([
      widget.api.get('/admin/overview').then(asMap).catchError((_) => <String, dynamic>{}),
      widget.api.get('/users').then(asList).catchError((_) => []),
      widget.api.get('/admin/venues').then(asList).catchError((_) => []),
      widget.api.get('/admin/events').then(asList).catchError((_) => []),
    ]);
    return _AdminData(
      overview: results[0] as Map<String, dynamic>,
      users: results[1] as List,
      venues: results[2] as List,
      events: results[3] as List,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Admin Console',
      subtitle: 'User, venue, event, request, and publication administration.',
      action: widget.session.isAdmin
          ? IconButton(
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => setState(() => _future = _load()),
      )
          : null,
      child: FutureBuilder<_AdminData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ShimmerLoader(count: 6);
          }
          if (snap.hasError) {
            return ErrorCard(
              error: snap.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final data = snap.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Overview metrics
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  MetricCard(
                    label: 'Total Users',
                    value:
                    '${data.overview['users'] ?? data.users.length}',
                    icon: Icons.group_rounded,
                    color: AppColors.primary,
                  ),
                  MetricCard(
                    label: 'Venues',
                    value:
                    '${data.overview['venues'] ?? data.venues.length}',
                    icon: Icons.place_rounded,
                    color: const Color(0xFF10B981),
                  ),
                  MetricCard(
                    label: 'Events',
                    value:
                    '${data.overview['events'] ?? data.events.length}',
                    icon: Icons.event_rounded,
                    color: const Color(0xFF8B5CF6),
                  ),
                  MetricCard(
                    label: 'Approvals',
                    value:
                    '${data.overview['approvals'] ?? '-'}',
                    icon: Icons.approval_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Tabs
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.card,
                ),
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabCtrl,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorSize: TabBarIndicatorSize.label,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      tabs: const [
                        Tab(text: 'Users'),
                        Tab(text: 'Venues'),
                        Tab(text: 'Events'),
                      ],
                    ),
                    SizedBox(
                      height: 420,
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _UsersList(users: data.users),
                          _VenuesList(venues: data.venues),
                          _EventsList(events: data.events),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Users List ───────────────────────────────────────────────────────────────

class _UsersList extends StatelessWidget {
  const _UsersList({required this.users});

  final List users;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const EmptyCard(
        message: 'No users found.',
        icon: Icons.group_rounded,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: users.length,
      itemBuilder: (context, i) {
        final m = asMap(users[i]);
        final name =
            m['name']?.toString() ?? m['email']?.toString() ?? 'User';
        final email = m['email']?.toString() ?? '';
        final role = m['role']?.toString() ?? 'faculty';
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withAlpha(22),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(email),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role.toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Venues List ──────────────────────────────────────────────────────────────

class _VenuesList extends StatelessWidget {
  const _VenuesList({required this.venues});

  final List venues;

  @override
  Widget build(BuildContext context) {
    if (venues.isEmpty) {
      return const EmptyCard(
        message: 'No venues found.',
        icon: Icons.place_rounded,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: venues.length,
      itemBuilder: (context, i) {
        final m = asMap(venues[i]);
        final name = m['name']?.toString() ?? 'Venue ${i + 1}';
        final capacity = m['capacity']?.toString() ?? '-';
        final loc = m['location']?.toString() ?? m['building']?.toString() ?? '';
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withAlpha(22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.place_rounded,
              color: Color(0xFF10B981),
              size: 20,
            ),
          ),
          title: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: loc.isNotEmpty ? Text(loc) : null,
          trailing: Text(
            'Cap: $capacity',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }
}

// ─── Events List ──────────────────────────────────────────────────────────────

class _EventsList extends StatelessWidget {
  const _EventsList({required this.events});

  final List events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const EmptyCard(
        message: 'No events found.',
        icon: Icons.event_rounded,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final m = asMap(events[i]);
        final name = m['name']?.toString() ?? 'Event ${i + 1}';
        final date = m['start_date']?.toString() ?? '-';
        final status = m['status']?.toString() ?? 'pending';
        return ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withAlpha(22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.event_rounded,
              color: Color(0xFF8B5CF6),
              size: 20,
            ),
          ),
          title: Text(name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(date),
          trailing: StatusBadge(status: status),
        );
      },
    );
  }
}

class _AdminData {
  _AdminData({
    required this.overview,
    required this.users,
    required this.venues,
    required this.events,
  });
  final Map<String, dynamic> overview;
  final List users;
  final List venues;
  final List events;
}
