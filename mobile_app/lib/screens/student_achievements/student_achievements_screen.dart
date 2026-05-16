import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/common/app_widgets.dart';
import '../home_screen.dart';

class StudentAchievementsScreen extends StatefulWidget {
  const StudentAchievementsScreen({super.key});

  @override
  State<StudentAchievementsScreen> createState() =>
      _StudentAchievementsScreenState();
}

class _StudentAchievementsScreenState extends State<StudentAchievementsScreen> {
  final _api = ApiService();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _criteriaLoading = true;
  bool _refreshing = false;
  String? _error;
  String _platformFilter = '';
  String _criterionFilter = '';
  List<Map<String, dynamic>> _items = [];
  List<_IqacCriterion> _criteria = [];

  static const _platforms = ['LinkedIn', 'Instagram', 'YouTube', 'VU Website'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isAdmin {
    final role = (context.read<AuthProvider>().user?.roleKey ?? '')
        .trim()
        .toLowerCase();
    return role == 'admin';
  }

  String get _userId => context.read<AuthProvider>().user?.id ?? '';

  Future<void> _loadAll({bool refresh = false}) async {
    if (!mounted) return;
    setState(() {
      _refreshing = refresh;
      if (!refresh) _loading = true;
      _error = null;
    });
    await Future.wait([_loadCriteria(), _loadItems()]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _refreshing = false;
    });
  }

  Future<void> _loadCriteria() async {
    setState(() => _criteriaLoading = true);
    try {
      final data = await _api.get<List<dynamic>>(
        '/student-achievements/iqac-criteria',
      );
      if (!mounted) return;
      setState(() {
        _criteria = data
            .whereType<Map>()
            .map((e) => _IqacCriterion.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _criteriaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _criteriaLoading = false);
    }
  }

  Future<void> _loadItems() async {
    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/student-achievements',
        params: {
          if (_platformFilter.isNotEmpty) 'platform': _platformFilter,
          if (_criterionFilter.isNotEmpty)
            'iqac_criterion_id': _criterionFilter,
          if (_searchController.text.trim().isNotEmpty)
            'search': _searchController.text.trim(),
        },
      );
      final raw = data['items'];
      if (!mounted) return;
      setState(() {
        _items = raw is List
            ? raw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : <Map<String, dynamic>>[];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageFromError(e));
    }
  }

  Future<void> _applyFilters() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _loadItems();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _openForm({Map<String, dynamic>? item}) async {
    final chatFabVisible = ChatFabVisibilityScope.maybeOf(context);
    final restoreChatFab = chatFabVisible?.value;
    chatFabVisible?.value = false;
    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _AchievementFormSheet(
          api: _api,
          criteria: _criteria,
          initialItem: item,
        ),
      );
      if (result == true) {
        await _loadAll(refresh: true);
      }
    } finally {
      if (mounted && restoreChatFab != null) {
        chatFabVisible?.value = restoreChatFab;
      }
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    Map<String, dynamic> detail = item;
    try {
      final id = (item['id'] ?? '').toString();
      if (id.isNotEmpty) {
        detail = await _api.get<Map<String, dynamic>>(
          '/student-achievements/$id',
        );
      }
    } catch (e) {
      _showMessage(_messageFromError(e));
    }

    if (!mounted) return;
    final chatFabVisible = ChatFabVisibilityScope.maybeOf(context);
    final restoreChatFab = chatFabVisible?.value;
    chatFabVisible?.value = false;
    try {
      final changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _AchievementDetailSheet(
          item: detail,
          criteria: _criteria,
          canEdit:
              !_isAdmin && (detail['created_by'] ?? '').toString() == _userId,
          canDelete: _isAdmin,
          onEdit: () async {
            Navigator.of(context).pop(false);
            await _openForm(item: detail);
          },
          onDelete: () => _deleteAchievement(detail),
        ),
      );
      if (changed == true) {
        await _loadAll(refresh: true);
      }
    } finally {
      if (mounted && restoreChatFab != null) {
        chatFabVisible?.value = restoreChatFab;
      }
    }
  }

  Future<bool> _deleteAchievement(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete submission?'),
        content: const Text(
          'This achievement submission will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return false;

    try {
      await _api.delete('/student-achievements/${item['id']}');
      if (mounted) Navigator.of(context).pop(true);
      return true;
    } catch (e) {
      _showMessage(_messageFromError(e));
      return false;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark
        ? theme.scaffoldBackgroundColor
        : const Color(0xFFF4F6F8);

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final fabClearance =
        bottomInset + 16.0 + 56.0 + 12.0; // inset + margin + height + gap

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadAll(refresh: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'INSTITUTIONAL COMMUNICATION',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Other Achievements',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (!_loading)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.1,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    LucideIcons.list,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${_items.length}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isAdmin
                            ? 'Manage student and faculty achievement submissions.'
                            : 'Submit student or faculty material for institutional visibility.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _FilterPanel(
                        searchController: _searchController,
                        platforms: _platforms,
                        criteria: _criteria,
                        platform: _platformFilter,
                        criterion: _criterionFilter,
                        criteriaLoading: _criteriaLoading,
                        onPlatformChanged: (value) {
                          setState(() => _platformFilter = value);
                          _applyFilters();
                        },
                        onCriterionChanged: (value) {
                          setState(() => _criterionFilter = value);
                          _applyFilters();
                        },
                        onSearch: _applyFilters,
                      ),
                    ],
                  ),
                ),
              ),
              if (_loading && !_refreshing)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorState(
                      message: _error!,
                      onRetry: () => _loadAll(refresh: true),
                    ),
                  ),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyState(
                      icon: LucideIcons.award,
                      title: 'No achievements found',
                      message:
                          'Submit student or faculty publicity inputs to see them here.',
                      actionLabel: 'Submit Achievement',
                      onAction: () => _openForm(),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, fabClearance),
                  sliver: SliverList.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _AchievementCard(
                          item: item,
                          iqacLabel: _buildIqacLabel(_criteria, item),
                          onTap: () => _openDetail(item),
                        ),
                      );
                    },
                  ),
                ),
              if (_refreshing)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        elevation: 8,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text(
          'Submit Achievement',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
        ),
      ),
    );
  }
}

class _AchievementFormSheet extends StatefulWidget {
  final ApiService api;
  final List<_IqacCriterion> criteria;
  final Map<String, dynamic>? initialItem;

  const _AchievementFormSheet({
    required this.api,
    required this.criteria,
    this.initialItem,
  });

  @override
  State<_AchievementFormSheet> createState() => _AchievementFormSheetState();
}

class _AchievementFormSheetState extends State<_AchievementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _iqacDescriptionFieldKey = GlobalKey();
  final _iqacDescriptionFocusNode = FocusNode();
  late String _achievementType;
  late List<_StudentDraft> _students;
  late List<_FacultyDraft> _facultyMembers;
  late TextEditingController _activityCtrl;
  late TextEditingController _contextCtrl;
  late TextEditingController _writeupCtrl;
  late TextEditingController _iqacDescriptionCtrl;
  final Set<String> _platforms = {};
  final List<PlatformFile> _attachments = [];
  String _criterionId = '';
  String _subFolderId = '';
  String _itemId = '';
  bool _saving = false;
  String? _error;

  static const _platformOptions = [
    'LinkedIn',
    'Instagram',
    'YouTube',
    'VU Website',
  ];

  bool get _isEdit => widget.initialItem != null;

  @override
  void initState() {
    super.initState();
    _iqacDescriptionFocusNode.addListener(_handleIqacDescriptionFocus);
    final item = widget.initialItem;
    _achievementType = _achievementTypeFromItem(item);
    final rawStudents = item?['students'];
    _students = rawStudents is List
        ? rawStudents
              .whereType<Map>()
              .map((e) => _StudentDraft.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.name.trim().isNotEmpty)
              .toList()
        : <_StudentDraft>[];
    if (_students.isEmpty) _students = [_StudentDraft()];
    _facultyMembers = _achievementType == 'faculty' && rawStudents is List
        ? rawStudents
              .whereType<Map>()
              .map((e) => _FacultyDraft.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.name.trim().isNotEmpty)
              .toList()
        : <_FacultyDraft>[];
    if (_facultyMembers.isEmpty) _facultyMembers = [_FacultyDraft()];
    _activityCtrl = TextEditingController(
      text: (item?['activity_description'] ?? '').toString(),
    );
    _contextCtrl = TextEditingController(
      text: (item?['additional_context_objective'] ?? '').toString(),
    );
    _writeupCtrl = TextEditingController(
      text: (item?['social_media_writeup'] ?? '').toString(),
    );
    _iqacDescriptionCtrl = TextEditingController(
      text: (item?['iqac_description'] ?? '').toString(),
    );
    final platforms = item?['suggested_platforms'];
    if (platforms is List) {
      _platforms.addAll(
        platforms.map((e) => e.toString()).where((e) => e.isNotEmpty),
      );
    }
    _criterionId = (item?['iqac_criterion_id'] ?? '').toString();
    _subFolderId = (item?['iqac_subfolder_id'] ?? '').toString();
    _itemId = (item?['iqac_item_id'] ?? '').toString();
  }

  @override
  void dispose() {
    _iqacDescriptionFocusNode
      ..removeListener(_handleIqacDescriptionFocus)
      ..dispose();
    _activityCtrl.dispose();
    _contextCtrl.dispose();
    _writeupCtrl.dispose();
    _iqacDescriptionCtrl.dispose();
    super.dispose();
  }

  void _handleIqacDescriptionFocus() {
    if (!_iqacDescriptionFocusNode.hasFocus) return;
    _scrollIqacDescriptionIntoView();
  }

  Future<void> _scrollIqacDescriptionIntoView() async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    final fieldContext = _iqacDescriptionFieldKey.currentContext;
    if (fieldContext == null) return;
    if (!fieldContext.mounted) return;
    await Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0.35,
    );
  }

  _IqacCriterion? get _criterion => widget.criteria
      .where((e) => e.id.toString() == _criterionId)
      .cast<_IqacCriterion?>()
      .firstOrNull;

  _IqacSubFolder? get _subFolder => _criterion?.subFolders
      .where((e) => e.id == _subFolderId)
      .cast<_IqacSubFolder?>()
      .firstOrNull;

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'pdf',
        'doc',
        'docx',
        'ppt',
        'pptx',
        'xls',
        'xlsx',
      ],
    );
    if (result == null) return;
    setState(() => _attachments.addAll(result.files));
  }

  Future<void> _openGoogleConnect() async {
    final response = await widget.api.get<Map<String, dynamic>>(
      '/calendar/connect-url',
    );
    final rawUrl = response['url']?.toString().trim() ?? '';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      throw Exception('Could not open Google connect.');
    }
    final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened) {
      throw Exception('Could not open Google connect.');
    }
  }

  Future<bool> _confirmGoogleReadyForFiles() async {
    if (_attachments.isEmpty) return true;

    try {
      final status = await widget.api.get<Map<String, dynamic>>(
        '/auth/google/status',
      );
      if (status['connected'] == true) return true;
    } catch (_) {
      // If status cannot be checked, let submit continue and show the server
      // response. This avoids blocking users because of a transient status call.
      return true;
    }

    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Connect Google',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Google Drive access is required to upload PDFs or documents. Connect Google, then try submitting again.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await _openGoogleConnect();
              } catch (e) {
                if (!mounted) return;
                setState(() => _error = friendlyErrorMessage(e));
              }
            },
            child: const Text('Connect Google'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final cleanedParticipants = _achievementType == 'faculty'
        ? _facultyMembers
              .map((faculty) => faculty.toStudentJson())
              .where(
                (faculty) => (faculty['student_name'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty,
              )
              .toList()
        : _students
              .map((student) => student.toJson())
              .where(
                (student) => (student['student_name'] ?? '')
                    .toString()
                    .trim()
                    .isNotEmpty,
              )
              .toList();
    if (cleanedParticipants.isEmpty) {
      setState(
        () => _error = _achievementType == 'faculty'
            ? 'Add at least one faculty name.'
            : 'Add at least one student name.',
      );
      return;
    }
    final googleReady = await _confirmGoogleReadyForFiles();
    if (!googleReady) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final formData = FormData();
      formData.fields
        ..add(MapEntry('achievement_type', _achievementType))
        ..add(MapEntry('students', jsonEncode(cleanedParticipants)))
        ..add(MapEntry('activity_description', _activityCtrl.text.trim()))
        ..add(
          MapEntry('additional_context_objective', _contextCtrl.text.trim()),
        )
        ..add(MapEntry('suggested_platforms', jsonEncode(_platforms.toList())))
        ..add(MapEntry('social_media_writeup', _writeupCtrl.text.trim()))
        ..add(MapEntry('iqac_criterion_id', _criterionId))
        ..add(MapEntry('iqac_subfolder_id', _subFolderId))
        ..add(MapEntry('iqac_item_id', _itemId))
        ..add(MapEntry('iqac_description', _iqacDescriptionCtrl.text.trim()));
      for (final file in _attachments) {
        final multipart = file.path != null
            ? await MultipartFile.fromFile(file.path!, filename: file.name)
            : MultipartFile.fromBytes(
                file.bytes ?? const [],
                filename: file.name,
              );
        formData.files.add(MapEntry('attachments', multipart));
      }

      if (_isEdit) {
        await widget.api.patch<Map<String, dynamic>>(
          '/student-achievements/${widget.initialItem!['id']}',
          data: formData,
        );
      } else {
        await widget.api.postMultipart<Map<String, dynamic>>(
          '/student-achievements',
          formData,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageFromError(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final inputDeco = _achievementInputDecoration(context);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 28,
                  offset: const Offset(0, -8),
                  color: Colors.black.withValues(alpha: 0.16),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: ListView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  _AchievementFormHeader(
                    isEdit: _isEdit,
                    achievementType: _achievementType,
                    saving: _saving,
                    onClose: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(height: 24),
                  _AchievementTypeSelector(
                    value: _achievementType,
                    onChanged: (value) =>
                        setState(() => _achievementType = value),
                  ),
                  const SizedBox(height: 28),
                  if (_achievementType == 'faculty') ...[
                    _SectionTitle(
                      title: '1. Faculty Included',
                      icon: LucideIcons.briefcase,
                      action: TextButton.icon(
                        onPressed: () => setState(
                          () => _facultyMembers.add(_FacultyDraft()),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text(
                          'Add Faculty',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    ...List.generate(_facultyMembers.length, (index) {
                      final faculty = _facultyMembers[index];
                      return _FacultyEditor(
                        key: ValueKey(faculty),
                        faculty: faculty,
                        canRemove: _facultyMembers.length > 1,
                        inputDeco: inputDeco,
                        onChanged: () => setState(() {}),
                        onRemove: () =>
                            setState(() => _facultyMembers.removeAt(index)),
                      );
                    }),
                  ] else ...[
                    _SectionTitle(
                      title: '1. Students Included',
                      icon: LucideIcons.users,
                      action: TextButton.icon(
                        onPressed: () =>
                            setState(() => _students.add(_StudentDraft())),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: const Text(
                          'Add Student',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    ...List.generate(_students.length, (index) {
                      final student = _students[index];
                      return _StudentEditor(
                        key: ValueKey(student),
                        student: student,
                        canRemove: _students.length > 1,
                        inputDeco: inputDeco,
                        onChanged: () => setState(() {}),
                        onRemove: () =>
                            setState(() => _students.removeAt(index)),
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                  const _SectionTitle(
                    title: '2. Achievement Details',
                    icon: LucideIcons.fileText,
                  ),
                  TextFormField(
                    controller: _activityCtrl,
                    minLines: 4,
                    maxLines: 7,
                    decoration: inputDeco.copyWith(
                      labelText: 'Description of Activity and Achievement',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Description is required.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contextCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: inputDeco.copyWith(
                      labelText: 'Additional Details (Context & Objective)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _SectionTitle(
                    title: '3. Publicity Preferences',
                    icon: LucideIcons.share2,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Suggested Platforms to Post',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _platformOptions.map((platform) {
                      final isSelected = _platforms.contains(platform);
                      return FilterChip(
                        label: Text(platform),
                        selected: isSelected,
                        showCheckmark: isSelected,
                        checkmarkColor: theme.colorScheme.onPrimary,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        selectedColor: theme.colorScheme.primary,
                        backgroundColor: theme.colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? Colors.transparent
                                : theme.colorScheme.outline.withValues(
                                    alpha: 0.2,
                                  ),
                          ),
                        ),
                        onSelected: (selected) {
                          setState(() {
                            selected
                                ? _platforms.add(platform)
                                : _platforms.remove(platform);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _writeupCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: inputDeco.copyWith(
                      labelText: 'Draft Social Media Write-up',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle(
                    title: '4. Images and Attachments/Documents',
                    icon: LucideIcons.paperclip,
                  ),
                  _AttachmentPickerBox(
                    attachments: _attachments,
                    onPick: _saving ? null : _pickAttachments,
                    onRemove: (file) =>
                        setState(() => _attachments.remove(file)),
                  ),
                  const SizedBox(height: 32),
                  const _SectionTitle(
                    title: '5. Relevant IQAC Criterion',
                    icon: LucideIcons.database,
                  ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.15,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey('criterion-$_criterionId'),
                          initialValue: _criterionId.isEmpty
                              ? null
                              : _criterionId,
                          isExpanded: true,
                          decoration: inputDeco.copyWith(
                            labelText: 'Criterion',
                          ),
                          items: widget.criteria
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id.toString(),
                                  child: Text(
                                    '${c.id}. ${c.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          selectedItemBuilder: (context) => widget.criteria
                              .map(
                                (c) => Text(
                                  '${c.id}. ${c.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _criterionId = value ?? '';
                              _subFolderId = '';
                              _itemId = '';
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            'subfolder-$_criterionId-$_subFolderId',
                          ),
                          initialValue: _subFolderId.isEmpty
                              ? null
                              : _subFolderId,
                          isExpanded: true,
                          decoration: inputDeco.copyWith(
                            labelText: 'Subfolder',
                          ),
                          items:
                              (_criterion?.subFolders ??
                                      const <_IqacSubFolder>[])
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Text(
                                        '${s.id} ${s.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                          selectedItemBuilder: (context) =>
                              (_criterion?.subFolders ??
                                      const <_IqacSubFolder>[])
                                  .map(
                                    (s) => Text(
                                      '${s.id} ${s.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .toList(),
                          onChanged: _criterion == null
                              ? null
                              : (value) {
                                  setState(() {
                                    _subFolderId = value ?? '';
                                    _itemId = '';
                                  });
                                },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey('item-$_subFolderId-$_itemId'),
                          initialValue: _itemId.isEmpty ? null : _itemId,
                          isExpanded: true,
                          decoration: inputDeco.copyWith(labelText: 'Item'),
                          items: (_subFolder?.items ?? const <_IqacItem>[])
                              .map(
                                (i) => DropdownMenuItem(
                                  value: i.id,
                                  child: Text(
                                    '${i.id} ${i.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          selectedItemBuilder: (context) =>
                              (_subFolder?.items ?? const <_IqacItem>[])
                                  .map(
                                    (i) => Text(
                                      '${i.id} ${i.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                  .toList(),
                          onChanged: _subFolder == null
                              ? null
                              : (value) =>
                                    setState(() => _itemId = value ?? ''),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: _iqacDescriptionFieldKey,
                          controller: _iqacDescriptionCtrl,
                          focusNode: _iqacDescriptionFocusNode,
                          onTap: _scrollIqacDescriptionIntoView,
                          decoration: inputDeco.copyWith(
                            labelText: 'IQAC Description',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isEdit
                                  ? 'Save Changes'
                                  : 'Submit ${_achievementTypeLabel(_achievementType)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AchievementFormHeader extends StatelessWidget {
  final bool isEdit;
  final String achievementType;
  final bool saving;
  final VoidCallback onClose;

  const _AchievementFormHeader({
    required this.isEdit,
    required this.achievementType,
    required this.saving,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final label = _achievementTypeLabel(achievementType);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isEdit ? LucideIcons.edit2 : LucideIcons.award,
              color: theme.colorScheme.primary,
              size: 23,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Edit $label' : 'Submit $label',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Share material for institutional visibility and IQAC records.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: saving ? null : onClose,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surface,
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.12),
                ),
              ),
            ),
            icon: const Icon(LucideIcons.x, size: 20),
          ),
        ],
      ),
    );
  }
}

class _AchievementDetailSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final List<_IqacCriterion> criteria;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;

  const _AchievementDetailSheet({
    required this.item,
    required this.criteria,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attachments = _listOfMaps(item['attachments']);
    final iqacLabel = _buildIqacLabel(criteria, item);
    final iqacDescription = _s(item['iqac_description']);
    final isFaculty = _isFacultyAchievement(item);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.surface
                : const Color(0xFFF8FAFC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: const [BoxShadow(blurRadius: 20, color: Colors.black26)],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final compact = constraints.maxWidth < 520;
              final contentPadding = wide
                  ? const EdgeInsets.fromLTRB(32, 12, 32, 28)
                  : const EdgeInsets.fromLTRB(16, 12, 16, 28);

              Widget responsiveRow(List<Widget> children) {
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children
                        .map(
                          (child) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: child,
                          ),
                        )
                        .toList(),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var index = 0; index < children.length; index++) ...[
                      if (index > 0) const SizedBox(width: 16),
                      Expanded(child: children[index]),
                    ],
                  ],
                );
              }

              return ListView(
                controller: scrollController,
                padding: contentPadding,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 22),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.3,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _DetailHeader(
                            title: _itemTitle(item),
                            submittedDate: _formatDate(item['created_at']),
                            onClose: () => Navigator.of(context).pop(false),
                          ),
                          const SizedBox(height: 20),
                          _DetailCard(
                            title: isFaculty ? 'Faculty' : 'Students',
                            child: _StudentTable(
                              students: _listOfMaps(item['students']),
                              isFaculty: isFaculty,
                            ),
                          ),
                          const SizedBox(height: 16),
                          responsiveRow([
                            _DetailCard(
                              title: 'Description',
                              child: _DetailText(
                                text: _s(item['activity_description']),
                                emptyText: 'No description provided.',
                              ),
                            ),
                            _DetailCard(
                              title: 'Additional Details',
                              child: _DetailText(
                                text: _s(item['additional_context_objective']),
                                emptyText: 'No additional details provided.',
                              ),
                            ),
                          ]),
                          if (wide) const SizedBox(height: 16),
                          responsiveRow([
                            _DetailCard(
                              title: 'Selected Platforms',
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: _platformWidgets(
                                  item['suggested_platforms'],
                                  theme,
                                ),
                              ),
                            ),
                            _DetailCard(
                              title: 'Attachments',
                              child: _AttachmentLinks(attachments: attachments),
                            ),
                          ]),
                          if (wide) const SizedBox(height: 16),
                          _DetailCard(
                            title: 'Social Media Write-up',
                            child: _SocialWriteupBox(
                              text: _s(item['social_media_writeup']),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _DetailCard(
                            title: 'IQAC Criterion',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _DetailText(
                                  text: iqacLabel,
                                  emptyText: 'No IQAC criterion selected.',
                                  weight: FontWeight.w700,
                                ),
                                if (iqacDescription.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.12),
                                      ),
                                    ),
                                    child: Text(
                                      iqacDescription,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            height: 1.45,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _StudentDetailSectionTitle(
                            'Audit Information',
                            icon: LucideIcons.clock,
                          ),
                          const SizedBox(height: 12),
                          _MetadataPanel(item: item, wide: !compact),
                          const SizedBox(height: 22),
                          _DetailActions(
                            canEdit: canEdit,
                            canDelete: canDelete,
                            compact: compact,
                            onClose: () => Navigator.of(context).pop(false),
                            onEdit: onEdit,
                            onDelete: onDelete,
                          ),
                          if (compact) const SizedBox(height: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final String title;
  final String submittedDate;
  final VoidCallback onClose;

  const _DetailHeader({
    required this.title,
    required this.submittedDate,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      LucideIcons.calendar,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Submitted $submittedDate',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.55),
            ),
            icon: const Icon(LucideIcons.x, size: 20),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _DetailText extends StatelessWidget {
  final String text;
  final String emptyText;
  final FontWeight weight;

  const _DetailText({
    required this.text,
    required this.emptyText,
    this.weight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = text.trim();
    if (value.isEmpty || value == '--') {
      return Text(
        emptyText,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
          height: 1.5,
        ),
      );
    }
    return Text(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.84),
        fontWeight: weight,
        height: 1.55,
      ),
    );
  }
}

class _SocialWriteupBox extends StatelessWidget {
  final String text;

  const _SocialWriteupBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.quote,
            size: 22,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DetailText(
              text: text,
              emptyText: 'No social media write-up provided.',
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentLinks extends StatelessWidget {
  final List<Map<String, dynamic>> attachments;

  const _AttachmentLinks({required this.attachments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (attachments.isEmpty) {
      return _DetailText(text: '', emptyText: 'No attachments uploaded.');
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: attachments.map((file) {
        final name = _s(file['file_name'], fallback: 'Document');
        final link = _s(file['web_view_link']);
        return ActionChip(
          avatar: Icon(
            LucideIcons.download,
            size: 16,
            color: link.isEmpty
                ? theme.colorScheme.onSurfaceVariant
                : const Color(0xFF047857),
          ),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: link.isEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : const Color(0xFF047857),
              ),
            ),
          ),
          backgroundColor: theme.colorScheme.surface,
          side: BorderSide(
            color: link.isEmpty
                ? theme.colorScheme.outline.withValues(alpha: 0.18)
                : const Color(0xFF10B981).withValues(alpha: 0.35),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onPressed: link.isEmpty ? null : () => _openUrl(link),
        );
      }).toList(),
    );
  }
}

class _MetadataPanel extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool wide;

  const _MetadataPanel({required this.item, required this.wide});

  @override
  Widget build(BuildContext context) {
    final entries = <({String label, String value, IconData icon})>[
      (
        label: 'Created by',
        value: _s(item['created_by_name'] ?? item['created_by_email']),
        icon: LucideIcons.user,
      ),
      (
        label: 'Created at',
        value: _formatDate(item['created_at']),
        icon: LucideIcons.calendar,
      ),
      (
        label: 'Last updated by',
        value: _s(item['updated_by_name'] ?? item['updated_by_email']),
        icon: LucideIcons.userCheck,
      ),
      (
        label: 'Updated at',
        value: _formatDate(item['updated_at']),
        icon: LucideIcons.clock,
      ),
    ];

    return Container(
      color: Colors.transparent,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < entries.length; index++) ...[
                  if (index > 0) const SizedBox(width: 12),
                  Expanded(child: _MetadataValue(entry: entries[index])),
                ],
              ],
            )
          : GridView.builder(
              itemCount: entries.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.72,
              ),
              itemBuilder: (context, index) =>
                  _MetadataValue(entry: entries[index]),
            ),
    );
  }
}

class _StudentDetailSectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _StudentDetailSectionTitle(this.title, {required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 7),
        Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _MetadataValue extends StatelessWidget {
  final ({String label, String value, IconData icon}) entry;

  const _MetadataValue({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = entry.value.trim().isEmpty ? '--' : entry.value;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(entry.icon, size: 16, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  shown,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
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

class _DetailActions extends StatelessWidget {
  final bool canEdit;
  final bool canDelete;
  final bool compact;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;

  const _DetailActions({
    required this.canEdit,
    required this.canDelete,
    required this.compact,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final closeButton = OutlinedButton(
      onPressed: onClose,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w800)),
    );

    final editButton = FilledButton.icon(
      onPressed: onEdit,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(LucideIcons.edit2, size: 18),
      label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.w800)),
    );

    final deleteButton = OutlinedButton.icon(
      onPressed: onDelete,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        foregroundColor: theme.colorScheme.error,
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(LucideIcons.trash2, size: 18),
      label: const Text(
        'Delete',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );

    if (compact) {
      return canEdit
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                editButton,
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: closeButton),
                    if (canDelete) ...[
                      const SizedBox(width: 10),
                      Expanded(child: deleteButton),
                    ],
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: closeButton),
                if (canDelete) ...[
                  const SizedBox(width: 10),
                  Expanded(child: deleteButton),
                ],
              ],
            );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 12,
      children: [
        closeButton,
        if (canEdit) editButton,
        if (canDelete) deleteButton,
      ],
    );
  }
}

class _FilterPanel extends StatelessWidget {
  final TextEditingController searchController;
  final List<String> platforms;
  final List<_IqacCriterion> criteria;
  final String platform;
  final String criterion;
  final bool criteriaLoading;
  final ValueChanged<String> onPlatformChanged;
  final ValueChanged<String> onCriterionChanged;
  final VoidCallback onSearch;

  const _FilterPanel({
    required this.searchController,
    required this.platforms,
    required this.criteria,
    required this.platform,
    required this.criterion,
    required this.criteriaLoading,
    required this.onPlatformChanged,
    required this.onCriterionChanged,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldFill = theme.colorScheme.surface;
    final fieldBorder = theme.colorScheme.outline.withValues(alpha: 0.15);

    InputDecoration filterInputDecoration(String hint, IconData icon) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, size: 20, color: theme.colorScheme.primary),
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
      );
    }

    final platformDropdown = DropdownButtonFormField<String>(
      key: ValueKey('platform-$platform'),
      initialValue: platform.isEmpty ? null : platform,
      isExpanded: true,
      icon: const Icon(LucideIcons.chevronDown, size: 18),
      decoration: filterInputDecoration('All Platforms', LucideIcons.share2),
      items: [
        const DropdownMenuItem(value: '', child: Text('All Platforms')),
        ...platforms.map(
          (p) => DropdownMenuItem(
            value: p,
            child: Text(p, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      selectedItemBuilder: (context) => [
        const Text('All Platforms', overflow: TextOverflow.ellipsis),
        ...platforms.map((p) => Text(p, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) => onPlatformChanged(value ?? ''),
    );

    final criterionDropdown = DropdownButtonFormField<String>(
      key: ValueKey('criterion-filter-$criterion'),
      initialValue: criterion.isEmpty ? null : criterion,
      isExpanded: true,
      icon: const Icon(LucideIcons.chevronDown, size: 18),
      decoration: filterInputDecoration(
        criteriaLoading ? 'Loading...' : 'IQAC Criteria',
        LucideIcons.database,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('All IQAC Criteria')),
        ...criteria.map(
          (c) => DropdownMenuItem(
            value: c.id.toString(),
            child: Text('${c.id}. ${c.title}', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      selectedItemBuilder: (context) => [
        const Text('All IQAC Criteria', overflow: TextOverflow.ellipsis),
        ...criteria.map(
          (c) => Text(
            '${c.id}. ${c.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      onChanged: (value) => onCriterionChanged(value ?? ''),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration:
                filterInputDecoration(
                  'Search name, batch, school...',
                  LucideIcons.search,
                ).copyWith(
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () {
                            searchController.clear();
                            onSearch();
                          },
                          icon: const Icon(LucideIcons.xCircle, size: 18),
                        ),
                ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 430;
              if (stacked) {
                return Column(
                  children: [
                    platformDropdown,
                    const SizedBox(height: 12),
                    criterionDropdown,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: platformDropdown),
                  const SizedBox(width: 12),
                  Expanded(child: criterionDropdown),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String iqacLabel;
  final VoidCallback onTap;

  const _AchievementCard({
    required this.item,
    required this.iqacLabel,
    required this.onTap,
  });

  String _getInitials(String name) {
    if (name.isEmpty) return '??';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, min(2, name.length)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = _itemTitle(item);
    final isFaculty = _isFacultyAchievement(item);
    final participants = _listOfMaps(item['students']);
    final firstName = participants.isEmpty
        ? title
        : _studentName(participants.first);
    final initials = _getInitials(firstName);
    final cardBg = isDark ? const Color(0xFF172033) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE8EEF7);
    final metaBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black26
                : Colors.black.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.tertiary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                isFaculty
                                    ? LucideIcons.briefcase
                                    : LucideIcons.graduationCap,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _studentLine(item),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: metaBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    _s(
                      item['activity_description'],
                      fallback: 'No description supplied.',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.85,
                      ),
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _MetaChip(
                      icon: isFaculty
                          ? LucideIcons.briefcase
                          : LucideIcons.graduationCap,
                      label: isFaculty ? 'Faculty' : 'Student',
                    ),
                    ..._buildPlatformTags(item['suggested_platforms'], theme),
                    _MetaChip(icon: LucideIcons.database, label: iqacLabel),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: borderColor),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.calendar,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formatShortDate(item['created_at']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View Details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPlatformTags(dynamic platforms, ThemeData theme) {
    if (platforms is! List || platforms.isEmpty) return [];
    return platforms
        .map((platform) => platform.toString())
        .where((platform) => platform.trim().isNotEmpty)
        .map(
          (platform) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.share2,
                  size: 12,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  platform,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}

class _AchievementTypeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _AchievementTypeSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [
      (
        value: 'student',
        label: 'Student',
        icon: LucideIcons.graduationCap,
        hint: 'Credit one or more students',
      ),
      (
        value: 'faculty',
        label: 'Faculty',
        icon: LucideIcons.briefcase,
        hint: 'Credit one or more faculty members',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.45,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 430;
          Widget buildOption(
            ({String value, String label, IconData icon, String hint}) option,
          ) {
            final selected = value == option.value;
            return Padding(
              padding: EdgeInsets.only(
                right: stacked || option.value == 'faculty' ? 0 : 6,
                bottom: stacked && option.value == 'student' ? 6 : 0,
              ),
              child: Material(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onChanged(option.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          option.icon,
                          size: 18,
                          color: selected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                option.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: selected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                option.hint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: selected
                                      ? theme.colorScheme.onPrimary.withValues(
                                          alpha: 0.78,
                                        )
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
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
            );
          }

          if (stacked) {
            return Column(children: options.map(buildOption).toList());
          }
          return Row(
            children: options
                .map((option) => Expanded(child: buildOption(option)))
                .toList(),
          );
        },
      ),
    );
  }
}

class _StudentEditor extends StatelessWidget {
  final _StudentDraft student;
  final bool canRemove;
  final InputDecoration inputDeco;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _StudentEditor({
    super.key,
    required this.student,
    required this.canRemove,
    required this.inputDeco,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackFields = constraints.maxWidth < 520;
        final nameField = TextFormField(
          initialValue: student.name,
          textInputAction: TextInputAction.next,
          decoration: inputDeco.copyWith(labelText: 'Student Name *'),
          onChanged: (value) {
            student.name = value;
            onChanged();
          },
          validator: (_) => student.name.trim().isEmpty ? 'Required' : null,
        );
        final batchField = TextFormField(
          initialValue: student.batch,
          textInputAction: TextInputAction.next,
          decoration: inputDeco.copyWith(labelText: 'Batch'),
          onChanged: (value) => student.batch = value,
        );
        final courseField = TextFormField(
          initialValue: student.course,
          textInputAction: TextInputAction.done,
          decoration: inputDeco.copyWith(labelText: 'Course'),
          onChanged: (value) => student.course = value,
        );
        final removeButton = Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            color: theme.colorScheme.error,
            icon: const Icon(LucideIcons.trash2, size: 18),
          ),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE8EEF7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.26 : 0.07,
                ),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              if (stackFields) ...[
                nameField,
                const SizedBox(height: 14),
                batchField,
                const SizedBox(height: 14),
                courseField,
                if (canRemove) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: removeButton),
                ],
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: nameField),
                    if (canRemove) ...[const SizedBox(width: 12), removeButton],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: batchField),
                    const SizedBox(width: 14),
                    Expanded(child: courseField),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _FacultyEditor extends StatelessWidget {
  final _FacultyDraft faculty;
  final bool canRemove;
  final InputDecoration inputDeco;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _FacultyEditor({
    super.key,
    required this.faculty,
    required this.canRemove,
    required this.inputDeco,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackFields = constraints.maxWidth < 520;
        final nameField = TextFormField(
          initialValue: faculty.name,
          textInputAction: TextInputAction.next,
          decoration: inputDeco.copyWith(labelText: 'Faculty Name *'),
          onChanged: (value) {
            faculty.name = value;
            onChanged();
          },
          validator: (_) => faculty.name.trim().isEmpty ? 'Required' : null,
        );
        final schoolField = TextFormField(
          initialValue: faculty.school,
          textInputAction: TextInputAction.done,
          decoration: inputDeco.copyWith(labelText: 'School'),
          onChanged: (value) => faculty.school = value,
        );
        final removeButton = Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            color: theme.colorScheme.error,
            icon: const Icon(LucideIcons.trash2, size: 18),
          ),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE8EEF7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.26 : 0.07,
                ),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: stackFields
              ? Column(
                  children: [
                    nameField,
                    const SizedBox(height: 14),
                    schoolField,
                    if (canRemove) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: removeButton,
                      ),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: nameField),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: schoolField),
                    if (canRemove) ...[const SizedBox(width: 12), removeButton],
                  ],
                ),
        );
      },
    );
  }
}

class _AttachmentPickerBox extends StatelessWidget {
  final List<PlatformFile> attachments;
  final VoidCallback? onPick;
  final ValueChanged<PlatformFile> onRemove;

  const _AttachmentPickerBox({
    required this.attachments,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attachments.isNotEmpty) ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: attachments
                  .map(
                    (file) => Chip(
                      backgroundColor: theme.colorScheme.surface,
                      side: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      deleteIcon: Icon(
                        LucideIcons.xCircle,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      onDeleted: () => onRemove(file),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onPick,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
                backgroundColor: theme.colorScheme.surface,
              ),
              icon: Icon(
                LucideIcons.upload,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              label: Text(
                attachments.isEmpty ? 'Upload Files' : 'Add More Files',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'PNG, JPG, PDF, DOC, PPT, or XLS files are supported.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentTable extends StatelessWidget {
  final List<Map<String, dynamic>> students;
  final bool isFaculty;

  const _StudentTable({required this.students, this.isFaculty = false});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) return const Text('--');
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 620) {
          if (isFaculty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(1),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
                children: [
                  const TableRow(
                    children: [
                      _StudentTableCell('Faculty Name', header: true),
                      _StudentTableCell('School', header: true),
                    ],
                  ),
                  ...students.map(
                    (faculty) => TableRow(
                      children: [
                        _StudentTableCell(_studentName(faculty), bold: true),
                        _StudentTableCell(
                          _s(faculty['course'], fallback: '--'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.25),
                1: FlexColumnWidth(0.8),
                2: FlexColumnWidth(1.35),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
              children: [
                const TableRow(
                  children: [
                    _StudentTableCell('Student Name', header: true),
                    _StudentTableCell('Batch', header: true),
                    _StudentTableCell('Course', header: true),
                  ],
                ),
                ...students.map(
                  (student) => TableRow(
                    children: [
                      _StudentTableCell(_studentName(student), bold: true),
                      _StudentTableCell(_s(student['batch'], fallback: '--')),
                      _StudentTableCell(_s(student['course'], fallback: '--')),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: students.map((student) {
            final batch = _s(student['batch'], fallback: '--');
            final course = _s(student['course'], fallback: '--');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFaculty ? LucideIcons.briefcase : LucideIcons.user,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _studentName(student),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isFaculty)
                    _StudentMetaValue(label: 'School', value: course)
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _StudentMetaValue(
                            label: 'Batch',
                            value: batch,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StudentMetaValue(
                            label: 'Course',
                            value: course,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StudentMetaValue extends StatelessWidget {
  final String label;
  final String value;

  const _StudentMetaValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _StudentTableCell extends StatelessWidget {
  final String value;
  final bool header;
  final bool bold;

  const _StudentTableCell(this.value, {this.header = false, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(
        value,
        maxLines: header ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: header
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onSurface.withValues(alpha: 0.82),
          fontWeight: header || bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? action;

  const _SectionTitle({required this.title, required this.icon, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentDraft {
  String name;
  String batch;
  String course;

  _StudentDraft({this.name = '', this.batch = '', this.course = ''});

  factory _StudentDraft.fromJson(Map<String, dynamic> json) => _StudentDraft(
    name: _studentName(json),
    batch: _s(json['batch']),
    course: _s(json['course']),
  );

  Map<String, String> toJson() => {
    'student_name': name.trim(),
    'batch': batch.trim(),
    'course': course.trim(),
  };
}

class _FacultyDraft {
  String name;
  String school;

  _FacultyDraft({this.name = '', this.school = ''});

  factory _FacultyDraft.fromJson(Map<String, dynamic> json) => _FacultyDraft(
    name: _studentName(json),
    school: _s(json['school'] ?? json['course']),
  );

  Map<String, String> toStudentJson() => {
    'student_name': name.trim(),
    'batch': '',
    'course': school.trim(),
  };
}

class _IqacCriterion {
  final dynamic id;
  final String title;
  final List<_IqacSubFolder> subFolders;

  const _IqacCriterion({
    required this.id,
    required this.title,
    required this.subFolders,
  });

  factory _IqacCriterion.fromJson(Map<String, dynamic> json) => _IqacCriterion(
    id: json['id'],
    title: _s(json['title']),
    subFolders:
        (json['subFolders'] is List ? json['subFolders'] as List : const [])
            .whereType<Map>()
            .map((e) => _IqacSubFolder.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
  );
}

class _IqacSubFolder {
  final String id;
  final String title;
  final List<_IqacItem> items;

  const _IqacSubFolder({
    required this.id,
    required this.title,
    required this.items,
  });

  factory _IqacSubFolder.fromJson(Map<String, dynamic> json) => _IqacSubFolder(
    id: _s(json['id']),
    title: _s(json['title']),
    items: (json['items'] is List ? json['items'] as List : const [])
        .whereType<Map>()
        .map((e) => _IqacItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class _IqacItem {
  final String id;
  final String title;

  const _IqacItem({required this.id, required this.title});

  factory _IqacItem.fromJson(Map<String, dynamic> json) =>
      _IqacItem(id: _s(json['id']), title: _s(json['title']));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

InputDecoration _achievementInputDecoration(BuildContext context) {
  final theme = Theme.of(context);
  return InputDecoration(
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(
        color: theme.colorScheme.outline.withValues(alpha: 0.15),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: theme.colorScheme.error),
    ),
  );
}

String _s(dynamic value, {String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

String _studentName(Map<String, dynamic> student) {
  return _s(student['student_name'] ?? student['name']);
}

String _achievementTypeFromItem(Map<String, dynamic>? item) {
  final value = _s(item?['achievement_type']).toLowerCase();
  return value == 'faculty' ? 'faculty' : 'student';
}

bool _isFacultyAchievement(Map<String, dynamic> item) {
  return _achievementTypeFromItem(item) == 'faculty';
}

String _achievementTypeLabel(String value) {
  return value == 'faculty' ? 'Faculty Achievement' : 'Student Achievement';
}

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

String _itemTitle(Map<String, dynamic> item) {
  final isFaculty = _isFacultyAchievement(item);
  final students = _listOfMaps(item['students']);
  final firstName = students.isEmpty ? '' : _studentName(students.first);
  if (firstName.isNotEmpty) {
    return '${isFaculty ? 'Faculty' : 'Student'} Achievement - $firstName';
  }
  return _s(
    item['achievement_title'],
    fallback: isFaculty ? 'Faculty Achievement' : 'Student Achievement',
  );
}

String _studentLine(Map<String, dynamic> item) {
  final isFaculty = _isFacultyAchievement(item);
  final students = _listOfMaps(item['students']);
  if (students.isEmpty) return '--';
  return students
      .map(
        (student) => [
          _studentName(student),
          if (!isFaculty) _s(student['batch']),
          _s(student['course']),
        ].where((part) => part.isNotEmpty).join(' - '),
      )
      .where((line) => line.isNotEmpty)
      .join(', ');
}

List<Widget> _platformWidgets(dynamic value, ThemeData theme) {
  if (value is! List || value.isEmpty) return [const Chip(label: Text('--'))];
  final platforms = value
      .map((entry) => entry.toString())
      .where((entry) => entry.trim().isNotEmpty)
      .toList();
  if (platforms.isEmpty) return [const Chip(label: Text('--'))];
  return platforms
      .map(
        (platform) => Chip(
          avatar: Icon(
            LucideIcons.share2,
            size: 15,
            color: _platformColor(platform),
          ),
          label: Text(
            platform,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
            ),
          ),
          backgroundColor: _platformColor(platform).withValues(alpha: 0.1),
          side: BorderSide(
            color: _platformColor(platform).withValues(alpha: 0.2),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      )
      .toList();
}

Color _platformColor(String platform) {
  final normalized = platform.trim().toLowerCase();
  if (normalized.contains('instagram')) return const Color(0xFFE11D48);
  if (normalized.contains('linkedin')) return const Color(0xFF0A66C2);
  if (normalized.contains('youtube')) return const Color(0xFFDC2626);
  if (normalized.contains('twitter') || normalized.contains('x')) {
    return const Color(0xFF0284C7);
  }
  if (normalized.contains('website')) return const Color(0xFF475569);
  return const Color(0xFF64748B);
}

String _buildIqacLabel(
  List<_IqacCriterion> criteria,
  Map<String, dynamic> item,
) {
  final criterionId = _s(item['iqac_criterion_id']);
  if (criterionId.isEmpty) return '--';
  final subId = _s(item['iqac_subfolder_id']);
  final itemId = _s(item['iqac_item_id']);
  final criterion = criteria
      .where((row) => row.id.toString() == criterionId)
      .cast<_IqacCriterion?>()
      .firstOrNull;
  final sub = criterion?.subFolders
      .where((row) => row.id == subId)
      .cast<_IqacSubFolder?>()
      .firstOrNull;
  final evidence = sub?.items
      .where((row) => row.id == itemId)
      .cast<_IqacItem?>()
      .firstOrNull;
  return [
    criterion == null ? criterionId : '${criterion.id}. ${criterion.title}',
    sub == null ? subId : '${sub.id} ${sub.title}',
    evidence == null ? itemId : '${evidence.id} ${evidence.title}',
  ].where((part) => part.trim().isNotEmpty).join(' / ');
}

String _formatDate(dynamic value) {
  final raw = _s(value);
  if (raw.isEmpty) return '--';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat.yMMMd().add_jm().format(parsed.toLocal());
}

String _formatShortDate(dynamic value) {
  final raw = _s(value);
  if (raw.isEmpty) return '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return '';
  return DateFormat('MMM d, yyyy').format(parsed.toLocal());
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _messageFromError(Object error) {
  return friendlyErrorMessage(error);
}
