import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../models/models.dart';
import '../home_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/common/error_state.dart';

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
          approvedEvents.add(Event.fromJson(eventJson));
        }
      }

      setState(() {
        _approvedEvents = approvedEvents;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: const Color(0xFF2563EB),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              sliver: SliverToBoxAdapter(child: _buildHeader()),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              sliver: SliverToBoxAdapter(child: _buildEventsContainer()),
            ),
            // Add padding to the bottom to allow scrolling past the card
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final heading = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OVERVIEW',
                    style: TextStyle(
                      color: muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Dashboard',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: heading,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16), // rounded-2xl
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.calendar,
                    size: 16,
                    color: Color(0xFF3B82F6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('MMMM d, yyyy').format(_currentTime),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// This creates the large white rounded card from the React code
  Widget _buildEventsContainer() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final query = DashboardSearchScope.maybeOf(context)?.searchQuery ?? '';
    final visibleEvents = _applySearch(_approvedEvents, query);

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(40), // rounded-[2.5rem]
        border: Border.all(
          color: isDark
              ? const Color(0xFF334155)
              : Colors.white.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.02),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Widget Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Events',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage your upcoming and scheduled activities',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              if (visibleEvents.isNotEmpty)
                Row(
                  children: [
                    _buildNavButton(LucideIcons.chevronLeft),
                    const SizedBox(width: 8),
                    _buildNavButton(LucideIcons.chevronRight),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 24),
          _buildContentArea(visibleEvents, query),
        ],
      ),
    );
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

  Widget _buildContentArea(List<Event> visibleEvents, String query) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                backgroundColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFEFF6FF),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(0xFF3B82F6),
                ), // blue-500
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Fetching latest data...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: ErrorState(message: _error!, onRetry: _loadData),
      );
    }

    if (_approvedEvents.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        child: Text(
          'No events approved by registrar yet.',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
          ),
        ),
      );
    }

    if (visibleEvents.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        child: Text(
          query.trim().isEmpty
              ? 'No events approved by registrar yet.'
              : 'No events match your search.',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        var crossAxisCount = 1;
        if (width >= 980) {
          crossAxisCount = 3;
        } else if (width >= 620) {
          crossAxisCount = 2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: visibleEvents.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 235,
          ),
          itemBuilder: (context, index) {
            final event = visibleEvents[index];
            return _DashboardEventCard(
              event: event,
              imageUrl: _resolveEventImageUrl(event),
              onTap: () => context.go('/events/${event.id}'),
            );
          },
        );
      },
    );
  }

  Widget _buildNavButton(IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final navFg = isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: navBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {}, // Add navigation logic here
          child: Icon(icon, size: 20, color: navFg),
        ),
      ),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF334155), Color(0xFF1E293B)]
              : const [Color(0xFF93C5FD), Color(0xFF60A5FA)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_rounded,
          size: 34,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  ({String label, Color bg, Color fg}) _statusStyle() {
    final status = event.status.toLowerCase();
    if (status == 'upcoming') {
      return (label: 'UPCOMING', bg: const Color(0xFF2563EB), fg: Colors.white);
    }
    if (status == 'ongoing') {
      return (label: 'ONGOING', bg: const Color(0xFFF39A2C), fg: Colors.white);
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
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final status = _statusStyle();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _eventPlaceholder(isDark),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.fromRGBO(13, 14, 20, 20 / 255),
                            Color.fromRGBO(13, 14, 20, 71 / 255),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: status.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          color: status.fg,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(LucideIcons.calendar, size: 14, color: muted),
                const SizedBox(width: 6),
                Text(
                  DateFormat('yyyy-MM-dd').format(event.startTime),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(width: 6),
                Text('•', style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(width: 6),
                Text(
                  DateFormat('h:mm a').format(event.startTime),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
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
