import 'dart:convert';

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
        title: const Text('Delete submission?'),
        content: const Text(
          'This student achievement submission will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: () => _loadAll(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Students' Achievements",
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isAdmin ? 'All submissions' : 'My submissions',
                        style: TextStyle(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Submit'),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              _StateCard(
                icon: LucideIcons.alertCircle,
                title: 'Unable to load submissions',
                message: _error!,
                actionLabel: 'Retry',
                onAction: () => _loadAll(refresh: true),
              )
            else if (_items.isEmpty)
              _StateCard(
                icon: LucideIcons.star,
                title: 'No student achievements found',
                message: 'Submit institutional publicity inputs from the app.',
                actionLabel: 'Submit Achievement',
                onAction: () => _openForm(),
              )
            else ...[
              Text(
                '${_items.length} record${_items.length == 1 ? '' : 's'}',
                style: TextStyle(color: muted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              ..._items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AchievementCard(
                    item: item,
                    iqacLabel: _buildIqacLabel(_criteria, item),
                    onTap: () => _openDetail(item),
                  ),
                ),
              ),
            ],
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Submit Achievement'),
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

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Material(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Form(
              key: _formKey,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEdit
                              ? 'Edit Student Achievement'
                              : 'Submit Student Achievement',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        icon: const Icon(LucideIcons.x),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionTitle(
                    title: 'Students',
                    action: TextButton.icon(
                      onPressed: () =>
                          setState(() => _students.add(_StudentDraft())),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Add'),
                    ),
                  ),
                  ...List.generate(_students.length, (index) {
                    final student = _students[index];
                    return _StudentEditor(
                      key: ValueKey(student),
                      student: student,
                      canRemove: _students.length > 1,
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() => _students.removeAt(index)),
                    );
                  }),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _activityCtrl,
                    minLines: 4,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Description of Activity and Achievement',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Description is required.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contextCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Additional Details',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(title: 'Suggested Platforms'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _platformOptions.map((platform) {
                      return FilterChip(
                        label: Text(platform),
                        selected: _platforms.contains(platform),
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _writeupCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Social Media Write-up',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickAttachments,
                    icon: const Icon(LucideIcons.paperclip, size: 18),
                    label: Text(
                      _attachments.isEmpty
                          ? 'Add images and documents'
                          : '${_attachments.length} attachment${_attachments.length == 1 ? '' : 's'} selected',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(title: 'Relevant IQAC Criterion'),
                  DropdownButtonFormField<String>(
                    key: ValueKey('criterion-$_criterionId'),
                    initialValue: _criterionId.isEmpty ? null : _criterionId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Criterion',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.criteria
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id.toString(),
                            child: Text('${c.id}. ${c.title}'),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('subfolder-$_criterionId-$_subFolderId'),
                    initialValue: _subFolderId.isEmpty ? null : _subFolderId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Subfolder',
                      border: OutlineInputBorder(),
                    ),
                    items: (_criterion?.subFolders ?? const <_IqacSubFolder>[])
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text('${s.id} ${s.title}'),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('item-$_subFolderId-$_itemId'),
                    initialValue: _itemId.isEmpty ? null : _itemId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Item',
                      border: OutlineInputBorder(),
                    ),
                    items: (_subFolder?.items ?? const <_IqacItem>[])
                        .map(
                          (i) => DropdownMenuItem(
                            value: i.id,
                            child: Text('${i.id} ${i.title}'),
                          ),
                        )
                        .toList(),
                    onChanged: _subFolder == null
                        ? null
                        : (value) => setState(() => _itemId = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _iqacDescriptionCtrl,
                    decoration: const InputDecoration(
                      labelText: 'IQAC Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.save, size: 18),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : (_isEdit
                                ? 'Save Changes'
                                : 'Submit Student Achievement'),
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
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Material(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _itemTitle(item),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DetailBlock(
                title: 'Students',
                child: _StudentTable(students: _listOfMaps(item['students'])),
              ),
              _DetailBlock(
                title: 'Description',
                text: _s(item['activity_description'], fallback: '--'),
              ),
              _DetailBlock(
                title: 'Additional Details',
                text: _s(item['additional_context_objective'], fallback: '--'),
              ),
              _DetailBlock(
                title: 'Selected Platforms',
                text: _joinList(item['suggested_platforms']),
              ),
              _DetailBlock(
                title: 'Social Media Write-up',
                text: _s(item['social_media_writeup'], fallback: '--'),
              ),
              _DetailBlock(
                title: 'IQAC Criterion',
                text: _buildIqacLabel(criteria, item),
              ),
              if (_s(item['iqac_description']).isNotEmpty)
                _DetailBlock(
                  title: 'IQAC Description',
                  text: _s(item['iqac_description']),
                ),
              _DetailBlock(
                title: 'Attachments',
                child: attachments.isEmpty
                    ? const Text('--')
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: attachments.map((file) {
                          final name = _s(
                            file['file_name'],
                            fallback: 'Attachment',
                          );
                          final link = _s(file['web_view_link']);
                          return ActionChip(
                            avatar: const Icon(
                              LucideIcons.externalLink,
                              size: 16,
                            ),
                            label: Text(name),
                            onPressed: link.isEmpty
                                ? null
                                : () => _openUrl(link),
                          );
                        }).toList(),
                      ),
              ),
              _DetailBlock(
                title: 'Audit',
                text:
                    'Created by ${_s(item['created_by_name'] ?? item['created_by_email'], fallback: '--')}\n'
                    'Created at ${_formatDate(item['created_at'])}\n'
                    'Updated by ${_s(item['updated_by_name'] ?? item['updated_by_email'], fallback: '--')}\n'
                    'Updated at ${_formatDate(item['updated_at'])}',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Close'),
                  ),
                  if (canEdit)
                    FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(LucideIcons.edit, size: 16),
                      label: const Text('Edit'),
                    ),
                  if (canDelete)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                      ),
                      onPressed: onDelete,
                      icon: const Icon(LucideIcons.trash2, size: 16),
                      label: const Text('Delete'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: 'Search student, batch, course, description',
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              suffixIcon: IconButton(
                tooltip: 'Search',
                onPressed: onSearch,
                icon: const Icon(LucideIcons.arrowRight, size: 18),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('platform-$platform'),
            initialValue: platform.isEmpty ? null : platform,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Platform',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All platforms')),
              ...platforms.map(
                (p) => DropdownMenuItem(value: p, child: Text(p)),
              ),
            ],
            onChanged: (value) => onPlatformChanged(value ?? ''),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('criterion-filter-$criterion'),
            initialValue: criterion.isEmpty ? null : criterion,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: criteriaLoading
                  ? 'Loading IQAC criteria...'
                  : 'IQAC criterion',
              border: const OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('All IQAC criteria'),
              ),
              ...criteria.map(
                (c) => DropdownMenuItem(
                  value: c.id.toString(),
                  child: Text('${c.id}. ${c.title}'),
                ),
              ),
            ],
            onChanged: (value) => onCriterionChanged(value ?? ''),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _itemTitle(item),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(LucideIcons.chevronRight, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(_studentLine(item), style: TextStyle(color: muted)),
            const SizedBox(height: 12),
            Text(
              _s(
                item['activity_description'],
                fallback: 'No description supplied.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  icon: LucideIcons.share2,
                  label: _joinList(item['suggested_platforms']),
                ),
                _MetaChip(icon: LucideIcons.database, label: iqacLabel),
                _MetaChip(
                  icon: LucideIcons.user,
                  label: _s(
                    item['created_by_name'] ?? item['created_by_email'],
                    fallback: '--',
                  ),
                ),
                _MetaChip(
                  icon: LucideIcons.clock,
                  label: _formatDate(item['created_at']),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentEditor extends StatelessWidget {
  final _StudentDraft student;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _StudentEditor({
    super.key,
    required this.student,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          TextFormField(
            initialValue: student.name,
            decoration: const InputDecoration(labelText: 'Student Name'),
            onChanged: (value) {
              student.name = value;
              onChanged();
            },
            validator: (_) => student.name.trim().isEmpty
                ? 'Student name is required.'
                : null,
          ),
          TextFormField(
            initialValue: student.batch,
            decoration: const InputDecoration(labelText: 'Batch'),
            onChanged: (value) => student.batch = value,
          ),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: student.course,
                  decoration: const InputDecoration(labelText: 'Course'),
                  onChanged: (value) => student.course = value,
                ),
              ),
              IconButton(
                tooltip: 'Remove student',
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(LucideIcons.trash2),
              ),
            ],
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
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            _studentName(student),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            [
              _s(student['batch']),
              _s(student['course']),
            ].where((e) => e.isNotEmpty).join(' - '),
          ),
        );
      }).toList(),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final String? text;
  final Widget? child;

  const _DetailBlock({required this.title, this.text, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          child ?? Text(text ?? '--'),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? action;

  const _SectionTitle({required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
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
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
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

String _joinList(dynamic value) {
  if (value is! List || value.isEmpty) return '--';
  final text = value
      .map((e) => e.toString())
      .where((e) => e.trim().isNotEmpty)
      .join(', ');
  return text.isEmpty ? '--' : text;
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
