import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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

    return Scaffold(
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
                                  'Student Achievements',
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
                            ? 'Manage all institutional submissions.'
                            : 'Submit student material for institutional visibility.',
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
                          'Submit institutional publicity inputs to see them here.',
                      actionLabel: 'Submit Achievement',
                      onAction: () => _openForm(),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
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
        elevation: 3,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text(
          'Submit',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: const [BoxShadow(blurRadius: 20, color: Colors.black26)],
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(24, 12, 24, 32 + bottom),
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isEdit ? LucideIcons.edit2 : LucideIcons.plus,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _isEdit ? 'Edit Achievement' : 'Submit Achievement',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                      icon: const Icon(LucideIcons.x, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Use this for non-event institutional publicity inputs.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
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
                    onRemove: () => setState(() => _students.removeAt(index)),
                  );
                }),
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
                  onRemove: (file) => setState(() => _attachments.remove(file)),
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
                      color: theme.colorScheme.outline.withValues(alpha: 0.15),
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
                        decoration: inputDeco.copyWith(labelText: 'Criterion'),
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
                        key: ValueKey('subfolder-$_criterionId-$_subFolderId'),
                        initialValue: _subFolderId.isEmpty
                            ? null
                            : _subFolderId,
                        isExpanded: true,
                        decoration: inputDeco.copyWith(labelText: 'Subfolder'),
                        items:
                            (_criterion?.subFolders ?? const <_IqacSubFolder>[])
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
                            (_criterion?.subFolders ?? const <_IqacSubFolder>[])
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
                            : (value) => setState(() => _itemId = value ?? ''),
                      ),
                      const SizedBox(height: 16),
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
                            _isEdit ? 'Save Changes' : 'Submit Achievement',
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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: const [BoxShadow(blurRadius: 20, color: Colors.black26)],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _itemTitle(item),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            height: 1.2,
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
                              'Submitted ${_formatDate(item['created_at'])}',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _DetailCard(
                icon: LucideIcons.users,
                title: 'Students',
                child: _StudentTable(students: _listOfMaps(item['students'])),
              ),
              _DetailCard(
                icon: LucideIcons.fileText,
                title: 'Details',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _s(item['activity_description'], fallback: '--'),
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Additional Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _s(item['additional_context_objective'], fallback: '--'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.6,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _DetailCard(
                icon: LucideIcons.share2,
                title: 'Publicity',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _platformWidgets(
                        item['suggested_platforms'],
                        theme,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Social Media Write-up',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.1,
                          ),
                        ),
                      ),
                      child: Text(
                        _s(item['social_media_writeup'], fallback: '--'),
                        style: const TextStyle(
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _DetailCard(
                icon: LucideIcons.paperclip,
                title: 'Attachments',
                child: attachments.isEmpty
                    ? Text(
                        '--',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
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
                            avatar: Icon(
                              LucideIcons.fileBox,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            label: Text(name),
                            backgroundColor: theme.colorScheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            ),
                            onPressed: link.isEmpty
                                ? null
                                : () => _openUrl(link),
                          );
                        }).toList(),
                      ),
              ),
              _DetailCard(
                icon: LucideIcons.database,
                title: 'IQAC Mapping',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _buildIqacLabel(criteria, item),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    if (_s(item['iqac_description']).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        _s(item['iqac_description']),
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Record ID: ${_s(item['id'])}\n'
                    'Last updated by ${_s(item['updated_by_name'] ?? item['updated_by_email'], fallback: '--')}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (canEdit) ...[
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onEdit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(LucideIcons.edit2, size: 18),
                        label: const Text(
                          'Edit',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (canDelete) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: onDelete,
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  label: const Text(
                    'Delete Submission',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _DetailCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
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
                  'Search student, batch...',
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
    final firstStudent = title.replaceAll('Student Achievement - ', '');
    final initials = _getInitials(firstStudent);
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
                                LucideIcons.graduationCap,
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

  const _StudentTable({required this.students});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) return const Text('--');
    return Column(
      children: students.map((student) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.user,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _studentName(student),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        _s(student['batch']),
                        _s(student['course']),
                      ].where((e) => e.isNotEmpty).join(' - '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
          label: Text(
            platform,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: theme.colorScheme.secondaryContainer.withValues(
            alpha: 0.5,
          ),
          side: BorderSide(
            color: theme.colorScheme.secondary.withValues(alpha: 0.2),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      )
      .toList();
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
