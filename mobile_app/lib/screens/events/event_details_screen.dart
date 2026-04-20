import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';

class EventDetailsScreen extends StatefulWidget {
  final String eventId;

  const EventDetailsScreen({super.key, required this.eventId});

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final _api = ApiService();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _detailsData;
  final Set<String> _expandedDepartments = <String>{};

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _onSurface => Theme.of(context).colorScheme.onSurface;
  Color get _muted =>
      _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _border =>
      _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _panel => _isDark
      ? Theme.of(context).colorScheme.surfaceContainerHighest
      : const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '/events/${widget.eventId}/details',
      );
      setState(() {
        _detailsData = res;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> get _event {
    final raw = _detailsData?['event'];
    if (raw is Map<String, dynamic>) return raw;
    return const <String, dynamic>{};
  }

  Map<String, dynamic> get _approval {
    final raw = _detailsData?['approval_request'];
    if (raw is Map<String, dynamic>) return raw;
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _mapList(String key) {
    final raw = _detailsData?[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  String _s(dynamic value, {String fallback = '—'}) {
    if (value == null) return fallback;
    final out = value.toString().trim();
    return out.isEmpty ? fallback : out;
  }

  String _buildAudience(Map<String, dynamic> event) {
    final audience = event['intendedAudience'];
    final other = _s(event['intendedAudienceOther'], fallback: '');
    if (audience is List && audience.isNotEmpty) {
      final items = audience
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        if (other.isNotEmpty) {
          return '${items.join(', ')} ($other)';
        }
        return items.join(', ');
      }
    }
    if (audience is String && audience.trim().isNotEmpty) {
      return audience.trim();
    }
    return other.isNotEmpty ? other : 'Unknown';
  }

  String _buildReviewRole(
    Map<String, dynamic> approval,
    Map<String, dynamic> event,
  ) {
    final requestedTo = _s(
      approval['requested_to'],
      fallback: '',
    ).toLowerCase();
    if (requestedTo.contains('vice')) return 'Vice Chancellor review';
    if (requestedTo.contains('registrar')) return 'Registrar review';
    final budget = (approval['budget'] ?? event['budget']);
    if (budget is num && budget > 30000) return 'Vice Chancellor review';
    return 'Registrar review';
  }

  Future<void> _openExternalLink(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) return;
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  void _closeDetails() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/events');
  }

  String _formatBudget(dynamic budgetValue) {
    if (budgetValue == null) return 'Rs 0';
    final parsed = budgetValue is num
        ? budgetValue.toDouble()
        : double.tryParse(budgetValue.toString());
    if (parsed == null) return 'Rs 0';
    if (parsed % 1 == 0) {
      return 'Rs ${NumberFormat('#,##0').format(parsed)}';
    }
    return 'Rs ${NumberFormat('#,##0.##').format(parsed)}';
  }

  String _formatDateTime(String? dateStr, String? timeStr) {
    if ((dateStr == null || dateStr.trim().isEmpty) &&
        (timeStr == null || timeStr.trim().isEmpty)) {
      return 'N/A';
    }

    final cleanDate = (dateStr ?? '').trim();
    final cleanTime = (timeStr ?? '').trim();

    try {
      final dt = DateTime.tryParse(
        '$cleanDate ${cleanTime.isEmpty ? '00:00' : cleanTime}',
      );
      if (dt != null) {
        return DateFormat('yyyy-MM-dd · h:mm a').format(dt);
      }
    } catch (_) {
      // Keep fallback rendering when parsing fails.
    }
    final combined = [
      cleanDate,
      cleanTime,
    ].where((e) => e.isNotEmpty).join(' · ');
    return combined.isEmpty ? 'N/A' : combined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: _surface,
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Approval request',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  InkWell(
                    onTap: _closeDetails,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(LucideIcons.x, size: 20, color: _muted),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.alertCircle,
                              color: Color(0xFFDC2626),
                              size: 28,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _error ?? 'Failed to load event details',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFB91C1C)),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _fetchDetails,
                              icon: const Icon(LucideIcons.refreshCw, size: 16),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildEventOverview(),
                          const SizedBox(height: 24),
                          _buildApprovalContext(),
                          const SizedBox(height: 24),
                          _buildDiscussion(),
                          const SizedBox(height: 24),
                          _buildRequirements(),
                          const SizedBox(height: 24),
                          _buildNotesAndDescription(),
                        ],
                      ),
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: _surface,
                border: Border(top: BorderSide(color: _border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _closeDetails,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: _border),
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildCard({
    required IconData icon,
    required String title,
    required Widget child,
    double topPadding = 0,
  }) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: 24,
        top: topPadding > 0 ? topPadding : 24,
      ),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(_isDark ? 0.24 : 0.03),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF2563EB), size: 20),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildLabelValue(IconData? icon, String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: _muted),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: _muted,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                valueWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventOverview() {
    final event = _event;
    final approval = _approval;

    final status = _s(event['status'], fallback: 'pending');
    final approvalStatus = _s(approval['status'], fallback: 'pending');
    final budgetValue = approval['budget'] ?? event['budget'];
    final budgetBreakdownLink = _s(
      event['budget_breakdown_web_view_link'] ??
          approval['budget_breakdown_web_view_link'],
      fallback: '',
    );

    return _buildCard(
      icon: LucideIcons.fileText,
      title: 'Event overview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabelValue(
            LucideIcons.flag,
            'Event Name',
            Text(
              _s(event['name'], fallback: 'Untitled'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.mail,
            'Requester',
            Text(
              _s(approval['requester_email'], fallback: 'Unknown'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2563EB),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.user,
            'Facilitator',
            Text(
              _s(event['facilitator'], fallback: _s(approval['facilitator'])),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.mapPin,
            'Venue',
            Text(
              _s(event['venue_name'], fallback: _s(approval['venue_name'])),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.users,
            'Intended Audience',
            Text(
              _buildAudience(event),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.creditCard,
            'Budget',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatBudget(budgetValue),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: budgetBreakdownLink.isEmpty
                      ? null
                      : () => _openExternalLink(budgetBreakdownLink),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Text(
                      budgetBreakdownLink.isEmpty
                          ? 'No budget file'
                          : 'Budget breakdown (PDF)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: budgetBreakdownLink.isEmpty
                            ? const Color(0xFF64748B)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildLabelValue(
            LucideIcons.disc,
            'Status',
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF0D5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    approvalStatus.toUpperCase().replaceAll('_', ' '),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB47B1E),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '· Event:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF0D5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.toUpperCase().replaceAll('_', ' '),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFB47B1E),
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildLabelValue(
            LucideIcons.calendar,
            'Start',
            Text(
              _formatDateTime(event['start_date'], event['start_time']),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.calendar,
            'End',
            Text(
              _formatDateTime(event['end_date'], event['end_time']),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
          _buildLabelValue(
            LucideIcons.alignLeft,
            'Description',
            Text(
              _s(event['description'], fallback: 'No description'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalContext() {
    final approval = _approval;
    final event = _event;
    final status = _s(approval['status'], fallback: 'Pending');

    return _buildCard(
      icon: LucideIcons.shieldCheck,
      title: 'Approval context',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabelValue(
            null,
            'Requested To',
            Text(
              _s(approval['requested_to'], fallback: 'None'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2563EB),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Current Status',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF0D5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB47B1E),
                ),
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Role',
            Text(
              _buildReviewRole(approval, event),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscussion() {
    final threads = _mapList('dept_request_threads');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(LucideIcons.messageCircle, color: Color(0xFF2563EB), size: 20),
            SizedBox(width: 12),
            Text(
              'Discussion',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (threads.isEmpty)
          const Text(
            'No department discussions yet. Use the button below to start a conversation with any department.',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
              height: 1.5,
            ),
          )
        else
          ...threads.map((thread) {
            final conversationId = _s(thread['id'], fallback: '');
            final label = _s(
              thread['department_label'],
              fallback: _s(thread['department'], fallback: 'Department'),
            );
            final status = _s(
              thread['dept_request_status'],
              fallback: _s(thread['thread_status'], fallback: 'active'),
            );
            final messages = thread['messages'];
            final messageCount = messages is List ? messages.length : 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: conversationId.isEmpty
                    ? null
                    : () => context.go('/chat/$conversationId'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _surface,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.messageSquare,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$label · $messageCount message${messageCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _onSurface,
                          ),
                        ),
                      ),
                      Text(
                        status.replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => context.go('/chat'),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Start new discussion'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF8B5CF6),
            side: const BorderSide(
              color: Color(0xFF8B5CF6),
              width: 1,
              style: BorderStyle.solid,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirements() {
    final items = <({String key, String title, String status, int count})>[];
    final facility = _mapList('facility_requests');
    final marketing = _mapList('marketing_requests');
    final it = _mapList('it_requests');
    final transport = _mapList('transport_requests');

    if (facility.isNotEmpty) {
      items.add((
        key: 'facility',
        title: 'Facility',
        status: _s(facility.first['status'], fallback: 'pending'),
        count: facility.length,
      ));
    }
    if (it.isNotEmpty) {
      items.add((
        key: 'it',
        title: 'IT',
        status: _s(it.first['status'], fallback: 'pending'),
        count: it.length,
      ));
    }
    if (marketing.isNotEmpty) {
      items.add((
        key: 'marketing',
        title: 'Marketing',
        status: _s(marketing.first['status'], fallback: 'pending'),
        count: marketing.length,
      ));
    }
    if (transport.isNotEmpty) {
      items.add((
        key: 'transport',
        title: 'Transport',
        status: _s(transport.first['status'], fallback: 'pending'),
        count: transport.length,
      ));
    }

    if (items.isEmpty) {
      items.add((key: 'iqac', title: 'IQAC', status: 'pending', count: 0));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(LucideIcons.layers, color: Color(0xFF2563EB), size: 20),
            SizedBox(width: 12),
            Text(
              'Requirements by department',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Department requirement statuses for your event.',
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        ...items.map((item) {
          final isOpen = _expandedDepartments.contains(item.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                setState(() {
                  if (isOpen) {
                    _expandedDepartments.remove(item.key);
                  } else {
                    _expandedDepartments.add(item.key);
                  }
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isDark ? 0.22 : 0.04),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.checkSquare,
                              size: 18,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _onSurface,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _panel,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: _border),
                              ),
                              child: Text(
                                item.status.replaceAll('_', ' '),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: _muted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isOpen
                                  ? LucideIcons.chevronUp
                                  : LucideIcons.chevronDown,
                              size: 18,
                              color: const Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isOpen) ...[
                      const SizedBox(height: 10),
                      Text(
                        item.count == 0
                            ? 'No requests created yet.'
                            : '${item.count} request${item.count == 1 ? '' : 's'} linked to this event.',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNotesAndDescription() {
    final event = _event;
    final approval = _approval;
    return _buildCard(
      icon: LucideIcons.fileText,
      title: 'Notes and description',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabelValue(
            null,
            'Other Notes',
            Text(
              _s(event['other_notes'], fallback: _s(approval['other_notes'])),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _onSurface,
              ),
            ),
          ),
          _buildLabelValue(
            null,
            'Description',
            Text(
              _s(event['description'], fallback: 'No description'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _onSurface,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
