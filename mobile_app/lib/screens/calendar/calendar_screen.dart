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

enum _CalendarSource { institution, personal, both }

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
  Map<DateTime, List<Event>> _eventsByDay = {};
  bool _isLoading = true;
  bool _isGoogleConnected = false;
  bool _isConnectingGoogle = false;
  bool _awaitingGoogleConsent = false;
  _CalendarSource _source = _CalendarSource.institution;
  CalendarFormat _calendarFormat = CalendarFormat.month;

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
    _log('App resumed after Google consent flow');
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
    _log('Bootstrap started');
    await _loadGoogleStatus();
    await _loadEvents();
    _log('Bootstrap finished');
  }

  Map<String, dynamic> _calendarRangeParams() {
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
    _log('GET /auth/google/status');
    try {
      final status = await _api.get<Map<String, dynamic>>(
        '/auth/google/status',
      );
      _log('Status response: $status');
      if (!mounted) return;
      setState(() {
        _isGoogleConnected = status['connected'] == true;
      });
      _log('Google connected=$_isGoogleConnected');
    } catch (_) {
      _log('GET /auth/google/status failed');
      if (!mounted) return;
      setState(() {
        _isGoogleConnected = false;
      });
    }
  }

  Event _calendarItemToEvent(
    Map<String, dynamic> item, {
    required String defaultStatus,
  }) {
    return Event.fromJson({
      'id': item['id'],
      'title': item['summary'] ?? item['title'] ?? 'Untitled event',
      'description': item['description'],
      'venue_name': item['location'] ?? '',
      'start_datetime': item['start'],
      'end_datetime': item['end'],
      'status': defaultStatus,
      'created_by': item['organizer'] ?? 'google',
      'notes': item['htmlLink'],
    });
  }

  Future<void> _connectGoogleCalendar() async {
    if (_isConnectingGoogle) return;
    _log('Connect Google tapped');
    setState(() => _isConnectingGoogle = true);
    try {
      _log('GET /calendar/connect-url');
      final response = await _api.get<Map<String, dynamic>>(
        '/calendar/connect-url',
      );
      _log('Connect-url response keys=${response.keys.toList()}');
      final rawUrl = response['url']?.toString() ?? '';
      if (rawUrl.isEmpty) {
        throw Exception('Server did not return a Google connect URL.');
      }
      _log('Connect-url length=${rawUrl.length}');

      final uri = Uri.tryParse(rawUrl);
      if (uri == null) {
        throw Exception('Received an invalid Google connect URL.');
      }
      _logOAuthUrl(uri);

      final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      _log('launchUrl result=$launched');
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
      _log('Connect Google failed: $e');
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
    setState(() => _isLoading = true);
    _log('Load events source=$_source connected=$_isGoogleConnected');
    try {
      final params = _calendarRangeParams();
      _log('Range params: $params');
      final List<Event> combined = [];

      if (_source == _CalendarSource.institution ||
          _source == _CalendarSource.both) {
        _log('GET /calendar/app-events');
        final appData = await _api.get<Map<String, dynamic>>(
          '/calendar/app-events',
          params: params,
        );
        final appItems =
            (appData['events'] as List? ?? appData['items'] as List? ?? []);
        _log('App events count=${appItems.length}');
        combined.addAll(
          appItems.whereType<Map<String, dynamic>>().map(
            (e) => _calendarItemToEvent(e, defaultStatus: 'approved'),
          ),
        );
      }

      if ((_source == _CalendarSource.personal ||
              _source == _CalendarSource.both) &&
          _isGoogleConnected) {
        try {
          _log('GET /calendar/events');
          final personalData = await _api.get<Map<String, dynamic>>(
            '/calendar/events',
            params: params,
          );
          final personalItems = (personalData['events'] as List? ?? []);
          _log('Personal events count=${personalItems.length}');
          combined.addAll(
            personalItems.whereType<Map<String, dynamic>>().map(
              (e) => _calendarItemToEvent(e, defaultStatus: 'upcoming'),
            ),
          );
        } catch (e) {
          _log('GET /calendar/events failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not load Google Calendar events. Reconnect Google if needed.',
                ),
              ),
            );
          }
        }
      }

      final Map<DateTime, List<Event>> byDay = {};
      for (final e in combined) {
        final day = DateTime(
          e.startTime.year,
          e.startTime.month,
          e.startTime.day,
        );
        byDay.putIfAbsent(day, () => []).add(e);
      }

      setState(() {
        _eventsByDay = {
          for (final day in byDay.keys)
            day: (byDay[day] ?? [])
              ..sort((a, b) => a.startTime.compareTo(b.startTime)),
        };
        _isLoading = false;
      });
      _log(
        'Combined events count=${combined.length} dayBuckets=${_eventsByDay.length}',
      );
    } catch (e) {
      _log('Load events failed: $e');
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
                          Row(
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
                              const Spacer(),
                              PopupMenuButton<_CalendarSource>(
                                initialValue: _source,
                                tooltip: 'Calendar source',
                                onSelected: (value) async {
                                  setState(() => _source = value);
                                  await _loadEvents();
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: _CalendarSource.institution,
                                    child: Text('Institution events'),
                                  ),
                                  PopupMenuItem(
                                    value: _CalendarSource.personal,
                                    child: Text('Personal Google events'),
                                  ),
                                  PopupMenuItem(
                                    value: _CalendarSource.both,
                                    child: Text('Both'),
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
                                        switch (_source) {
                                          _CalendarSource.institution =>
                                            'Institution',
                                          _CalendarSource.personal =>
                                            'Personal',
                                          _CalendarSource.both => 'Both',
                                        },
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: heading,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.arrow_drop_down, color: muted),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          _buildCalendar(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_selectedEvents.isNotEmpty) _buildEventList(),
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

    return TableCalendar<Event>(
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      calendarFormat: _calendarFormat,
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
      onFormatChanged: (format) {
        if (_calendarFormat != format) {
          setState(() {
            _calendarFormat = format;
          });
        }
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
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(color: muted),
        weekendStyle: TextStyle(color: weekend),
      ),
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
              child: _CalendarEventCard(event: e),
            );
          },
        ),
      ],
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
          InfoRow(
            icon: Icons.schedule,
            text: '${tf.format(event.startTime)} – ${tf.format(event.endTime)}',
          ),
          const SizedBox(height: 4),
          InfoRow(icon: Icons.location_on_outlined, text: event.venueName),
        ],
      ),
    );
  }
}
