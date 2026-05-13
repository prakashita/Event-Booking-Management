import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

class EventReportsScreen extends StatefulWidget {
  const EventReportsScreen({super.key});

  @override
  State<EventReportsScreen> createState() => _EventReportsScreenState();
}

class _EventReportsScreenState extends State<EventReportsScreen> {
  final _api = ApiService();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _searchQuery = '';

  List<Map<String, dynamic>> _reports = [];

  bool get _canAccess {
    final role = (context.read<AuthProvider>().user?.roleKey ?? '')
        .toLowerCase()
        .trim();
    return role == 'admin' ||
        role == 'registrar' ||
        role == 'vice_chancellor' ||
        role == 'deputy_registrar' ||
        role == 'finance_team';
  }

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports({bool forceRefresh = false}) async {
    if (!mounted || !_canAccess) return;

    setState(() {
      if (forceRefresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final data = await _api.get<Map<String, dynamic>>('/admin/event-reports');
      final raw = data['items'];
      final items = raw is List
          ? raw.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _reports = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _extractError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  String _extractError(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) return 'Unable to load event reports.';
    return text;
  }

  String _statusLabel(Map<String, dynamic> item) {
    final raw = (item['status'] ?? 'closed').toString().trim().toLowerCase();
    if (raw.isEmpty) return 'Closed';
    return raw
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String _dateLabel(Map<String, dynamic> item) {
    final startDate = (item['start_date'] ?? '').toString().trim();
    if (startDate.isNotEmpty) {
      final parsed = DateTime.tryParse(startDate);
      if (parsed != null) {
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final mon = months[parsed.month - 1];
        return '$mon ${parsed.day}, ${parsed.year}';
      }
      return startDate;
    }

    final createdAt = (item['created_at'] ?? '').toString().trim();
    final parsedCreated = DateTime.tryParse(createdAt);
    if (parsedCreated != null) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final mon = months[parsedCreated.month - 1];
      return '$mon ${parsedCreated.day}, ${parsedCreated.year}';
    }

    return '-';
  }

  String _attendeeLabel(Map<String, dynamic> item) {
    final raw = item['audience_count'];
    if (raw is int) return '$raw';
    if (raw is double) return raw.toInt().toString();
    final parsed = int.tryParse((raw ?? '').toString());
    if (parsed != null) return '$parsed';
    return '-';
  }

  List<Map<String, dynamic>> get _filteredReports {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _reports;
    return _reports.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList();
  }

  bool _hasAttendance(Map<String, dynamic> item) {
    final link = (item['attendance_web_view_link'] ?? '').toString().trim();
    final fileId = (item['attendance_file_id'] ?? '').toString().trim();
    return link.isNotEmpty || fileId.isNotEmpty;
  }

  Future<void> _openReport(Map<String, dynamic> item) async {
    final link = (item['report_web_view_link'] ?? '').toString().trim();
    if (link.isEmpty) {
      _showMessage('Report link unavailable.');
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null) {
      _showMessage('Report link unavailable.');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showMessage('Could not open report link.');
    }
  }

  Future<void> _openAttendance(Map<String, dynamic> item) async {
    final link = (item['attendance_web_view_link'] ?? '').toString().trim();
    final fileId = (item['attendance_file_id'] ?? '').toString().trim();

    String? target;
    if (link.isNotEmpty) {
      target = link;
    } else if (fileId.isNotEmpty) {
      target =
          'https://drive.google.com/file/d/${Uri.encodeComponent(fileId)}/view';
    }

    if (target == null) {
      _showMessage('Attendance file link unavailable.');
      return;
    }

    final uri = Uri.tryParse(target);
    if (uri == null) {
      _showMessage('Attendance file link unavailable.');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showMessage('Could not open attendance file.');
    }
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final panel = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);

    if (!_canAccess) {
      return const Scaffold(body: Center(child: Text('Access denied.')));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadReports(forceRefresh: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Event Reports',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4F46E5),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${_reports.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Access detailed analytics, post-event reports, and attendance records for your past events.',
                  style: TextStyle(fontSize: 15, color: muted),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.transparent
                                  : const Color(
                                      0xFF4F46E5,
                                    ).withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search reports by name or date...',
                            hintStyle: TextStyle(
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 20,
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF4F46E5),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.transparent
                                  : Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: OutlinedButton(
                          onPressed: _refreshing
                              ? null
                              : () => _loadReports(forceRefresh: true),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF1E293B)
                                : Colors.white,
                            padding: EdgeInsets.zero,
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _refreshing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Color(0xFF4F46E5),
                                  ),
                                )
                              : Icon(
                                  Icons.refresh,
                                  size: 20,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: _loadReports,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_reports.isEmpty)
                  _EmptyState(panel: panel, muted: muted)
                else if (_filteredReports.isEmpty)
                  _NoSearchResults(panel: panel, muted: muted)
                else
                  _ReportsGrid(
                    items: _filteredReports,
                    isDark: isDark,
                    onOpenReport: _openReport,
                    onOpenAttendance: _openAttendance,
                    hasAttendance: _hasAttendance,
                    statusLabel: _statusLabel,
                    dateLabel: _dateLabel,
                    attendeeLabel: _attendeeLabel,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Color panel;
  final Color muted;

  const _EmptyState({required this.panel, required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.bar_chart_outlined, color: muted),
            ),
            const SizedBox(height: 12),
            Text(
              'No event reports found.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool isDark;
  final Future<void> Function(Map<String, dynamic>) onOpenReport;
  final Future<void> Function(Map<String, dynamic>) onOpenAttendance;
  final bool Function(Map<String, dynamic>) hasAttendance;
  final String Function(Map<String, dynamic>) statusLabel;
  final String Function(Map<String, dynamic>) dateLabel;
  final String Function(Map<String, dynamic>) attendeeLabel;

  const _ReportsGrid({
    required this.items,
    required this.isDark,
    required this.onOpenReport,
    required this.onOpenAttendance,
    required this.hasAttendance,
    required this.statusLabel,
    required this.dateLabel,
    required this.attendeeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var crossAxisCount = 1;
        if (constraints.maxWidth >= 1120) {
          crossAxisCount = 3;
        } else if (constraints.maxWidth >= 700) {
          crossAxisCount = 2;
        }

        Widget buildCard(int index) {
          final item = items[index];
          final name = (item['name'] ?? 'Untitled event').toString();
          final status = statusLabel(item);
          final attendance = hasAttendance(item);
          final date = dateLabel(item);
          final attendees = attendeeLabel(item);

          return _ReportCard(
            isDark: isDark,
            name: name,
            status: status,
            date: date,
            attendees: attendees,
            hasAttendance: attendance,
            onViewReport: () => onOpenReport(item),
            onViewAttendance: () => onOpenAttendance(item),
          );
        }

        if (crossAxisCount == 1) {
          return ListView.separated(
            itemCount: items.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) => buildCard(index),
          );
        }

        return GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.5,
          ),
          itemBuilder: (context, index) => buildCard(index),
        );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  final bool isDark;
  final String name;
  final String status;
  final String date;
  final String attendees;
  final bool hasAttendance;
  final VoidCallback onViewReport;
  final VoidCallback onViewAttendance;

  const _ReportCard({
    required this.isDark,
    required this.name,
    required this.status,
    required this.date,
    required this.attendees,
    required this.hasAttendance,
    required this.onViewReport,
    required this.onViewAttendance,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF0651ED,
            ).withValues(alpha: isDark ? 0.0 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
            spreadRadius: -3,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 450;

          final content = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Container
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF312E81).withValues(alpha: 0.5)
                      : const Color(0xFFEEF2FF).withValues(alpha: 0.5),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF3730A3)
                        : const Color(0xFFE0E7FF),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.bar_chart,
                  color: isDark
                      ? const Color(0xFF818CF8)
                      : const Color(0xFF4F46E5),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Badge
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    // Title
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Subtitle
                    Text(
                      'Event Report & Analytics',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Meta Info (Date & Attendees)
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _MetaBadge(
                          icon: Icons.calendar_today_outlined,
                          text: date,
                          isDark: isDark,
                        ),
                        _MetaBadge(
                          icon: Icons.people_outline,
                          text: attendees,
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );

          Widget buildReportBtn() {
            return ElevatedButton.icon(
              onPressed: onViewReport,
              icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
              label: const Text('View Report'),
              style: ElevatedButton.styleFrom(
                foregroundColor: isDark
                    ? const Color(0xFF818CF8)
                    : const Color(0xFF4338CA),
                backgroundColor: isDark
                    ? const Color(0xFF312E81).withValues(alpha: 0.5)
                    : const Color(0xFFEEF2FF),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            );
          }

          Widget buildAttendanceBtn() {
            return OutlinedButton.icon(
              onPressed: onViewAttendance,
              icon: const Icon(Icons.description_outlined, size: 16),
              label: const Text('Attendance'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark
                    ? const Color(0xFFC084FC)
                    : const Color(0xFF7E22CE),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF6B21A8)
                      : const Color(0xFFE9D5FF),
                ),
                backgroundColor: isDark ? Colors.transparent : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            );
          }

          Widget buildActions() {
            if (isSmall) {
              return Row(
                children: [
                  Expanded(child: buildReportBtn()),
                  if (hasAttendance) ...[
                    const SizedBox(width: 10),
                    Expanded(child: buildAttendanceBtn()),
                  ],
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  buildReportBtn(),
                  if (hasAttendance) ...[
                    const SizedBox(height: 10),
                    buildAttendanceBtn(),
                  ],
                ],
              );
            }
          }

          if (isSmall) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                ),
                const SizedBox(height: 16),
                buildActions(),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: 16),
              SizedBox(width: 140, child: buildActions()),
            ],
          );
        },
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isDark;

  const _MetaBadge({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  final Color panel;
  final Color muted;

  const _NoSearchResults({required this.panel, required this.muted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.search, color: muted, size: 30),
            ),
            const SizedBox(height: 12),
            Text(
              'No reports found',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try adjusting your search query.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
