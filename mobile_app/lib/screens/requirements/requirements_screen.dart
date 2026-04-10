import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class RequirementsScreen extends StatefulWidget {
  const RequirementsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<RequirementsScreen> createState() => _RequirementsScreenState();
}

class _RequirementsScreenState extends State<RequirementsScreen> {
  late Future<_RequirementsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RequirementsData> _load() async {
    final results = await Future.wait([
      widget.api.get('/facility/requests/me').then(asList).catchError((_) => []),
      widget.api.get('/marketing/requests/me').then(asList).catchError((_) => []),
      widget.api.get('/it/requests/me').then(asList).catchError((_) => []),
      widget.api.get('/transport/requests/me').then(asList).catchError((_) => []),
    ]);
    return _RequirementsData(
      facility: results[0],
      marketing: results[1],
      it: results[2],
      transport: results[3],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Requirements',
      subtitle: 'View your submitted operational requirements by channel.',
      action: IconButton(
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => setState(() => _future = _load()),
      ),
      child: FutureBuilder<_RequirementsData>(
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
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  MetricCard(
                    label: 'Facility',
                    value: '${data.facility.length}',
                    icon: Icons.meeting_room_rounded,
                    color: const Color(0xFF8B5CF6),
                  ),
                  MetricCard(
                    label: 'Marketing',
                    value: '${data.marketing.length}',
                    icon: Icons.campaign_rounded,
                    color: const Color(0xFFEC4899),
                  ),
                  MetricCard(
                    label: 'IT',
                    value: '${data.it.length}',
                    icon: Icons.computer_rounded,
                    color: const Color(0xFF0EA5E9),
                  ),
                  MetricCard(
                    label: 'Transport',
                    value: '${data.transport.length}',
                    icon: Icons.directions_bus_rounded,
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _RequirementsSection(
                title: 'Facility Requests',
                items: data.facility,
                icon: Icons.meeting_room_rounded,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(height: 16),
              _RequirementsSection(
                title: 'Marketing Requests',
                items: data.marketing,
                icon: Icons.campaign_rounded,
                color: const Color(0xFFEC4899),
              ),
              const SizedBox(height: 16),
              _RequirementsSection(
                title: 'IT Requests',
                items: data.it,
                icon: Icons.computer_rounded,
                color: const Color(0xFF0EA5E9),
              ),
              const SizedBox(height: 16),
              _RequirementsSection(
                title: 'Transport Requests',
                items: data.transport,
                icon: Icons.directions_bus_rounded,
                color: const Color(0xFF10B981),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RequirementsSection extends StatelessWidget {
  const _RequirementsSection({
    required this.title,
    required this.items,
    required this.icon,
    required this.color,
  });

  final String title;
  final List items;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        ...items.take(5).map((item) {
          final m = asMap(item);
          final name = m['name']?.toString() ??
              m['event_name']?.toString() ??
              'Request';
          final status = m['status']?.toString() ?? 'pending';
          return RowCard(
            title: name,
            subtitle: m['description']?.toString() ?? status,
            trailing: StatusBadge(status: status),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withAlpha(22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
          );
        }),
      ],
    );
  }
}

class _RequirementsData {
  _RequirementsData({
    required this.facility,
    required this.marketing,
    required this.it,
    required this.transport,
  });
  final List facility;
  final List marketing;
  final List it;
  final List transport;
}
