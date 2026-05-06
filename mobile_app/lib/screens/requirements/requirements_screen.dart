import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
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
        _errorInbox = e.toString();
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
    final date = (startDate ?? '').trim();
    final time = (startTime ?? '').trim();
    if (date.isEmpty) return false;
    final parsed = DateTime.tryParse('$date ${time.isEmpty ? '00:00' : time}');
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now());
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
    // Matching website functionality: uploads are never locked by date.
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
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail']?.toString().trim();
        if (detail != null && detail.isNotEmpty) return detail;
      } else if (data is String && data.trim().isNotEmpty) {
        return data.trim();
      }
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
    }
    final text = error.toString().trim();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length).trim();
    }
    return text.isEmpty ? 'Something went wrong.' : text;
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
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openDecisionDialog(dynamic item) async {
    final status = _itemStatus(item);
    if (!_canTakeAction(status)) return;

    String selected = 'approved';
    final commentCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Update $_channelLabel request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Decision',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'approved', child: Text('Noted')),
                    DropdownMenuItem(value: 'rejected', child: Text('Reject')),
                    DropdownMenuItem(
                      value: 'clarification_requested',
                      child: Text('Clarification'),
                    ),
                  ],
                  onChanged: (value) {
                    setLocal(() => selected = value ?? 'approved');
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: selected == 'approved'
                        ? 'Comment (optional)'
                        : 'Comment (required)',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
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
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Requirements'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [Tab(text: _channelLabel)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          if (!_showInbox)
            const EmptyState(
              icon: Icons.lock_outline,
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
                    const Icon(Icons.error_outline, color: AppColors.error),
                    const SizedBox(height: 10),
                    Text(
                      _errorInbox!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _loadInbox,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_inboxItems.isEmpty)
            const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'All caught up',
              message: 'No requirement requests in your inbox.',
            )
          else
            RefreshIndicator(
              onRefresh: _loadInbox,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: _inboxItems.length,
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

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RequestCard(
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
                    ),
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
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
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

  @override
  Widget build(BuildContext context) {
    String title = '';
    String status = '';
    String requestedBy = '';
    String details = '';

    if (item is FacilityRequest) {
      final r = item as FacilityRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      details = [
        if (r.setupDetails != null) 'Setup: ${r.setupDetails}',
        if (r.refreshmentDetails != null)
          'Refreshments: ${r.refreshmentDetails}',
      ].join('\n');
    } else if (item is ITRequest) {
      final r = item as ITRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      details =
          'Mode: ${r.mode.toUpperCase()}${r.paSystem ? ' · Audio System' : ''}${r.projection ? ' · Projection' : ''}';
    } else if (item is MarketingRequest) {
      final r = item as MarketingRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      details = r.items.join(', ');
    } else if (item is TransportRequest) {
      final r = item as TransportRequest;
      title = r.eventTitle;
      status = r.status;
      requestedBy = r.requestedBy;
      details = 'Type: ${r.transportType.replaceAll('_', ' ')}';
    }

    final normalizedStatus = status.trim().toLowerCase();
    final badgeBg = normalizedStatus == 'pending'
        ? const Color(0xFFFEF3C7)
        : normalizedStatus == 'approved'
        ? const Color(0xFFDCFCE7)
        : normalizedStatus == 'rejected'
        ? const Color(0xFFFEE2E2)
        : normalizedStatus == 'clarification' ||
              normalizedStatus == 'clarification_requested'
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFE2E8F0);
    final badgeFg = normalizedStatus == 'pending'
        ? const Color(0xFF92400E)
        : normalizedStatus == 'approved'
        ? const Color(0xFF166534)
        : normalizedStatus == 'rejected'
        ? const Color(0xFF991B1B)
        : normalizedStatus == 'clarification' ||
              normalizedStatus == 'clarification_requested'
        ? const Color(0xFF9F1239)
        : const Color(0xFF334155);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (normalizedStatus == 'clarification' ||
                          normalizedStatus == 'clarification_requested')
                      ? 'CLARIFICATION'
                      : normalizedStatus == 'approved'
                      ? 'NOTED'
                      : normalizedStatus.replaceAll('_', ' ').toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeFg,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                LucideIcons.user,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  requestedBy,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    LucideIcons.info,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    details,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (showUpload)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: OutlinedButton.icon(
                      onPressed: uploadEnabled ? onUpload : null,
                      icon: const Icon(LucideIcons.uploadCloud, size: 16),
                      label: Text('Upload', style: GoogleFonts.inter()),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: OutlinedButton(
                  onPressed: onDetails,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Details',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              if (canTakeAction) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Action',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'No action',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (showUpload && !uploadEnabled && uploadHint.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertCircle,
                    size: 16,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uploadHint,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
