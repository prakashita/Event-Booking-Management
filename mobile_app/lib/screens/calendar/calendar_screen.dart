import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late Future<List<dynamic>> _future;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final res = await widget.api.get('/calendar/app-events');
    return asList(res);
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString().split('T').first);
    } catch (_) {
      return null;
    }
  }

  List<dynamic> _eventsForDay(List<dynamic> all, DateTime day) {
    return all.where((e) {
      final m = asMap(e);
      final d = _parseDate(m['start'] ?? m['start_date']);
      return d != null && isSameDay(d, day);
    }).toList();
  }

  Future<void> _connectCalendar() async {
    try {
      final res = asMap(await widget.api.get('/calendar/connect-url'));
      final url = res['url']?.toString();
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showUrlDialog(url);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No connect URL returned.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  void _showUrlDialog(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Google Calendar Connect URL'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Calendar View',
      subtitle: 'Events synced through calendar endpoints.',
      action: FilledButton.icon(
        onPressed: _connectCalendar,
        icon: const Icon(Icons.link_rounded, size: 18),
        label: const Text('Connect Calendar'),
      ),
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ShimmerLoader(count: 3);
          }
          if (snap.hasError) {
            return ErrorCard(
              error: snap.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final events = snap.data ?? [];

          return Column(
            children: [
              // Calendar widget
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppShadows.card,
                ),
                child: TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calFormat,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: (day) => _eventsForDay(events, day),
                  onDaySelected: (selected, focused) {
                    setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    });
                  },
                  onFormatChanged: (f) => setState(() => _calFormat = f),
                  onPageChanged: (f) => _focusedDay = f,
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(60),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    markerDecoration: const BoxDecoration(
                      color: AppColors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: const HeaderStyle(
                    formatButtonDecoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    formatButtonTextStyle: TextStyle(color: Colors.white),
                    titleCentered: true,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Events for selected day
              if (_selectedDay != null) ...[
                SectionHeader(
                  title: 'Events on ${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}',
                ),
                ..._eventsForDay(events, _selectedDay!).map((e) {
                  final m = asMap(e);
                  return RowCard(
                    title: m['title']?.toString() ??
                        m['name']?.toString() ??
                        'Event',
                    subtitle:
                    '${m['start'] ?? m['start_date'] ?? '-'}',
                    leading: const Icon(
                      Icons.circle,
                      size: 12,
                      color: AppColors.primary,
                    ),
                  );
                }),
                if (_eventsForDay(events, _selectedDay!).isEmpty)
                  const EmptyCard(
                    message: 'No events on this day.',
                    icon: Icons.event_busy_rounded,
                  ),
              ] else ...[
                const SectionHeader(title: 'All Upcoming Events'),
                ...events.take(10).map((e) {
                  final m = asMap(e);
                  return RowCard(
                    title: m['title']?.toString() ??
                        m['name']?.toString() ??
                        'Calendar Item',
                    subtitle: m['start']?.toString() ??
                        m['start_date']?.toString() ??
                        '-',
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.event,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                  );
                }),
                if (events.isEmpty)
                  const EmptyCard(
                    message: 'No calendar events found.',
                    icon: Icons.event_busy_rounded,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
