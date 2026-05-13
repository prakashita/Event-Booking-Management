import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

const _saPageBg = AppColors.background;
const _saSurface = AppColors.surface;
const _saBorder = AppColors.border;
const _saText = AppColors.textPrimary;
const _saMuted = AppColors.textSecondary;
const _saFaint = AppColors.surfaceVariant;
const _saAccent = AppColors.primary;
const _saAccentStrong = AppColors.primaryDark;
const _saAccentSoft = AppColors.primaryContainer;
const _saAccentBorder = Color(0xFFBBDEFB);
const _saDanger = AppColors.error;
const _saDangerSoft = AppColors.errorLight;

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
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
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
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
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
  }

  Future<bool> _deleteAchievement(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete submission?'),
        content: const Text(
          'This student achievement submission will be permanently removed.',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? theme.scaffoldBackgroundColor : _saPageBg;
    final width = MediaQuery.sizeOf(context).width;
    final isPhone = width < 640;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadAll(refresh: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isPhone ? 16 : 24,
                    isPhone ? 20 : 24,
                    isPhone ? 16 : 24,
                    8,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 720;
                      final titleBlock = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? theme.colorScheme.primaryContainer
                                            .withValues(alpha: 0.28)
                                      : _saAccentSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  LucideIcons.star,
                                  color: isDark
                                      ? theme.colorScheme.primary
                                      : _saAccent,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Student Achievements',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: isDark
                                                ? theme.colorScheme.onSurface
                                                : _saText,
                                            height: 1.1,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _isAdmin
                                          ? 'Review institutional publicity submissions'
                                          : 'Submit student visibility inputs',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: isDark
                                                ? theme
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                : _saMuted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                      final button = FilledButton.icon(
                        onPressed: () => _openForm(),
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: const Text('Submit Achievement'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _saAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      );
                      if (compact) {
                        return titleBlock;
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: titleBlock),
                          const SizedBox(width: 24),
                          button,
                        ],
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isPhone ? 16 : 24,
                    8,
                    isPhone ? 16 : 24,
                    16,
                  ),
                  child: _FilterPanel(
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
                          'Submit institutional publicity inputs to see them here.',
                      actionLabel: 'Submit Achievement',
                      onAction: () => _openForm(),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    isPhone ? 16 : 24,
                    0,
                    isPhone ? 16 : 24,
                    112,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1024),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  'All submissions',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? theme.colorScheme.onSurface
                                        : _saText,
                                  ),
                                ),
                                const Spacer(),
                                if (!_loading)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? theme.colorScheme.primaryContainer
                                          : _saAccentSoft,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${_items.length} records',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                        color: isDark
                                            ? theme
                                                  .colorScheme
                                                  .onPrimaryContainer
                                            : _saAccentStrong,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            ..._items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _AchievementCard(
                                  item: item,
                                  iqacLabel: _buildIqacLabel(_criteria, item),
                                  onTap: () => _openDetail(item),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_refreshing)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
            ],
          ),
        ),
      ),
      floatingActionButton: isPhone
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              elevation: 6,
              backgroundColor: _saAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              icon: const Icon(LucideIcons.plus, size: 20),
              label: const Text(
                'Submit',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
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
  late List<_StudentDraft> _students;
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
    final item = widget.initialItem;
    final rawStudents = item?['students'];
    _students = rawStudents is List
        ? rawStudents
              .whereType<Map>()
              .map((e) => _StudentDraft.fromJson(Map<String, dynamic>.from(e)))
              .where((e) => e.name.trim().isNotEmpty)
              .toList()
        : <_StudentDraft>[];
    if (_students.isEmpty) _students = [_StudentDraft()];
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
    _activityCtrl.dispose();
    _contextCtrl.dispose();
    _writeupCtrl.dispose();
    _iqacDescriptionCtrl.dispose();
    super.dispose();
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
      withData: true,
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final cleanedStudents = _students
        .map((s) => s.toJson())
        .where((s) => (s['student_name'] ?? '').toString().trim().isNotEmpty)
        .toList();
    if (cleanedStudents.isEmpty) {
      setState(() => _error = 'Add at least one student name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final formData = FormData();
      formData.fields
        ..add(MapEntry('students', jsonEncode(cleanedStudents)))
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

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 768),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.surface
                      : _saSurface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 24,
                      offset: Offset(0, -8),
                      color: Color(0x22000000),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: theme.brightness == Brightness.dark
                                  ? theme.colorScheme.outline.withValues(
                                      alpha: 0.18,
                                    )
                                  : _saBorder,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isEdit
                                        ? 'Edit Student Achievement'
                                        : 'Submit Student Achievement',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: theme.brightness == Brightness.dark
                                          ? theme.colorScheme.onSurface
                                          : _saText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Use this for non-event institutional publicity inputs.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.brightness == Brightness.dark
                                          ? theme.colorScheme.onSurfaceVariant
                                          : _saMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(false),
                              style: IconButton.styleFrom(
                                backgroundColor:
                                    theme.brightness == Brightness.dark
                                    ? theme.colorScheme.surfaceContainerHighest
                                    : _saFaint,
                              ),
                              icon: const Icon(LucideIcons.x, size: 20),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                          children: [
                            _FormSection(
                              child: Column(
                                children: [
                                  _SectionTitle(
                                    title: 'Students',
                                    subtitle:
                                        'Add every student who should be credited in the post.',
                                    action: TextButton(
                                      onPressed: () => setState(
                                        () => _students.add(_StudentDraft()),
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: _saAccent,
                                        backgroundColor: _saAccentSoft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      child: const Text('Add Student'),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  ...List.generate(_students.length, (index) {
                                    final student = _students[index];
                                    return _StudentEditor(
                                      key: ValueKey(student),
                                      student: student,
                                      canRemove: _students.length > 1,
                                      inputDeco: inputDeco,
                                      onChanged: () => setState(() {}),
                                      onRemove: () => setState(
                                        () => _students.removeAt(index),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: _activityCtrl,
                              minLines: 4,
                              maxLines: 7,
                              decoration: inputDeco.copyWith(
                                labelText:
                                    'Description of Activity and Achievement',
                                alignLabelWithHint: true,
                              ),
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? 'Description is required.'
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _contextCtrl,
                              minLines: 3,
                              maxLines: 6,
                              decoration: inputDeco.copyWith(
                                labelText: 'Additional Details',
                                hintText:
                                    'Context and objective of the activity',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              'Suggested Platforms to Post',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _platformOptions.map((platform) {
                                return _PlatformCheckChip(
                                  label: platform,
                                  selected: _platforms.contains(platform),
                                  onChanged: (selected) {
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
                              minLines: 4,
                              maxLines: 7,
                              decoration: inputDeco.copyWith(
                                labelText: 'Social Media Write-up',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _AttachmentPickerBox(
                              attachments: _attachments,
                              onPick: _saving ? null : _pickAttachments,
                              onRemove: (file) =>
                                  setState(() => _attachments.remove(file)),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: theme.brightness == Brightness.dark
                                    ? theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.14)
                                    : const Color(0xFFF5F7FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.brightness == Brightness.dark
                                      ? theme.colorScheme.primary.withValues(
                                          alpha: 0.22,
                                        )
                                      : _saAccentBorder,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Relevant IQAC Criterion',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final compact =
                                          constraints.maxWidth < 620;
                                      final fields = [
                                        DropdownButtonFormField<String>(
                                          key: ValueKey(
                                            'criterion-$_criterionId',
                                          ),
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
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
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
                                        DropdownButtonFormField<String>(
                                          key: ValueKey(
                                            'item-$_subFolderId-$_itemId',
                                          ),
                                          initialValue: _itemId.isEmpty
                                              ? null
                                              : _itemId,
                                          isExpanded: true,
                                          decoration: inputDeco.copyWith(
                                            labelText: 'Item',
                                          ),
                                          items:
                                              (_subFolder?.items ??
                                                      const <_IqacItem>[])
                                                  .map(
                                                    (i) => DropdownMenuItem(
                                                      value: i.id,
                                                      child: Text(
                                                        '${i.id} ${i.title}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                          onChanged: _subFolder == null
                                              ? null
                                              : (value) => setState(
                                                  () => _itemId = value ?? '',
                                                ),
                                        ),
                                      ];
                                      if (compact) {
                                        return Column(
                                          children: fields
                                              .map(
                                                (field) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 12,
                                                      ),
                                                  child: field,
                                                ),
                                              )
                                              .toList(),
                                        );
                                      }
                                      return Row(
                                        children: fields
                                            .map(
                                              (field) => Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 12,
                                                      ),
                                                  child: field,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: _iqacDescriptionCtrl,
                                    decoration: inputDeco.copyWith(
                                      labelText: 'IQAC Description',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: theme.colorScheme.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: theme.colorScheme.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark
                              ? theme.colorScheme.surface
                              : _saSurface,
                          border: Border(
                            top: BorderSide(
                              color: theme.brightness == Brightness.dark
                                  ? theme.colorScheme.outline.withValues(
                                      alpha: 0.18,
                                    )
                                  : _saBorder,
                            ),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final phone = constraints.maxWidth < 420;
                            final cancel = OutlinedButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _saText,
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            );
                            final submit = FilledButton(
                              onPressed: _saving ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: _saAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      phone
                                          ? (_isEdit ? 'Save' : 'Submit')
                                          : (_isEdit
                                                ? 'Save Changes'
                                                : 'Submit Student Achievement'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            );
                            if (phone) {
                              return Row(
                                children: [
                                  Expanded(child: cancel),
                                  const SizedBox(width: 10),
                                  Expanded(child: submit),
                                ],
                              );
                            }
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                cancel,
                                const SizedBox(width: 12),
                                submit,
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
    final isDark = theme.brightness == Brightness.dark;
    final iqacText = [
      _buildIqacLabel(criteria, item),
      _s(item['iqac_description']),
    ].where((part) => part.trim().isNotEmpty && part != '--').join('\n');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 768),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.surface : _saSurface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 24,
                    offset: Offset(0, -8),
                    color: Color(0x22000000),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? theme.colorScheme.outline.withValues(
                                  alpha: 0.18,
                                )
                              : _saBorder,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _itemTitle(item),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? theme.colorScheme.onSurface
                                      : _saText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Submitted ${_formatDate(item['created_at'])}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? theme.colorScheme.onSurfaceVariant
                                      : _saMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark
                                ? theme.colorScheme.surfaceContainerHighest
                                : _saFaint,
                          ),
                          icon: const Icon(LucideIcons.x, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      children: [
                        _DetailCard(
                          title: 'Students',
                          child: _StudentTable(
                            students: _listOfMaps(item['students']),
                          ),
                        ),
                        _DetailCard(
                          title: 'Description',
                          child: Text(
                            _s(
                              item['activity_description'],
                              fallback: 'No description provided.',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ),
                        _DetailCard(
                          title: 'Additional Details',
                          child: Text(
                            _s(
                              item['additional_context_objective'],
                              fallback: 'No additional details.',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ),
                        _DetailCard(
                          title: 'Selected Platforms',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _platformWidgets(
                              item['suggested_platforms'],
                            ),
                          ),
                        ),
                        _DetailCard(
                          title: 'Social Media Write-up',
                          child: Text(
                            _s(
                              item['social_media_writeup'],
                              fallback: 'No write-up provided.',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ),
                        _DetailCard(
                          title: 'Attachments',
                          child: attachments.isEmpty
                              ? Text(
                                  'No attachments',
                                  style: TextStyle(
                                    color: isDark
                                        ? theme.colorScheme.onSurfaceVariant
                                        : _saMuted,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: attachments.map((file) {
                                    final name = _s(
                                      file['file_name'],
                                      fallback: 'Document',
                                    );
                                    final link = _s(file['web_view_link']);
                                    return ActionChip(
                                      avatar: const Icon(
                                        LucideIcons.fileText,
                                        size: 16,
                                      ),
                                      label: Text(name),
                                      backgroundColor: isDark
                                          ? theme.colorScheme.primaryContainer
                                                .withValues(alpha: 0.22)
                                          : const Color(0xFFECFDF5),
                                      side: BorderSide(
                                        color: isDark
                                            ? theme.colorScheme.primary
                                                  .withValues(alpha: 0.24)
                                            : const Color(0xFFA7F3D0),
                                      ),
                                      labelStyle: TextStyle(
                                        color: isDark
                                            ? theme.colorScheme.primary
                                            : const Color(0xFF047857),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      onPressed: link.isEmpty
                                          ? null
                                          : () => _openUrl(link),
                                    );
                                  }).toList(),
                                ),
                        ),
                        if (iqacText.isNotEmpty)
                          _DetailCard(
                            title: 'IQAC Criterion',
                            child: Text(
                              iqacText,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.45,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.28)
                                : _saFaint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? theme.colorScheme.outline.withValues(
                                      alpha: 0.18,
                                    )
                                  : _saBorder,
                            ),
                          ),
                          child: Wrap(
                            spacing: 32,
                            runSpacing: 16,
                            children: [
                              _MetaBlock(
                                label: 'Created By',
                                value: _s(
                                  item['created_by_name'] ??
                                      item['created_by_email'],
                                  fallback: '--',
                                ),
                              ),
                              _MetaBlock(
                                label: 'Created At',
                                value: _formatDate(item['created_at']),
                              ),
                              _MetaBlock(
                                label: 'Last Updated By',
                                value: _s(
                                  item['updated_by_name'] ??
                                      item['updated_by_email'],
                                  fallback: '--',
                                ),
                              ),
                              _MetaBlock(
                                label: 'Updated At',
                                value: _formatDate(item['updated_at']),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: isDark ? theme.colorScheme.surface : _saSurface,
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? theme.colorScheme.outline.withValues(
                                  alpha: 0.18,
                                )
                              : _saBorder,
                        ),
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? theme.colorScheme.onSurface
                                : _saText,
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Close'),
                        ),
                        if (canEdit)
                          FilledButton.icon(
                            onPressed: onEdit,
                            style: FilledButton.styleFrom(
                              backgroundColor: _saAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(LucideIcons.edit, size: 17),
                            label: const Text('Edit'),
                          ),
                        if (canDelete)
                          OutlinedButton(
                            onPressed: onDelete,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _saDanger,
                              side: const BorderSide(color: Color(0xFFFECACA)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Delete'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : _saSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.18)
              : _saBorder,
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
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: isDark ? theme.colorScheme.onSurface : _saText,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  final Widget child;

  const _FormSection({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : _saSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.2)
              : _saBorder,
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
      child: child,
    );
  }
}

class _PlatformCheckChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _PlatformCheckChip({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? (isDark
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.26)
                    : _saAccentSoft)
              : (isDark ? theme.colorScheme.surface : _saSurface),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? (isDark
                      ? theme.colorScheme.primary.withValues(alpha: 0.3)
                      : _saAccentBorder)
                : (isDark
                      ? theme.colorScheme.outline.withValues(alpha: 0.2)
                      : _saBorder),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: selected,
                onChanged: (value) => onChanged(value ?? false),
                activeColor: _saAccent,
                visualDensity: VisualDensity.compact,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? theme.colorScheme.onSurface
                    : const Color(0xFF334155),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaBlock extends StatelessWidget {
  final String label;
  final String value;

  const _MetaBlock({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 132,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: isDark
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : _saMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              color: isDark ? Theme.of(context).colorScheme.onSurface : _saText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
    final isDark = theme.brightness == Brightness.dark;

    InputDecoration filterInputDecoration(String hint, IconData icon) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark
              ? theme.colorScheme.onSurfaceVariant
              : const Color(0xFF94A3B8),
          fontSize: 14,
        ),
        prefixIcon: Icon(
          icon,
          size: 18,
          color: isDark ? theme.colorScheme.primary : _saMuted,
        ),
        filled: true,
        fillColor: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22)
            : AppColors.surfaceVariant.withValues(alpha: 0.55),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? theme.colorScheme.outline.withValues(alpha: 0.2)
                : AppColors.divider,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? theme.colorScheme.outline.withValues(alpha: 0.2)
                : AppColors.divider,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? theme.colorScheme.primary : _saAccent,
            width: 2,
          ),
        ),
      );
    }

    final platformDropdown = DropdownButtonFormField<String>(
      key: ValueKey('platform-$platform'),
      initialValue: platform.isEmpty ? null : platform,
      isExpanded: true,
      icon: const Icon(LucideIcons.chevronDown, size: 18),
      decoration: filterInputDecoration('All platforms', LucideIcons.filter),
      items: [
        const DropdownMenuItem(value: '', child: Text('All platforms')),
        ...platforms.map(
          (p) => DropdownMenuItem(
            value: p,
            child: Text(p, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) => onPlatformChanged(value ?? ''),
    );

    final criterionDropdown = DropdownButtonFormField<String>(
      key: ValueKey('criterion-filter-$criterion'),
      initialValue: criterion.isEmpty ? null : criterion,
      isExpanded: true,
      icon: const Icon(LucideIcons.chevronDown, size: 18),
      decoration: filterInputDecoration(
        criteriaLoading ? 'Loading...' : 'All IQAC criteria',
        LucideIcons.filter,
      ),
      items: [
        const DropdownMenuItem(value: '', child: Text('All IQAC criteria')),
        ...criteria.map(
          (c) => DropdownMenuItem(
            value: c.id.toString(),
            child: Text('${c.id}. ${c.title}', overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) => onCriterionChanged(value ?? ''),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : _saSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.16)
              : AppColors.divider,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final phone = constraints.maxWidth < 460;
          final search = TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration:
                filterInputDecoration(
                  'Search by student, batch, course...',
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
          );
          final controls = Row(
            children: [
              Expanded(child: platformDropdown),
              const SizedBox(width: 12),
              if (!phone) ...[
                Expanded(child: criterionDropdown),
                const SizedBox(width: 12),
              ],
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isDark
                        ? theme.colorScheme.outline.withValues(alpha: 0.2)
                        : AppColors.divider,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  icon: Icon(
                    LucideIcons.refreshCw,
                    size: 18,
                    color: isDark
                        ? theme.colorScheme.onSurfaceVariant
                        : const Color(0xFF475569),
                  ),
                  onPressed: onSearch,
                  tooltip: 'Refresh',
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              children: [
                search,
                const SizedBox(height: 12),
                controls,
                if (phone) ...[const SizedBox(height: 12), criterionDropdown],
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: search),
              const SizedBox(width: 16),
              Expanded(flex: 4, child: controls),
            ],
          );
        },
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
    final firstStudent = title.replaceAll('Student Achievement - ', '');
    final initials = _getInitials(firstStudent);
    final creatorName = _s(
      item['created_by_name'] ?? item['created_by_email'],
      fallback: 'Unknown',
    );
    final shortDate = _formatShortDate(item['created_at']);
    final borderColor = isDark
        ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
        : AppColors.divider;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isDark
                            ? theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.3,
                              )
                            : _saAccentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: isDark ? theme.colorScheme.primary : _saAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? theme.colorScheme.onSurface
                                  : _saText,
                              fontSize: 15.5,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _studentLine(item),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark
                                  ? theme.colorScheme.onSurfaceVariant
                                  : const Color(0xFF64748B),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (shortDate.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? theme.colorScheme.surfaceContainerHighest
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          shortDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? theme.colorScheme.onSurfaceVariant
                                : _saMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _s(
                    item['activity_description'],
                    fallback: 'No description supplied.',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.82)
                        : AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: isDark
                      ? theme.colorScheme.outline.withValues(alpha: 0.14)
                      : AppColors.divider,
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    final meta = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.users,
                          size: 14,
                          color: isDark
                              ? theme.colorScheme.onSurfaceVariant
                              : _saMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            creatorName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? theme.colorScheme.onSurfaceVariant
                                  : _saMuted,
                            ),
                          ),
                        ),
                      ],
                    );
                    final details = TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: _saAccent,
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                      ),
                      onPressed: onTap,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('View'),
                          SizedBox(width: 4),
                          Icon(LucideIcons.chevronRight, size: 16),
                        ],
                      ),
                    );
                    final tags = Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _buildPlatformTags(
                        item['suggested_platforms'],
                        theme,
                        isDark,
                      ),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tags,
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(child: meta),
                              details,
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: tags),
                        const SizedBox(width: 16),
                        Flexible(child: meta),
                        const SizedBox(width: 16),
                        details,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPlatformTags(
    dynamic platforms,
    ThemeData theme,
    bool isDark,
  ) {
    if (platforms is! List || platforms.isEmpty) return [];
    return platforms
        .map((platform) => platform.toString())
        .where((platform) => platform.trim().isNotEmpty)
        .map(
          (platform) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : _saAccentSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isDark
                    ? theme.colorScheme.primary.withValues(alpha: 0.2)
                    : _saAccentBorder,
              ),
            ),
            child: Text(
              platform,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? theme.colorScheme.primary : _saAccentStrong,
              ),
            ),
          ),
        )
        .toList();
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
    final nameField = TextFormField(
      initialValue: student.name,
      decoration: inputDeco.copyWith(labelText: 'Student Name *'),
      onChanged: (value) {
        student.name = value;
        onChanged();
      },
      validator: (_) => student.name.trim().isEmpty ? 'Required' : null,
    );
    final batchField = TextFormField(
      initialValue: student.batch,
      decoration: inputDeco.copyWith(labelText: 'Batch'),
      onChanged: (value) => student.batch = value,
    );
    final courseField = TextFormField(
      initialValue: student.course,
      decoration: inputDeco.copyWith(labelText: 'Course'),
      onChanged: (value) => student.course = value,
    );
    final removeButton = TextButton(
      onPressed: canRemove ? onRemove : null,
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.error,
        backgroundColor: canRemove ? _saDangerSoft : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Remove'),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 620) {
            return Column(
              children: [
                nameField,
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: batchField),
                    const SizedBox(width: 12),
                    Expanded(child: courseField),
                  ],
                ),
                if (canRemove) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: removeButton),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: nameField),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: batchField),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: courseField),
              const SizedBox(width: 12),
              SizedBox(width: 92, child: removeButton),
            ],
          );
        },
      ),
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
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22)
            : _saSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.outline.withValues(alpha: 0.22)
              : _saBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Images and Attachments/Documents',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.onSurfaceVariant
                  : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 12),
          if (attachments.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: attachments
                  .map(
                    (file) => Chip(
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onDeleted: () => onRemove(file),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPick,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? theme.colorScheme.surface
                    : _saSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.brightness == Brightness.dark
                      ? theme.colorScheme.outline.withValues(alpha: 0.28)
                      : _saBorder,
                  width: 1.4,
                  strokeAlign: BorderSide.strokeAlignInside,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    LucideIcons.upload,
                    size: 34,
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.onSurfaceVariant
                        : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 10),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        color: isDark
                            ? theme.colorScheme.onSurfaceVariant
                            : _saMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: attachments.isEmpty
                              ? 'Upload a file'
                              : 'Add more files',
                          style: TextStyle(
                            color: isDark
                                ? theme.colorScheme.primary
                                : _saAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: ' or drag and drop'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'PNG, JPG, PDF up to 10MB',
                    style: TextStyle(
                      color: isDark
                          ? theme.colorScheme.onSurfaceVariant
                          : _saMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentTable extends StatelessWidget {
  final List<Map<String, dynamic>> students;

  const _StudentTable({required this.students});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) return const Text('--');
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Table(
        border: TableBorder.all(
          color: theme.brightness == Brightness.dark
              ? theme.colorScheme.outline.withValues(alpha: 0.16)
              : _saBorder,
        ),
        columnWidths: const {
          0: FlexColumnWidth(1.3),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.24,
                    )
                  : _saFaint,
            ),
            children: const [
              _TableCellText('Student Name', header: true),
              _TableCellText('Batch', header: true),
              _TableCellText('Course', header: true),
            ],
          ),
          ...students.map(
            (student) => TableRow(
              children: [
                _TableCellText(_studentName(student), bold: true),
                _TableCellText(_s(student['batch'], fallback: '-')),
                _TableCellText(_s(student['course'], fallback: '-')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableCellText extends StatelessWidget {
  final String text;
  final bool header;
  final bool bold;

  const _TableCellText(this.text, {this.header = false, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          color: isDark
              ? theme.colorScheme.onSurface
              : (header ? _saText : const Color(0xFF334155)),
          fontSize: 14,
          fontWeight: header || bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const _SectionTitle({required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isDark ? theme.colorScheme.onSurface : _saText,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: isDark
                          ? theme.colorScheme.onSurfaceVariant
                          : _saMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?action,
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
  final isDark = theme.brightness == Brightness.dark;
  return InputDecoration(
    filled: true,
    fillColor: isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18)
        : Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8), // rounded-lg
      borderSide: BorderSide(
        color: isDark
            ? theme.colorScheme.outline.withValues(alpha: 0.2)
            : _saBorder,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: isDark
            ? theme.colorScheme.outline.withValues(alpha: 0.2)
            : _saBorder,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: isDark ? theme.colorScheme.primary : _saAccent,
        width: 2,
      ), // ring-indigo-500
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
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

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

String _itemTitle(Map<String, dynamic> item) {
  final students = _listOfMaps(item['students']);
  final firstName = students.isEmpty ? '' : _studentName(students.first);
  if (firstName.isNotEmpty) return 'Student Achievement - $firstName';
  return _s(item['achievement_title'], fallback: 'Student Achievement');
}

String _studentLine(Map<String, dynamic> item) {
  final students = _listOfMaps(item['students']);
  if (students.isEmpty) return '--';
  return students
      .map(
        (student) => [
          _studentName(student),
          _s(student['batch']),
          _s(student['course']),
        ].where((part) => part.isNotEmpty).join(' - '),
      )
      .where((line) => line.isNotEmpty)
      .join(', ');
}

List<Widget> _platformWidgets(dynamic value) {
  if (value is! List || value.isEmpty) {
    return [const _PillLabel('--')];
  }
  final platforms = value
      .map((entry) => entry.toString())
      .where((entry) => entry.trim().isNotEmpty)
      .toList();
  if (platforms.isEmpty) return [const _PillLabel('--')];
  return platforms.map((platform) => _PillLabel(platform)).toList();
}

class _PillLabel extends StatelessWidget {
  final String label;

  const _PillLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7)
            : _saFaint,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? theme.colorScheme.onSurface : const Color(0xFF334155),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (error.message != null) return error.message!;
  }
  final text = error.toString();
  return text.isEmpty ? 'Something went wrong.' : text;
}
