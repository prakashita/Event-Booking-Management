import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/error_state.dart';
import '../home_screen.dart';
import '../../services/api_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  List<Event> _approvedEvents = [];
  List<dynamic> _workflowItems = [];
  bool _isLoading = true;
  String? _error;
  late DateTime _currentTime;
  Timer? _timer;
  late final String _roleKey;

  @override
  void initState() {
    super.initState();
    _roleKey = _normalizedRole();
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

  String _normalizedRole() {
    final role = context.read<AuthProvider>().user?.roleKey ?? '';
    return role.trim().toLowerCase();
  }

   bool get _isApproverRole =>
       _roleKey == 'registrar' ||
       _roleKey == 'vice_chancellor' ||
       _roleKey == 'deputy_registrar' ||
       _roleKey == 'finance_team';

   bool get _isDepartmentRole =>
       _roleKey == 'facility_manager' ||
       _roleKey == 'marketing' ||
       _roleKey == 'it' ||
       _roleKey == 'transport';

  bool get _isWorkflowDashboard =>
      _isApproverRole ||
      _roleKey == 'facility_manager' ||
      _roleKey == 'marketing' ||
      _roleKey == 'it' ||
      _roleKey == 'transport';

  String get _workflowChannel {
    if (_isApproverRole) return 'approval';
    if (_roleKey == 'facility_manager') return 'facility';
    if (_roleKey == 'marketing') return 'marketing';
    if (_roleKey == 'it') return 'it';
    if (_roleKey == 'transport') return 'transport';
    return '';
  }

  String get _workflowTitle {
    switch (_workflowChannel) {
      case 'approval':
        return 'Approval Requests';
      case 'facility':
        return 'Facility Requests';
      case 'marketing':
        return 'Marketing Requests';
      case 'it':
        return 'IT Requests';
      case 'transport':
        return 'Transport Requests';
      default:
        return 'Workflow Inbox';
    }
  }

  String get _workflowEmptyMessage {
    switch (_workflowChannel) {
      case 'approval':
        return 'No pending approval requests.';
      case 'facility':
        return 'No pending facility requests.';
      case 'marketing':
        return 'No pending marketing requests.';
      case 'it':
        return 'No pending IT requests.';
      case 'transport':
        return 'No pending transport requests.';
      default:
        return 'No pending workflow items.';
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (_isWorkflowDashboard) {
        await _loadWorkflowInbox();
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        return;
      }

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

  Future<void> _loadWorkflowInbox() async {
    dynamic payload;
    switch (_workflowChannel) {
      case 'approval':
        payload = await _api.get<Map<String, dynamic>>('/approvals/inbox');
        break;
      case 'facility':
        payload = await _api.get<dynamic>('/facility/inbox');
        break;
      case 'marketing':
        payload = await _api.get<dynamic>('/marketing/inbox');
        break;
      case 'it':
        payload = await _api.get<dynamic>('/it/inbox');
        break;
      case 'transport':
        payload = await _api.get<dynamic>('/transport/inbox');
        break;
      default:
        _workflowItems = [];
        return;
    }

    final items = payload is List
        ? payload
        : (payload is Map<String, dynamic>
              ? (payload['items'] as List? ?? [])
              : const []);

    if (_workflowChannel == 'approval') {
      _workflowItems = items
          .whereType<Map<String, dynamic>>()
          .map(ApprovalRequest.fromJson)
          .toList();
      return;
    }
    if (_workflowChannel == 'facility') {
      _workflowItems = items
          .whereType<Map<String, dynamic>>()
          .map(FacilityRequest.fromJson)
          .toList();
      return;
    }
    if (_workflowChannel == 'marketing') {
      _workflowItems = items
          .whereType<Map<String, dynamic>>()
          .map(MarketingRequest.fromJson)
          .toList();
      return;
    }
    if (_workflowChannel == 'it') {
      _workflowItems = items
          .whereType<Map<String, dynamic>>()
          .map(ITRequest.fromJson)
          .toList();
      return;
    }
    _workflowItems = items
        .whereType<Map<String, dynamic>>()
        .map(TransportRequest.fromJson)
        .toList();
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

  List<dynamic> _applyWorkflowSearch(List<dynamic> items, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where((item) => _workflowSearchText(item).contains(q))
        .toList();
  }

  String _workflowSearchText(dynamic item) {
    return [
      _workflowItemTitle(item),
      _workflowRequestedBy(item),
      _workflowStatus(item),
      _workflowDateLabel(item),
    ].join(' ').toLowerCase();
  }

  String _workflowItemTitle(dynamic item) {
    if (item is ApprovalRequest) return item.eventTitle;
    if (item is FacilityRequest) return item.eventTitle;
    if (item is MarketingRequest) return item.eventTitle;
    if (item is ITRequest) return item.eventTitle;
    if (item is TransportRequest) return item.eventTitle;
    return 'Request';
  }

  String _workflowRequestedBy(dynamic item) {
    if (item is ApprovalRequest) return item.requestedBy;
    if (item is FacilityRequest) return item.requestedBy;
    if (item is MarketingRequest) return item.requestedBy;
    if (item is ITRequest) return item.requestedBy;
    if (item is TransportRequest) return item.requestedBy;
    return '';
  }

  String _workflowStatus(dynamic item) {
    if (item is ApprovalRequest) return item.status;
    if (item is FacilityRequest) return item.status;
    if (item is MarketingRequest) return item.status;
    if (item is ITRequest) return item.status;
    if (item is TransportRequest) return item.status;
    return '';
  }

  DateTime _workflowCreatedAt(dynamic item) {
    if (item is ApprovalRequest) return item.createdAt;
    if (item is FacilityRequest) return item.createdAt;
    if (item is MarketingRequest) return item.createdAt;
    if (item is ITRequest) return item.createdAt;
    if (item is TransportRequest) return item.createdAt;
    return DateTime.now();
  }

  String _workflowDateLabel(dynamic item) {
    final dt = _workflowCreatedAt(item);
    return DateFormat('MMM d, yyyy').format(dt);
  }

  String? _workflowEventId(dynamic item) {
    if (item is FacilityRequest) return item.eventId;
    if (item is MarketingRequest) return item.eventId;
    if (item is ITRequest) return item.eventId;
    if (item is TransportRequest) return item.eventId;
    return null;
  }

  String _workflowRequestId(dynamic item) {
    if (item is ApprovalRequest) return item.id;
    if (item is FacilityRequest) return item.id;
    if (item is MarketingRequest) return item.id;
    if (item is ITRequest) return item.id;
    if (item is TransportRequest) return item.id;
    return '';
  }

  bool _workflowCanAct(dynamic item) {
    final normalized = _workflowStatus(item).trim().toLowerCase();
    return normalized == 'pending' ||
        normalized == 'clarification' ||
        normalized == 'clarification_requested';
  }

  String _workflowPatchPath(String id) {
    switch (_workflowChannel) {
      case 'approval':
        return '/approvals/$id';
      case 'facility':
        return '/facility/requests/$id';
      case 'marketing':
        return '/marketing/requests/$id';
      case 'it':
        return '/it/requests/$id';
      case 'transport':
        return '/transport/requests/$id';
      default:
        return '';
    }
  }

  String _workflowActionLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Approve';
      case 'rejected':
        return 'Reject';
      case 'clarification':
      case 'clarification_requested':
        return 'Clarification';
      default:
        return status;
    }
  }

  Future<void> _openWorkflowDecisionDialog(dynamic item) async {
    var selected = 'approved';
    final commentCtrl = TextEditingController();
    var submitting = false;
    String? localError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(_workflowActionLabel(selected)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _workflowItemTitle(item),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: selected,
                items: const [
                  DropdownMenuItem(value: 'approved', child: Text('Approve')),
                  DropdownMenuItem(value: 'rejected', child: Text('Reject')),
                  DropdownMenuItem(
                    value: 'clarification_requested',
                    child: Text('Clarification'),
                  ),
                ],
                onChanged: submitting
                    ? null
                    : (value) => setLocal(() => selected = value ?? 'approved'),
                decoration: InputDecoration(
                  labelText: 'Action',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentCtrl,
                enabled: !submitting,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: selected == 'approved'
                      ? 'Comment (optional)'
                      : 'Comment',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
              if (localError != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        localError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final comment = commentCtrl.text.trim();
                      if (selected != 'approved' && comment.isEmpty) {
                        setLocal(() => localError = 'Comment is required.');
                        return;
                      }
                      setLocal(() {
                        submitting = true;
                        localError = null;
                      });
                      try {
                        await _api.patch<Map<String, dynamic>>(
                          _workflowPatchPath(_workflowRequestId(item)),
                          data: {
                            'status': selected,
                            if (comment.isNotEmpty) 'comment': comment,
                          },
                        );
                        if (!mounted || !ctx.mounted) return;
                        Navigator.of(ctx).pop();
                        await _loadData();
                        _showMessage(
                          '${_workflowActionLabel(selected)} submitted.',
                          isSuccess: true,
                        );
                      } catch (e) {
                        setLocal(() {
                          submitting = false;
                          localError = e.toString().replaceFirst(
                            'Exception: ',
                            '',
                          );
                        });
                      }
                    },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(submitting ? 'Submitting...' : 'Submit'),
            ),
          ],
        ),
      ),
    );

    commentCtrl.dispose();
  }

  void _showMessage(
    String text, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(text),
        backgroundColor: isError
            ? Colors.red.shade800
            : isSuccess
            ? Colors.green.shade700
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: theme.colorScheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              sliver: SliverToBoxAdapter(child: _buildHeader()),
            ),
            SliverToBoxAdapter(
              child: _isWorkflowDashboard
                  ? _buildWorkflowContainer()
                  : _buildEventsContainer(),
            ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: 80),
            ), // Space for bottom nav/FAB
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OVERVIEW',
                style: TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Dashboard',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.calendar,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMM d, yyyy').format(_currentTime),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEventsContainer() {
    final theme = Theme.of(context);
    final query = DashboardSearchScope.maybeOf(context)?.searchQuery ?? '';
    final visibleEvents = _applySearch(_approvedEvents, query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Events',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Upcoming and scheduled activities',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (visibleEvents.isNotEmpty)
                TextButton(
                  onPressed: () => context.go('/events'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('See All'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildEventsContent(visibleEvents, query),
      ],
    );
  }

  Widget _buildEventsContent(List<Event> visibleEvents, String query) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorState(message: _error!, onRetry: _loadData),
      );
    }

    if (_approvedEvents.isEmpty || visibleEvents.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Center(
          child: Column(
            children: [
              Icon(
                LucideIcons.calendarX,
                size: 48,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                query.trim().isEmpty
                    ? 'No upcoming events found.'
                    : 'No events match your search.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: visibleEvents.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final event = visibleEvents[index];
        return _DashboardEventCard(
          event: event,
          imageUrl: _resolveEventImageUrl(event),
          onTap: () => context.push('/events/${event.id}'),
        );
      },
    );
  }

  Widget _buildWorkflowContainer() {
    final theme = Theme.of(context);
    final query = DashboardSearchScope.maybeOf(context)?.searchQuery ?? '';
    final visibleItems = _applyWorkflowSearch(_workflowItems, query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
               Expanded(
                 child: Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Text(
                       _workflowTitle,
                       style: TextStyle(
                         fontSize: 18,
                         fontWeight: FontWeight.w800,
                         color: theme.colorScheme.onSurface,
                       ),
                     ),
                     const SizedBox(height: 2),
                     Text(
                       _isApproverRole
                           ? 'Review and manage incoming requests'
                           : 'Role-based inbox',
                       style: TextStyle(
                         fontSize: 13,
                         color: theme.colorScheme.onSurfaceVariant,
                       ),
                     ),
                   ],
                 ),
               ),
               if (_isApproverRole)
                 FilledButton.tonal(
                   onPressed: () => context.go('/approvals'),
                   style: FilledButton.styleFrom(
                     visualDensity: VisualDensity.compact,
                     padding: const EdgeInsets.symmetric(horizontal: 16),
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(12),
                     ),
                   ),
                   child: const Text('Inbox'),
                 ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorState(message: _error!, onRetry: _loadData),
          )
        else if (_workflowItems.isEmpty || visibleItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    LucideIcons.inbox,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    visibleItems.isEmpty && _workflowItems.isNotEmpty
                        ? 'No items match your search.'
                        : _workflowEmptyMessage,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visibleItems.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _buildWorkflowCard(visibleItems[index]),
          ),
      ],
    );
  }

  Widget _buildWorkflowCard(dynamic item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = _workflowStatus(item).trim().toLowerCase();
    final actionable = _workflowCanAct(item);
    final eventId = _workflowEventId(item);

    final Color badgeBg;
    final Color badgeFg;
    switch (status) {
      case 'approved':
        badgeBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFDCFCE7);
        badgeFg = isDark ? const Color(0xFF34D399) : const Color(0xFF166534);
        break;
      case 'rejected':
        badgeBg = isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2);
        badgeFg = isDark ? const Color(0xFFF87171) : const Color(0xFF991B1B);
        break;
      case 'clarification':
      case 'clarification_requested':
        badgeBg = isDark ? const Color(0xFF78350F) : const Color(0xFFFEF3C7);
        badgeFg = isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
        break;
      default:
        badgeBg = isDark ? const Color(0xFF1E3A8A) : const Color(0xFFDBEAFE);
        badgeFg = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
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
            children: [
              Expanded(
                child: Text(
                  _workflowItemTitle(item),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  (status == 'clarification' ||
                          status == 'clarification_requested')
                      ? 'CLARIFICATION'
                      : status.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                    color: badgeFg,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                LucideIcons.user,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _workflowRequestedBy(item).isEmpty
                      ? 'Unknown user'
                      : _workflowRequestedBy(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                LucideIcons.clock,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                _workflowDateLabel(item),
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_workflowChannel == 'approval')
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push(
                      '/approval-details/${_workflowRequestId(item)}',
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Details'),
                  ),
                )
              else if (eventId != null && eventId.trim().isNotEmpty)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push('/events/$eventId'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Details'),
                  ),
                ),
              if (actionable) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _openWorkflowDecisionDialog(item),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Take Action'),
                  ),
                ),
              ],
            ],
          ),
        ],
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
        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      ),
      child: Center(
        child: Icon(
          LucideIcons.image,
          size: 32,
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
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
      return (label: 'ONGOING', bg: const Color(0xFFF59E0B), fg: Colors.white);
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
    final status = _statusStyle();

    return Card(
      elevation: isDark ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : Colors.transparent,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _eventPlaceholder(isDark),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status.bg.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: status.fg,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('MMM d, yyyy').format(event.startTime),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        LucideIcons.clock,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('h:mm a').format(event.startTime),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
