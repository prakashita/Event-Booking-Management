import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

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
          color: const Color(0xFF4299E1).withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        markerDecoration: const BoxDecoration(
          color: Color(0xFF4299E1),
          shape: BoxShape.circle,
        ),
        outsideDaysVisible: false,
        weekendTextStyle: const TextStyle(color: Color(0xFFE53E3E)),
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
    final tf = DateFormat('h:mm a');
    final df = DateFormat('MMM d, yyyy');
    final schedule =
        '${df.format(event.startTime)} ${tf.format(event.startTime)} - ${df.format(event.endTime)} ${tf.format(event.endTime)}';
    final typeLabel = event.sourceType == 'institution_calendar'
        ? (event.entryType == 'holiday'
              ? 'Institution Holiday'
              : 'Institution Academic')
        : 'Event Booking';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _detailRow('Type', typeLabel),
                  _detailRow('Schedule', schedule),
                  if (event.dayLabel.trim().isNotEmpty)
                    _detailRow('Day', event.dayLabel),
                  if (event.category.trim().isNotEmpty)
                    _detailRow('Category', event.category),
                  if (event.academicYear.trim().isNotEmpty)
                    _detailRow('Academic Year', event.academicYear),
                  if (event.semesterType.trim().isNotEmpty ||
                      event.semester.trim().isNotEmpty)
                    _detailRow(
                      'Semester',
                      [
                        event.semesterType,
                        event.semester,
                      ].where((v) => v.trim().isNotEmpty).join(' | '),
                    ),
                  if (event.location.trim().isNotEmpty)
                    _detailRow('Venue', event.location),
                  if ((event.description ?? '').trim().isNotEmpty)
                    _detailRow('Notes', event.description!.trim()),
                  const SizedBox(height: 16),
                  if ((event.url ?? '').trim().isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
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
                                content: Text('Could not open calendar link.'),
                              ),
                            );
                          }
                        },
                        child: const Text('Open in Google Calendar'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarEventCard extends StatelessWidget {
  final _CalendarItem event;
  final VoidCallback onTap;

  const _CalendarEventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tf = DateFormat('h:mm a');

    Color stripeColor() {
      final raw = event.color;
      if (raw != null && raw.isNotEmpty) {
        try {
          return Color(int.parse(raw.replaceFirst('#', '0xFF')));
        } catch (_) {
          // Fallback for unexpected color format.
        }
      }
      return AppColors.statusColor(event.status);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: stripeColor(), width: 4)),
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
            InfoRow(
              icon: Icons.schedule,
              text:
                  '${tf.format(event.startTime)} - ${tf.format(event.endTime)}',
            ),
            const SizedBox(height: 4),
            InfoRow(icon: Icons.location_on_outlined, text: event.location),
          ],
        ),
      ),
    );
  }
}
