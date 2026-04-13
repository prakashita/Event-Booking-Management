import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadGoogleStatus();
              await _loadEvents();
            },
            tooltip: 'Refresh',
          ),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isConnectingGoogle
                              ? null
                              : _connectGoogleCalendar,
                          icon: _isConnectingGoogle
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.link),
                          label: Text(
                            _isGoogleConnected
                                ? 'Google Connected'
                                : 'Connect Google Calendar',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                switch (_source) {
                                  _CalendarSource.institution => 'Institution',
                                  _CalendarSource.personal => 'Personal',
                                  _CalendarSource.both => 'Both',
                                },
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
                      todayTextStyle: const TextStyle(color: AppColors.primary),
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
                        Icons.chevron_left,
                        color: AppColors.textSecondary,
                      ),
                      rightChevronIcon: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
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
                      _loadEvents();
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
                              const Icon(
                                Icons.event_available,
                                size: 48,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _selectedDay != null
                                    ? 'No events on ${DateFormat('MMM d').format(_selectedDay!)}'
                                    : 'Select a day to view events',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                ),
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
          InfoRow(
            icon: Icons.schedule,
            text:
                '${tf.format(event.startTime)} – ${tf.format(event.endTime)}',
          ),
          const SizedBox(height: 4),
          InfoRow(icon: Icons.location_on_outlined, text: event.venueName),
        ],
      ),
    );
  }
}
