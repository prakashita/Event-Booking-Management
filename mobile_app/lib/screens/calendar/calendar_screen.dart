import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

enum _CalendarFilter { all, events, holidays, academic }

enum _CalendarView { month, week, day }

class _CalendarItem {
  final String id;
  final String title;
  final String? description;
  final String location;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String? url;
  final String sourceType;
  final String entryType;
  final String category;
  final String academicYear;
  final String semesterType;
  final String semester;
  final String dayLabel;
  final String dateRangeLabel;
  final String? color;

  const _CalendarItem({
    required this.id,
    required this.title,
    this.description,
    required this.location,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.url,
    required this.sourceType,
    required this.entryType,
    required this.category,
    required this.academicYear,
    required this.semesterType,
    required this.semester,
    required this.dayLabel,
    required this.dateRangeLabel,
    this.color,
  });
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<_CalendarItem>> _eventsByDay = {};
  List<_CalendarItem> _allItems = [];

  bool _isLoading = true;
  bool _isGoogleConnected = false;
  bool _isConnectingGoogle = false;
  bool _awaitingGoogleConsent = false;

  _CalendarFilter _filter = _CalendarFilter.all;
  _CalendarView _view = _CalendarView.month;
  double? _pointerStartDy;

  _CalendarView _nextView(_CalendarView v) {
    switch (v) {
      case _CalendarView.month:
        return _CalendarView.week;
      case _CalendarView.week:
        return _CalendarView.day;
      case _CalendarView.day:
        return _CalendarView.month;
    }
  }

  _CalendarView _prevView(_CalendarView v) {
    switch (v) {
      case _CalendarView.month:
        return _CalendarView.day;
      case _CalendarView.week:
        return _CalendarView.month;
      case _CalendarView.day:
        return _CalendarView.week;
    }
  }

  Future<void> _setView(_CalendarView next) async {
    if (_view == next) return;
    setState(() => _view = next);
  }

  Future<void> _handlePointerSwipe(double endDy) async {
    final start = _pointerStartDy;
    _pointerStartDy = null;
    if (start == null) return;

    final delta = endDy - start;
    if (delta <= -45) {
      await _setView(_nextView(_view));
    } else if (delta >= 45) {
      await _setView(_prevView(_view));
    }
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[CalendarScreen] $message');
    }
  }

  void _logOAuthUrl(Uri uri) {
    final qp = uri.queryParameters;
    _log('OAuth URL host=${uri.host} path=${uri.path}');
    _log('OAuth redirect_uri=${qp['redirect_uri'] ?? ''}');
    _log('OAuth client_id=${qp['client_id'] ?? ''}');
    _log(
      'OAuth has_device_id=${qp.containsKey('device_id')} has_device_name=${qp.containsKey('device_name')}',
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedDay = _focusedDay;
    _bootstrapCalendar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onReturnedFromBrowser();
    }
  }

  Future<void> _onReturnedFromBrowser() async {
    if (!_awaitingGoogleConsent) return;
    _awaitingGoogleConsent = false;
    await _loadGoogleStatus();
    await _loadEvents();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isGoogleConnected
              ? 'Google Calendar connected successfully.'
              : 'Google Calendar not connected yet. Please complete consent and retry.',
        ),
      ),
    );
  }

  Future<void> _bootstrapCalendar() async {
    await _loadGoogleStatus();
    await _loadEvents();
  }

  Map<String, dynamic> _calendarRangeParams() {
    // Fetch month range once, then render month/week/day locally.
    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final end = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      0,
      23,
      59,
      59,
    );
    return {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
    };
  }

  Future<void> _loadGoogleStatus() async {
    try {
      final status = await _api.get<Map<String, dynamic>>(
        '/auth/google/status',
      );
      if (!mounted) return;
      setState(() {
        _isGoogleConnected = status['connected'] == true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isGoogleConnected = false;
      });
    }
  }

  _CalendarItem _calendarItemToEvent(
    Map<String, dynamic> item, {
    required String defaultStatus,
    required String defaultSourceType,
    required String defaultEntryType,
  }) {
    final fallback = Event.fromJson({
      'id': item['id'] ?? '',
      'title': item['summary'] ?? item['title'] ?? 'Untitled event',
      'description': item['description'],
      'venue_name': item['location'] ?? '',
      'start_datetime': item['start'],
      'end_datetime': item['end'],
      'status': defaultStatus,
      'created_by': item['organizer'] ?? 'google',
      'notes': item['htmlLink'],
    });

    final start =
        DateTime.tryParse((item['start'] ?? '').toString()) ??
        fallback.startTime;
    final rawEnd = (item['end'] ?? '').toString();
    var end = DateTime.tryParse(rawEnd) ?? fallback.endTime;

    final isAllDay = item['allDay'] == true;
    if (isAllDay && rawEnd.length <= 10 && end.isAfter(start)) {
      end = end.subtract(const Duration(seconds: 1));
    }

    return _CalendarItem(
      id: (item['id'] ?? fallback.id).toString(),
      title: (item['summary'] ?? item['title'] ?? fallback.title).toString(),
      description: item['description']?.toString(),
      location: (item['location'] ?? fallback.venueName).toString(),
      startTime: start,
      endTime: end,
      status: defaultStatus,
      url: item['htmlLink']?.toString(),
      sourceType: (item['sourceType'] ?? defaultSourceType).toString(),
      entryType: (item['entryType'] ?? defaultEntryType).toString(),
      category: (item['category'] ?? '').toString(),
      academicYear: (item['academicYear'] ?? '').toString(),
      semesterType: (item['semesterType'] ?? '').toString(),
      semester: (item['semester'] ?? '').toString(),
      dayLabel: (item['dayLabel'] ?? '').toString(),
      dateRangeLabel: (item['dateRangeLabel'] ?? '').toString(),
      color: item['color']?.toString(),
    );
  }

  bool _matchesFilter(_CalendarItem item) {
    if (_filter == _CalendarFilter.all) return true;
    final source = item.sourceType;
    final entryType = item.entryType;
    if (_filter == _CalendarFilter.events) {
      return source != 'institution_calendar';
    }
    if (_filter == _CalendarFilter.holidays) {
      return source == 'institution_calendar' && entryType == 'holiday';
    }
    if (_filter == _CalendarFilter.academic) {
      return source == 'institution_calendar' && entryType == 'academic';
    }
    return true;
  }

  void _rebuildDayBuckets() {
    final Map<DateTime, List<_CalendarItem>> byDay = {};
    for (final e in _allItems) {
      if (!_matchesFilter(e)) continue;
      final day = DateTime(
        e.startTime.year,
        e.startTime.month,
        e.startTime.day,
      );
      byDay.putIfAbsent(day, () => []).add(e);
    }

    _eventsByDay = {
      for (final day in byDay.keys)
        day: ([...byDay[day] ?? []]
          ..sort((a, b) => a.startTime.compareTo(b.startTime))),
    };
  }

  Future<void> _connectGoogleCalendar() async {
    if (_isConnectingGoogle) return;
    setState(() => _isConnectingGoogle = true);

    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/calendar/connect-url',
      );
      final rawUrl = response['url']?.toString() ?? '';
      if (rawUrl.isEmpty) {
        throw Exception('Server did not return a Google connect URL.');
      }

      final uri = Uri.tryParse(rawUrl);
      if (uri == null) {
        throw Exception('Received an invalid Google connect URL.');
      }
      _logOAuthUrl(uri);

      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!launched) {
        throw Exception('Could not open the Google consent page.');
      }

      if (!mounted) return;
      _awaitingGoogleConsent = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete Google consent and return to the app. Status will auto-verify.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Google connect failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _isConnectingGoogle = false);
      }
    }
  }

  Future<void> _loadEvents() async {
    final showBlockingLoader = _allItems.isEmpty;
    if (showBlockingLoader) {
      setState(() => _isLoading = true);
    }

    try {
      final params = _calendarRangeParams();
      final List<_CalendarItem> combined = [];

      _log('GET /calendar/app-events');
      Map<String, dynamic> appData;
      try {
        appData = await _api.get<Map<String, dynamic>>(
          '/calendar/app-events',
          params: params,
        );
      } catch (firstError) {
        // Server-side range filtering can fail on timezone-mixed comparisons.
        // Retry without range params so calendar remains functional.
        _log(
          'Retry GET /calendar/app-events without start/end due to: $firstError',
        );
        appData = await _api.get<Map<String, dynamic>>('/calendar/app-events');
      }
      final appItems =
          (appData['events'] as List? ?? appData['items'] as List? ?? []);

      combined.addAll(
        appItems.whereType<Map<String, dynamic>>().map(
          (e) => _calendarItemToEvent(
            e,
            defaultStatus: 'approved',
            defaultSourceType: 'event_booking',
            defaultEntryType: 'event',
          ),
        ),
      );

      setState(() {
        _allItems = combined;
        _rebuildDayBuckets();
        _isLoading = false;
      });
    } catch (e) {
      if (showBlockingLoader) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<_CalendarItem> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _eventsByDay[key] ?? [];
  }

  List<_CalendarItem> get _selectedEvents {
    return _selectedDay != null ? _getEventsForDay(_selectedDay!) : [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = theme.scaffoldBackgroundColor;
    final cardBg = theme.colorScheme.surface;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF718096);
    final heading = theme.colorScheme.onSurface;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final primaryButton = isDark
        ? const Color(0xFF2563EB)
        : const Color(0xFF4299E1);
    final inputBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.white;

    return Scaffold(
      backgroundColor: pageBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCHEDULING',
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Calendar View',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: heading,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: border),
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _focusedDay = DateTime.now();
                            _selectedDay = _focusedDay;
                          });
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today, size: 16, color: muted),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat.yMMMMd().format(DateTime.now()),
                              style: TextStyle(
                                color: heading,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Calendar',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: heading,
                                    ),
                                  ),
                                  Text(
                                    'All approved events',
                                    style: TextStyle(color: muted),
                                  ),
                                ],
                              ),
                              FilledButton.icon(
                                icon: const FaIcon(
                                  FontAwesomeIcons.google,
                                  size: 18,
                                ),
                                label: const Text('Connect'),
                                onPressed: _connectGoogleCalendar,
                                style: FilledButton.styleFrom(
                                  backgroundColor: primaryButton,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                OutlinedButton.icon(
                                  icon: Icon(Icons.refresh, color: heading),
                                  label: Text(
                                    'Refresh',
                                    style: TextStyle(color: heading),
                                  ),
                                  onPressed: _loadEvents,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: border),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<_CalendarView>(
                                  initialValue: _view,
                                  tooltip: 'Calendar view',
                                  onSelected: (value) async {
                                    await _setView(value);
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: _CalendarView.month,
                                      child: Text('Month'),
                                    ),
                                    PopupMenuItem(
                                      value: _CalendarView.week,
                                      child: Text('Week'),
                                    ),
                                    PopupMenuItem(
                                      value: _CalendarView.day,
                                      child: Text('Day'),
                                    ),
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: inputBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          switch (_view) {
                                            _CalendarView.month => 'Month',
                                            _CalendarView.week => 'Week',
                                            _CalendarView.day => 'Day',
                                          },
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: heading,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_drop_down,
                                          color: muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<_CalendarFilter>(
                                  initialValue: _filter,
                                  tooltip: 'Event type filter',
                                  onSelected: (value) {
                                    setState(() {
                                      _filter = value;
                                      _rebuildDayBuckets();
                                    });
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: _CalendarFilter.all,
                                      child: Text('All'),
                                    ),
                                    PopupMenuItem(
                                      value: _CalendarFilter.events,
                                      child: Text('Events'),
                                    ),
                                    PopupMenuItem(
                                      value: _CalendarFilter.holidays,
                                      child: Text('Holidays'),
                                    ),
                                    PopupMenuItem(
                                      value: _CalendarFilter.academic,
                                      child: Text('Academic'),
                                    ),
                                  ],
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: inputBg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: border),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          switch (_filter) {
                                            _CalendarFilter.all => 'All',
                                            _CalendarFilter.events => 'Events',
                                            _CalendarFilter.holidays =>
                                              'Holidays',
                                            _CalendarFilter.academic =>
                                              'Academic',
                                          },
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: heading,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.arrow_drop_down,
                                          color: muted,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Listener(
                            onPointerDown: (event) {
                              _pointerStartDy = event.position.dy;
                            },
                            onPointerUp: (event) {
                              _handlePointerSwipe(event.position.dy);
                            },
                            child: _view == _CalendarView.day
                                ? _buildDayAgenda(context)
                                : _buildCalendar(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_view != _CalendarView.day &&
                        _selectedEvents.isNotEmpty)
                      _buildEventList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCalendar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final heading = theme.colorScheme.onSurface;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF4A5568);
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E0);
    final weekend = isDark ? const Color(0xFFFCA5A5) : const Color(0xFFC53030);

    return TableCalendar<_CalendarItem>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: _view == _CalendarView.week
          ? CalendarFormat.week
          : CalendarFormat.month,
      eventLoader: _getEventsForDay,
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
        _loadEvents();
      },
      calendarStyle: CalendarStyle(
        selectedDecoration: const BoxDecoration(
          color: Color(0xFF4299E1),
          shape: BoxShape.circle,
        ),
        todayDecoration: BoxDecoration(
          color: const Color(0xFF4299E1).withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        markersMaxCount: 0,
        outsideDaysVisible: false,
        weekendTextStyle: const TextStyle(color: Color(0xFFE53E3E)),
      ),
      calendarBuilders: CalendarBuilders<_CalendarItem>(
        markerBuilder: (context, day, events) {
          return _buildCalendarMarkers(context, events);
        },
      ),
      headerStyle: HeaderStyle(
        titleCentered: true,
        titleTextStyle: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
          color: heading,
        ),
        formatButtonDecoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(12.0),
        ),
        formatButtonTextStyle: TextStyle(color: heading),
        formatButtonShowsNext: false,
        formatButtonVisible: false,
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(color: muted),
        weekendStyle: TextStyle(color: weekend),
      ),
    );
  }

  Widget _buildCalendarMarkers(
    BuildContext context,
    List<_CalendarItem> events,
  ) {
    if (events.isEmpty) return const SizedBox.shrink();

    final visibleEvents = events.take(3).toList();
    final extraCount = events.length - visibleEvents.length;

    return Positioned(
      bottom: 5,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final event in visibleEvents)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: _calendarAccentColor(event),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _calendarAccentColor(event).withValues(alpha: 0.3),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          if (extraCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 2),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '+$extraCount',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayAgenda(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final heading = theme.colorScheme.onSurface;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final day = _selectedDay ?? _focusedDay;
    final events = _getEventsForDay(day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () async {
                final d = day.subtract(const Duration(days: 1));
                setState(() {
                  _selectedDay = d;
                  _focusedDay = d;
                });
                if (d.month != day.month || d.year != day.year) {
                  await _loadEvents();
                }
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                DateFormat('EEEE, MMM d').format(day),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: heading,
                ),
              ),
            ),
            IconButton(
              onPressed: () async {
                final d = day.add(const Duration(days: 1));
                setState(() {
                  _selectedDay = d;
                  _focusedDay = d;
                });
                if (d.month != day.month || d.year != day.year) {
                  await _loadEvents();
                }
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'No events scheduled for this day.',
                style: TextStyle(color: muted, fontWeight: FontWeight.w500),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final e = events[index];
              return _CalendarEventCard(
                event: e,
                onTap: () => _openEventDetails(context, e),
              );
            },
          ),
      ],
    );
  }

  Widget _buildEventList() {
    final heading = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Events on ${DateFormat.yMMMMd().format(_selectedDay!)}',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: heading,
          ),
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _selectedEvents.length,
          itemBuilder: (ctx, i) {
            final e = _selectedEvents[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CalendarEventCard(
                event: e,
                onTap: () => _openEventDetails(context, e),
              ),
            );
          },
        ),
      ],
    );
  }

  void _openEventDetails(BuildContext context, _CalendarItem event) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final handleColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFCBD5E1);
    final cardBgColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFFAFBFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final labelColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final valueColor = isDark
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF1E293B);
    final accentColor = _calendarAccentColor(event);
    final schedule = _calendarDetailSchedule(event);
    final typeLabel = _calendarTypeLabel(event);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: handleColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(
                              alpha: isDark ? 0.2 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _calendarIcon(event),
                            color: accentColor,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Event Details',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                              height: 1.2,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF1E293B)
                                : const Color(0xFFF1F5F9),
                            foregroundColor: labelColor,
                            fixedSize: const Size(36, 36),
                          ),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? borderColor : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.16 : 0.035,
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _buildSheetTypePill(
                                _calendarChipLabel(event),
                                accentColor,
                                isDark,
                              ),
                              const Spacer(),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          _buildDivider(borderColor),
                          _buildPremiumDetailRow(
                            'Title',
                            event.title,
                            labelColor,
                            valueColor,
                          ),
                          _buildDivider(borderColor),
                          _buildPremiumDetailRow(
                            'Type',
                            typeLabel,
                            labelColor,
                            valueColor,
                          ),
                          if (event.category.trim().isNotEmpty) ...[
                            _buildDivider(borderColor),
                            _buildPremiumDetailRow(
                              'Category',
                              event.category,
                              labelColor,
                              valueColor,
                            ),
                          ],
                          if (event.academicYear.trim().isNotEmpty) ...[
                            _buildDivider(borderColor),
                            _buildPremiumDetailRow(
                              'Academic Year',
                              event.academicYear,
                              labelColor,
                              valueColor,
                            ),
                          ],
                          if (event.semesterType.trim().isNotEmpty ||
                              event.semester.trim().isNotEmpty) ...[
                            _buildDivider(borderColor),
                            _buildPremiumDetailRow(
                              'Semester',
                              [
                                event.semesterType,
                                event.semester,
                              ].where((v) => v.trim().isNotEmpty).join(' | '),
                              labelColor,
                              valueColor,
                            ),
                          ],
                          _buildDivider(borderColor),
                          _buildPremiumDetailRow(
                            'Schedule',
                            schedule,
                            labelColor,
                            valueColor,
                          ),
                          if (event.dayLabel.trim().isNotEmpty) ...[
                            _buildDivider(borderColor),
                            _buildPremiumDetailRow(
                              'Day',
                              event.dayLabel,
                              labelColor,
                              valueColor,
                            ),
                          ],
                          if (event.location.trim().isNotEmpty) ...[
                            _buildDivider(borderColor),
                            _buildPremiumDetailRow(
                              'Venue',
                              event.location,
                              labelColor,
                              valueColor,
                            ),
                          ],
                          if ((event.description ?? '').trim().isNotEmpty) ...[
                            _buildDivider(borderColor),
                            _buildPremiumDetailRow(
                              'Notes',
                              event.description!.trim(),
                              labelColor,
                              valueColor,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if ((event.url ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          icon: const FaIcon(FontAwesomeIcons.google, size: 15),
                          label: const Text(
                            'Open in Google Calendar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shadowColor: accentColor.withValues(alpha: 0.28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final uri = Uri.tryParse(event.url!);
                            if (uri == null) return;
                            final launched = await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!launched && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not open Google Calendar link.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 64,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _calendarDetailSchedule(_CalendarItem event) {
    final rawLabel = event.dateRangeLabel.trim();
    if (rawLabel.isNotEmpty) {
      final formatted = _formatRawDateRangeLabel(rawLabel);
      if (formatted != null) return formatted;
    }
    return _formatCalendarDateRange(event.startTime, event.endTime);
  }

  String _formatCalendarDateRange(DateTime start, DateTime end) {
    final dateFormatter = DateFormat('EEEE, d MMMM y');
    final timeFormatter = DateFormat('h:mm a');
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) {
      return '${dateFormatter.format(start)}, ${timeFormatter.format(start)} - ${timeFormatter.format(end)}';
    }
    return '${dateFormatter.format(start)} - ${dateFormatter.format(end)}';
  }

  String? _formatRawDateRangeLabel(String label) {
    final match = RegExp(
      r'^(\d{4}-\d{2}-\d{2})(?:\s+\d{2}:\d{2})?(?:\s+to\s+(\d{4}-\d{2}-\d{2})(?:\s+\d{2}:\d{2})?)?$',
    ).firstMatch(label);
    if (match == null) return null;

    final formatter = DateFormat('EEEE, d MMMM y');
    final start = DateTime.tryParse(match.group(1)!);
    final endRaw = match.group(2);
    final end = endRaw == null ? null : DateTime.tryParse(endRaw);
    if (start == null) return null;
    if (end == null || _isSameDate(start, end)) return formatter.format(start);
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildPremiumDetailRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: labelColor,
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.7,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, thickness: 1, color: color),
    );
  }

  Widget _buildSheetTypePill(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

Color _calendarAccentColor(_CalendarItem event) {
  final raw = event.color;
  if (raw != null && raw.isNotEmpty) {
    try {
      return Color(int.parse(raw.replaceFirst('#', '0xFF')));
    } catch (_) {
      // Fall back to status color if the backend sends an unexpected color.
    }
  }
  return AppColors.statusColor(event.status);
}

String _calendarTypeLabel(_CalendarItem event) {
  if (event.sourceType != 'institution_calendar') return 'Event Booking';
  return event.entryType == 'holiday'
      ? 'Institution Holiday'
      : 'Institution Academic';
}

String _calendarChipLabel(_CalendarItem event) {
  if (event.sourceType != 'institution_calendar') return 'Event Booking';
  return event.entryType == 'holiday' ? 'Holiday' : 'Academic';
}

IconData _calendarIcon(_CalendarItem event) {
  if (event.entryType == 'holiday') return Icons.celebration_rounded;
  if (event.sourceType == 'institution_calendar') return Icons.school_rounded;
  return Icons.event_note_rounded;
}

class _CalendarEventCard extends StatelessWidget {
  final _CalendarItem event;
  final VoidCallback onTap;

  const _CalendarEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tf = DateFormat('h:mm a');
    final accentColor = _calendarAccentColor(event);
    final cardColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFFAFBFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : accentColor.withValues(alpha: 0.16);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final iconColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final textColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : const Color(0xFFE2E8F0).withValues(alpha: 0.6);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: accentColor.withValues(alpha: 0.1),
            highlightColor: accentColor.withValues(alpha: 0.05),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 5, color: accentColor),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(19, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  margin: const EdgeInsets.only(right: 10),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(
                                      alpha: isDark ? 0.2 : 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                    _calendarIcon(event),
                                    color: accentColor,
                                    size: 16,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    event.title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: titleColor,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildPremiumBadge(event.status, isDark),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildPremiumInfoRow(
                        Icons.access_time_filled_rounded,
                        '${tf.format(event.startTime)} - ${tf.format(event.endTime)}',
                        iconColor,
                        textColor,
                      ),
                      if (event.location.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _buildPremiumInfoRow(
                          Icons.location_on_rounded,
                          event.location,
                          iconColor,
                          textColor,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildChip(_calendarChipLabel(event), accentColor),
                          if (event.category.trim().isNotEmpty)
                            _buildChip(event.category, iconColor),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumBadge(String status, bool isDark) {
    final isApproved = status.toLowerCase() == 'approved';
    final Color bgColor;
    final Color textColor;

    if (isApproved) {
      bgColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7);
      textColor = isDark ? const Color(0xFF34D399) : const Color(0xFF166534);
    } else {
      bgColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
      textColor = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPremiumInfoRow(
    IconData icon,
    String text,
    Color iconColor,
    Color textColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
