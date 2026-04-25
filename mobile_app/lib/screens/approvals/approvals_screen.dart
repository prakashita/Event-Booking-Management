import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../constants/approval_ui.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/approval_widgets.dart';
import '../../widgets/common/app_widgets.dart';

enum _DecisionAction { approve, reject, clarify }

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen>
    with SingleTickerProviderStateMixin {
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

  final _api = ApiService();
  final _searchCtrl = TextEditingController();

  late TabController _tabController;
  late String _roleKey;

  List<ApprovalRequest> _inbox = [];
  List<dynamic> _departmentInbox = [];

  bool _loadingInbox = true;
  bool _loadingDepartment = false;
  bool _refreshing = false;

  String? _departmentError;

  bool get _isApproverRole => AppConstants.approvalRoles.contains(_roleKey);
  bool get _isFacilityRole => AppConstants.facilityRoles.contains(_roleKey);
  bool get _isMarketingRole => AppConstants.marketingRoles.contains(_roleKey);
  bool get _isItRole => AppConstants.itRoles.contains(_roleKey);
  bool get _isTransportRole => AppConstants.transportRoles.contains(_roleKey);
  bool get _isDepartmentRole =>
      _isFacilityRole || _isMarketingRole || _isItRole || _isTransportRole;

  bool get _canAccess => _isApproverRole || _isDepartmentRole;

  String get _departmentLabel {
    if (_isFacilityRole) return 'Facility Manager';
    if (_isMarketingRole) return 'Marketing';
    if (_isItRole) return 'IT';
    if (_isTransportRole) return 'Transport';
    return 'Department';
  }

  String get _departmentInboxPath {
    if (_isFacilityRole) return '/facility/inbox';
    if (_isMarketingRole) return '/marketing/inbox';
    if (_isItRole) return '/it/inbox';
    if (_isTransportRole) return '/transport/inbox';
    return '';
  }

  @override
  void initState() {
    super.initState();
    _roleKey = (context.read<AuthProvider>().user?.roleKey ?? '')
        .toLowerCase()
        .trim();
    _tabController = TabController(length: 1, vsync: this);

    if (_canAccess) {
      if (_isApproverRole) {
        _loadInbox();
      } else {
        _loadDepartmentInbox();
      }
    } else {
      _loadingInbox = false;
      _loadingDepartment = false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInbox() async {
    setState(() => _loadingInbox = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/approvals/inbox');
      setState(() {
        _inbox = (data['items'] as List? ?? [])
            .map((e) => ApprovalRequest.fromJson(e))
            .toList();
        _loadingInbox = false;
      });
    } catch (_) {
      setState(() => _loadingInbox = false);
    }
  }

  Future<void> _loadDepartmentInbox() async {
    setState(() {
      _loadingDepartment = true;
      _departmentError = null;
    });

    try {
      final data = await _api.get<dynamic>(_departmentInboxPath);
      final items = data is List
          ? data
          : (data is Map<String, dynamic>
                ? (data['items'] as List? ?? [])
                : const []);
      setState(() {
        _departmentInbox = _parseDepartmentItems(items);
        _loadingDepartment = false;
      });
    } catch (e) {
      setState(() {
        _departmentError = _extractApiErrorMessage(e);
        _loadingDepartment = false;
      });
    }
  }

  List<dynamic> _parseDepartmentItems(List items) {
    if (_isFacilityRole) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(FacilityRequest.fromJson)
          .toList();
    }
    if (_isMarketingRole) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(MarketingRequest.fromJson)
          .toList();
    }
    if (_isTransportRole) {
      return items
          .whereType<Map<String, dynamic>>()
          .map(TransportRequest.fromJson)
          .toList();
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(ITRequest.fromJson)
        .toList();
  }

  bool _isActionable(ApprovalRequest req) {
    final status = req.status.trim().toLowerCase();
    return status == 'pending' ||
        status == 'clarification' ||
        status == 'clarification_requested';
  }

  bool _canTakeDepartmentAction(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'pending' ||
        normalized == 'clarification' ||
        normalized == 'clarification_requested';
  }

  int get _pendingCount => _inbox.where((r) => _isActionable(r)).length;

  int get _departmentPendingCount => _departmentInbox
      .where((item) => _canTakeDepartmentAction(_departmentStatus(item)))
      .length;

  String _decisionStatus(_DecisionAction action) {
    switch (action) {
      case _DecisionAction.approve:
        return 'approved';
      case _DecisionAction.reject:
        return 'rejected';
      case _DecisionAction.clarify:
        return 'clarification_requested';
    }
  }

  String _decisionLabel(_DecisionAction action) {
    switch (action) {
      case _DecisionAction.approve:
        return 'Approve';
      case _DecisionAction.reject:
        return 'Reject';
      case _DecisionAction.clarify:
        return 'Clarification';
    }
  }

  Future<void> _handleDecision(
    ApprovalRequest req,
    _DecisionAction action,
  ) async {
    final isApprove = action == _DecisionAction.approve;
    final isReject = action == _DecisionAction.reject;

    final confirmed = await showConfirmDialog(
      context,
      title: '${_decisionLabel(action)} Event',
      message: isApprove
          ? '${_decisionLabel(action)} "${req.eventTitle}"?'
          : '${_decisionLabel(action)} "${req.eventTitle}"? Please provide a comment for the requester.',
      confirmLabel: _decisionLabel(action),
      isDestructive: isReject,
    );
    if (confirmed != true || !mounted) return;

    String? comment;
    if (!isApprove) {
      comment = await _promptDecisionComment(
        title: action == _DecisionAction.reject
            ? 'Reject request'
            : 'Request clarification',
        hint: action == _DecisionAction.reject
            ? 'Add rejection reason'
            : 'Ask for clarification',
      );
      if (!mounted || comment == null) return;
      if (comment.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == _DecisionAction.reject
                  ? 'Comment is required when rejecting a request.'
                  : 'Comment is required when requesting clarification.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }

    try {
      final updated = await _api.patch<Map<String, dynamic>>(
        '/approvals/${req.id}',
        data: {
          'status': _decisionStatus(action),
          if ((comment ?? '').trim().isNotEmpty) 'comment': comment!.trim(),
        },
      );

      final status = (updated['status'] ?? '').toString().toLowerCase();
      final stage = (updated['pipeline_stage'] ?? '').toString().toLowerCase();
      String message;
      if (action == _DecisionAction.approve && stage == 'after_deputy') {
        message =
            'Approved at Deputy stage. Requester can now send to Finance.';
      } else if (action == _DecisionAction.approve &&
          stage == 'after_finance') {
        message =
            'Approved at Finance stage. Requester can now send to the final approver.';
      } else if (action == _DecisionAction.approve && status == 'approved') {
        message = 'Final approval completed.';
      } else if (action == _DecisionAction.clarify) {
        message = 'Clarification requested from requester.';
      } else {
        message = isApprove ? 'Request approved.' : 'Request rejected.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isApprove
                ? AppColors.success
                : AppColors.textSecondary,
          ),
        );
        _inbox = [];
        _loadInbox();
      }
    } catch (e) {
      if (mounted) {
        final message = _extractApiErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _extractApiErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        if (detail is List && detail.isNotEmpty) {
          final joined = detail
              .map((e) {
                if (e is Map<String, dynamic>) {
                  return (e['msg'] ?? e.toString()).toString();
                }
                return e.toString();
              })
              .where((e) => e.trim().isNotEmpty)
              .join(' ')
              .trim();
          if (joined.isNotEmpty) return joined;
        }
      } else if (data is String && data.trim().isNotEmpty) {
        return data.trim();
      }
      return error.message ?? 'Request failed. Please try again.';
    }
    return error.toString();
  }

  Future<void> _refreshActiveTab() async {
    setState(() => _refreshing = true);
    try {
      if (_isApproverRole) {
        await _loadInbox();
      } else {
        await _loadDepartmentInbox();
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  List<ApprovalRequest> _applyApprovalSearch(List<ApprovalRequest> source) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((item) {
      return item.eventTitle.toLowerCase().contains(query) ||
          item.requestedBy.toLowerCase().contains(query) ||
          item.requestedTo.toLowerCase().contains(query) ||
          (item.description ?? '').toLowerCase().contains(query);
    }).toList();
  }

  List<dynamic> _applyDepartmentSearch(List<dynamic> source) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((item) {
      final values = [
        _departmentTitle(item),
        _departmentRequestedBy(item),
        _departmentDetails(item),
        _departmentStatus(item),
      ];
      return values.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  Future<String?> _promptDecisionComment({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
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
    final startDate = (request.startDate ?? '').trim();
    if (startDate.isEmpty) {
      return (locked: true, hint: 'Event schedule unavailable.');
    }

    final req = _normalizeMarketingRequirements(request);
    final pre = req['pre_event'] as Map<String, dynamic>;
    final post = req['post_event'] as Map<String, dynamic>;
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
      await _loadDepartmentInbox();
      return null;
    } catch (e) {
      final message = _extractApiErrorMessage(e);
      if (message.toLowerCase().contains('google')) {
        return 'Google not connected';
      }
      return message;
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
            'This request does not need any uploadable deliverables yet.',
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
    final filesByType = <String, MultipartFile?>{
      for (final opt in enabledOptions) opt['type']!: null,
    };
    final fileNameByType = <String, String>{
      for (final opt in enabledOptions)
        if (existingByType[opt['type']]?.isNa != true &&
            (existingByType[opt['type']]?.link ?? '').isNotEmpty)
          opt['type']!: existingByType[opt['type']]!.link!,
    };
    var submitStatus = 'idle';
    var submitError = '';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final hasSelection = enabledOptions.any((opt) {
            final type = opt['type']!;
            final lock = _marketingDeliverableRowLock(type, request);
            if (lock.locked) return false;
            return naByType[type] == true || filesByType[type] != null;
          });

          return AlertDialog(
            title: const Text('Upload Deliverables'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final opt in enabledOptions) ...[
                    Builder(
                      builder: (_) {
                        final type = opt['type']!;
                        final lock = _marketingDeliverableRowLock(
                          type,
                          request,
                        );
                        final fileName = fileNameByType[type];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                opt['label']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (lock.locked) ...[
                                const SizedBox(height: 4),
                                Text(
                                  lock.hint,
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          lock.locked || naByType[type] == true
                                          ? null
                                          : () async {
                                              final pick = await FilePicker
                                                  .platform
                                                  .pickFiles(
                                                    withData: kIsWeb,
                                                    withReadStream: !kIsWeb,
                                                  );
                                              final file = pick?.files.first;
                                              if (file == null) return;

                                              MultipartFile? multipart;
                                              if (file.path != null &&
                                                  file.path!
                                                      .trim()
                                                      .isNotEmpty) {
                                                multipart =
                                                    await MultipartFile.fromFile(
                                                      file.path!,
                                                      filename: file.name,
                                                    );
                                              } else if (file.bytes != null) {
                                                multipart =
                                                    MultipartFile.fromBytes(
                                                      file.bytes!,
                                                      filename: file.name,
                                                    );
                                              } else if (file.readStream !=
                                                  null) {
                                                multipart =
                                                    MultipartFile.fromStream(
                                                      () => file.readStream!,
                                                      file.size,
                                                      filename: file.name,
                                                    );
                                              }
                                              if (multipart == null) return;
                                              setLocal(() {
                                                filesByType[type] = multipart;
                                                fileNameByType[type] =
                                                    file.name;
                                                naByType[type] = false;
                                              });
                                            },
                                      icon: const Icon(Icons.upload_file),
                                      label: Text(
                                        fileName == null || fileName.isEmpty
                                            ? 'Choose file'
                                            : fileName,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: naByType[type] == true,
                                        onChanged: lock.locked
                                            ? null
                                            : (value) {
                                                setLocal(() {
                                                  naByType[type] =
                                                      value == true;
                                                  if (value == true) {
                                                    filesByType[type] = null;
                                                    fileNameByType[type] =
                                                        'N/A';
                                                  } else if (fileNameByType[type] ==
                                                      'N/A') {
                                                    fileNameByType.remove(type);
                                                  }
                                                });
                                              },
                                      ),
                                      const Text('N/A'),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  if (submitStatus == 'error') ...[
                    const SizedBox(height: 12),
                    Text(
                      submitError,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12,
                      ),
                    ),
                    if (submitError == 'Google not connected') ...[
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () async {
                          try {
                            await _connectGoogle();
                          } catch (e) {
                            if (!ctx.mounted) return;
                            setLocal(() {
                              submitError = _extractApiErrorMessage(e);
                            });
                          }
                        },
                        child: const Text('Connect Google'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submitStatus == 'loading' || !hasSelection
                    ? null
                    : () async {
                        setLocal(() {
                          submitStatus = 'loading';
                          submitError = '';
                        });
                        final error = await _uploadMarketingDeliverablesBatch(
                          requestId: request.id,
                          naByType: naByType,
                          filesByType: filesByType,
                        );
                        if (!ctx.mounted) return;
                        if (error == null) {
                          Navigator.of(ctx).pop();
                          return;
                        }
                        setLocal(() {
                          submitStatus = 'error';
                          submitError = error;
                        });
                      },
                child: Text(submitStatus == 'loading' ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _decideDepartment(
    String id,
    String decision,
    String comment,
  ) async {
    try {
      await _api.patch<Map<String, dynamic>>(
        _departmentPatchPath(id),
        data: {'status': decision, 'comment': comment},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approved'
                ? 'Request approved.'
                : decision == 'rejected'
                ? 'Request rejected.'
                : 'Clarification requested.',
          ),
          backgroundColor: decision == 'approved'
              ? AppColors.success
              : AppColors.textSecondary,
        ),
      );
      await _loadDepartmentInbox();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_extractApiErrorMessage(e)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _departmentPatchPath(String id) {
    if (_isFacilityRole) return '/facility/requests/$id';
    if (_isMarketingRole) return '/marketing/requests/$id';
    if (_isTransportRole) return '/transport/requests/$id';
    return '/it/requests/$id';
  }

  Future<void> _openDepartmentDecisionDialog(dynamic item) async {
    final status = _departmentStatus(item);
    if (!_canTakeDepartmentAction(status)) return;

    String selected = 'approved';
    final commentCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Update $_departmentLabel request'),
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
                    DropdownMenuItem(value: 'approved', child: Text('Approve')),
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
            FilledButton(
              onPressed: () async {
                final comment = commentCtrl.text.trim();
                if (selected != 'approved' && comment.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Comment is required for reject or clarification.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                await _decideDepartment(_departmentId(item), selected, comment);
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
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

  bool _eventHasEnded(dynamic item) {
    String? endDate;
    String? endTime;
    if (item is FacilityRequest) {
      endDate = item.endDate;
      endTime = item.endTime;
    } else if (item is MarketingRequest) {
      endDate = item.endDate;
      endTime = item.endTime;
    } else if (item is ITRequest) {
      endDate = item.endDate;
      endTime = item.endTime;
    } else if (item is TransportRequest) {
      endDate = item.endDate;
      endTime = item.endTime;
    }
    final date = (endDate ?? '').trim();
    final time = (endTime ?? '').trim();
    if (date.isEmpty) return false;
    final parsed = DateTime.tryParse('$date ${time.isEmpty ? '23:59' : time}');
    if (parsed == null) return false;
    return !parsed.isAfter(DateTime.now());
  }

  String _departmentId(dynamic item) {
    if (item is FacilityRequest) return item.id;
    if (item is MarketingRequest) return item.id;
    if (item is ITRequest) return item.id;
    if (item is TransportRequest) return item.id;
    return '';
  }

  String? _departmentEventId(dynamic item) {
    if (item is FacilityRequest) return item.eventId;
    if (item is MarketingRequest) return item.eventId;
    if (item is ITRequest) return item.eventId;
    if (item is TransportRequest) return item.eventId;
    return null;
  }

  String _departmentStatus(dynamic item) {
    if (item is FacilityRequest) return item.status;
    if (item is MarketingRequest) return item.status;
    if (item is ITRequest) return item.status;
    if (item is TransportRequest) return item.status;
    return 'pending';
  }

  String _departmentTitle(dynamic item) {
    if (item is FacilityRequest) return item.eventTitle;
    if (item is MarketingRequest) return item.eventTitle;
    if (item is ITRequest) return item.eventTitle;
    if (item is TransportRequest) return item.eventTitle;
    return 'Untitled';
  }

  String _departmentRequestedBy(dynamic item) {
    if (item is FacilityRequest) return item.requestedBy;
    if (item is MarketingRequest) return item.requestedBy;
    if (item is ITRequest) return item.requestedBy;
    if (item is TransportRequest) return item.requestedBy;
    return '';
  }

  String _departmentDetails(dynamic item) {
    if (item is FacilityRequest) {
      return [
        if ((item.setupDetails ?? '').trim().isNotEmpty)
          'Setup: ${item.setupDetails}',
        if ((item.refreshmentDetails ?? '').trim().isNotEmpty)
          'Refreshments: ${item.refreshmentDetails}',
      ].join('\n');
    }
    if (item is ITRequest) {
      return 'Mode: ${item.mode.toUpperCase()}'
          '${item.paSystem ? ' · PA System' : ''}'
          '${item.projection ? ' · Projection' : ''}';
    }
    if (item is MarketingRequest) {
      return item.items.join(', ');
    }
    if (item is TransportRequest) {
      return 'Type: ${item.transportType.replaceAll('_', ' ')}';
    }
    return '';
  }

  String? _departmentSchedule(dynamic item) {
    String? startDate;
    String? startTime;
    String? endTime;
    if (item is FacilityRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
      endTime = item.endTime;
    } else if (item is MarketingRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
      endTime = item.endTime;
    } else if (item is ITRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
      endTime = item.endTime;
    } else if (item is TransportRequest) {
      startDate = item.startDate;
      startTime = item.startTime;
      endTime = item.endTime;
    }
    if ((startDate ?? '').isEmpty) return null;
    final pieces = [
      startDate!,
      if ((startTime ?? '').isNotEmpty) startTime!,
      if ((endTime ?? '').isNotEmpty) '→ $endTime',
    ];
    return pieces.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccess) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Access denied. This page is available to approval workflow roles only.',
          ),
        ),
      );
    }

    final tabIndex = _tabController.index;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Approvals',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _refreshing ? null : _refreshActiveTab,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        icon: AnimatedRotation(
                          turns: _refreshing ? 0.35 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: const Icon(Icons.refresh),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: _isApproverRole
                          ? 'Search events, requester, email...'
                          : 'Search requests, requester, status...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFF4F46E5),
                    labelColor: const Color(0xFF4F46E5),
                    unselectedLabelColor: const Color(0xFF64748B),
                    isScrollable: !_isApproverRole,
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isApproverRole
                                  ? 'Approval Requests'
                                  : _departmentLabel,
                            ),
                            const SizedBox(width: 6),
                            if ((_isApproverRole
                                    ? _pendingCount
                                    : _departmentPendingCount) >
                                0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF43F5E),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${_isApproverRole ? _pendingCount : _departmentPendingCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _isApproverRole
                      ? _buildApprovalList(
                          loading: _loadingInbox,
                          source: _inbox,
                          emptyIcon: Icons.inbox_outlined,
                          emptyTitle: 'Inbox is empty',
                          emptyMessage: 'No pending approval requests.',
                          showActions: true,
                        )
                      : _buildDepartmentList(),
                ],
              ),
            ),
            if (tabIndex == 0) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalList({
    required bool loading,
    required List<ApprovalRequest> source,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptyMessage,
    required bool showActions,
  }) {
    final requests = _applyApprovalSearch(source);
    if (loading) return _buildLoadingList();

    return RefreshIndicator(
      onRefresh: _refreshActiveTab,
      child: requests.isEmpty
          ? EmptyState(
              icon: emptyIcon,
              title: emptyTitle,
              message: emptyMessage,
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              itemCount: requests.length,
              itemBuilder: (ctx, i) {
                final req = requests[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ApprovalCard(
                    request: req,
                    showActions: showActions && _isActionable(req),
                    onDetails: () =>
                        context.push('/approval-details/${req.id}'),
                    onDecision: (action) => _handleDecision(req, action),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildDepartmentList() {
    if (_loadingDepartment) return _buildLoadingList();
    if (_departmentError != null) {
      return ErrorState(
        message: _departmentError!,
        onRetry: _loadDepartmentInbox,
      );
    }

    final requests = _applyDepartmentSearch(_departmentInbox);
    return RefreshIndicator(
      onRefresh: _refreshActiveTab,
      child: requests.isEmpty
          ? EmptyState(
              icon: Icons.inbox_outlined,
              title: 'Inbox is empty',
              message: 'No $_departmentLabel requests are waiting right now.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              itemCount: requests.length,
              itemBuilder: (ctx, i) {
                final item = requests[i];
                final eventId = _departmentEventId(item);
                final canTakeAction =
                    _canTakeDepartmentAction(_departmentStatus(item)) &&
                    !_eventHasStarted(item);
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
                        'No uploadable deliverables are needed for this request.';
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
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DepartmentApprovalCard(
                    title: _departmentTitle(item),
                    status: _departmentStatus(item),
                    requestedBy: _departmentRequestedBy(item),
                    details: _departmentDetails(item),
                    schedule: _departmentSchedule(item),
                    canTakeAction: canTakeAction,
                    onDetails: eventId == null
                        ? null
                        : () => context.push('/events/$eventId'),
                    onUpdate: () => _openDepartmentDecisionDialog(item),
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
    );
  }

  Widget _buildLoadingList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 5,
      itemBuilder: (_, i) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: ShimmerBox(width: double.infinity, height: 130, radius: 12),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final ApprovalRequest request;
  final bool showActions;
  final VoidCallback? onDetails;
  final Future<void> Function(_DecisionAction action)? onDecision;

  const _ApprovalCard({
    required this.request,
    required this.showActions,
    this.onDetails,
    this.onDecision,
  });

  Future<void> _openActionSheet(BuildContext context) async {
    if (onDecision == null) return;
    final selected = await showModalBottomSheet<_DecisionAction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        final bottomInset = mediaQuery.viewInsets.bottom;
        final maxHeight = mediaQuery.size.height * 0.82;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: ApprovalUi.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Take Action',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: ApprovalUi.heading,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose how you want to handle "${request.eventTitle}".',
                        style: const TextStyle(
                          fontSize: 14,
                          color: ApprovalUi.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _DecisionSheetOption(
                        icon: Icons.check_circle_rounded,
                        label: 'Approve',
                        subtitle: 'Accept this request and move it forward.',
                        foreground: const Color(0xFF166534),
                        background: const Color(0xFFECFDF5),
                        border: const Color(0xFFA7F3D0),
                        onTap: () => Navigator.of(sheetContext).pop(
                          _DecisionAction.approve,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DecisionSheetOption(
                        icon: Icons.help_center_rounded,
                        label: 'Clarification',
                        subtitle: 'Ask the requester for more information.',
                        foreground: const Color(0xFFB45309),
                        background: const Color(0xFFFFFBEB),
                        border: const Color(0xFFFDE68A),
                        onTap: () => Navigator.of(sheetContext).pop(
                          _DecisionAction.clarify,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DecisionSheetOption(
                        icon: Icons.cancel_rounded,
                        label: 'Reject',
                        subtitle: 'Decline this request with a reason.',
                        foreground: const Color(0xFFB91C1C),
                        background: const Color(0xFFFEF2F2),
                        border: const Color(0xFFFECACA),
                        onTap: () => Navigator.of(sheetContext).pop(
                          _DecisionAction.reject,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await onDecision!(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 430;

    return ApprovalCardShell(
      padding: EdgeInsets.all(isCompact ? 18 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ApprovalIconTile(
                icon: Icons.send_outlined,
                size: isCompact ? 42 : 46,
              ),
              SizedBox(width: isCompact ? 12 : 14),
              Expanded(
                child: Text(
                  request.eventTitle,
                  style: TextStyle(
                    fontSize: isCompact ? 17 : 18,
                    fontWeight: FontWeight.w800,
                    color: ApprovalUi.heading,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(request.status),
            ],
          ),
          if (request.description != null &&
              request.description!.isNotEmpty) ...[
            SizedBox(height: isCompact ? 8 : 10),
            Text(
              request.description!,
              style: TextStyle(
                fontSize: isCompact ? 12.5 : 13,
                color: ApprovalUi.muted,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: isCompact ? 14 : 16),
          ApprovalPanelBox(
            padding: EdgeInsets.all(isCompact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                  icon: Icons.person_outline,
                  text: 'By: ${request.requestedBy}',
                ),
                const SizedBox(height: 6),
                InfoRow(
                  icon: Icons.alternate_email_rounded,
                  text: request.requestedBy,
                ),
                const SizedBox(height: 6),
                InfoRow(
                  icon: Icons.schedule,
                  text:
                      '${df.format(request.startDatetime)} · ${tf.format(request.startDatetime)} → ${tf.format(request.endDatetime)}',
                ),
              ],
            ),
          ),
          if ((request.pipelineStage ?? '').trim().isNotEmpty) ...[
            SizedBox(height: isCompact ? 10 : 12),
            ApprovalPanelBox(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 14,
                vertical: isCompact ? 10 : 12,
              ),
              backgroundColor: ApprovalUi.accentSoft,
              borderColor: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InfoRow(
                icon: Icons.route_outlined,
                text: _pipelineStageLabel(request.pipelineStage),
                iconColor: ApprovalUi.accent,
              ),
            ),
          ],
          if (request.overrideConflict) ...[
            SizedBox(height: isCompact ? 10 : 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, size: 14, color: AppColors.warning),
                  SizedBox(width: 6),
                  Text(
                    'Conflict override requested',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: isCompact ? 16 : 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: onDetails,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 18 : 20,
                    vertical: isCompact ? 13 : 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Details'),
              ),
              if (showActions)
                InkWell(
                  onTap: () => _openActionSheet(context),
                  borderRadius: BorderRadius.circular(14),
                  child: const ApprovalActionButton(label: 'Action'),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                  'No action',
                  style: TextStyle(
                    fontSize: 12,
                    color: ApprovalUi.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecisionSheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color foreground;
  final Color background;
  final Color border;
  final VoidCallback onTap;

  const _DecisionSheetOption({
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: foreground, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ApprovalUi.text,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DepartmentApprovalCard extends StatelessWidget {
  final String title;
  final String status;
  final String requestedBy;
  final String details;
  final String? schedule;
  final bool canTakeAction;
  final VoidCallback? onDetails;
  final VoidCallback? onUpdate;
  final bool showUpload;
  final bool uploadEnabled;
  final String uploadHint;
  final VoidCallback? onUpload;

  const _DepartmentApprovalCard({
    required this.title,
    required this.status,
    required this.requestedBy,
    required this.details,
    required this.canTakeAction,
    this.schedule,
    this.onDetails,
    this.onUpdate,
    this.showUpload = false,
    this.uploadEnabled = false,
    this.uploadHint = '',
    this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 430;

    return ApprovalCardShell(
      padding: EdgeInsets.all(isCompact ? 18 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ApprovalIconTile(
                icon: Icons.approval_outlined,
                size: isCompact ? 42 : 46,
              ),
              SizedBox(width: isCompact ? 12 : 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isCompact ? 17 : 18,
                    fontWeight: FontWeight.w800,
                    color: ApprovalUi.heading,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusBadge(status),
            ],
          ),
          SizedBox(height: isCompact ? 14 : 16),
          ApprovalPanelBox(
            padding: EdgeInsets.all(isCompact ? 14 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(icon: Icons.person_outline, text: 'By: $requestedBy'),
          if ((schedule ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                InfoRow(icon: Icons.schedule, text: schedule!),
          ],
          if (details.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  details,
                  style: TextStyle(
                    fontSize: isCompact ? 12.5 : 13,
                    color: ApprovalUi.muted,
                    height: 1.4,
                  ),
                ),
          ],
              ],
            ),
          ),
          SizedBox(height: isCompact ? 16 : 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: onDetails,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 18 : 20,
                    vertical: isCompact ? 13 : 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Details'),
              ),
              if (showUpload)
                OutlinedButton(
                  onPressed: uploadEnabled ? onUpload : null,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 18 : 20,
                      vertical: isCompact ? 13 : 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Upload'),
                ),
              if (canTakeAction)
                FilledButton(
                  onPressed: onUpdate,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 18 : 20,
                      vertical: isCompact ? 13 : 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Action'),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No action',
                    style: TextStyle(
                    fontSize: 12,
                    color: ApprovalUi.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ),
            ],
          ),
          if (showUpload && !uploadEnabled && uploadHint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              uploadHint,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _pipelineStageLabel(String? stage) {
  switch ((stage ?? '').trim().toLowerCase()) {
    case 'deputy':
      return 'Pending Deputy Registrar review';
    case 'after_deputy':
      return 'Deputy approved - send to Finance';
    case 'finance':
      return 'Pending Finance review';
    case 'after_finance':
      return 'Finance approved - send to final approver';
    case 'final':
      return 'Pending final approval';
    default:
      return 'Approval workflow';
  }
}
