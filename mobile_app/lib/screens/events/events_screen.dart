import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';
import '../requirements/requirements_wizard_dialog.dart';
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

  bool _canSendRequirementForStatus(String? status) {
    final normalized = status?.trim().toLowerCase() ?? '';
    return normalized.isEmpty ||
        normalized == 'none' ||
        normalized == 'rejected';
  }

  List<String> _sendableRequirementDepartments(Event event) {
    final statuses = <String, String?>{
      'facility': event.facilityStatus,
      'it': event.itStatus,
      'marketing': event.marketingStatus,
      'transport': event.transportStatus,
    };

    return statuses.entries
        .where((entry) => _canSendRequirementForStatus(entry.value))
        .map((entry) => entry.key)
        .toList();
  }

  bool _canSendRequirements(Event event) {
    if (_isApprovalItem(event)) return false;

    final approvalStatus = event.approvalStatus?.trim().toLowerCase() ?? '';
    final eventStatus = event.status.trim().toLowerCase();
    if (approvalStatus.isNotEmpty && approvalStatus != 'approved') return false;
    if (_hasStarted(event)) return false;
    if (eventStatus == 'completed' || eventStatus == 'closed') return false;

    return _sendableRequirementDepartments(event).isNotEmpty;
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

  String _pdfText(String value) {
    return value
        .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E]'), '-')
        .replaceAll('\\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  List<String> _wrapPdfLine(String text, {int maxChars = 88}) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [''];
    final words = cleaned.split(RegExp(r'\s+'));
    final lines = <String>[];
    var line = '';
    for (final word in words) {
      if (line.isEmpty) {
        line = word;
      } else if (line.length + word.length + 1 <= maxChars) {
        line = '$line $word';
      } else {
        lines.add(line);
        line = word;
      }
    }
    if (line.isNotEmpty) lines.add(line);
    return lines;
  }

  Uint8List _buildReportPdfBytes({
    required Event event,
    required String executiveSummary,
    required String attendance,
    required String programAgenda,
    required String outcomesLearnings,
    required String followUp,
    required String appendix,
  }) {
    final lines = <String>[];

    void addLine(String line) => lines.add(line);

    void addWrapped(String text) {
      for (final line in text.split('\n')) {
        lines.addAll(_wrapPdfLine(line));
      }
    }

    void addSection(String title, String text) {
      addLine('');
      addLine(title);
      if (text.trim().isEmpty) {
        addLine('-');
      } else {
        addWrapped(text);
      }
    }

    addLine('Event Report');
    addLine('');
    addLine('Event: ${event.title}');
    addLine('Date: ${DateFormat('yyyy-MM-dd').format(event.startTime)}');
    addLine('Venue: ${event.venueName.isEmpty ? '-' : event.venueName}');
    addLine(
      'Facilitator: ${event.facilitator?.trim().isNotEmpty == true ? event.facilitator!.trim() : '-'}',
    );
    addLine(
      'Report submitted on: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
    );
    addSection('Executive Summary', executiveSummary);
    addSection('Attendance', attendance);
    addSection('Program / Agenda', programAgenda);
    addSection('Outcomes and Learnings', outcomesLearnings);
    if (followUp.trim().isNotEmpty) addSection('Follow-up', followUp);
    if (appendix.trim().isNotEmpty) addSection('Appendix', appendix);

    const pageLineLimit = 52;
    final pages = <List<String>>[];
    for (var i = 0; i < lines.length; i += pageLineLimit) {
      pages.add(
        lines.sublist(
          i,
          i + pageLineLimit > lines.length ? lines.length : i + pageLineLimit,
        ),
      );
    }
    if (pages.isEmpty) pages.add(const ['Event Report']);

    final objects = <String>[];
    final pageObjectIds = <int>[];
    final contentObjectIds = <int>[];
    final fontObjectId = 3 + pages.length * 2;

    objects.add('<< /Type /Catalog /Pages 2 0 R >>');

    for (var i = 0; i < pages.length; i++) {
      final pageId = 3 + i * 2;
      final contentId = pageId + 1;
      pageObjectIds.add(pageId);
      contentObjectIds.add(contentId);
    }

    objects.add(
      '<< /Type /Pages /Kids [${pageObjectIds.map((id) => '$id 0 R').join(' ')}] /Count ${pages.length} >>',
    );

    for (var i = 0; i < pages.length; i++) {
      final content = StringBuffer()
        ..writeln('BT')
        ..writeln('/F1 10 Tf')
        ..writeln('50 792 Td')
        ..writeln('14 TL');
      for (final line in pages[i]) {
        content.writeln('(${_pdfText(line)}) Tj');
        content.writeln('T*');
      }
      content.writeln('ET');
      final contentText = content.toString();

      objects.add(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 $fontObjectId 0 R >> >> /Contents ${contentObjectIds[i]} 0 R >>',
      );
      objects.add(
        '<< /Length ${utf8.encode(contentText).length} >>\nstream\n$contentText'
        'endstream',
      );
    }

    objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

    final out = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[0];
    var byteOffset = utf8.encode(out.toString()).length;
    for (var i = 0; i < objects.length; i++) {
      offsets.add(byteOffset);
      final objectText = '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
      out.write(objectText);
      byteOffset += utf8.encode(objectText).length;
    }
    final xrefOffset = byteOffset;
    out.writeln('xref');
    out.writeln('0 ${objects.length + 1}');
    out.writeln('0000000000 65535 f ');
    for (var i = 1; i < offsets.length; i++) {
      out.writeln('${offsets[i].toString().padLeft(10, '0')} 00000 n ');
    }
    out.writeln('trailer');
    out.writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>');
    out.writeln('startxref');
    out.writeln(xrefOffset);
    out.writeln('%%EOF');

    return Uint8List.fromList(utf8.encode(out.toString()));
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
      final facilityData = await _api.get<dynamic>('/facility/requests/me');
      final marketingData = await _api.get<dynamic>('/marketing/requests/me');
      final itData = await _api.get<dynamic>('/it/requests/me');
      final transportData = await _api.get<dynamic>('/transport/requests/me');
      final inviteData = await _api.get<List<dynamic>>('/invites/me');

      final events = (eventData['items'] as List? ?? [])
          .map((e) => Event.fromJson(e))
          .toList();
      final approvalsRaw = _itemsFromPayload(approvalData);
      final facilityRaw = _itemsFromPayload(facilityData);
      final marketingRaw = _itemsFromPayload(marketingData);
      final itRaw = _itemsFromPayload(itData);
      final transportRaw = _itemsFromPayload(transportData);

      final approvalByEventId = <String, String>{};
      final facilityByEventId = <String, String>{};
      final marketingByEventId = <String, String>{};
      final itByEventId = <String, String>{};
      final transportByEventId = <String, String>{};

      final approvalByEventKey = <String, String>{};
      final facilityByEventKey = <String, String>{};
      final marketingByEventKey = <String, String>{};
      final itByEventKey = <String, String>{};
      final transportByEventKey = <String, String>{};

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

      for (final item in approvalsRaw) {
        final status = (item['status'] ?? '').toString();
        final eventId = (item['event_id'] ?? '').toString().trim();
        final eventKey = _buildWorkflowEventKey(item);
        if (eventId.isNotEmpty) {
          approvalByEventId[eventId] = status;
        }
        if (eventKey.isNotEmpty) {
          approvalByEventKey[eventKey] = status;
        }
      }
      _indexWorkflowStatuses(
        facilityRaw,
        byEventId: facilityByEventId,
        byEventKey: facilityByEventKey,
      );
      _indexWorkflowStatuses(
        marketingRaw,
        byEventId: marketingByEventId,
        byEventKey: marketingByEventKey,
      );
      _indexWorkflowStatuses(
        itRaw,
        byEventId: itByEventId,
        byEventKey: itByEventKey,
      );
      _indexWorkflowStatuses(
        transportRaw,
        byEventId: transportByEventId,
        byEventKey: transportByEventKey,
      );

      final approvals = approvalsRaw
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
              approvalStatus: (a['status'] ?? '').toString(),
              facilityStatus: null,
              marketingStatus: null,
              itStatus: null,
              transportStatus: null,
              inviteStatus: null,
              googleEventLink: null,
            );
          })
          .toList();

      final enrichedEvents = events.map((event) {
        final eventKey = _buildEventKeyFromEvent(event);
        return Event(
          id: event.id,
          title: event.title,
          facilitator: event.facilitator,
          description: event.description,
          imageUrl: event.imageUrl,
          venueName: event.venueName,
          startTime: event.startTime,
          endTime: event.endTime,
          status: event.status,
          createdBy: event.createdBy,
          createdAt: event.createdAt,
          reportFileId: event.reportFileId,
          reportFileName: event.reportFileName,
          reportWebViewLink: event.reportWebViewLink,
          attendanceFileId: event.attendanceFileId,
          attendanceFileName: event.attendanceFileName,
          attendanceWebViewLink: event.attendanceWebViewLink,
          audienceCount: event.audienceCount,
          notes: event.notes,
          pipelineStage: event.pipelineStage,
          approvalRequestId: event.approvalRequestId,
          approvalStatus:
              approvalByEventId[event.id] ?? approvalByEventKey[eventKey],
          facilityStatus:
              facilityByEventId[event.id] ?? facilityByEventKey[eventKey],
          marketingStatus:
              marketingByEventId[event.id] ?? marketingByEventKey[eventKey],
          itStatus: itByEventId[event.id] ?? itByEventKey[eventKey],
          transportStatus:
              transportByEventId[event.id] ?? transportByEventKey[eventKey],
          inviteStatus: event.inviteStatus,
          googleEventLink: event.googleEventLink,
        );
      }).toList();

      final allEvents = [...approvals, ...enrichedEvents]
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

  List<Map<String, dynamic>> _itemsFromPayload(dynamic payload) {
    if (payload is List) {
      return payload.whereType<Map<String, dynamic>>().toList();
    }
    if (payload is Map<String, dynamic>) {
      final items = payload['items'];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList();
      }
    }
    return const <Map<String, dynamic>>[];
  }

  void _indexWorkflowStatuses(
    List<Map<String, dynamic>> items, {
    required Map<String, String> byEventId,
    required Map<String, String> byEventKey,
  }) {
    for (final item in items) {
      final status = (item['status'] ?? '').toString();
      final eventId = (item['event_id'] ?? '').toString().trim();
      final eventKey = _buildWorkflowEventKey(item);
      if (eventId.isNotEmpty) {
        byEventId[eventId] = status;
      }
      if (eventKey.isNotEmpty) {
        byEventKey[eventKey] = status;
      }
    }
  }

  String _normalizeTimeString(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    return '${parts[0]}:${parts[1]}';
  }

  String _buildWorkflowEventKey(Map<String, dynamic> item) {
    return [
      (item['event_name'] ?? '').toString().trim(),
      (item['start_date'] ?? '').toString().trim(),
      _normalizeTimeString(item['start_time']?.toString()),
      (item['end_date'] ?? '').toString().trim(),
      _normalizeTimeString(item['end_time']?.toString()),
    ].join('|');
  }

  String _buildEventKeyFromEvent(Event event) {
    return [
      event.title.trim(),
      DateFormat('yyyy-MM-dd').format(event.startTime),
      DateFormat('HH:mm').format(event.startTime),
      DateFormat('yyyy-MM-dd').format(event.endTime),
      DateFormat('HH:mm').format(event.endTime),
    ].join('|');
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

  Future<void> _sendRequirements(Event event) async {
    final departments = _sendableRequirementDepartments(event);
    if (departments.isEmpty) {
      _showMessage(
        'All requirement requests are already active.',
        isSuccess: true,
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RequirementsWizardDialog(
        event: event,
        departments: departments,
        requesterEmail: event.createdBy,
        onSuccess: () async {
          await _refreshCurrentTab();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  Future<void> _uploadReport(Event event) async {
    final executiveSummaryCtrl = TextEditingController();
    final programAgendaCtrl = TextEditingController();
    final outcomesLearningsCtrl = TextEditingController();
    final followUpCtrl = TextEditingController();
    final appendixCtrl = TextEditingController();
    String? attendancePath;
    String? attendanceName;
    var attendanceNotApplicable = false;
    var submitting = false;
    final expectedName = _expectedReportFilename(event);
    final hasExistingReport = event.reportFileId?.trim().isNotEmpty ?? false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void closeDialog() {
            FocusScope.of(ctx).unfocus();
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
          }

          final colorScheme = Theme.of(ctx).colorScheme;
          return Dialog(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          hasExistingReport
                              ? 'Replace Report'
                              : 'Submit Event Report',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: submitting ? null : closeDialog,
                        icon: const Icon(Icons.close, size: 20),
                        color: colorScheme.onPrimaryContainer,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // ── Scrollable form ──
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cover details
                        _SectionLabel(
                          icon: Icons.event,
                          label: 'Event Details',
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${event.title} · ${DateFormat('yyyy-MM-dd').format(event.startTime)} · ${event.venueName.isEmpty ? '—' : event.venueName} · ${event.facilitator?.trim().isNotEmpty == true ? event.facilitator!.trim() : '—'}',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Executive summary
                        _SectionLabel(
                          icon: Icons.summarize,
                          label: 'Executive Summary *',
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: executiveSummaryCtrl,
                          minLines: 3,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Executive summary (required)',
                            helperText:
                                'Brief overview, goal, and main outcome',
                            hintText:
                                'e.g. The workshop aimed to… and achieved…',
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Attendance
                        _SectionLabel(
                          icon: Icons.how_to_reg,
                          label: 'Attendance',
                        ),
                        const SizedBox(height: 8),
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
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Not applicable'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          attendanceNotApplicable
                              ? 'No attendance document will be stored. Any previous file will be removed on submit.'
                              : 'Upload a PDF, Word, or Excel file (max 10 MB), or tick Not applicable.',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: submitting || attendanceNotApplicable
                                ? null
                                : () async {
                                    final result = await FilePicker.platform
                                        .pickFiles(
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
                                    if (picked!.size > 10 * 1024 * 1024) {
                                      _showMessage(
                                        'Attendance file must be 10 MB or smaller.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                    setLocal(() {
                                      attendancePath = picked.path!;
                                      attendanceName = picked.name;
                                    });
                                  },
                            icon: const Icon(Icons.attach_file),
                            label: Text(
                              attendanceName == null
                                  ? ((event.attendanceFileName
                                                ?.trim()
                                                .isNotEmpty ??
                                            false)
                                        ? 'Replace attendance file'
                                        : 'Choose attendance file')
                                  : attendanceName!,
                            ),
                          ),
                        ),
                        if (attendanceName != null) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: submitting
                                  ? null
                                  : () {
                                      setLocal(() {
                                        attendancePath = null;
                                        attendanceName = null;
                                      });
                                    },
                              child: const Text('Remove file'),
                            ),
                          ),
                        ],
                        if ((event.attendanceFileName?.trim().isNotEmpty ??
                                false) &&
                            attendanceName == null &&
                            !attendanceNotApplicable) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Current: ${event.attendanceFileName}',
                                  style: Theme.of(ctx).textTheme.bodySmall,
                                ),
                                if (_canViewAttendance(event))
                                  TextButton(
                                    onPressed: () => _openExternalLink(
                                      event.attendanceWebViewLink ?? '',
                                      fallbackFileId: event.attendanceFileId,
                                    ),
                                    child: const Text(
                                      'View current attendance',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),

                        // Program / agenda
                        _SectionLabel(
                          icon: Icons.schedule,
                          label: 'Program / Agenda *',
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: programAgendaCtrl,
                          minLines: 4,
                          maxLines: 7,
                          decoration: const InputDecoration(
                            labelText: 'Program / agenda (required)',
                            helperText: 'Sessions or activities with times',
                            hintText:
                                'e.g. 10:00-10:30 Intro, 10:30-12:00 Session 1…',
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Outcomes
                        _SectionLabel(
                          icon: Icons.lightbulb_outline,
                          label: 'Outcomes & Learnings *',
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: outcomesLearningsCtrl,
                          minLines: 4,
                          maxLines: 7,
                          decoration: const InputDecoration(
                            labelText: 'Outcomes and learnings (required)',
                            helperText: 'Key takeaways and feedback highlights',
                            hintText:
                                'e.g. Participants reported… Next steps include…',
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Follow-up
                        _SectionLabel(
                          icon: Icons.follow_the_signs,
                          label: 'Follow-up',
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: followUpCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Follow-up (optional)',
                            helperText: 'Action items or next steps',
                            hintText: 'e.g. Send follow-up survey by…',
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Appendix
                        _SectionLabel(icon: Icons.note_add, label: 'Appendix'),
                        const SizedBox(height: 8),
                        TextField(
                          controller: appendixCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Appendix (optional)',
                            helperText:
                                'Any additional notes, photos summary, or supporting material',
                            hintText:
                                'e.g. Key photos uploaded separately; feedback quotes…',
                          ),
                        ),
                        const SizedBox(height: 16),

                        // PDF filename note
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer.withValues(
                              alpha: 0.5,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.picture_as_pdf,
                                size: 16,
                                color: colorScheme.onTertiaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Saved as: $expectedName',
                                  style: Theme.of(ctx).textTheme.bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onTertiaryContainer,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                // ── Sticky action bar ──
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: submitting ? null : closeDialog,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final hasExistingAttendance =
                                      event.attendanceFileId
                                          ?.trim()
                                          .isNotEmpty ??
                                      false;
                                  final executiveSummary = executiveSummaryCtrl
                                      .text
                                      .trim();
                                  final programAgenda = programAgendaCtrl.text
                                      .trim();
                                  final outcomesLearnings =
                                      outcomesLearningsCtrl.text.trim();
                                  if (executiveSummary.isEmpty ||
                                      programAgenda.isEmpty ||
                                      outcomesLearnings.isEmpty) {
                                    _showMessage(
                                      'Executive summary, program / agenda, and outcomes are required.',
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
                                    final attendanceText =
                                        attendanceNotApplicable
                                        ? 'Not applicable.'
                                        : attendancePath != null
                                        ? 'Supporting attendance document uploaded with this submission: $attendanceName'
                                        : 'Supporting attendance document on file: ${event.attendanceFileName?.trim() ?? ''}';
                                    final reportBytes = _buildReportPdfBytes(
                                      event: event,
                                      executiveSummary: executiveSummary,
                                      attendance: attendanceText,
                                      programAgenda: programAgenda,
                                      outcomesLearnings: outcomesLearnings,
                                      followUp: followUpCtrl.text.trim(),
                                      appendix: appendixCtrl.text.trim(),
                                    );
                                    final payload = <String, dynamic>{
                                      'file': MultipartFile.fromBytes(
                                        reportBytes,
                                        filename: expectedName,
                                        contentType: DioMediaType(
                                          'application',
                                          'pdf',
                                        ),
                                      ),
                                    };
                                    if (attendanceNotApplicable) {
                                      payload['attendance_not_applicable'] =
                                          '1';
                                    } else if (attendancePath != null) {
                                      payload['attendance_file'] =
                                          await MultipartFile.fromFile(
                                            attendancePath!,
                                            filename: attendanceName,
                                          );
                                    }
                                    await _api
                                        .postMultipart<Map<String, dynamic>>(
                                          '/events/${event.id}/report',
                                          FormData.fromMap(payload),
                                        );
                                    if (!mounted) return;
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pop();
                                    await _refreshCurrentTab();
                                    _showMessage(
                                      'Report uploaded.',
                                      isSuccess: true,
                                    );
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
                          child: Text(
                            submitting
                                ? 'Generating & uploading...'
                                : 'Generate PDF & upload',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    executiveSummaryCtrl.dispose();
    programAgendaCtrl.dispose();
    outcomesLearningsCtrl.dispose();
    followUpCtrl.dispose();
    appendixCtrl.dispose();
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
                canSendRequirements: _canSendRequirements(events[i]),
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
                onSendRequirements: () => _sendRequirements(events[i]),
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

    final cardBg = isDark ? const Color(0xFF172033) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE8EEF7);
    final titleColor = isDark ? Colors.white : const Color(0xFF172033);

    final metaBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final metaBorder = isDark
        ? const Color(0xFF273449)
        : const Color(0xFFE6EDF5);
    final labelColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF718096);
    final valueColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF263445);

    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    final statusColor = _getStatusColor(event.status);
    final statusBgColor = _getStatusBgColor(event.status);
    final statusBorderColor = _getStatusBorderColor(event.status);
    final statusLabel = _statusLabel(event);
    final pipelineText = _approvalPipelineText(event);
    final workflowBadges = _workflowBadges(event);
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
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.07),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              color: cardBg,
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                            height: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: statusBgColor,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: statusBorderColor),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _EventMetaTile(
                          icon: Icons.calendar_today_outlined,
                          label: 'Date',
                          value: df.format(event.startTime),
                          backgroundColor: metaBg,
                          borderColor: metaBorder,
                          labelColor: labelColor,
                          valueColor: valueColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _EventMetaTile(
                          icon: Icons.schedule_outlined,
                          label: 'Time',
                          value: tf.format(event.startTime),
                          backgroundColor: metaBg,
                          borderColor: metaBorder,
                          labelColor: labelColor,
                          valueColor: valueColor,
                        ),
                      ),
                    ],
                  ),
                  if (pipelineText.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.route_outlined,
                            size: 16,
                            color: statusColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pipelineText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? const Color(0xFFBFDBFE)
                                    : const Color(0xFF1E3A8A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (workflowBadges.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: workflowBadges
                          .map(
                            (badge) => _WorkflowBadge(
                              label: badge.$1,
                              value: badge.$2,
                              color: badge.$3,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (showForwardAction) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onApprovalForward,
                        icon: const Icon(Icons.send_outlined, size: 16),
                        label: Text(
                          approvalForwardLabel,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0891B2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF1F7FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF273449)
                            : const Color(0xFFDDEBFF),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.remove_red_eye_outlined,
                          size: 16,
                          color: Color(0xFF2563EB),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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

  List<(String, String, Color)> _workflowBadges(Event value) {
    if (value.id.startsWith('approval-')) return const [];

    final badges = <(String, String, Color)>[];

    void addBadge(String label, String? status, {bool teamChannel = false}) {
      final normalized = status?.trim().toLowerCase() ?? '';
      if (normalized.isEmpty) return;
      badges.add((
        label,
        teamChannel && normalized == 'approved'
            ? 'Noted'
            : _formatWorkflowStatus(normalized),
        _workflowColor(normalized),
      ));
    }

    addBadge('Approval', value.approvalStatus);
    addBadge('Facility', value.facilityStatus, teamChannel: true);
    addBadge('Marketing', value.marketingStatus, teamChannel: true);
    addBadge('IT', value.itStatus, teamChannel: true);
    addBadge('Transport', value.transportStatus, teamChannel: true);
    return badges;
  }

  String _formatWorkflowStatus(String value) {
    return value
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Color _workflowColor(String value) {
    switch (value) {
      case 'approved':
        return const Color(0xFF059669);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'clarification':
      case 'clarification_requested':
        return const Color(0xFF7C3AED);
      case 'pending':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF475569);
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
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

class _EventMetaTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color backgroundColor;
  final Color borderColor;
  final Color labelColor;
  final Color valueColor;

  const _EventMetaTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.backgroundColor,
    required this.borderColor,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: labelColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _WorkflowBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}
