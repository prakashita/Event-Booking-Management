import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api, required this.session});

  final ApiClient api;
  final AppSession session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final results = await Future.wait([
      widget.api.get('/events').then(asList).catchError((_) => []),
      widget.api.get('/approvals/me').then(asList).catchError((_) => []),
      widget.api.get('/invites/me').then(asList).catchError((_) => []),
      widget.api
          .get('/facility/requests/me')
          .then(asList)
          .catchError((_) => []),
    ]);

    return _DashboardData(
      events: results[0],
      approvals: results[1],
      invites: results[2],
      facilityRequests: results[3],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return PageShell(
      title: 'Dashboard',
      subtitle: 'Overview of your events, approvals, invites, and requests.',
      action: IconButton(
        onPressed: () => setState(() => _future = _load()),
        icon: const Icon(Icons.refresh_rounded),
        tooltip: 'Refresh',
      ),
      child: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ShimmerLoader(count: 4);
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
              // Greeting Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: AppGradients.hero,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting, ${widget.session.name.split(' ').first}!',
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Here's what's happening today.",
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Metric Cards
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  MetricCard(
                    label: 'Total Events',
                    value: '${data.events.length}',
                    icon: Icons.event_rounded,
                    color: AppColors.primary,
                  ),
                  MetricCard(
                    label: 'Pending Approvals',
                    value: '${data.approvals.length}',
                    icon: Icons.approval_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                  MetricCard(
                    label: 'Invites',
                    value: '${data.invites.length}',
                    icon: Icons.mail_outline_rounded,
                    color: const Color(0xFF10B981),
                  ),
                  MetricCard(
                    label: 'Facility Requests',
                    value: '${data.facilityRequests.length}',
                    icon: Icons.meeting_room_rounded,
                    color: const Color(0xFF8B5CF6),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Recent Events
              if (data.events.isNotEmpty) ...[
                const SectionHeader(title: 'Recent Events'),
                ...data.events.take(5).map((e) {
                  final m = asMap(e);
                  return RowCard(
                    title: m['name']?.toString() ?? 'Untitled Event',
                    subtitle:
                    '${m['start_date'] ?? '-'}  •  ${m['venue_name'] ?? 'No venue'}',
                    trailing: StatusBadge(
                      status: m['status']?.toString() ?? 'pending',
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.event,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  );
                }),
              ],

              // Recent Approvals
              if (data.approvals.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader(title: 'Pending Approvals'),
                ...data.approvals.take(3).map((a) {
                  final m = asMap(a);
                  return RowCard(
                    title:
                    m['event_name']?.toString() ??
                        m['name']?.toString() ??
                        'Approval',
                    subtitle:
                    'Submitted: ${m['created_at']?.toString().split('T').first ?? '-'}',
                    trailing: StatusBadge(
                      status: m['status']?.toString() ?? 'pending',
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withAlpha(22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.approval,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DashboardData {
  _DashboardData({
    required this.events,
    required this.approvals,
    required this.invites,
    required this.facilityRequests,
  });

  final List events;
  final List approvals;
  final List invites;
  final List facilityRequests;
}
