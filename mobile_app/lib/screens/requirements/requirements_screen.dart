import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../constants/approval_ui.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/common/app_widgets.dart';
import '../../widgets/common/marketing_deliverables_upload_dialog.dart';
import '../../services/api_service.dart';

class RequirementsScreen extends StatefulWidget {
  const RequirementsScreen({super.key});

  @override
  State<RequirementsScreen> createState() => _RequirementsScreenState();
}

class _RequirementsScreenState extends State<RequirementsScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  static const List<Map<String, String>> _marketingDeliverableOptions = [
    {'key': 'poster_required', 'type': 'poster', 'label': 'Poster'},
    {'key': 'video_required', 'type': 'video', 'label': 'Videoshoot'},
    {'key': 'linkedin_post', 'type': 'linkedin', 'label': 'Social Media Post'},
    {
      'key': 'photography',
      'type': 'photography',
      'label': 'Photoshoot / Photo upload',
    },
    {'key': 'recording', 'type': 'recording', 'label': 'Video Upload'},
  ];
  late TabController _tabController;
  late String _role;

  List<dynamic> _inboxItems = [];
  bool _loadingInbox = true;
  String? _errorInbox;

  @override
  void initState() {
    super.initState();
    _role = context.read<AuthProvider>().user?.roleKey ?? 'faculty';
    _tabController = TabController(length: 1, vsync: this);
    _loadInbox();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _showInbox =>
      AppConstants.facilityRoles.contains(_role) ||
      AppConstants.marketingRoles.contains(_role) ||
      AppConstants.itRoles.contains(_role) ||
      AppConstants.transportRoles.contains(_role);

  String get _channelLabel {
    if (AppConstants.facilityRoles.contains(_role)) return 'Facility';
    if (AppConstants.marketingRoles.contains(_role)) return 'Marketing';
    if (AppConstants.itRoles.contains(_role)) return 'IT';
    if (AppConstants.transportRoles.contains(_role)) return 'Transport';
    return 'Requirements';
  }

  String get _inboxPath {
    if (AppConstants.facilityRoles.contains(_role)) return '/facility/inbox';
    if (AppConstants.marketingRoles.contains(_role)) return '/marketing/inbox';
    if (AppConstants.itRoles.contains(_role)) return '/it/inbox';
    if (AppConstants.transportRoles.contains(_role)) return '/transport/inbox';
    return '/requirements';
  }

  String _patchPath(String id) {
    if (AppConstants.facilityRoles.contains(_role)) {
      return '/facility/requests/$id';
    }
    if (AppConstants.marketingRoles.contains(_role)) {
      return '/marketing/requests/$id';
    }
    if (AppConstants.transportRoles.contains(_role)) {
      return '/transport/requests/$id';
    }
    return '/it/requests/$id';
  }

  Future<void> _loadInbox() async {
    setState(() => _loadingInbox = true);
    try {
      final data = await _api.get<dynamic>(_inboxPath);
      final items = data is List
          ? data
          : (data is Map<String, dynamic>
                ? (data['items'] as List? ?? [])
                : []);
      setState(() {
        _inboxItems = _parseItems(items);
        _errorInbox = null;
        _loadingInbox = false;
      });
    } catch (e) {
      setState(() {
        _errorInbox = friendlyErrorMessage(
          e,
          fallback: 'Could not load requests. Please try again.',
        );
        _loadingInbox = false;
      });
    }
  }

  List<dynamic> _parseItems(List items) {
    if (AppConstants.facilityRoles.contains(_role)) {
      return items.map((e) => FacilityRequest.fromJson(e)).toList();
    }
    if (AppConstants.marketingRoles.contains(_role)) {
      return items.map((e) => MarketingRequest.fromJson(e)).toList();
    }
    if (AppConstants.transportRoles.contains(_role)) {
      return items.map((e) => TransportRequest.fromJson(e)).toList();
    }
    return items.map((e) => ITRequest.fromJson(e)).toList();
  }

  bool _canTakeAction(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'pending' ||
        normalized == 'clarification' ||
        normalized == 'clarification_requested';
  }

  bool _eventHasStarted(dynamic item) {
    String? startDate;
    String? startTime;
    if (item is FacilityRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
    } else if (item is MarketingRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
    } else if (item is ITRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
    } else if (item is TransportRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
    }
    final parsed = _parseRequestDateTime(startDate, startTime);
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now());
  }

  bool _eventHasEnded(MarketingRequest request) {
    final parsed = _parseRequestDateTime(
      request.endDate ?? request.startDate,
      request.endTime ?? request.startTime,
    );
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now());
  }

  DateTime? _parseRequestDateTime(String? date, String? time) {
    final cleanDate = (date ?? '').trim();
    if (cleanDate.isEmpty) return null;
    final cleanTime = _normalizeTimeToHHMMSS(time);
    return DateTime.tryParse('${cleanDate}T$cleanTime');
  }

  String _normalizeTimeToHHMMSS(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '00:00:00';
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(raw);
    if (match == null) return '00:00:00';
    final hour = int.tryParse(match.group(1) ?? '');
    if (hour == null || hour > 23) return '00:00:00';
    final minute = match.group(2) ?? '00';
    final second = (match.group(3) ?? '00').padLeft(2, '0');
    return '${hour.toString().padLeft(2, '0')}:$minute:$second';
  }

  Map<String, dynamic> _normalizeMarketingRequirements(
    MarketingRequest request,
  ) {
    final req = request.marketingRequirements;
    final pre = req['pre_event'] is Map
        ? Map<String, dynamic>.from(req['pre_event'] as Map)
        : const <String, dynamic>{};
    final during = req['during_event'] is Map
        ? Map<String, dynamic>.from(req['during_event'] as Map)
        : const <String, dynamic>{};
    final post = req['post_event'] is Map
        ? Map<String, dynamic>.from(req['post_event'] as Map)
        : const <String, dynamic>{};

    return {
      'pre_event': {
        'poster': pre['poster'] ?? request.posterRequired,
        'social_media': pre['social_media'] ?? request.linkedinPost,
      },
      'during_event': {
        'photo': during['photo'] ?? request.photography,
        'video': during['video'] ?? request.videoRequired,
      },
      'post_event': {
        'social_media': post['social_media'] ?? false,
        'photo_upload': post['photo_upload'] ?? false,
        'video': post['video'] ?? request.recording,
      },
    };
  }

  Map<String, bool> _marketingDeliverableUploadFlags(MarketingRequest request) {
    final normalized = _normalizeMarketingRequirements(request);
    final pre = normalized['pre_event'] as Map<String, dynamic>;
    final post = normalized['post_event'] as Map<String, dynamic>;
    return {
      'poster_required': pre['poster'] == true,
      'video_required': false,
      'linkedin_post':
          pre['social_media'] == true || post['social_media'] == true,
      'photography': post['photo_upload'] == true,
      'recording': post['video'] == true,
    };
  }

  ({bool locked, String hint}) _marketingDeliverableRowLock(
    String type,
    MarketingRequest request,
  ) {
    if ((request.startDate ?? '').trim().isEmpty) {
      return (locked: true, hint: 'Event schedule unavailable.');
    }

    final normalized = _normalizeMarketingRequirements(request);
    final pre = normalized['pre_event'] as Map<String, dynamic>;
    final post = normalized['post_event'] as Map<String, dynamic>;
    final started = _eventHasStarted(request);
    final ended = _eventHasEnded(request);
    final preSocial = pre['social_media'] == true;
    final postSocial = post['social_media'] == true;

    if (type == 'poster') {
      return started
          ? (locked: true, hint: 'Upload before the event starts.')
          : (locked: false, hint: '');
    }
    if (type == 'linkedin') {
      if (preSocial && !postSocial) {
        return started
            ? (
                locked: true,
                hint: 'Pre-event social posts: upload before the event starts.',
              )
            : (locked: false, hint: '');
      }
      if (postSocial && !preSocial) {
        return !ended
            ? (
                locked: true,
                hint:
                    'Post-event social posts: upload after the event has ended.',
              )
            : (locked: false, hint: '');
      }
      return started && !ended
          ? (
              locked: true,
              hint:
                  'Upload before the event starts or after it ends (not during).',
            )
          : (locked: false, hint: '');
    }
    if (type == 'recording') {
      return !ended
          ? (
              locked: true,
              hint: 'Post-event video: upload after the event has ended.',
            )
          : (locked: false, hint: '');
    }
    if (type == 'photography') {
      return !ended
          ? (
              locked: true,
              hint: 'Post-event photo: upload after the event has ended.',
            )
          : (locked: false, hint: '');
    }
    return (locked: false, hint: '');
  }

  Future<String?> _uploadMarketingDeliverablesBatch({
    required String requestId,
    required Map<String, bool> naByType,
    required Map<String, MultipartFile?> filesByType,
  }) async {
    try {
      final payload = <String, dynamic>{};
      for (final entry in naByType.entries) {
        if (entry.value) {
          payload['na_${entry.key}'] = '1';
        }
      }
      for (final entry in filesByType.entries) {
        final file = entry.value;
        if (file != null) {
          payload['file_${entry.key}'] = file;
        }
      }

      if (payload.isEmpty) {
        return 'Choose at least one file or mark an item as N/A.';
      }

      await _api.postMultipart<Map<String, dynamic>>(
        '/marketing/requests/$requestId/deliverables/batch',
        FormData.fromMap(payload),
      );
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marketing deliverables submitted.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadInbox();
      return null;
    } catch (e) {
      return _extractApiErrorMessage(e);
    }
  }

  String _extractApiErrorMessage(Object error) {
    return friendlyErrorMessage(error);
  }

  Future<void> _connectGoogle() async {
    final res = await _api.get<Map<String, dynamic>>('/calendar/connect-url');
    final url = res['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw Exception('Failed to obtain Google connect URL.');
    }
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      final fallback = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!fallback) {
        throw Exception('Could not open the Google consent page.');
      }
    }
  }

  Future<void> _openMarketingUploadDialog(MarketingRequest request) async {
    final uploadFlags = _marketingDeliverableUploadFlags(request);
    final enabledOptions = _marketingDeliverableOptions
        .where((opt) => uploadFlags[opt['key']] == true)
        .toList();

    if (enabledOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This request only includes during-event marketing. No file uploads are required.',
          ),
        ),
      );
      return;
    }

    final existingByType = <String, MarketingDeliverable>{
      for (final d in request.deliverables) d.type: d,
    };
    final naByType = <String, bool>{
      for (final opt in enabledOptions)
        opt['type']!: existingByType[opt['type']]?.isNa ?? false,
    };
    final fileNameByType = <String, String>{
      for (final opt in enabledOptions)
        if (existingByType[opt['type']]?.isNa != true &&
            (existingByType[opt['type']]?.link ?? '').isNotEmpty)
          opt['type']!: existingByType[opt['type']]!.link!,
    };
    await showMarketingDeliverablesUploadDialog(
      context: context,
      enabledOptions: enabledOptions,
      initialNaByType: naByType,
      initialFileNameByType: fileNameByType,
      rowLock: (type) => _marketingDeliverableRowLock(type, request),
      onUpload: ({required naByType, required filesByType}) =>
          _uploadMarketingDeliverablesBatch(
            requestId: request.id,
            naByType: naByType,
            filesByType: filesByType,
          ),
      onConnectGoogle: _connectGoogle,
      extractErrorMessage: _extractApiErrorMessage,
      eventTitle: request.eventTitle,
    );
  }

  Future<void> _decide(String id, String decision, String comment) async {
    try {
      await _api.patch(
        _patchPath(id),
        data: {'status': decision, 'comment': comment},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approved'
                ? 'Request noted.'
                : decision == 'rejected'
                ? 'Request rejected.'
                : 'Clarification requested.',
          ),
          backgroundColor: decision == 'approved'
              ? AppColors.success
              : AppColors.textSecondary,
        ),
      );
      await _loadInbox();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openDecisionDialog(dynamic item) async {
    final status = _itemStatus(item);
    if (!_canTakeAction(status)) return;

    String selected = 'approved';
    final commentCtrl = TextEditingController();
    final title = _itemTitle(item);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final theme = Theme.of(ctx);
          final isDark = theme.brightness == Brightness.dark;
          final dialogBg = isDark ? const Color(0xFF111827) : Colors.white;
          final panel = isDark ? const Color(0xFF0F172A) : ApprovalUi.panel;
          final border = isDark ? const Color(0xFF334155) : ApprovalUi.border;
          final heading = isDark ? const Color(0xFFE2E8F0) : ApprovalUi.heading;
          final muted = isDark ? const Color(0xFF94A3B8) : ApprovalUi.muted;
          final isApprove = selected == 'approved';
          final isReject = selected == 'rejected';
          final accent = isApprove
              ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF16A34A))
              : isReject
              ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626))
              : (isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309));
          final actionLabel = isApprove
              ? 'Noted'
              : isReject
              ? 'Reject'
              : 'Clarification';

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isApprove
                              ? LucideIcons.checkCircle2
                              : isReject
                              ? LucideIcons.xCircle
                              : LucideIcons.helpCircle,
                          color: accent,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update $_channelLabel request',
                              style: GoogleFonts.poppins(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: heading,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              title.isEmpty ? 'Choose an action' : title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _RequirementDecisionOption(
                    selected: selected == 'approved',
                    icon: LucideIcons.checkCircle2,
                    label: 'Noted',
                    subtitle: 'Mark this requirement as handled.',
                    foreground: const Color(0xFF166534),
                    background: const Color(0xFFECFDF5),
                    border: const Color(0xFFA7F3D0),
                    onTap: () => setLocal(() => selected = 'approved'),
                  ),
                  const SizedBox(height: 10),
                  _RequirementDecisionOption(
                    selected: selected == 'clarification_requested',
                    icon: LucideIcons.helpCircle,
                    label: 'Clarification',
                    subtitle: 'Ask the requester for more information.',
                    foreground: const Color(0xFFB45309),
                    background: const Color(0xFFFFFBEB),
                    border: const Color(0xFFFDE68A),
                    onTap: () =>
                        setLocal(() => selected = 'clarification_requested'),
                  ),
                  const SizedBox(height: 10),
                  _RequirementDecisionOption(
                    selected: selected == 'rejected',
                    icon: LucideIcons.xCircle,
                    label: 'Reject',
                    subtitle: 'Decline this request with a reason.',
                    foreground: const Color(0xFFB91C1C),
                    background: const Color(0xFFFEF2F2),
                    border: const Color(0xFFFECACA),
                    onTap: () => setLocal(() => selected = 'rejected'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: commentCtrl,
                    minLines: 4,
                    maxLines: 6,
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: isApprove
                          ? 'Add an optional message'
                          : isReject
                          ? 'Add rejection reason'
                          : 'Ask for clarification',
                      helperText: isApprove
                          ? 'Optional message sent with the update.'
                          : 'A message is required for this action.',
                      helperStyle: GoogleFonts.inter(
                        color: muted,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: panel,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final comment = commentCtrl.text.trim();
                            if (selected != 'approved' && comment.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Comment is required for reject/clarification.',
                                  ),
                                ),
                              );
                              return;
                            }
                            Navigator.of(ctx).pop();
                            await _decide(_itemId(item), selected, comment);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            actionLabel,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    commentCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = isDark
        ? theme.scaffoldBackgroundColor
        : const Color(0xFFF4F6F8);
    final appBarBg = isDark ? theme.colorScheme.surface : Colors.white;
    final headingColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF1E293B);
    final tabInactive = isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: appBarBg,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: Text(
          'Requirements',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: headingColor,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              isScrollable: false,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: tabInactive,
              labelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(
                  width: 3.0,
                  color: theme.colorScheme.primary,
                ),
                insets: const EdgeInsets.symmetric(horizontal: 16.0),
              ),
              dividerColor: Colors.transparent,
              tabs: [Tab(text: _channelLabel)],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          if (!_showInbox)
            const EmptyState(
              icon: LucideIcons.lock,
              title: 'No access',
              message:
                  'Requirements inbox is available for Facility, IT, Marketing, and Transport roles.',
            )
          else if (_loadingInbox)
            _buildLoading()
          else if (_errorInbox != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.error.withValues(alpha: 0.16)
                            : Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        LucideIcons.alertTriangle,
                        color: Colors.red.shade400,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorInbox!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: isDark
                            ? const Color(0xFFFCA5A5)
                            : Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadInbox,
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF1F2937)
                            : Colors.white,
                        foregroundColor: isDark
                            ? const Color(0xFFE2E8F0)
                            : Colors.grey.shade800,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_inboxItems.isEmpty)
            const EmptyState(
              icon: LucideIcons.checkCircle,
              title: 'All caught up',
              message: 'No requirement requests in your inbox.',
            )
          else
            RefreshIndicator(
              onRefresh: _loadInbox,
              color: Theme.of(context).primaryColor,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                itemCount: _inboxItems.length,
                separatorBuilder: (_, index) => const SizedBox(height: 16),
                itemBuilder: (ctx, i) {
                  final item = _inboxItems[i];
                  final eventId = _itemEventId(item);
                  final status = _itemStatus(item);
                  final canTakeAction =
                      _canTakeAction(status) && !_eventHasStarted(item);
                  bool showUpload = false;
                  bool uploadEnabled = false;
                  String uploadHint = '';

                  if (item is MarketingRequest) {
                    showUpload = true;
                    final flags = _marketingDeliverableUploadFlags(item);
                    final relevant = _marketingDeliverableOptions
                        .where((opt) => flags[opt['key']] == true)
                        .toList();

                    if (relevant.isEmpty) {
                      uploadHint =
                          'No file uploads needed for during-event-only requirements.';
                    } else {
                      final unlocked = relevant
                          .where(
                            (opt) => !_marketingDeliverableRowLock(
                              opt['type']!,
                              item,
                            ).locked,
                          )
                          .toList();
                      uploadEnabled = unlocked.isNotEmpty;
                      if (!uploadEnabled) {
                        uploadHint = _marketingDeliverableRowLock(
                          relevant.first['type']!,
                          item,
                        ).hint;
                      }
                    }
                  }

                  return _RequestCard(
                    item: item,
                    canTakeAction: canTakeAction,
                    onDetails: eventId == null
                        ? null
                        : () => context.push('/events/$eventId'),
                    onUpdate: () => _openDecisionDialog(item),
                    showUpload: showUpload,
                    uploadEnabled: uploadEnabled,
                    uploadHint: uploadHint,
                    onUpload: showUpload
                        ? () => _openMarketingUploadDialog(
                            item as MarketingRequest,
                          )
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _itemId(dynamic item) {
    if (item is FacilityRequest) return item.id;
    if (item is MarketingRequest) return item.id;
    if (item is ITRequest) return item.id;
    if (item is TransportRequest) return item.id;
    return '';
  }

  String? _itemEventId(dynamic item) {
    if (item is FacilityRequest) return item.eventId;
    if (item is MarketingRequest) return item.eventId;
    if (item is ITRequest) return item.eventId;
    if (item is TransportRequest) return item.eventId;
    return null;
  }

  String _itemTitle(dynamic item) {
    if (item is FacilityRequest) return item.eventTitle;
    if (item is MarketingRequest) return item.eventTitle;
    if (item is ITRequest) return item.eventTitle;
    if (item is TransportRequest) return item.eventTitle;
    return '';
  }

  String _itemStatus(dynamic item) {
    if (item is FacilityRequest) return item.status;
    if (item is MarketingRequest) return item.status;
    if (item is ITRequest) return item.status;
    if (item is TransportRequest) return item.status;
    return 'pending';
  }

  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequirementDecisionOption extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final String subtitle;
  final Color foreground;
  final Color background;
  final Color border;
  final VoidCallback onTap;

  const _RequirementDecisionOption({
    required this.selected,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.foreground,
    required this.background,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color darkForeground = switch (label) {
      'Noted' => const Color(0xFF86EFAC),
      'Reject' => const Color(0xFFFCA5A5),
      _ => const Color(0xFFFCD34D),
    };
    final effectiveForeground = isDark ? darkForeground : foreground;
    final optionBg = selected
        ? (isDark ? effectiveForeground.withValues(alpha: 0.14) : background)
        : (isDark ? const Color(0xFF0F172A) : ApprovalUi.panel);
    final optionBorder = selected
        ? (isDark ? effectiveForeground.withValues(alpha: 0.34) : border)
        : (isDark ? const Color(0xFF334155) : ApprovalUi.border);
    final iconBg = selected
        ? (isDark
              ? effectiveForeground.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.78))
        : (isDark ? const Color(0xFF111827) : Colors.white);
    final subtitleColor = isDark ? const Color(0xFFCBD5E1) : ApprovalUi.text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: optionBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: optionBorder, width: selected ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: effectiveForeground, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: effectiveForeground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        color: subtitleColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(LucideIcons.check, color: effectiveForeground, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final dynamic item;
  final bool canTakeAction;
  final VoidCallback? onDetails;
  final VoidCallback? onUpdate;
  final bool showUpload;
  final bool uploadEnabled;
  final String uploadHint;
  final VoidCallback? onUpload;

  const _RequestCard({
    required this.item,
    required this.canTakeAction,
    this.onDetails,
    this.onUpdate,
    this.showUpload = false,
    this.uploadEnabled = false,
    this.uploadHint = '',
    this.onUpload,
  });

  String _getInitials(String email) {
    if (email.isEmpty) return '?';
    final parts = email.split('@')[0].split('.');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return email.substring(0, 1).toUpperCase();
  }

  String _getId(dynamic item) {
    if (item is FacilityRequest) return item.id;
    if (item is MarketingRequest) return item.id;
    if (item is ITRequest) return item.id;
    if (item is TransportRequest) return item.id;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF172033) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : Colors.grey.shade100;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500;
    final metaBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final metaBorder = isDark
        ? const Color(0xFF273449)
        : const Color(0xFFF1F5F9);
    final metaText = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
    final detailText = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF334155);
    final dividerColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9);
    final warningBg = isDark
        ? const Color(0xFFEA580C).withValues(alpha: 0.14)
        : const Color(0xFFFFF7ED);
    final warningBorder = isDark
        ? const Color(0xFFEA580C).withValues(alpha: 0.28)
        : const Color(0xFFFFEDD5);
    final warningText = isDark
        ? const Color(0xFFFDBA74)
        : const Color(0xFFC2410C);

    String title = '';
    String status = '';
    String requestedBy = '';
    String details = '';
    IconData categoryIcon = LucideIcons.layoutTemplate;
    Color categoryColor = Theme.of(context).primaryColor;

    if (item is FacilityRequest) {
      final r = item as FacilityRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      categoryIcon = LucideIcons.building2;
      categoryColor = const Color(0xFF0284C7); // Light Blue
      details = [
        if (r.setupDetails != null) 'Setup: ${r.setupDetails}',
        if (r.refreshmentDetails != null)
          'Refreshments: ${r.refreshmentDetails}',
      ].join(' • ');
    } else if (item is ITRequest) {
      final r = item as ITRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      categoryIcon = LucideIcons.monitor;
      categoryColor = const Color(0xFF7C3AED); // Purple
      details =
          'Mode: ${r.mode.toUpperCase()}${r.paSystem ? ' • Audio' : ''}${r.projection ? ' • Projection' : ''}';
    } else if (item is MarketingRequest) {
      final r = item as MarketingRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      categoryIcon = LucideIcons.megaphone;
      categoryColor = const Color(0xFFDB2777); // Pink
      details = r.items.join(', ');
    } else if (item is TransportRequest) {
      final r = item as TransportRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      categoryIcon = LucideIcons.car;
      categoryColor = const Color(0xFFEA580C); // Orange
      details = r.transportType.replaceAll('_', ' ').toUpperCase();
    }

    final normalizedStatus = status.trim().toLowerCase();

    // Modern badge coloring
    final Color badgeBg;
    final Color badgeFg;

    if (normalizedStatus == 'pending') {
      badgeBg = isDark
          ? const Color(0xFFD97706).withValues(alpha: 0.16)
          : const Color(0xFFFFFBEB);
      badgeFg = const Color(0xFFD97706);
    } else if (normalizedStatus == 'approved') {
      badgeBg = isDark
          ? const Color(0xFF16A34A).withValues(alpha: 0.16)
          : const Color(0xFFF0FDF4);
      badgeFg = const Color(0xFF16A34A);
    } else if (normalizedStatus == 'rejected') {
      badgeBg = isDark
          ? const Color(0xFFDC2626).withValues(alpha: 0.16)
          : const Color(0xFFFEF2F2);
      badgeFg = const Color(0xFFDC2626);
    } else if (normalizedStatus == 'clarification' ||
        normalizedStatus == 'clarification_requested') {
      badgeBg = isDark
          ? const Color(0xFFE11D48).withValues(alpha: 0.16)
          : const Color(0xFFFEF2F2);
      badgeFg = const Color(0xFFE11D48);
    } else {
      badgeBg = metaBg;
      badgeFg = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: cardBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(categoryIcon, size: 20, color: categoryColor),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Request ID: ${_getId(item).substring(0, 8)}...',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: badgeFg.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    (normalizedStatus == 'clarification' ||
                            normalizedStatus == 'clarification_requested')
                        ? 'CLARIFICATION'
                        : normalizedStatus == 'approved'
                        ? 'NOTED'
                        : normalizedStatus.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: badgeFg,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Metadata section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: metaBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: metaBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Theme.of(
                          context,
                        ).primaryColor.withValues(alpha: 0.15),
                        child: Text(
                          _getInitials(requestedBy),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          requestedBy,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: metaText,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: dividerColor),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.list, size: 16, color: muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            details,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: detailText,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Upload Warning
          if (showUpload && !uploadEnabled && uploadHint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: warningBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: warningBorder),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 16, color: warningText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        uploadHint,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: warningText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
          Divider(height: 1, color: dividerColor),

          // Actions section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                if (showUpload)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: OutlinedButton.icon(
                        onPressed: uploadEnabled ? onUpload : null,
                        icon: const Icon(LucideIcons.uploadCloud, size: 16),
                        label: Text(
                          'Upload',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: detailText,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: isDark
                                ? const Color(0xFF475569)
                                : const Color(0xFFCBD5E1),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onDetails,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: detailText,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: isDark
                            ? const Color(0xFF475569)
                            : const Color(0xFFCBD5E1),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Details',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (canTakeAction) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? const Color(0xFF2563EB)
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Action',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            LucideIcons.checkCircle2,
                            size: 16,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Processed',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
