import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
    'Pending',
    'Upcoming',
    'Ongoing',
    'Completed',
    'Closed',
  ];

  final Map<String, List<Event>> _eventsByTab = {};
  final Map<String, bool> _loading = {};
  final Map<String, String?> _errors = {};
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
        return s == 'pending' || s == 'clarification_requested';
      }).toList();
    }
    return all.where((e) => (e.status).toLowerCase() == status).toList();
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

      final events = (eventData['items'] as List? ?? [])
          .map((e) => Event.fromJson(e))
          .toList();

      final approvals = (approvalData['items'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((a) {
            final status = (a['status'] ?? '').toString().toLowerCase();
            return status == 'pending' || status == 'clarification_requested';
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
              audienceCount: null,
              notes: null,
              pipelineStage: a['pipeline_stage']?.toString(),
              approvalRequestId: (a['id'] ?? '').toString(),
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
    if (stage == 'after_finance') return 'SEND TO REGISTRAR';
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
                : 'Sent to Registrar for final approval.',
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

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadEventsForTab(_tabController.index, force: true);
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
                        Colors.black.withOpacity(0.05),
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
            return const _MyEventsEmptyState();
          }

          return RefreshIndicator(
            onRefresh: () async {
              _eventsByTab.remove(key);
              await _loadEventsForTab(entry.key);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              itemCount: events.length,
              separatorBuilder: (_, __) => const SizedBox(height: 20),
              itemBuilder: (ctx, i) => _EventCard(
                event: events[i],
                onTap: () => context.go('/events/${events[i].id}'),
                approvalForwardLabel: _approvalForwardLabel(events[i]),
                onApprovalForward: () => _forwardApproval(events[i]),
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
  const _MyEventsEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
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
              'No events found.',
              style: TextStyle(
                fontSize: 20, // text-xl
                fontWeight: FontWeight.w800, // font-extrabold
                color: titleColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first event to get started.',
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

  const _EventCard({
    required this.event,
    required this.onTap,
    this.approvalForwardLabel = '',
    this.onApprovalForward,
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
        : const Color(0xFFEFF6FF).withOpacity(0.5); // blue-50/50
    final detailsFg = isDark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB); // blue-600

    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    final statusColor = _getStatusColor(event.status);
    final statusBgColor = _getStatusBgColor(event.status);
    final statusBorderColor = _getStatusBorderColor(event.status);
    final pipelineText = _approvalPipelineText(event);
    final showForwardAction = approvalForwardLabel.trim().isNotEmpty;

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
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
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
                    event.status.toUpperCase(),
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
    if (status == 'clarification_requested') return 'Clarification requested';

    final stage = (value.pipelineStage ?? '').toLowerCase().trim();
    switch (stage) {
      case 'deputy':
        return 'Awaiting Deputy Registrar';
      case 'after_deputy':
        return 'Deputy approved - send to Finance';
      case 'finance':
        return 'Awaiting Finance Team';
      case 'after_finance':
        return 'Finance approved - send to Registrar';
      case 'registrar':
        return 'Awaiting Registrar / Vice Chancellor';
      case 'complete':
        return 'Final approval completed';
      default:
        return 'Awaiting approval';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFD97706); // amber-600
      case 'upcoming':
        return const Color(0xFF2563EB); // blue-600
      case 'ongoing':
        return const Color(0xFF4F46E5); // indigo-600
      case 'completed':
        return const Color(0xFF059669); // emerald-600
      default:
        return const Color(0xFF475569); // slate-600
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFFFBEB); // amber-50
      case 'upcoming':
        return const Color(0xFFEFF6FF); // blue-50
      case 'ongoing':
        return const Color(0xFFEEF2FF); // indigo-50
      case 'completed':
        return const Color(0xFFECFDF5); // emerald-50
      default:
        return const Color(0xFFF8FAFC); // slate-50
    }
  }

  Color _getStatusBorderColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFEF3C7); // amber-100
      case 'upcoming':
        return const Color(0xFFDBEAFE); // blue-100
      case 'ongoing':
        return const Color(0xFFE0E7FF); // indigo-100
      case 'completed':
        return const Color(0xFFD1FAE5); // emerald-100
      default:
        return const Color(0xFFF1F5F9); // slate-100
    }
  }
}
