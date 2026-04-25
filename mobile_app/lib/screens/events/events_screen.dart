import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';
import 'package:intl/intl.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();

  static const _tabs = [
    'All',
    'Approvals',
    'Upcoming',
    'Ongoing',
    'Completed',
    'Closed',
  ];

  final Map<String, List<Event>> _eventsByTab = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};
  final Set<String> _inviteSentEventIds = <String>{};
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadEventsForTab(0);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
    if (!_tabController.indexIsChanging) {
      _loadEventsForTab(_tabController.index);
    }
  }

  String _statusForTab(int idx) {
    switch (idx) {
      case 1:
        return 'pending';
      case 2:
        return 'upcoming';
      case 3:
        return 'ongoing';
      case 4:
        return 'completed';
      case 5:
        return 'closed';
      default:
        return '';
    }
  }

  List<Event> _filterEventsForTab(List<Event> all, int idx) {
    final status = _statusForTab(idx);
    if (status.isEmpty) return all;
    if (status == 'pending') {
      return all.where((e) {
        final s = e.status.toLowerCase();
        return s == 'pending' ||
            s == 'clarification' ||
            s == 'clarification_requested';
      }).toList();
    }
    return all.where((e) => (e.status).toLowerCase() == status).toList();
  }

  bool _isApprovalItem(Event event) => event.id.startsWith('approval-');

  bool _hasStarted(Event event) => !event.startTime.isAfter(DateTime.now());

  bool _canInvite(Event event) {
    if (_isApprovalItem(event)) return false;
    final status = event.status.trim().toLowerCase();
    if (status != 'upcoming') return false;
    if (_hasStarted(event)) return false;
    if (_inviteSentEventIds.contains(event.id)) return false;
    return true;
  }

  bool _canUploadReport(Event event) {
    if (_isApprovalItem(event)) return false;
    return event.status.trim().toLowerCase() == 'completed';
  }

  bool _canCloseEvent(Event event) {
    if (_isApprovalItem(event)) return false;
    final status = event.status.trim().toLowerCase();
    return status == 'completed' &&
        (event.reportFileId?.trim().isNotEmpty ?? false);
  }

  bool _canViewReport(Event event) {
    return (event.reportWebViewLink?.trim().isNotEmpty ?? false) ||
        (event.reportFileId?.trim().isNotEmpty ?? false);
  }

  bool _canViewAttendance(Event event) {
    return (event.attendanceWebViewLink?.trim().isNotEmpty ?? false) ||
        (event.attendanceFileId?.trim().isNotEmpty ?? false);
  }

  String _expectedReportFilename(Event event) {
    final sanitized = event.title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    final eventName = sanitized.isEmpty ? 'Event' : sanitized;
    final datePart = DateFormat('yyyy-MM-dd').format(event.startTime);
    return '${eventName}_${datePart}_Report.pdf';
  }

  String _extractError(
    Object error, {
    String fallback = 'Something went wrong.',
  }) {
    final text = error.toString().trim();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length).trim();
    }
    return text.isEmpty ? fallback : text;
  }

  void _showMessage(
    String text, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError
            ? Colors.red
            : isSuccess
            ? const Color(0xFF16A34A)
            : null,
      ),
    );
  }

  Future<void> _refreshCurrentTab() async {
    _eventsByTab.clear();
    await _loadEventsForTab(_tabController.index, force: true);
  }

  Future<void> _openExternalLink(String url, {String? fallbackFileId}) async {
    var target = url.trim();
    if (target.isEmpty &&
        fallbackFileId != null &&
        fallbackFileId.trim().isNotEmpty) {
      target =
          'https://drive.google.com/file/d/${Uri.encodeComponent(fallbackFileId.trim())}/view';
    }
    final uri = Uri.tryParse(target);
    if (uri == null) {
      _showMessage('Link unavailable.', isError: true);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showMessage('Could not open link.', isError: true);
    }
  }

  Future<void> _loadEventsForTab(int idx, {bool force = false}) async {
    final key = _tabs[idx];
    if (_eventsByTab.containsKey(key) && !force) return;

    if (!force) {
      setState(() {
        _loading[key] = true;
        _errors[key] = null;
      });
    }

    try {
      final eventData = await _api.get<Map<String, dynamic>>('/events');
      final approvalData = await _api.get<Map<String, dynamic>>(
        '/approvals/me',
      );
      final inviteData = await _api.get<List<dynamic>>('/invites/me');

      final events = (eventData['items'] as List? ?? [])
          .map((e) => Event.fromJson(e))
          .toList();

      final sentInviteIds = inviteData
          .whereType<Map<String, dynamic>>()
          .where(
            (invite) =>
                (invite['status'] ?? 'sent').toString().trim().toLowerCase() ==
                'sent',
          )
          .map((invite) => (invite['event_id'] ?? '').toString().trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      final approvals = (approvalData['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((a) {
            final status = (a['status'] ?? '').toString().toLowerCase();
            return status == 'pending' ||
                status == 'clarification' ||
                status == 'clarification_requested';
          })
          .map((a) {
            final startDate = (a['start_date'] ?? '').toString();
            final startTime = (a['start_time'] ?? '').toString();
            final endDate = (a['end_date'] ?? '').toString();
            final endTime = (a['end_time'] ?? '').toString();

            final start =
                DateTime.tryParse('${startDate}T$startTime') ?? DateTime.now();
            final end = DateTime.tryParse('${endDate}T$endTime') ?? start;

            return Event(
              id: 'approval-${a['id'] ?? ''}',
              title: (a['event_name'] ?? '').toString(),
              facilitator: a['facilitator']?.toString(),
              description: a['description']?.toString(),
              venueName: (a['venue_name'] ?? '').toString(),
              startTime: start,
              endTime: end,
              status: (a['status'] ?? 'pending').toString(),
              createdBy: (a['requester_id'] ?? '').toString(),
              createdAt: DateTime.tryParse(
                (a['created_at'] ?? '').toString(),
              )?.toLocal(),
              reportFileId: null,
              reportFileName: null,
              reportWebViewLink: null,
              attendanceFileId: null,
              attendanceFileName: null,
              attendanceWebViewLink: null,
              audienceCount: null,
              notes: null,
              pipelineStage: a['pipeline_stage']?.toString(),
              approvalRequestId: (a['id'] ?? '').toString(),
              inviteStatus: null,
              googleEventLink: null,
            );
          })
          .toList();

      final allEvents = [...approvals, ...events]
        ..sort((a, b) {
          final aCreated = a.createdAt ?? a.startTime;
          final bCreated = b.createdAt ?? b.startTime;
          final byCreated = bCreated.compareTo(aCreated);
          if (byCreated != 0) return byCreated;
          return b.startTime.compareTo(a.startTime);
        });
      setState(() {
        _inviteSentEventIds
          ..clear()
          ..addAll(sentInviteIds);
        _eventsByTab[key] = _filterEventsForTab(allEvents, idx);
        _loading[key] = false;
      });
    } catch (e) {
      setState(() {
        _errors[key] = e.toString();
        _loading[key] = false;
      });
    }
  }

  String _approvalForwardLabel(Event event) {
    final stage = (event.pipelineStage ?? '').toLowerCase().trim();
    if (stage == 'after_deputy') return 'SEND TO FINANCE DEPARTMENT';
    if (stage == 'after_finance') return 'SEND TO FINAL APPROVER';
    return '';
  }

  Future<void> _forwardApproval(Event event) async {
    final rawId = (event.approvalRequestId ?? '').trim().replaceFirst(
      'approval-',
      '',
    );
    if (rawId.isEmpty) return;

    final stage = (event.pipelineStage ?? '').toLowerCase().trim();
    final toFinance = stage == 'after_deputy';
    final toRegistrar = stage == 'after_finance';
    if (!toFinance && !toRegistrar) return;

    final endpoint = toFinance
        ? '/approvals/$rawId/forward-to-finance'
        : '/approvals/$rawId/forward-to-registrar';

    try {
      await _api.post<Map<String, dynamic>>(endpoint);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            toFinance
                ? 'Sent to Finance for approval.'
                : 'Sent to the final approver for approval.',
          ),
        ),
      );
      _eventsByTab.clear();
      await _loadEventsForTab(_tabController.index, force: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _sendInvite(Event event) async {
    final toCtrl = TextEditingController();
    final subjectCtrl = TextEditingController(
      text: '${event.title} Invitation',
    );
    final bodyCtrl = TextEditingController(
      text:
          'You are invited to ${event.title} on ${DateFormat('MMM d, yyyy').format(event.startTime)} at ${event.venueName}.',
    );
    var submitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void closeDialog() {
            FocusScope.of(ctx).unfocus();
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
          }

          return AlertDialog(
            title: const Text('Send Invite'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: toCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'To',
                      hintText: 'recipient@campus.edu',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjectCtrl,
                    decoration: const InputDecoration(labelText: 'Subject'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyCtrl,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : closeDialog,
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final toEmail = toCtrl.text.trim();
                        if (toEmail.isEmpty) {
                          _showMessage(
                            'Recipient email is required.',
                            isError: true,
                          );
                          return;
                        }
                        setLocal(() => submitting = true);
                        try {
                          await _api.post<Map<String, dynamic>>(
                            '/invites',
                            data: {
                              'event_id': event.id,
                              'to_email': toEmail,
                              'subject': subjectCtrl.text.trim(),
                              'body': bodyCtrl.text.trim(),
                            },
                          );
                          if (!mounted) return;
                          closeDialog();
                          if (!mounted) return;
                          setState(() => _inviteSentEventIds.add(event.id));
                          _showMessage('Invite sent.', isSuccess: true);
                        } catch (e) {
                          setLocal(() => submitting = false);
                          _showMessage(
                            _extractError(
                              e,
                              fallback: 'Unable to send invite.',
                            ),
                            isError: true,
                          );
                        }
                      },
                child: Text(submitting ? 'Sending...' : 'Send Invite'),
              ),
            ],
          );
        },
      ),
    );

    await WidgetsBinding.instance.endOfFrame;
    toCtrl.dispose();
    subjectCtrl.dispose();
    bodyCtrl.dispose();
  }

  Future<void> _uploadReport(Event event) async {
    String? reportPath;
    String? reportName;
    String? attendancePath;
    String? attendanceName;
    var attendanceNotApplicable = false;
    var submitting = false;
    final expectedName = _expectedReportFilename(event);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
            (event.reportFileId?.trim().isNotEmpty ?? false)
                ? 'Replace Report'
                : 'Upload Report',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The report will be uploaded as:',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  expectedName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: submitting
                      ? null
                      : () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: const ['pdf'],
                          );
                          final picked = result?.files.single;
                          if (picked?.path == null) return;
                          setLocal(() {
                            reportPath = picked!.path!;
                            reportName = picked.name;
                          });
                        },
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    reportName == null ? 'Choose report PDF' : reportName!,
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: attendanceNotApplicable,
                  onChanged: submitting
                      ? null
                      : (value) {
                          setLocal(() {
                            attendanceNotApplicable = value ?? false;
                            if (attendanceNotApplicable) {
                              attendancePath = null;
                              attendanceName = null;
                            }
                          });
                        },
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Attendance not applicable'),
                ),
                const SizedBox(height: 4),
                Text(
                  attendanceNotApplicable
                      ? 'Existing attendance will be removed when you submit.'
                      : 'Upload a PDF, Word, or Excel file unless not applicable.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: submitting || attendanceNotApplicable
                      ? null
                      : () async {
                          final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: const [
                              'pdf',
                              'doc',
                              'docx',
                              'xls',
                              'xlsx',
                            ],
                          );
                          final picked = result?.files.single;
                          if (picked?.path == null) return;
                          setLocal(() {
                            attendancePath = picked!.path!;
                            attendanceName = picked.name;
                          });
                        },
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    attendanceName == null
                        ? ((event.attendanceFileName?.trim().isNotEmpty ??
                                  false)
                              ? 'Replace attendance file'
                              : 'Choose attendance file')
                        : attendanceName!,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final hasExistingAttendance =
                          event.attendanceFileId?.trim().isNotEmpty ?? false;
                      if (reportPath == null) {
                        _showMessage(
                          'Choose a report PDF first.',
                          isError: true,
                        );
                        return;
                      }
                      if (!attendanceNotApplicable &&
                          attendancePath == null &&
                          !hasExistingAttendance) {
                        _showMessage(
                          'Upload an attendance file or mark it as not applicable.',
                          isError: true,
                        );
                        return;
                      }
                      setLocal(() => submitting = true);
                      try {
                        final payload = <String, dynamic>{
                          'file': await MultipartFile.fromFile(
                            reportPath!,
                            filename: expectedName,
                          ),
                        };
                        if (attendanceNotApplicable) {
                          payload['attendance_not_applicable'] = '1';
                        } else if (attendancePath != null) {
                          payload['attendance_file'] =
                              await MultipartFile.fromFile(
                                attendancePath!,
                                filename: attendanceName,
                              );
                        }
                        await _api.postMultipart<Map<String, dynamic>>(
                          '/events/${event.id}/report',
                          FormData.fromMap(payload),
                        );
                        if (!mounted) return;
                        Navigator.of(context, rootNavigator: true).pop();
                        await _refreshCurrentTab();
                        _showMessage('Report uploaded.', isSuccess: true);
                      } catch (e) {
                        setLocal(() => submitting = false);
                        _showMessage(
                          _extractError(
                            e,
                            fallback: 'Unable to upload report.',
                          ),
                          isError: true,
                        );
                      }
                    },
              child: Text(submitting ? 'Uploading...' : 'Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _closeEvent(Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Event'),
        content: const Text(
          'This matches the website behavior and marks the completed event as closed. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.patch<Map<String, dynamic>>(
        '/events/${event.id}/status',
        data: {'status': 'closed'},
      );
      await _refreshCurrentTab();
      _showMessage('Event closed.', isSuccess: true);
    } catch (e) {
      _showMessage(
        _extractError(e, fallback: 'Unable to close event.'),
        isError: true,
      );
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await _refreshCurrentTab();
    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? theme.scaffoldBackgroundColor
          : const Color(0xFFF4F7FE),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildTopSection(),
            const SizedBox(height: 24),
            _buildFilterPills(),
            const SizedBox(height: 16),
            _buildEventsContainer(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headingColor = isDark
        ? Colors.white
        : const Color(0xFF1E293B); // slate-800
    final refreshFg = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF64748B); // slate-500
    final refreshBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    final currentTabEvents =
        _eventsByTab[_tabs[_tabController.index]]?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'My Events',
                style: GoogleFonts.poppins(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: headingColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFF2563EB), // blue-600
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x4D2563EB),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '$currentTabEvents',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => context.go('/events/create'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Event'),
                style:
                    ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ).copyWith(
                      shadowColor: WidgetStateProperty.all(
                        const Color(0x332563EB),
                      ),
                      elevation: WidgetStateProperty.all(8),
                    ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _handleRefresh,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF3B82F6), // blue-500
                        ),
                      )
                    : const Icon(Icons.sync, size: 16),
                label: const Text('Refresh'),
                style:
                    OutlinedButton.styleFrom(
                      foregroundColor: refreshFg,
                      backgroundColor: refreshBg,
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFDADCE0),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: GoogleFonts.roboto(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      elevation: 0,
                    ).copyWith(
                      shadowColor: WidgetStateProperty.all(
                        Colors.black.withValues(alpha: 0.05),
                      ),
                      elevation: WidgetStateProperty.all(2),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final inactiveBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final inactiveText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B); // slate-500

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final isActive = _tabController.index == index;
          return GestureDetector(
            onTap: () {
              _tabController.animateTo(index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: isActive ? const Color(0xFF2563EB) : inactiveBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isActive ? const Color(0xFF2563EB) : inactiveBorder,
                  width: 1.5,
                ),
                boxShadow: isActive
                    ? const [
                        BoxShadow(
                          color: Color(0x332563EB),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                _tabs[index],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isActive ? Colors.white : inactiveText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEventsContainer() {
    return Expanded(
      child: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: _tabs.asMap().entries.map((entry) {
          final key = entry.value;
          final isLoading = _loading[key] ?? true;
          final error = _errors[key];
          final events = _eventsByTab[key] ?? [];

          if (isLoading) {
            return _LoadingList();
          }
          if (error != null) {
            return ErrorState(
              message: error,
              onRetry: () {
                _eventsByTab.remove(key);
                _loadEventsForTab(entry.key);
              },
            );
          }
          if (events.isEmpty) {
            return _MyEventsEmptyState(tabLabel: key);
          }

          return RefreshIndicator(
            onRefresh: () async {
              _eventsByTab.remove(key);
              await _loadEventsForTab(entry.key);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              itemCount: events.length,
              separatorBuilder: (context, index) => const SizedBox(height: 20),
              itemBuilder: (ctx, i) => _EventCard(
                event: events[i],
                onTap: () {
                  final event = events[i];
                  final approvalId = (event.approvalRequestId ?? '')
                      .trim()
                      .replaceFirst('approval-', '');
                  if (event.id.startsWith('approval-') &&
                      approvalId.isNotEmpty) {
                    context.push('/approval-details/$approvalId');
                    return;
                  }
                  context.push('/events/${event.id}');
                },
                approvalForwardLabel: _approvalForwardLabel(events[i]),
                onApprovalForward: () => _forwardApproval(events[i]),
                canInvite: _canInvite(events[i]),
                canUploadReport: _canUploadReport(events[i]),
                canCloseEvent: _canCloseEvent(events[i]),
                canViewReport: _canViewReport(events[i]),
                canViewAttendance: _canViewAttendance(events[i]),
                // Requirement eligibility depends on per-department request
                // state from the event-details payload, so we only expose the
                // action from the details screen where that full context exists.
                canSendRequirements: false,
                inviteSent: _inviteSentEventIds.contains(events[i].id),
                onSendInvite: () => _sendInvite(events[i]),
                onUploadReport: () => _uploadReport(events[i]),
                onCloseEvent: () => _closeEvent(events[i]),
                onViewReport: () => _openExternalLink(
                  events[i].reportWebViewLink ?? '',
                  fallbackFileId: events[i].reportFileId,
                ),
                onViewAttendance: () => _openExternalLink(
                  events[i].attendanceWebViewLink ?? '',
                  fallbackFileId: events[i].attendanceFileId,
                ),
                onSendRequirements: null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ShimmerBox(width: double.infinity, height: 160, radius: 16),
      ),
    );
  }
}

class _MyEventsEmptyState extends StatelessWidget {
  final String tabLabel;

  const _MyEventsEmptyState({required this.tabLabel});

  ({String title, String subtitle}) _copy() {
    switch (tabLabel.trim().toLowerCase()) {
      case 'approvals':
        return (
          title: 'No approval requests right now.',
          subtitle:
              'New event submissions waiting for Deputy, Finance, or final approval will appear here.',
        );
      case 'upcoming':
        return (
          title: 'No upcoming events.',
          subtitle:
              'Approved events that have not started yet will show up here.',
        );
      case 'ongoing':
        return (
          title: 'No ongoing events.',
          subtitle:
              'Events move here automatically once their start time begins.',
        );
      case 'completed':
        return (
          title: 'No completed events.',
          subtitle:
              'Finished events stay here until the report is uploaded and the event is closed.',
        );
      case 'closed':
        return (
          title: 'No closed events.',
          subtitle:
              'Events appear here after report upload and manual closure.',
        );
      default:
        return (
          title: 'No events found.',
          subtitle: 'Create your first event to get started.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final copy = _copy();

    final iconColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFFCBD5E1); // slate-300
    final titleColor = isDark
        ? Colors.white
        : const Color(0xFF334155); // slate-700
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF94A3B8); // slate-400

    final boxBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final boxBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9); // slate-100

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: boxBg,
                borderRadius: BorderRadius.circular(32), // rounded-[2rem]
                border: Border.all(color: boxBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.calendar_today_outlined,
                size: 40,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 24), // mb-6 equivalent
            Text(
              copy.title,
              style: TextStyle(
                fontSize: 20, // text-xl
                fontWeight: FontWeight.w800, // font-extrabold
                color: titleColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              copy.subtitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: subtitleColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;
  final String approvalForwardLabel;
  final VoidCallback? onApprovalForward;
  final bool canInvite;
  final bool canUploadReport;
  final bool canCloseEvent;
  final bool canViewReport;
  final bool canViewAttendance;
  final bool canSendRequirements;
  final bool inviteSent;
  final VoidCallback? onSendInvite;
  final VoidCallback? onUploadReport;
  final VoidCallback? onCloseEvent;
  final VoidCallback? onViewReport;
  final VoidCallback? onViewAttendance;
  final VoidCallback? onSendRequirements;

  const _EventCard({
    required this.event,
    required this.onTap,
    this.approvalForwardLabel = '',
    this.onApprovalForward,
    this.canInvite = false,
    this.canUploadReport = false,
    this.canCloseEvent = false,
    this.canViewReport = false,
    this.canViewAttendance = false,
    this.canSendRequirements = false,
    this.inviteSent = false,
    this.onSendInvite,
    this.onUploadReport,
    this.onCloseEvent,
    this.onViewReport,
    this.onViewAttendance,
    this.onSendRequirements,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9); // slate-100
    final titleColor = isDark
        ? Colors.white
        : const Color(0xFF1E293B); // slate-800

    final labelColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFFCBD5E1); // slate-300
    final valueColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF334155); // slate-700

    final detailsBg = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFEFF6FF).withValues(alpha: 0.5); // blue-50/50
    final detailsFg = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB); // blue-600

    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    final statusColor = _getStatusColor(event.status);
    final statusBgColor = _getStatusBgColor(event.status);
    final statusBorderColor = _getStatusBorderColor(event.status);
    final statusLabel = _statusLabel(event);
    final pipelineText = _approvalPipelineText(event);
    final showForwardAction = approvalForwardLabel.trim().isNotEmpty;
    final actions = <Widget>[
      if (canCloseEvent && onCloseEvent != null)
        _ActionChip(
          label: 'Close Event',
          icon: Icons.task_alt_outlined,
          color: const Color(0xFFDC2626),
          onTap: onCloseEvent!,
        ),
      if (inviteSent)
        const _ActionChip(
          label: 'Invite Sent',
          icon: Icons.check_circle_outline,
          color: Color(0xFF16A34A),
        ),
      if (canInvite && onSendInvite != null)
        _ActionChip(
          label: 'Send Invite',
          icon: Icons.mail_outline,
          color: const Color(0xFF7C3AED),
          onTap: onSendInvite!,
        ),
      if (canUploadReport && onUploadReport != null)
        _ActionChip(
          label: (event.reportFileId?.trim().isNotEmpty ?? false)
              ? 'Replace Report'
              : 'Upload Report',
          icon: Icons.upload_file_outlined,
          color: const Color(0xFF0F766E),
          onTap: onUploadReport!,
        ),
      if (canSendRequirements && onSendRequirements != null)
        _ActionChip(
          label: 'Send Requirements',
          icon: Icons.send_outlined,
          color: const Color(0xFF2563EB),
          onTap: onSendRequirements!,
        ),
      if (canViewReport && onViewReport != null)
        _ActionChip(
          label: 'View Report',
          icon: Icons.description_outlined,
          color: const Color(0xFF4F46E5),
          onTap: onViewReport!,
        ),
      if (canViewAttendance && onViewAttendance != null)
        _ActionChip(
          label: 'Attendance',
          icon: Icons.groups_2_outlined,
          color: const Color(0xFF9333EA),
          onTap: onViewAttendance!,
        ),
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24), // rounded-3xl
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                      height: 1.25, // leading-tight
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(9999), // full
                    border: Border.all(color: statusBorderColor),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      letterSpacing: 2.0, // tracking-widest
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24), // gap-6
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DATE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900, // font-black
                          color: labelColor,
                          letterSpacing: 2.0, // tracking-widest
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        df.format(event.startTime),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: valueColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TIME',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900, // font-black
                          color: labelColor,
                          letterSpacing: 2.0, // tracking-widest
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tf.format(event.startTime),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: valueColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (pipelineText.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0B1220)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  pipelineText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFBFDBFE)
                        : const Color(0xFF1E3A8A),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (showForwardAction) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onApprovalForward,
                  icon: const Icon(Icons.send_outlined, size: 16),
                  label: Text(
                    approvalForwardLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0891B2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (actions.isNotEmpty) ...[
              Wrap(spacing: 10, runSpacing: 10, children: actions),
              const SizedBox(height: 16),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14), // py-3.5
              decoration: BoxDecoration(
                color: detailsBg,
                borderRadius: BorderRadius.circular(16), // rounded-2xl
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.remove_red_eye,
                    size: 16,
                    color: detailsFg,
                  ), // Eye icon
                  const SizedBox(width: 8),
                  Text(
                    'VIEW DETAILS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: detailsFg,
                      letterSpacing: 2.0, // tracking-widest
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _approvalPipelineText(Event value) {
    if (!value.id.startsWith('approval-')) return '';

    final status = value.status.toLowerCase().trim();
    if (status == 'rejected') return 'Rejected';
    if (status == 'clarification' || status == 'clarification_requested') {
      return 'Clarification';
    }

    final stage = (value.pipelineStage ?? '').toLowerCase().trim();
    switch (stage) {
      case 'deputy':
        return 'Awaiting Deputy Registrar';
      case 'after_deputy':
        return 'Deputy approved - send to Finance';
      case 'finance':
        return 'Awaiting Finance Team';
      case 'after_finance':
        return 'Finance approved - send to final approver';
      case 'registrar':
        return 'Awaiting Registrar / Vice Chancellor';
      case 'complete':
        return 'Final approval completed';
      default:
        return 'Awaiting approval';
    }
  }

  String _statusLabel(Event value) {
    final normalized = value.status.toLowerCase().trim();
    if (value.id.startsWith('approval-')) {
      if (normalized == 'pending') return 'PENDING APPROVAL';
      if (normalized == 'clarification' ||
          normalized == 'clarification_requested') {
        return 'CLARIFICATION';
      }
    }
    if (normalized == 'clarification' ||
        normalized == 'clarification_requested') {
      return 'CLARIFICATION';
    }
    return normalized.toUpperCase().replaceAll('_', ' ');
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFD97706); // amber-600
      case 'clarification':
      case 'clarification_requested':
        return const Color(0xFF7C3AED); // violet-600
      case 'rejected':
        return const Color(0xFFDC2626); // red-600
      case 'upcoming':
        return const Color(0xFF2563EB); // blue-600
      case 'ongoing':
        return const Color(0xFF4F46E5); // indigo-600
      case 'completed':
        return const Color(0xFF059669); // emerald-600
      case 'closed':
        return const Color(0xFF475569); // slate-600
      default:
        return const Color(0xFF475569); // slate-600
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFFFBEB); // amber-50
      case 'clarification':
      case 'clarification_requested':
        return const Color(0xFFF5F3FF); // violet-50
      case 'rejected':
        return const Color(0xFFFEF2F2); // red-50
      case 'upcoming':
        return const Color(0xFFEFF6FF); // blue-50
      case 'ongoing':
        return const Color(0xFFEEF2FF); // indigo-50
      case 'completed':
        return const Color(0xFFECFDF5); // emerald-50
      case 'closed':
        return const Color(0xFFF8FAFC); // slate-50
      default:
        return const Color(0xFFF8FAFC); // slate-50
    }
  }

  Color _getStatusBorderColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFEF3C7); // amber-100
      case 'clarification':
      case 'clarification_requested':
        return const Color(0xFFDDD6FE); // violet-200
      case 'rejected':
        return const Color(0xFFFECACA); // red-200
      case 'upcoming':
        return const Color(0xFFDBEAFE); // blue-100
      case 'ongoing':
        return const Color(0xFFE0E7FF); // indigo-100
      case 'completed':
        return const Color(0xFFD1FAE5); // emerald-100
      case 'closed':
        return const Color(0xFFE2E8F0); // slate-200
      default:
        return const Color(0xFFF1F5F9); // slate-100
    }
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: disabled ? 0.08 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: color.withValues(alpha: disabled ? 0.12 : 0.28),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
