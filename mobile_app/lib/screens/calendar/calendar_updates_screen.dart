import 'package:dio/dio.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

enum _EntryTypeFilter { all, holiday, academic }

enum _SyncFilter { all, synced, pending, failed, disabled }

enum _ActiveFilter { all, active, inactive }

class _InstitutionEntry {
  final String id;
  final String title;
  final String description;
  final String entryType;
  final String category;
  final String academicYear;
  final String semesterType;
  final String semester;
  final String startDate;
  final String endDate;
  final int? calendarYear;
  final bool isActive;
  final bool isAllDay;
  final bool visibleToAll;
  final bool googleSyncEnabled;
  final String syncStatus;
  final String? color;

  const _InstitutionEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.entryType,
    required this.category,
    required this.academicYear,
    required this.semesterType,
    required this.semester,
    required this.startDate,
    required this.endDate,
    required this.calendarYear,
    required this.isActive,
    required this.isAllDay,
    required this.visibleToAll,
    required this.googleSyncEnabled,
    required this.syncStatus,
    required this.color,
  });

  factory _InstitutionEntry.fromJson(Map<String, dynamic> json) {
    final dynamic calendarYearRaw = json['calendar_year'];
    return _InstitutionEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? json['holiday_name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      entryType: (json['entry_type'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      academicYear: (json['academic_year'] ?? '').toString(),
      semesterType: (json['semester_type'] ?? '').toString(),
      semester: (json['semester'] ?? '').toString(),
      startDate: (json['start_date'] ?? json['date'] ?? '').toString(),
      endDate: (json['end_date'] ?? json['date'] ?? '').toString(),
      calendarYear: calendarYearRaw is int
          ? calendarYearRaw
          : int.tryParse((calendarYearRaw ?? '').toString()),
      isActive: json['is_active'] == true,
      isAllDay: json['all_day'] != false,
      visibleToAll: json['visible_to_all'] != false,
      googleSyncEnabled: json['google_sync_enabled'] == true,
      syncStatus: (json['sync_status'] ?? 'disabled').toString(),
      color: json['color']?.toString(),
    );
  }

  String get dateLabel {
    if (endDate.isEmpty || endDate == startDate) return startDate;
    return '$startDate to $endDate';
  }
}

class CalendarUpdatesScreen extends StatefulWidget {
  const CalendarUpdatesScreen({super.key});

  @override
  State<CalendarUpdatesScreen> createState() => _CalendarUpdatesScreenState();
}

class _CalendarUpdatesScreenState extends State<CalendarUpdatesScreen> {
  final _api = ApiService();

  static const int _minCalendarYear = 1900;
  static const int _maxCalendarYear = 3000;
  static final RegExp _hexColorRegex = RegExp(r'^#?[0-9a-fA-F]{6}$');

  bool _isLoading = true;
  String? _error;

  List<_InstitutionEntry> _entries = [];
  _EntryTypeFilter _typeFilter = _EntryTypeFilter.all;
  String _search = '';
  String _yearFilter = 'All Years';
  String _semesterFilter = 'All Semesters';
  String _categoryFilter = 'All Categories';
  _SyncFilter _syncFilter = _SyncFilter.all;
  _ActiveFilter _activeFilter = _ActiveFilter.all;

  static const List<String> _academicCategories = [
    'Commencement',
    'Registration',
    'Submission',
    'Instruction',
    'Examination',
    'Assessment',
    'Committee Meeting',
    'Fest',
    'Result',
    'Application',
    'Eligibility List',
    'Semester Closure',
    'Semester Start',
    'Semester End',
    'Other',
  ];

  static const List<String> _semesterTypes = [
    'Even Semester',
    'Odd Semester',
    'Summer Term',
  ];

  static const List<String> _semesters = [
    'Semester I',
    'Semester II',
    'Semester III',
    'Semester IV',
    'Semester V',
    'Semester VI',
    'Semester VII',
    'Semester VIII',
    'Summer Term',
  ];

  static List<String> _generateAcademicYears({
    int startYear = 2025,
    int endYear = 2050,
  }) {
    final years = <String>[];
    for (var y = startYear; y <= endYear; y++) {
      years.add('$y-${y + 1}');
    }
    return years;
  }

  String _currentAcademicYear() {
    final now = DateTime.now();
    final year = now.month >= 6 ? now.year : now.year - 1;
    return '$year-${year + 1}';
  }

  bool get _canManage {
    final role = (context.read<AuthProvider>().user?.roleKey ?? '')
        .toLowerCase();
    return role == 'admin' ||
        role == 'registrar' ||
        role == 'vice_chancellor' ||
        role == 'deputy_registrar' ||
        role == 'finance_team';
  }

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final path = _canManage
          ? '/institution-calendar'
          : '/institution-calendar/public';
      final params = <String, dynamic>{};

      if (_typeFilter == _EntryTypeFilter.holiday) {
        params['entry_type'] = 'holiday';
      } else if (_typeFilter == _EntryTypeFilter.academic) {
        params['entry_type'] = 'academic';
      }
      if (_yearFilter != 'All Years') {
        params['academic_year'] = _yearFilter;
      }
      if (_semesterFilter != 'All Semesters') {
        params['semester'] = _semesterFilter;
      }
      if (_categoryFilter != 'All Categories') {
        params['category'] = _categoryFilter;
      }

      final data = await _api.get<List<dynamic>>(path, params: params);
      if (!mounted) return;
      setState(() {
        _entries = data
            .whereType<Map<String, dynamic>>()
            .map(_InstitutionEntry.fromJson)
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _extractError(e);
        _isLoading = false;
      });
    }
  }

  String _extractError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        final errors = data['errors'] ?? detail;
        if (errors is List) {
          return errors.map((e) => e.toString()).join('\n');
        }
      }
      return error.message ?? 'Request failed.';
    }
    return error.toString();
  }

  String _normalizeHexColor(String value, {required String fallback}) {
    final raw = value.trim();
    if (!_hexColorRegex.hasMatch(raw)) return fallback;
    final withHash = raw.startsWith('#') ? raw : '#$raw';
    return withHash.toLowerCase();
  }

  DateTime? _parseIsoDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _toIsoDate(DateTime value) {
    final mm = value.month.toString().padLeft(2, '0');
    final dd = value.day.toString().padLeft(2, '0');
    return '${value.year}-$mm-$dd';
  }

  int _clampCalendarYear(int year) {
    if (year < _minCalendarYear) return _minCalendarYear;
    if (year > _maxCalendarYear) return _maxCalendarYear;
    return year;
  }

  Future<void> _pickHolidayDate({
    required BuildContext context,
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final initial = _parseIsoDate(current) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(3000),
    );
    if (picked == null) return;
    onPicked(_toIsoDate(picked));
  }

  Future<void> _openColorPickerDialog({
    required BuildContext context,
    required String initialColor,
    required ValueChanged<String> onSelected,
  }) async {
    var current = _normalizeHexColor(initialColor, fallback: '#2563eb');
    var selected = Color(int.parse(current.replaceFirst('#', '0xFF')));

    final hex = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pick Display Color'),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: selected,
                  onColorChanged: (value) {
                    setDialogState(() {
                      selected = value;
                      current =
                          '#${value.value.toRadixString(16).substring(2)}';
                    });
                  },
                  enableAlpha: false,
                  displayThumbColor: true,
                  paletteType: PaletteType.hsv,
                  pickerAreaHeightPercent: 0.75,
                  labelTypes: const [],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(current),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (hex == null) return;
    onSelected(_normalizeHexColor(hex, fallback: '#2563eb'));
  }

  Widget _buildColorPickerField({
    required String label,
    required String color,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final normalized = _normalizeHexColor(color, fallback: '#2563eb');
    final preview = Color(int.parse(normalized.replaceFirst('#', '0xFF')));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () => _openColorPickerDialog(
                context: context,
                initialColor: normalized,
                onSelected: onChanged,
              ),
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: const Text('Pick Color'),
              style: OutlinedButton.styleFrom(
                foregroundColor: textColor,
                side: BorderSide(color: borderColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: ValueKey('color-$normalized'),
          initialValue: normalized,
          decoration: _inputDecoration('Display Color (Hex)'),
          onChanged: onChanged,
        ),
      ],
    );
  }

  List<_InstitutionEntry> get _filtered {
    return _entries.where((e) {
      if (_activeFilter == _ActiveFilter.active && !e.isActive) return false;
      if (_activeFilter == _ActiveFilter.inactive && e.isActive) return false;

      if (_syncFilter == _SyncFilter.synced && e.syncStatus != 'synced') {
        return false;
      }
      if (_syncFilter == _SyncFilter.pending && e.syncStatus != 'pending') {
        return false;
      }
      if (_syncFilter == _SyncFilter.failed && e.syncStatus != 'sync_failed') {
        return false;
      }
      if (_syncFilter == _SyncFilter.disabled && e.syncStatus != 'disabled') {
        return false;
      }

      final q = _search.trim().toLowerCase();
      if (q.isEmpty) return true;
      return [
        e.title,
        e.description,
        e.category,
        e.academicYear,
        e.semester,
        e.semesterType,
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  List<String> get _yearOptions {
    return ['All Years', ..._generateAcademicYears()];
  }

  List<String> get _semesterOptions {
    final known = <String>{..._semesters};
    final extras = <String>[];
    for (final e in _entries) {
      final value = e.semester.trim();
      if (value.isEmpty || known.contains(value) || extras.contains(value)) {
        continue;
      }
      extras.add(value);
    }
    return ['All Semesters', ..._semesters, ...extras];
  }

  List<String> get _categoryOptions {
    final values = <String>{'Holiday', ..._academicCategories};
    final extras = <String>[];
    for (final e in _entries) {
      final value = e.category.trim();
      if (value.isEmpty || values.contains(value) || extras.contains(value)) {
        continue;
      }
      extras.add(value);
    }
    return ['All Categories', 'Holiday', ..._academicCategories, ...extras];
  }

  Future<void> _deleteEntry(_InstitutionEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text('Delete "${entry.title}" from institution calendar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.delete('/institution-calendar/${entry.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry deleted.')));
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${_extractError(e)}')),
      );
    }
  }

  Future<void> _toggleSync(_InstitutionEntry entry, bool shouldSync) async {
    try {
      if (shouldSync) {
        await _api.post('/institution-calendar/${entry.id}/sync-google');
      } else {
        await _api.delete('/institution-calendar/${entry.id}/unsync-google');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shouldSync ? 'Sync requested.' : 'Sync removed.'),
        ),
      );
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${shouldSync ? 'Sync' : 'Unsync'} failed: ${_extractError(e)}',
          ),
        ),
      );
    }
  }

  Future<String> _buildHolidaySaveMessage({
    required bool isUpdate,
    required bool googleSyncEnabled,
    required Map<String, dynamic>? mutation,
  }) async {
    final action = isUpdate ? 'Holiday updated' : 'Holiday added';
    if (!googleSyncEnabled) {
      return '$action successfully.';
    }

    final sync = mutation?['sync'];
    if (sync is Map<String, dynamic>) {
      final success = sync['success'] == true;
      if (success) {
        return '$action and synced to Google Calendar.';
      }

      final syncError = sync['sync_error']?.toString();
      if (syncError != null && syncError.trim().isNotEmpty) {
        final entry = mutation?['entry'];
        final entryId = entry is Map<String, dynamic>
            ? entry['id']?.toString()
            : null;
        if (entryId == null || entryId.isEmpty) {
          return '$action. Sync error: $syncError';
        }
      }
    }

    final entry = mutation?['entry'];
    final entryId = entry is Map<String, dynamic>
        ? entry['id']?.toString()
        : null;
    if (entryId == null || entryId.isEmpty) {
      return '$action. Google sync could not be verified.';
    }

    try {
      final retry = await _api.post<Map<String, dynamic>>(
        '/institution-calendar/$entryId/sync-google',
      );
      final retrySync = retry['sync'];
      if (retrySync is Map<String, dynamic> && retrySync['success'] == true) {
        return '$action and synced to Google Calendar.';
      }

      final retryError = retrySync is Map<String, dynamic>
          ? retrySync['sync_error']?.toString()
          : null;
      if (retryError != null && retryError.trim().isNotEmpty) {
        return '$action. Sync error: $retryError';
      }
      return '$action. Google sync is pending.';
    } catch (e) {
      return '$action. Sync failed: ${_extractError(e)}';
    }
  }

  Future<String> _buildAcademicSaveMessage({
    required bool isUpdate,
    required bool googleSyncEnabled,
    required Map<String, dynamic>? mutation,
  }) async {
    final action = isUpdate ? 'Academic entry updated' : 'Academic entry added';
    if (!googleSyncEnabled) {
      return '$action successfully.';
    }

    final sync = mutation?['sync'];
    if (sync is Map<String, dynamic>) {
      final success = sync['success'] == true;
      if (success) {
        return '$action and synced to Google Calendar.';
      }

      final syncError = sync['sync_error']?.toString();
      if (syncError != null && syncError.trim().isNotEmpty) {
        final entry = mutation?['entry'];
        final entryId = entry is Map<String, dynamic>
            ? entry['id']?.toString()
            : null;
        if (entryId == null || entryId.isEmpty) {
          return '$action. Sync error: $syncError';
        }
      }
    }

    final entry = mutation?['entry'];
    final entryId = entry is Map<String, dynamic>
        ? entry['id']?.toString()
        : null;
    if (entryId == null || entryId.isEmpty) {
      return '$action. Google sync could not be verified.';
    }

    try {
      final retry = await _api.post<Map<String, dynamic>>(
        '/institution-calendar/$entryId/sync-google',
      );
      final retrySync = retry['sync'];
      if (retrySync is Map<String, dynamic> && retrySync['success'] == true) {
        return '$action and synced to Google Calendar.';
      }

      final retryError = retrySync is Map<String, dynamic>
          ? retrySync['sync_error']?.toString()
          : null;
      if (retryError != null && retryError.trim().isNotEmpty) {
        return '$action. Sync error: $retryError';
      }
      return '$action. Google sync is pending.';
    } catch (e) {
      return '$action. Sync failed: ${_extractError(e)}';
    }
  }

  Future<void> _openHolidaySheet({_InstitutionEntry? entry}) async {
    final formKey = GlobalKey<FormState>();
    final now = DateTime.now();
    final currentAcademicYear = _currentAcademicYear();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modalSurface = isDark ? theme.colorScheme.surface : Colors.white;
    final mutedText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final secondaryAction = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    String academicYear = entry?.academicYear.isNotEmpty == true
        ? entry!.academicYear
        : currentAcademicYear;
    int calendarYear = entry?.calendarYear ?? now.year;
    String date = entry?.startDate ?? '';
    String holidayName = entry?.title ?? '';
    String description = entry?.description ?? '';
    String color = _normalizeHexColor(
      entry?.color ?? '#f59e0b',
      fallback: '#f59e0b',
    );
    bool visibleToAll = entry?.visibleToAll ?? true;
    bool googleSyncEnabled = entry?.googleSyncEnabled ?? false;
    bool isActive = entry?.isActive ?? true;

    final savedMessage = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: modalSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            String dayLabel() {
              if (date.isEmpty) return '---';
              final parsed = DateTime.tryParse(date);
              if (parsed == null) return '---';
              const names = [
                'Monday',
                'Tuesday',
                'Wednesday',
                'Thursday',
                'Friday',
                'Saturday',
                'Sunday',
              ];
              return names[parsed.weekday - 1];
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_month,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            entry == null ? 'Add Holiday' : 'Edit Holiday',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildLabeledDropdown(
                        label: 'Academic Year *',
                        value: academicYear,
                        options: _yearOptions
                            .where((e) => e != 'All Years')
                            .toList(),
                        onChanged: (v) =>
                            setModal(() => academicYear = v ?? academicYear),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: ValueKey('holiday-year-$calendarYear'),
                        initialValue: calendarYear.toString(),
                        decoration: _inputDecoration('Calendar Year').copyWith(
                          prefixIcon: IconButton(
                            onPressed: () => setModal(() {
                              calendarYear = _clampCalendarYear(
                                calendarYear - 1,
                              );
                            }),
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: 'Decrease year',
                          ),
                          suffixIcon: IconButton(
                            onPressed: () => setModal(() {
                              calendarYear = _clampCalendarYear(
                                calendarYear + 1,
                              );
                            }),
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Increase year',
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return null;
                          final year = int.tryParse(value);
                          if (year == null) return 'Enter a valid year.';
                          if (year < _minCalendarYear ||
                              year > _maxCalendarYear) {
                            return 'Year must be between $_minCalendarYear and $_maxCalendarYear.';
                          }
                          return null;
                        },
                        onChanged: (v) => setModal(() {
                          final parsed = int.tryParse(v);
                          calendarYear = _clampCalendarYear(parsed ?? now.year);
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: ValueKey('holiday-date-$date'),
                        initialValue: date,
                        decoration: _inputDecoration('Date (YYYY-MM-DD) *'),
                        readOnly: true,
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Date is required.';
                          return DateTime.tryParse(value) == null
                              ? 'Use format YYYY-MM-DD.'
                              : null;
                        },
                        onTap: () => _pickHolidayDate(
                          context: context,
                          current: date,
                          onPicked: (v) {
                            setModal(() {
                              date = v;
                              final parsed = _parseIsoDate(v);
                              if (parsed != null) calendarYear = parsed.year;
                            });
                          },
                        ),
                        onChanged: (v) {
                          setModal(() {
                            date = v.trim();
                            final parsed = DateTime.tryParse(date);
                            if (parsed != null) calendarYear = parsed.year;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Day: ${dayLabel()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: holidayName,
                        decoration: _inputDecoration('Holiday Name *'),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Holiday name is required.'
                            : null,
                        onChanged: (v) => holidayName = v,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _inputDecoration('Description / Notes'),
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 12),
                      _buildColorPickerField(
                        label: 'Display Color',
                        color: color,
                        onChanged: (v) => setModal(() {
                          color = v.trim();
                        }),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        value: visibleToAll,
                        onChanged: (v) => setModal(() => visibleToAll = v),
                        title: const Text('Visible to all'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        value: googleSyncEnabled,
                        onChanged: (v) => setModal(() => googleSyncEnabled = v),
                        title: const Text('Google Sync'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        value: isActive,
                        onChanged: (v) => setModal(() => isActive = v),
                        title: const Text('Active'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      if (entry != null) ...[
                        Row(
                          children: [
                            if (entry.syncStatus == 'synced')
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    Navigator.of(context).pop();
                                    await _toggleSync(entry, false);
                                  },
                                  icon: const Icon(Icons.link_off, size: 16),
                                  label: const Text('Unsync'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: secondaryAction,
                                    side: BorderSide(color: borderColor),
                                  ),
                                ),
                              ),
                            if (entry.syncStatus == 'synced')
                              const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  await _deleteEntry(entry);
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                label: const Text('Delete'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFDC2626),
                                  side: BorderSide(
                                    color: isDark
                                        ? const Color(0xFF7F1D1D)
                                        : const Color(0xFFFECACA),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (entry == null)
                            OutlinedButton(
                              onPressed: () => setModal(() {
                                academicYear = currentAcademicYear;
                                calendarYear = now.year;
                                date = '';
                                holidayName = '';
                                description = '';
                                color = '#f59e0b';
                                visibleToAll = true;
                                googleSyncEnabled = false;
                                isActive = true;
                              }),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: secondaryAction,
                                side: BorderSide(color: borderColor),
                              ),
                              child: const Text('Reset'),
                            )
                          else
                            const SizedBox.shrink(),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () async {
                                  if (!formKey.currentState!.validate()) return;
                                  final payload = {
                                    if (entry == null) 'entry_type': 'holiday',
                                    'academic_year': academicYear,
                                    'calendar_year': calendarYear,
                                    'date': date,
                                    'holiday_name': holidayName.trim(),
                                    'description': description.trim().isEmpty
                                        ? null
                                        : description.trim(),
                                    'color': _normalizeHexColor(
                                      color,
                                      fallback: '#f59e0b',
                                    ),
                                    'visible_to_all': visibleToAll,
                                    'google_sync_enabled': googleSyncEnabled,
                                    'is_active': isActive,
                                  };

                                  try {
                                    Map<String, dynamic>? mutation;
                                    if (entry == null) {
                                      mutation = await _api
                                          .post<Map<String, dynamic>>(
                                            '/institution-calendar',
                                            data: payload,
                                          );
                                    } else {
                                      mutation = await _api
                                          .patch<Map<String, dynamic>>(
                                            '/institution-calendar/${entry.id}',
                                            data: payload,
                                          );
                                    }

                                    final message =
                                        await _buildHolidaySaveMessage(
                                          isUpdate: entry != null,
                                          googleSyncEnabled: googleSyncEnabled,
                                          mutation: mutation,
                                        );
                                    if (!mounted) return;
                                    Navigator.of(context).pop(message);
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Save failed: ${_extractError(e)}',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                  entry == null
                                      ? 'Add Holiday'
                                      : 'Save Changes',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (savedMessage != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(savedMessage)));
      await _loadEntries();
    }
  }

  Future<void> _openAcademicSheet({_InstitutionEntry? entry}) async {
    final formKey = GlobalKey<FormState>();
    final currentAcademicYear = _currentAcademicYear();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modalSurface = isDark ? theme.colorScheme.surface : Colors.white;
    final secondaryAction = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    String academicYear = entry?.academicYear.isNotEmpty == true
        ? entry!.academicYear
        : currentAcademicYear;
    String semesterType = entry?.semesterType.isNotEmpty == true
        ? entry!.semesterType
        : _semesterTypes.first;
    String semester = entry?.semester.isNotEmpty == true
        ? entry!.semester
        : 'Semester I';
    String title = entry?.title ?? '';
    String category = entry?.category.isNotEmpty == true
        ? entry!.category
        : 'Registration';
    String startDate = entry?.startDate ?? '';
    String endDate = entry?.endDate ?? '';
    bool allDay = entry?.isAllDay ?? true;
    String description = entry?.description ?? '';
    String color = _normalizeHexColor(
      entry?.color ?? '#2563eb',
      fallback: '#2563eb',
    );
    bool visibleToAll = entry?.visibleToAll ?? true;
    bool googleSyncEnabled = entry?.googleSyncEnabled ?? false;
    bool isActive = entry?.isActive ?? true;

    final savedMessage = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: modalSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.book_outlined,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            entry == null
                                ? 'Add Academic Entry'
                                : 'Edit Academic Entry',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _buildLabeledDropdown(
                        label: 'Academic Year *',
                        value: academicYear,
                        options: _yearOptions
                            .where((e) => e != 'All Years')
                            .toList(),
                        onChanged: (v) =>
                            setModal(() => academicYear = v ?? academicYear),
                      ),
                      const SizedBox(height: 12),
                      _buildLabeledDropdown(
                        label: 'Semester Type *',
                        value: semesterType,
                        options: _semesterTypes,
                        onChanged: (v) =>
                            setModal(() => semesterType = v ?? semesterType),
                      ),
                      const SizedBox(height: 12),
                      _buildLabeledDropdown(
                        label: 'Semester',
                        value: semester.isEmpty ? 'None' : semester,
                        options: const ['None', ..._semesters],
                        onChanged: (v) => setModal(
                          () => semester = (v == 'None') ? '' : (v ?? semester),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: title,
                        decoration: _inputDecoration('Academic Event Title *'),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Title is required.'
                            : null,
                        onChanged: (v) => title = v,
                      ),
                      const SizedBox(height: 12),
                      _buildLabeledDropdown(
                        label: 'Event Category *',
                        value: category,
                        options: _academicCategories,
                        onChanged: (v) =>
                            setModal(() => category = v ?? category),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: ValueKey('academic-start-$startDate'),
                        initialValue: startDate,
                        decoration: _inputDecoration(
                          'Start Date (YYYY-MM-DD) *',
                        ),
                        readOnly: true,
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Start date is required.';
                          return DateTime.tryParse(value) == null
                              ? 'Use format YYYY-MM-DD.'
                              : null;
                        },
                        onTap: () => _pickHolidayDate(
                          context: context,
                          current: startDate,
                          onPicked: (v) {
                            setModal(() {
                              startDate = v;
                              final parsedStart = DateTime.tryParse(startDate);
                              final parsedEnd = DateTime.tryParse(endDate);
                              if (parsedStart != null &&
                                  parsedEnd != null &&
                                  parsedEnd.isBefore(parsedStart)) {
                                endDate = startDate;
                              }
                            });
                          },
                        ),
                        onChanged: (v) => startDate = v.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: ValueKey('academic-end-$endDate'),
                        initialValue: endDate,
                        decoration: _inputDecoration('End Date (YYYY-MM-DD)'),
                        readOnly: true,
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return null;
                          final parsed = DateTime.tryParse(value);
                          if (parsed == null) return 'Use format YYYY-MM-DD.';
                          final start = DateTime.tryParse(startDate);
                          if (start != null && parsed.isBefore(start)) {
                            return 'End date cannot be before start date.';
                          }
                          return null;
                        },
                        onTap: () => _pickHolidayDate(
                          context: context,
                          current: endDate.isEmpty ? startDate : endDate,
                          onPicked: (v) {
                            setModal(() {
                              final parsedPicked = DateTime.tryParse(v);
                              final parsedStart = DateTime.tryParse(startDate);
                              if (parsedPicked != null &&
                                  parsedStart != null &&
                                  parsedPicked.isBefore(parsedStart)) {
                                endDate = startDate;
                              } else {
                                endDate = v;
                              }
                            });
                          },
                        ),
                        onChanged: (v) => endDate = v.trim(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: description,
                        minLines: 2,
                        maxLines: 4,
                        decoration: _inputDecoration('Description / Notes'),
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 12),
                      _buildColorPickerField(
                        label: 'Display Color',
                        color: color,
                        onChanged: (v) => setModal(() {
                          color = v.trim();
                        }),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        value: allDay,
                        onChanged: (v) => setModal(() => allDay = v),
                        title: const Text('All Day'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        value: visibleToAll,
                        onChanged: (v) => setModal(() => visibleToAll = v),
                        title: const Text('Visible to all'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        value: googleSyncEnabled,
                        onChanged: (v) => setModal(() => googleSyncEnabled = v),
                        title: const Text('Google Sync'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        value: isActive,
                        onChanged: (v) => setModal(() => isActive = v),
                        title: const Text('Active'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      if (entry != null) ...[
                        Row(
                          children: [
                            if (entry.syncStatus == 'synced')
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    Navigator.of(context).pop();
                                    await _toggleSync(entry, false);
                                  },
                                  icon: const Icon(Icons.link_off, size: 16),
                                  label: const Text('Unsync'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: secondaryAction,
                                    side: BorderSide(color: borderColor),
                                  ),
                                ),
                              ),
                            if (entry.syncStatus == 'synced')
                              const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  await _deleteEntry(entry);
                                },
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                label: const Text('Delete'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFDC2626),
                                  side: BorderSide(
                                    color: isDark
                                        ? const Color(0xFF7F1D1D)
                                        : const Color(0xFFFECACA),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              final payload = {
                                if (entry == null) 'entry_type': 'academic',
                                'academic_year': academicYear,
                                'semester_type': semesterType,
                                'semester': semester.isEmpty ? null : semester,
                                'title': title.trim(),
                                'category': category,
                                'start_date': startDate,
                                'end_date': endDate.isEmpty
                                    ? startDate
                                    : endDate,
                                'all_day': allDay,
                                'description': description.trim().isEmpty
                                    ? null
                                    : description.trim(),
                                'color': _normalizeHexColor(
                                  color,
                                  fallback: '#2563eb',
                                ),
                                'visible_to_all': visibleToAll,
                                'google_sync_enabled': googleSyncEnabled,
                                'is_active': isActive,
                              };

                              try {
                                Map<String, dynamic>? mutation;
                                if (entry == null) {
                                  mutation = await _api
                                      .post<Map<String, dynamic>>(
                                        '/institution-calendar',
                                        data: payload,
                                      );
                                } else {
                                  mutation = await _api
                                      .patch<Map<String, dynamic>>(
                                        '/institution-calendar/${entry.id}',
                                        data: payload,
                                      );
                                }

                                final message = await _buildAcademicSaveMessage(
                                  isUpdate: entry != null,
                                  googleSyncEnabled: googleSyncEnabled,
                                  mutation: mutation,
                                );
                                if (!mounted) return;
                                Navigator.of(context).pop(message);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Save failed: ${_extractError(e)}',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              entry == null ? 'Add Entry' : 'Save Changes',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (savedMessage != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(savedMessage)));
      await _loadEntries();
    }
  }

  InputDecoration _inputDecoration(String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final labelColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final fillColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor),
      filled: true,
      fillColor: fillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
    );
  }

  Widget _buildLabeledDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final panelColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    final safeValue = options.contains(value)
        ? value
        : (options.isNotEmpty ? options.first : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue.isEmpty ? null : safeValue,
              isExpanded: true,
              items: options
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final heading = isDark
        ? Colors.white
        : const Color(0xFF1E293B); // slate-800
    final subheading = isDark
        ? const Color(0xFF94A3B8) // slate-400
        : const Color(0xFF64748B); // slate-500

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _isLoading && _entries.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
              )
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calendar Updates',
                            style: TextStyle(
                              fontSize: 30, // matches 3xl
                              fontWeight: FontWeight.w900,
                              color: heading,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage institution holidays and academic calendar entries visible on the shared calendar.',
                            style: TextStyle(
                              color: subheading,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildActions(),
                          const SizedBox(height: 12),
                          _buildFilterCard(),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _error != null
                        ? SliverToBoxAdapter(
                            child: Center(
                              child: Column(
                                children: [
                                  Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: _loadEntries,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _filtered.isEmpty
                        ? SliverToBoxAdapter(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 60,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_rounded,
                                      size: 48,
                                      color: subheading.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No entries match the active filters.',
                                      style: TextStyle(
                                        color: subheading,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 400,
                                  mainAxisSpacing: 6,
                                  crossAxisSpacing: 8,
                                  mainAxisExtent: _canManage ? 220 : 172,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final entry = _filtered[index];
                              return _EntryCard(
                                entry: entry,
                                canManage: _canManage,
                                onEdit: () {
                                  if (entry.entryType == 'holiday') {
                                    _openHolidaySheet(entry: entry);
                                  } else {
                                    _openAcademicSheet(entry: entry);
                                  }
                                },
                                onDelete: () => _deleteEntry(entry),
                                onSyncToggle: () => _toggleSync(
                                  entry,
                                  entry.syncStatus != 'synced',
                                ),
                              );
                            }, childCount: _filtered.length),
                          ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 60)),
                ],
              ),
      ),
    );
  }

  Widget _buildFilterCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgSurface = isDark ? const Color(0xFF1E293B) : Colors.white;
    final topBarBg = isDark
        ? const Color(0xFF0F172A).withValues(alpha: 0.5)
        : const Color(0xFFF8FAFC); // slate-50
    final borderCol = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9); // slate-100

    final headingColor = isDark ? Colors.white : const Color(0xFF1E293B);
    return Container(
      decoration: BoxDecoration(
        color: bgSurface,
        borderRadius: BorderRadius.circular(12), // flatter corners
        border: Border.all(color: borderCol),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: topBarBg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: Border(bottom: BorderSide(color: borderCol)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage Current Entries',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: headingColor,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSearchAndFilters(),
              ],
            ),
          ),
          // Additional space for children visually if needed
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hintColor = isDark
        ? const Color(0xFF64748B) // slate-500
        : const Color(0xFF94A3B8); // slate-400
    final fieldBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main Search Bar
        Container(
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search events, holidays...',
              hintStyle: TextStyle(
                color: hintColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(Icons.search, color: hintColor, size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(height: 12),
        // Horizontal Scrollable Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              // Filters label pill
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF8FAFC),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFE2E8F0),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.filter_list,
                      size: 12,
                      color: isDark
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'FILTERS',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: isDark
                            ? const Color(0xFFE2E8F0)
                            : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),

              _buildFilterPill(
                label: 'Type',
                value: switch (_typeFilter) {
                  _EntryTypeFilter.all => 'All',
                  _EntryTypeFilter.holiday => 'Holiday',
                  _EntryTypeFilter.academic => 'Academic',
                },
                options: const ['All', 'Holiday', 'Academic'],
                onChanged: (v) {
                  setState(() {
                    if (v == 'Holiday') {
                      _typeFilter = _EntryTypeFilter.holiday;
                    } else if (v == 'Academic') {
                      _typeFilter = _EntryTypeFilter.academic;
                    } else {
                      _typeFilter = _EntryTypeFilter.all;
                    }
                  });
                  _loadEntries();
                },
              ),
              const SizedBox(width: 8),

              _buildFilterPill(
                label: 'Year',
                value: _yearFilter == 'All Years' ? 'All' : _yearFilter,
                options: [
                  'All',
                  ..._yearOptions.where((y) => y != 'All Years'),
                ],
                onChanged: (v) {
                  setState(() => _yearFilter = (v == 'All') ? 'All Years' : v!);
                  _loadEntries();
                },
              ),
              const SizedBox(width: 8),

              _buildFilterPill(
                label: 'Sem',
                value: _semesterFilter == 'All Semesters'
                    ? 'All'
                    : _semesterFilter,
                options: [
                  'All',
                  ..._semesterOptions.where((s) => s != 'All Semesters'),
                ],
                onChanged: (v) {
                  setState(
                    () => _semesterFilter = (v == 'All') ? 'All Semesters' : v!,
                  );
                  _loadEntries();
                },
              ),
              const SizedBox(width: 8),

              _buildFilterPill(
                label: 'Cat',
                value: _categoryFilter == 'All Categories'
                    ? 'All'
                    : _categoryFilter,
                options: [
                  'All',
                  ..._categoryOptions.where((c) => c != 'All Categories'),
                ],
                onChanged: (v) {
                  setState(
                    () =>
                        _categoryFilter = (v == 'All') ? 'All Categories' : v!,
                  );
                  _loadEntries();
                },
              ),
              const SizedBox(width: 8),

              _buildFilterPill(
                label: 'Sync',
                value: switch (_syncFilter) {
                  _SyncFilter.all => 'All',
                  _SyncFilter.synced => 'Synced',
                  _SyncFilter.pending => 'Pending',
                  _SyncFilter.failed => 'Failed',
                  _SyncFilter.disabled => 'Disabled',
                },
                options: const [
                  'All',
                  'Synced',
                  'Pending',
                  'Failed',
                  'Disabled',
                ],
                onChanged: (v) {
                  setState(() {
                    if (v == 'Synced') {
                      _syncFilter = _SyncFilter.synced;
                    } else if (v == 'Pending') {
                      _syncFilter = _SyncFilter.pending;
                    } else if (v == 'Failed') {
                      _syncFilter = _SyncFilter.failed;
                    } else if (v == 'Disabled') {
                      _syncFilter = _SyncFilter.disabled;
                    } else {
                      _syncFilter = _SyncFilter.all;
                    }
                  });
                },
              ),
              const SizedBox(width: 8),

              _buildFilterPill(
                label: 'Status',
                value: switch (_activeFilter) {
                  _ActiveFilter.all => 'All',
                  _ActiveFilter.active => 'Active',
                  _ActiveFilter.inactive => 'Inactive',
                },
                options: const ['All', 'Active', 'Inactive'],
                onChanged: (v) {
                  setState(() {
                    if (v == 'Active') {
                      _activeFilter = _ActiveFilter.active;
                    } else if (v == 'Inactive') {
                      _activeFilter = _ActiveFilter.inactive;
                    } else {
                      _activeFilter = _ActiveFilter.all;
                    }
                  });
                },
              ),
              const SizedBox(width: 6),

              // Clear Button
              InkWell(
                onTap: () {
                  setState(() {
                    _search = '';
                    _typeFilter = _EntryTypeFilter.all;
                    _yearFilter = 'All Years';
                    _semesterFilter = 'All Semesters';
                    _categoryFilter = 'All Categories';
                    _syncFilter = _SyncFilter.all;
                    _activeFilter = _ActiveFilter.all;
                  });
                  _loadEntries();
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF7F1D1D).withValues(alpha: 0.3)
                        : const Color(0xFFFEF2F2),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF991B1B)
                          : const Color(0xFFFECACA),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 10, // matching compact sizes
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPill({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pillBg = isDark ? theme.colorScheme.surface : Colors.white;
    final pillBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF334155);

    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 8, right: 6),
      decoration: BoxDecoration(
        color: pillBg,
        border: Border.all(color: pillBorder),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.01),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: Icon(
            Icons.keyboard_arrow_down,
            size: 14,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
          alignment: Alignment.centerRight,
          isDense: true,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
          onChanged: onChanged,
          selectedItemBuilder: (BuildContext context) {
            return options.map<Widget>((String val) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '$label: ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    val,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 4), // extra buffer spacing before icon
                ],
              );
            }).toList();
          },
          items: options
              .map((val) => DropdownMenuItem(value: val, child: Text(val)))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildActions() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final neutralBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final neutralFg = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF334155); // slate-700
    final neutralBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0); // slate-200

    final holidayBg = isDark
        ? const Color(0xFF3F2A12)
        : const Color(0xFFFFFBEB); // amber-50
    final holidayFg = isDark
        ? const Color(0xFFFCD34D)
        : const Color(0xFFD97706); // amber-600
    final holidayBorder = isDark
        ? const Color(0xFF92400E)
        : const Color(0xFFFDE68A); // amber-200

    final academicBg = isDark
        ? const Color(0xFF132C4D)
        : const Color(0xFFEFF6FF); // blue-50
    final academicFg = isDark
        ? const Color(0xFF93C5FD)
        : const Color(0xFF2563EB); // blue-600
    final academicBorder = isDark
        ? const Color(0xFF1D4ED8)
        : const Color(0xFFBFDBFE); // blue-200

    return Row(
      children: [
        if (_canManage) ...[
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _openHolidaySheet(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Holiday', overflow: TextOverflow.ellipsis),
              style:
                  ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: holidayBg,
                    foregroundColor: holidayFg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: holidayBorder),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ).copyWith(
                    shadowColor: WidgetStateProperty.all(
                      Colors.black.withValues(alpha: 0.05),
                    ),
                    elevation: WidgetStateProperty.all(2),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _openAcademicSheet(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text(
                'Add Academic Entry',
                overflow: TextOverflow.ellipsis,
              ),
              style:
                  ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: academicBg,
                    foregroundColor: academicFg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: academicBorder),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ).copyWith(
                    shadowColor: WidgetStateProperty.all(
                      Colors.black.withValues(alpha: 0.05),
                    ),
                    elevation: WidgetStateProperty.all(2),
                  ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton(
          onPressed: _loadEntries,
          style:
              ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: neutralBg,
                foregroundColor: neutralFg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: neutralBorder),
                ),
                padding: const EdgeInsets.all(10),
                minimumSize: const Size(40, 40),
              ).copyWith(
                shadowColor: WidgetStateProperty.all(
                  Colors.black.withValues(alpha: 0.05),
                ),
                elevation: WidgetStateProperty.all(2),
              ),
          child: const Icon(Icons.sync, size: 18),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final _InstitutionEntry entry;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSyncToggle;

  const _EntryCard({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.onSyncToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0); // slate-200
    final titleColor = isDark
        ? Colors.white
        : const Color(0xFF1E293B); // slate-800
    final bodyColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B); // slate-500
    final detailsBg = isDark
        ? const Color(0xFF0F172A).withValues(alpha: 0.5)
        : const Color(0xFFF8FAFC); // slate-50
    final detailsBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9); // slate-100
    final mutedLabel = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8); // slate-400
    final activeBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5);
    final syncBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    Color stripeColor() {
      final raw = entry.color;
      if (raw != null && raw.isNotEmpty && raw.startsWith('#')) {
        try {
          return Color(int.parse(raw.replaceFirst('#', '0xFF')));
        } catch (_) {}
      }
      return entry.entryType == 'holiday'
          ? const Color(0xFFF59E0B)
          : const Color(0xFF3B82F6);
    }

    String syncLabel() {
      switch (entry.syncStatus) {
        case 'synced':
          return 'SYNCED';
        case 'pending':
          return 'PENDING';
        case 'sync_failed':
          return 'FAILED';
        default:
          return 'DISABLED';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 6,
            child: ColoredBox(color: stripeColor()),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: entry.entryType == 'holiday'
                            ? const Color(0xFFFFFBEB)
                            : const Color(0xFFEFF6FF),
                        border: Border.all(
                          color: entry.entryType == 'holiday'
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFDBEAFE),
                        ),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        entry.entryType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: entry.entryType == 'holiday'
                              ? const Color(0xFFD97706)
                              : const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (entry.isActive)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: activeBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: syncBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            syncLabel(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: bodyColor,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  entry.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  entry.description.isEmpty
                      ? 'No description provided.'
                      : entry.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: entry.description.isEmpty ? mutedLabel : bodyColor,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: detailsBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: detailsBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildPropColumn(
                          'ACAD. YEAR',
                          entry.academicYear,
                          labelColor: mutedLabel,
                          valueColor: titleColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: _buildPropColumn(
                          'SEM/CAT',
                          entry.category.isNotEmpty
                              ? entry.category
                              : (entry.entryType == 'holiday'
                                    ? 'Holiday'
                                    : 'N/A'),
                          labelColor: mutedLabel,
                          valueColor: titleColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 6,
                        child: _buildPropColumn(
                          'DATE',
                          entry.dateLabel,
                          labelColor: mutedLabel,
                          valueColor: titleColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage) ...[
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSyncToggle,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFF1D4ED8)
                                  : const Color(0xFFBFDBFE),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 0),
                            minimumSize: const Size(0, 32),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          child: Text(
                            entry.syncStatus == 'synced' ? 'Unsync' : 'Sync',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          backgroundColor: Colors.white,
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32),
                        ),
                        child: const Icon(Icons.edit_outlined, size: 14),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          backgroundColor: Color(0xFFFEF2F2),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32),
                        ),
                        child: const Icon(Icons.delete_outline, size: 14),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPropColumn(
    String label,
    String value, {
    required Color labelColor,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: labelColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}
