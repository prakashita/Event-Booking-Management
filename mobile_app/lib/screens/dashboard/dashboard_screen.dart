import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/error_state.dart';
import '../home_screen.dart';
import '../../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  List<Event> _approvedEvents = [];
  bool _isLoading = true;
  String? _error;
  late DateTime _currentTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final eventsData = await _api.get<dynamic>('/events');
      final approvalsData = await _api.get<dynamic>('/approvals/me');

      if (!mounted) return;

      final eventsRaw = eventsData is List
          ? eventsData
          : (eventsData is Map
                ? eventsData['items'] as List? ?? const []
                : const []);
      final approvalsRaw = approvalsData is List
          ? approvalsData
          : (approvalsData is Map
                ? approvalsData['items'] as List? ?? const []
                : const []);

      final approvalByEventId = <String, String>{};
      final approvalByEventKey = <String, String>{};

      for (final raw in approvalsRaw) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final status = (item['status'] ?? '').toString().toLowerCase();
        final eventId = (item['event_id'] ?? '').toString();
        if (eventId.isNotEmpty) {
          approvalByEventId[eventId] = status;
        }
        approvalByEventKey[_buildEventKey(item)] = status;
      }

      final approvedEvents = <Event>[];
      for (final raw in eventsRaw) {
        if (raw is! Map) continue;
        final eventJson = Map<String, dynamic>.from(raw);
        final eventId = (eventJson['id'] ?? eventJson['_id'] ?? '').toString();
        final status =
            approvalByEventId[eventId] ??
            approvalByEventKey[_buildEventKey(eventJson)] ??
            '';
        if (status == 'approved') {
          eventJson['approval_status'] = status;
          approvedEvents.add(Event.fromJson(eventJson));
        }
      }

      setState(() {
        _approvedEvents = approvedEvents;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && e.response?.statusCode == 401) {
        context.read<AuthProvider>().handleUnauthorized();
        return;
      }
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  String _normalizeTime(String? value) {
    if (value == null || value.isEmpty) return '';
    final parts = value.split(':');
    if (parts.length < 2) return value;
    return '${parts[0]}:${parts[1]}';
  }

  String _buildEventKey(Map<String, dynamic> item) {
    return [
      (item['event_name'] ?? item['name'] ?? '').toString(),
      (item['start_date'] ?? '').toString(),
      _normalizeTime((item['start_time'] ?? '').toString()),
      (item['end_date'] ?? '').toString(),
      _normalizeTime((item['end_time'] ?? '').toString()),
    ].join('|');
  }

  String _fallbackEventImageUrl(Event event) {
    final seedSource = event.id.isNotEmpty ? event.id : event.title;
    final seed = Uri.encodeComponent('event-$seedSource');
    return 'https://picsum.photos/seed/$seed/640/360';
  }

  String _resolveEventImageUrl(Event event) {
    final raw = (event.imageUrl ?? '').trim();
    if (raw.isEmpty) return _fallbackEventImageUrl(event);

    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) {
      return raw;
    }

    final base = _api.baseUrl;
    if (base != null && base.isNotEmpty) {
      if (raw.startsWith('/')) {
        return '$base$raw';
      }
      return '$base/$raw';
    }

    return _fallbackEventImageUrl(event);
  }

  List<Event> _applySearch(List<Event> events, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return events;
    return events.where((event) {
      final haystack = [
        event.title,
        event.description ?? '',
        event.venueName,
        event.status,
        DateFormat('yyyy-MM-dd').format(event.startTime),
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: theme.colorScheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              sliver: SliverToBoxAdapter(child: _buildHeader()),
            ),
            SliverToBoxAdapter(child: _buildEventsContainer()),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: 80),
            ), // Space for bottom nav/FAB
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OVERVIEW',
                style: TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.calendar,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMM d, yyyy').format(_currentTime),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventsContainer() {
    final theme = Theme.of(context);
    final query = DashboardSearchScope.maybeOf(context)?.searchQuery ?? '';
    final visibleEvents = _applySearch(_approvedEvents, query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Events',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Upcoming and scheduled activities',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (visibleEvents.isNotEmpty)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.go('/events'),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        'See All',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildEventsContent(visibleEvents, query),
      ],
    );
  }

  Widget _buildEventsContent(List<Event> visibleEvents, String query) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorState(message: _error!, onRetry: _loadData),
      );
    }

    if (_approvedEvents.isEmpty || visibleEvents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              Icon(
                LucideIcons.calendarX,
                size: 48,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                query.trim().isEmpty
                    ? 'No events approved by registrar yet.'
                    : 'No events match your search.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: visibleEvents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = visibleEvents[index];
        return _DashboardEventCard(
          event: event,
          imageUrl: _resolveEventImageUrl(event),
          onTap: () => context.push('/events/${event.id}'),
        );
      },
    );
  }
}

class _DashboardEventCard extends StatelessWidget {
  const _DashboardEventCard({
    required this.event,
    required this.imageUrl,
    required this.onTap,
  });

  final Event event;
  final String imageUrl;
  final VoidCallback onTap;

  Widget _eventPlaceholder(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      ),
      child: Center(
        child: Icon(
          LucideIcons.image,
          size: 32,
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
        ),
      ),
    );
  }

  ({String label, Color bg, Color fg}) _statusStyle() {
    if ((event.approvalStatus ?? '').toLowerCase() == 'approved') {
      return (label: 'APPROVED', bg: const Color(0xFF10B981), fg: Colors.white);
    }
    final status = event.status.toLowerCase();
    if (status == 'upcoming') {
      return (label: 'UPCOMING', bg: const Color(0xFF2563EB), fg: Colors.white);
    }
    if (status == 'ongoing') {
      return (label: 'ONGOING', bg: const Color(0xFFF59E0B), fg: Colors.white);
    }
    if (status == 'completed' || status == 'closed') {
      return (
        label: status.toUpperCase(),
        bg: const Color(0xFF10B981),
        fg: Colors.white,
      );
    }
    return (
      label: status.isEmpty ? 'EVENT' : status.toUpperCase(),
      bg: const Color(0xFF64748B),
      fg: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = _statusStyle();

    return Card(
      elevation: isDark ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.transparent,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _eventPlaceholder(isDark),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status.bg.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: status.fg,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMM d, yyyy').format(event.startTime),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        LucideIcons.clock,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('h:mm a').format(event.startTime),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
