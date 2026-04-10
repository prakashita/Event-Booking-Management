import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../widgets/common.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<List<dynamic>> _future;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final res = await widget.api.get('/admin/event-reports');
    return asList(res);
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Event Reports',
      subtitle: 'Admin and registrar reports from the event management system.',
      action: IconButton(
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => setState(() => _future = _load()),
        tooltip: 'Refresh',
      ),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search reports…',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const ShimmerLoader();
              }
              if (snap.hasError) {
                return ErrorCard(
                  error: snap.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                );
              }

              final reports = (snap.data ?? []).where((r) {
                final m = asMap(r);
                final name = (m['event_name'] ?? m['name'] ?? '')
                    .toString()
                    .toLowerCase();
                return _searchQuery.isEmpty ||
                    name.contains(_searchQuery.toLowerCase());
              }).toList();

              if (reports.isEmpty) {
                return const EmptyCard(
                  message: 'No reports available for this account.',
                  icon: Icons.receipt_long_rounded,
                );
              }

              return Column(
                children: reports.map((r) {
                  final m = asMap(r);
                  final name =
                      m['event_name']?.toString() ??
                          m['name']?.toString() ??
                          'Event Report';
                  final sub =
                      m['summary']?.toString() ??
                          m['status']?.toString() ??
                          '-';
                  final status = m['status']?.toString() ?? 'pending';
                  return RowCard(
                    title: name,
                    subtitle: sub,
                    trailing: StatusBadge(status: status),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007BFF).withAlpha(22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Color(0xFF007BFF),
                        size: 20,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
