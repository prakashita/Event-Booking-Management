import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _api = ApiService();
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Event>> _eventsByDay = {};
  List<Event> _allEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/calendar/app-events');
      final events = (data['items'] as List? ?? data as List? ?? [])
          .map((e) => Event.fromJson(e is Map<String, dynamic> ? e : {}))
          .toList();

      final Map<DateTime, List<Event>> byDay = {};
      for (final e in events) {
        final day = DateTime(
          e.startDatetime.year,
          e.startDatetime.month,
          e.startDatetime.day,
        );
        byDay.putIfAbsent(day, () => []).add(e);
      }

      setState(() {
        _allEvents = events;
        _eventsByDay = byDay;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Event> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _eventsByDay[key] ?? [];
  }

  List<Event> get _selectedEvents {
    return _selectedDay != null ? _getEventsForDay(_selectedDay!) : [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = DateTime.now();
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: AppColors.surface,
                  child: TableCalendar<Event>(
                    firstDay: DateTime(2020),
                    lastDay: DateTime(2030),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
                    eventLoader: _getEventsForDay,
                    calendarStyle: CalendarStyle(
                      selectedDecoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle:
                          const TextStyle(color: AppColors.primary),
                      markerDecoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 3,
                      outsideDaysVisible: false,
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      leftChevronIcon: const Icon(
                          Icons.chevron_left, color: AppColors.textSecondary),
                      rightChevronIcon: const Icon(
                          Icons.chevron_right, color: AppColors.textSecondary),
                    ),
                    daysOfWeekStyle: const DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                      weekendStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDay = selected;
                        _focusedDay = focused;
                      });
                    },
                    onPageChanged: (focused) {
                      _focusedDay = focused;
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _selectedEvents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.event_available,
                                  size: 48, color: AppColors.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                _selectedDay != null
                                    ? 'No events on ${DateFormat('MMM d').format(_selectedDay!)}'
                                    : 'Select a day to view events',
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _selectedEvents.length,
                          itemBuilder: (ctx, i) {
                            final e = _selectedEvents[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _CalendarEventCard(event: e),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _CalendarEventCard extends StatelessWidget {
  final Event event;
  const _CalendarEventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final tf = DateFormat('h:mm a');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: AppColors.statusColor(event.status),
            width: 4,
          ),
        ),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              StatusBadge(event.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              InfoRow(
                icon: Icons.schedule,
                text:
                    '${tf.format(event.startDatetime)} – ${tf.format(event.endDatetime)}',
              ),
            ],
          ),
          const SizedBox(height: 4),
          InfoRow(icon: Icons.location_on_outlined, text: event.venueName),
        ],
      ),
    );
  }
}
