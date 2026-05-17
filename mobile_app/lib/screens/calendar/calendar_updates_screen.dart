import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/friendly_error.dart';

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
    return friendlyErrorMessage(
      error,
      fallback: 'Request failed. Please try again.',
    );
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Pick Display Color',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              content: SingleChildScrollView(
                child: ColorPicker(
                  pickerColor: selected,
                  onColorChanged: (value) {
                    setDialogState(() {
                      selected = value;
                      current =
                          '#${value.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
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
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: preview,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: preview.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openColorPickerDialog(
                  context: context,
                  initialColor: normalized,
                  onSelected: onChanged,
                ),
                icon: const Icon(Icons.palette_outlined, size: 18),
                label: const Text('Pick Color'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: textColor,
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('color-$normalized'),
          initialValue: normalized,
          decoration: _inputDecoration('Hex Code'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Entry',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete "${entry.title}" from the institution calendar? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _api.delete('/institution-calendar/${entry.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entry deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: ${_extractError(e)}'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
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
          behavior: SnackBarBehavior.floating,
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
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
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

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
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
      useSafeArea: true,
      backgroundColor: modalSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            String dayLabel() {
              if (date.isEmpty) return 'Select a date';
              final parsed = DateTime.tryParse(date);
              if (parsed == null) return 'Invalid date';
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
                left: 24,
                right: 24,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDragHandle(),
                      _CalendarSheetHeader(
                        title: entry == null ? 'New Holiday' : 'Edit Holiday',
                        subtitle:
                            'Add a date that appears on the institution calendar.',
                        icon: Icons.celebration_rounded,
                        accent: const Color(0xFFD97706),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildLabeledDropdown(
                              label: 'Academic Year *',
                              value: academicYear,
                              options: _yearOptions
                                  .where((e) => e != 'All Years')
                                  .toList(),
                              onChanged: (v) => setModal(
                                () => academicYear = v ?? academicYear,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Calendar Year',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: mutedText,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  key: ValueKey('holiday-year-$calendarYear'),
                                  initialValue: calendarYear.toString(),
                                  decoration: _inputDecoration('').copyWith(
                                    labelText: null,
                                    hintText: 'Year',
                                    contentPadding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      6,
                                      16,
                                    ),
                                    suffixIconConstraints:
                                        const BoxConstraints.tightFor(
                                          width: 40,
                                          height: 48,
                                        ),
                                    suffixIcon: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        InkWell(
                                          onTap: () => setModal(() {
                                            calendarYear = _clampCalendarYear(
                                              calendarYear + 1,
                                            );
                                          }),
                                          child: const Icon(
                                            Icons.keyboard_arrow_up,
                                            size: 20,
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () => setModal(() {
                                            calendarYear = _clampCalendarYear(
                                              calendarYear - 1,
                                            );
                                          }),
                                          child: const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 20,
                                          ),
                                        ),
                                      ],
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
                                    if (year == null) return 'Invalid';
                                    if (year < _minCalendarYear ||
                                        year > _maxCalendarYear) {
                                      return 'Out of range';
                                    }
                                    return null;
                                  },
                                  onChanged: (v) => setModal(() {
                                    final parsed = int.tryParse(v);
                                    calendarYear = _clampCalendarYear(
                                      parsed ?? now.year,
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: ValueKey('holiday-date-$date'),
                        initialValue: date,
                        decoration: _inputDecoration('Date (YYYY-MM-DD) *')
                            .copyWith(
                              suffixIcon: const Icon(
                                Icons.calendar_today_outlined,
                                size: 20,
                              ),
                              helperText: dayLabel(),
                            ),
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
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: holidayName,
                        decoration: _inputDecoration('Holiday Name *'),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Holiday name is required.'
                            : null,
                        onChanged: (v) => holidayName = v,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: description,
                        minLines: 3,
                        maxLines: 5,
                        decoration: _inputDecoration('Description / Notes'),
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 20),
                      _buildColorPickerField(
                        label: 'Display Color',
                        color: color,
                        onChanged: (v) => setModal(() {
                          color = v.trim();
                        }),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: mutedText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              value: visibleToAll,
                              onChanged: (v) =>
                                  setModal(() => visibleToAll = v),
                              title: const Text(
                                'Visible to all',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                            SwitchListTile(
                              value: googleSyncEnabled,
                              onChanged: (v) =>
                                  setModal(() => googleSyncEnabled = v),
                              title: const Text(
                                'Google Sync',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                            SwitchListTile(
                              value: isActive,
                              onChanged: (v) => setModal(() => isActive = v),
                              title: const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
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
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop(message);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Save failed: ${_extractError(e)}',
                                      ),
                                      backgroundColor: Colors.red.shade600,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                entry == null ? 'Add Holiday' : 'Save Changes',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(savedMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadEntries();
    }
  }

  Future<void> _openAcademicSheet({_InstitutionEntry? entry}) async {
    final formKey = GlobalKey<FormState>();
    final currentAcademicYear = _currentAcademicYear();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modalSurface = isDark ? theme.colorScheme.surface : Colors.white;
    final mutedText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

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
      useSafeArea: true,
      backgroundColor: modalSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDragHandle(),
                      _CalendarSheetHeader(
                        title: entry == null
                            ? 'New Academic Entry'
                            : 'Edit Academic Entry',
                        subtitle:
                            'Schedule a term, exam, registration, or campus milestone.',
                        icon: Icons.school_rounded,
                        accent: const Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildLabeledDropdown(
                              label: 'Academic Year *',
                              value: academicYear,
                              options: _yearOptions
                                  .where((e) => e != 'All Years')
                                  .toList(),
                              onChanged: (v) => setModal(
                                () => academicYear = v ?? academicYear,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildLabeledDropdown(
                              label: 'Semester Type *',
                              value: semesterType,
                              options: _semesterTypes,
                              onChanged: (v) => setModal(
                                () => semesterType = v ?? semesterType,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledDropdown(
                        label: 'Semester',
                        value: semester.isEmpty ? 'None' : semester,
                        options: const ['None', ..._semesters],
                        onChanged: (v) => setModal(
                          () => semester = (v == 'None') ? '' : (v ?? semester),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: title,
                        decoration: _inputDecoration('Academic Event Title *'),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Title is required.'
                            : null,
                        onChanged: (v) => title = v,
                      ),
                      const SizedBox(height: 16),
                      _buildLabeledDropdown(
                        label: 'Event Category *',
                        value: category,
                        options: _academicCategories,
                        onChanged: (v) =>
                            setModal(() => category = v ?? category),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('academic-start-$startDate'),
                              initialValue: startDate,
                              decoration: _inputDecoration('Start Date *')
                                  .copyWith(
                                    suffixIcon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                    ),
                                  ),
                              readOnly: true,
                              validator: (v) {
                                final value = (v ?? '').trim();
                                if (value.isEmpty) return 'Required';
                                return DateTime.tryParse(value) == null
                                    ? 'Invalid'
                                    : null;
                              },
                              onTap: () => _pickHolidayDate(
                                context: context,
                                current: startDate,
                                onPicked: (v) {
                                  setModal(() {
                                    startDate = v;
                                    final parsedStart = DateTime.tryParse(
                                      startDate,
                                    );
                                    final parsedEnd = DateTime.tryParse(
                                      endDate,
                                    );
                                    if (parsedStart != null &&
                                        parsedEnd != null &&
                                        parsedEnd.isBefore(parsedStart)) {
                                      endDate = startDate;
                                    }
                                  });
                                },
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              key: ValueKey('academic-end-$endDate'),
                              initialValue: endDate,
                              decoration: _inputDecoration('End Date').copyWith(
                                suffixIcon: const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                ),
                              ),
                              readOnly: true,
                              validator: (v) {
                                final value = (v ?? '').trim();
                                if (value.isEmpty) return null;
                                final parsed = DateTime.tryParse(value);
                                if (parsed == null) return 'Invalid';
                                final start = DateTime.tryParse(startDate);
                                if (start != null && parsed.isBefore(start)) {
                                  return 'Before start';
                                }
                                return null;
                              },
                              onTap: () => _pickHolidayDate(
                                context: context,
                                current: endDate.isEmpty ? startDate : endDate,
                                onPicked: (v) {
                                  setModal(() {
                                    final parsedPicked = DateTime.tryParse(v);
                                    final parsedStart = DateTime.tryParse(
                                      startDate,
                                    );
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
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: description,
                        minLines: 3,
                        maxLines: 5,
                        decoration: _inputDecoration('Description / Notes'),
                        onChanged: (v) => description = v,
                      ),
                      const SizedBox(height: 20),
                      _buildColorPickerField(
                        label: 'Display Color',
                        color: color,
                        onChanged: (v) => setModal(() {
                          color = v.trim();
                        }),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: mutedText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              value: allDay,
                              onChanged: (v) => setModal(() => allDay = v),
                              title: const Text(
                                'All Day Event',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                            SwitchListTile(
                              value: visibleToAll,
                              onChanged: (v) =>
                                  setModal(() => visibleToAll = v),
                              title: const Text(
                                'Visible to all',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                            SwitchListTile(
                              value: googleSyncEnabled,
                              onChanged: (v) =>
                                  setModal(() => googleSyncEnabled = v),
                              title: const Text(
                                'Google Sync',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : const Color(0xFFE2E8F0),
                            ),
                            SwitchListTile(
                              value: isActive,
                              onChanged: (v) => setModal(() => isActive = v),
                              title: const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                final payload = {
                                  if (entry == null) 'entry_type': 'academic',
                                  'academic_year': academicYear,
                                  'semester_type': semesterType,
                                  'semester': semester.isEmpty
                                      ? null
                                      : semester,
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

                                  final message =
                                      await _buildAcademicSaveMessage(
                                        isUpdate: entry != null,
                                        googleSyncEnabled: googleSyncEnabled,
                                        mutation: mutation,
                                      );
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop(message);
                                } catch (e) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Save failed: ${_extractError(e)}',
                                      ),
                                      backgroundColor: Colors.red.shade600,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                entry == null ? 'Add Entry' : 'Save Changes',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(savedMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : const Color(0xFFF1F5F9); // slate-100

    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor, fontSize: 14),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
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
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : const Color(0xFFF1F5F9);
    final labelColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    final safeValue = options.contains(value)
        ? value
        : (options.isNotEmpty ? options.first : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue.isEmpty ? null : safeValue,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down, color: labelColor),
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              dropdownColor: isDark
                  ? theme.colorScheme.surfaceContainerHighest
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isLarge = screenWidth > 1200;
    final isMedium = screenWidth > 768;

    final heading = isDark
        ? Colors.white
        : const Color(0xFF0F172A); // slate-900
    final subheading = isDark
        ? const Color(0xFF94A3B8) // slate-400
        : const Color(0xFF64748B); // slate-500

    final horizontalPadding = isLarge
        ? (screenWidth - 1100) / 2
        : (isMedium ? 32.0 : 20.0);
    final verticalPadding = isLarge ? 32.0 : 16.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading && _entries.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
              )
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      verticalPadding,
                      horizontalPadding,
                      verticalPadding,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calendar Updates',
                            style: TextStyle(
                              fontSize: isLarge ? 32 : 28,
                              fontWeight: FontWeight.w800,
                              color: heading,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: isLarge ? 900 : null,
                            child: Text(
                              'Manage institution holidays and academic calendar events visible across the organization.',
                              style: TextStyle(
                                color: subheading,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _buildActions(),
                          const SizedBox(height: 24),
                          _buildSearchAndFilters(),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    sliver: _error != null
                        ? SliverToBoxAdapter(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 600,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _error!,
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: _loadEntries,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Retry'),
                                    ),
                                  ],
                                ),
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
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFF1F5F9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.event_busy_rounded,
                                        size: 48,
                                        color: subheading.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'No entries match your filters',
                                      style: TextStyle(
                                        color: heading,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try adjusting your search or clearing filters.',
                                      style: TextStyle(color: subheading),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: isLarge
                                      ? 450
                                      : (isMedium ? 380 : 400),
                                  mainAxisSpacing: isMedium ? 20 : 16,
                                  crossAxisSpacing: isMedium ? 20 : 16,
                                  mainAxisExtent: _canManage ? 200 : 148,
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
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompactLayout = screenWidth < 600;
    final isMedium = screenWidth > 768;

    final hintColor = isDark
        ? const Color(0xFF64748B) // slate-500
        : const Color(0xFF94A3B8); // slate-400
    final fieldBg = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9); // slate-100

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main Search Bar
        Container(
          decoration: BoxDecoration(
            color: fieldBg,
            borderRadius: BorderRadius.circular(16),
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search events, holidays, categories...',
              hintStyle: TextStyle(
                color: hintColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(Icons.search, color: hintColor, size: 22),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(height: 16),
        // Filter Chips - Wrapping or Scrolling based on screen size
        isCompactLayout
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: _buildFilterRow(isMedium),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _buildFilterRowItems(isMedium),
              ),
      ],
    );
  }

  List<Widget> _buildFilterRowItems(bool isMedium) {
    return [
      if (_typeFilter != _EntryTypeFilter.all ||
          _yearFilter != 'All Years' ||
          _semesterFilter != 'All Semesters' ||
          _categoryFilter != 'All Categories' ||
          _syncFilter != _SyncFilter.all ||
          _activeFilter != _ActiveFilter.all)
        Padding(
          padding: const EdgeInsets.only(right: 0),
          child: _buildClearChip(),
        ),
      _buildFilterChip(
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
      _buildFilterChip(
        label: 'Year',
        value: _yearFilter == 'All Years' ? 'All' : _yearFilter,
        options: ['All', ..._yearOptions.where((y) => y != 'All Years')],
        onChanged: (v) {
          setState(() => _yearFilter = (v == 'All') ? 'All Years' : v!);
          _loadEntries();
        },
      ),
      _buildFilterChip(
        label: 'Semester',
        value: _semesterFilter == 'All Semesters' ? 'All' : _semesterFilter,
        options: [
          'All',
          ..._semesterOptions.where((s) => s != 'All Semesters'),
        ],
        onChanged: (v) {
          setState(() => _semesterFilter = (v == 'All') ? 'All Semesters' : v!);
          _loadEntries();
        },
      ),
      _buildFilterChip(
        label: 'Category',
        value: _categoryFilter == 'All Categories' ? 'All' : _categoryFilter,
        options: [
          'All',
          ..._categoryOptions.where((c) => c != 'All Categories'),
        ],
        onChanged: (v) {
          setState(
            () => _categoryFilter = (v == 'All') ? 'All Categories' : v!,
          );
          _loadEntries();
        },
      ),
      _buildFilterChip(
        label: 'Sync',
        value: switch (_syncFilter) {
          _SyncFilter.all => 'All',
          _SyncFilter.synced => 'Synced',
          _SyncFilter.pending => 'Pending',
          _SyncFilter.failed => 'Failed',
          _SyncFilter.disabled => 'Disabled',
        },
        options: const ['All', 'Synced', 'Pending', 'Failed', 'Disabled'],
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
      _buildFilterChip(
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
    ];
  }

  Widget _buildFilterRow(bool isMedium) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_typeFilter != _EntryTypeFilter.all ||
            _yearFilter != 'All Years' ||
            _semesterFilter != 'All Semesters' ||
            _categoryFilter != 'All Categories' ||
            _syncFilter != _SyncFilter.all ||
            _activeFilter != _ActiveFilter.all)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _buildClearChip(),
          ),
        _buildFilterChip(
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
        _buildFilterChip(
          label: 'Year',
          value: _yearFilter == 'All Years' ? 'All' : _yearFilter,
          options: ['All', ..._yearOptions.where((y) => y != 'All Years')],
          onChanged: (v) {
            setState(() => _yearFilter = (v == 'All') ? 'All Years' : v!);
            _loadEntries();
          },
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          label: 'Semester',
          value: _semesterFilter == 'All Semesters' ? 'All' : _semesterFilter,
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
        _buildFilterChip(
          label: 'Category',
          value: _categoryFilter == 'All Categories' ? 'All' : _categoryFilter,
          options: [
            'All',
            ..._categoryOptions.where((c) => c != 'All Categories'),
          ],
          onChanged: (v) {
            setState(
              () => _categoryFilter = (v == 'All') ? 'All Categories' : v!,
            );
            _loadEntries();
          },
        ),
        const SizedBox(width: 8),
        _buildFilterChip(
          label: 'Sync',
          value: switch (_syncFilter) {
            _SyncFilter.all => 'All',
            _SyncFilter.synced => 'Synced',
            _SyncFilter.pending => 'Pending',
            _SyncFilter.failed => 'Failed',
            _SyncFilter.disabled => 'Disabled',
          },
          options: const ['All', 'Synced', 'Pending', 'Failed', 'Disabled'],
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
        _buildFilterChip(
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
      ],
    );
  }

  Widget _buildClearChip() {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(Icons.close, size: 16, color: theme.colorScheme.error),
      label: Text(
        'Clear',
        style: TextStyle(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: theme.colorScheme.error.withValues(alpha: 0.1),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
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
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isSelected = value != 'All';
    final chipBg = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : (isDark ? const Color(0xFF1E293B) : Colors.white);

    final textColor = isSelected
        ? theme.colorScheme.primary
        : (isDark ? Colors.white : const Color(0xFF334155));

    final borderColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.3)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: chipBg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: textColor),
          alignment: Alignment.centerRight,
          isDense: true,
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: textColor,
          ),
          onChanged: onChanged,
          selectedItemBuilder: (BuildContext context) {
            return options.map<Widget>((String val) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!isSelected)
                    Text(
                      '$label: ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  Text(
                    val,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(width: 4),
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
    final iconColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    Widget buildRefresh({required bool compact}) {
      final size = compact ? 42.0 : 46.0;

      return Tooltip(
        message: 'Refresh',
        child: SizedBox.square(
          dimension: size,
          child: Material(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isDark
                    ? const Color(0xFF334155)
                    : const Color(0xFFE2E8F0),
              ),
            ),
            elevation: 0,
            child: InkWell(
              onTap: _loadEntries,
              borderRadius: BorderRadius.circular(16),
              child: Icon(
                Icons.refresh_rounded,
                color: iconColor,
                size: compact ? 20 : 22,
              ),
            ),
          ),
        ),
      );
    }

    Widget buildHolidayButton({required bool compact}) {
      return _CalendarActionButton(
        compact: compact,
        title: compact ? 'Holiday' : 'New Holiday',
        subtitle: 'Institution day off',
        icon: Icons.celebration_rounded,
        accent: const Color(0xFFD97706),
        onTap: () => _openHolidaySheet(),
      );
    }

    Widget buildAcademicButton({required bool compact}) {
      return _CalendarActionButton(
        compact: compact,
        title: compact ? 'Academic' : 'New Academic',
        subtitle: 'Term or exam event',
        icon: Icons.school_rounded,
        accent: const Color(0xFF2563EB),
        onTap: () => _openAcademicSheet(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 340;
        final isCompact = constraints.maxWidth < 430;
        final gap = isCompact ? 8.0 : 12.0;

        if (!_canManage) {
          return Align(
            alignment: Alignment.centerLeft,
            child: buildRefresh(compact: isCompact),
          );
        }

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildHolidayButton(compact: false),
              const SizedBox(height: 12),
              buildAcademicButton(compact: false),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: buildRefresh(compact: false),
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: buildHolidayButton(compact: isCompact)),
            SizedBox(width: gap),
            Expanded(child: buildAcademicButton(compact: isCompact)),
            SizedBox(width: gap),
            buildRefresh(compact: isCompact),
          ],
        );
      },
    );
  }
}

class _CalendarActionButton extends StatelessWidget {
  final bool compact;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _CalendarActionButton({
    required this.compact,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E293B) : Colors.white;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Semantics(
      button: true,
      child: Material(
        color: surface,
        elevation: isDark ? 2 : 10,
        shadowColor: accent.withValues(alpha: isDark ? 0.12 : 0.16),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: accent.withValues(alpha: 0.10),
          highlightColor: accent.withValues(alpha: 0.06),
          child: Container(
            constraints: BoxConstraints(minHeight: compact ? 52 : 62),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark
                    ? accent.withValues(alpha: 0.34)
                    : accent.withValues(alpha: 0.22),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: border.withValues(alpha: isDark ? 0.08 : 0.28),
                  blurRadius: 0,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      width: compact ? 32 : 38,
                      height: compact ? 32 : 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(compact ? 12 : 13),
                      ),
                      child: Icon(icon, color: accent, size: compact ? 17 : 20),
                    ),
                    SizedBox(width: compact ? 8 : 12),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: compact ? 18 : 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: compact ? 12.5 : 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: 0,
                  child: Container(
                    width: compact ? 18 : 24,
                    height: compact ? 18 : 24,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.24),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: compact ? 14 : 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarSheetHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _CalendarSheetHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
        ],
      ),
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
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);
    final mutedIcon = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    final activeBg = isDark
        ? const Color(0xFF064E3B).withValues(alpha: 0.4)
        : const Color(0xFFD1FAE5);
    final activeFg = isDark ? const Color(0xFF34D399) : const Color(0xFF059669);

    final syncBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Left Accent Stripe
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 4,
            child: ColoredBox(color: stripeColor()),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: 20,
              right: 16,
              top: 16,
              bottom: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Badges
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: entry.entryType == 'holiday'
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                            : const Color(0xFF3B82F6).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.entryType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: entry.entryType == 'holiday'
                              ? const Color(0xFFD97706)
                              : const Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (entry.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: activeBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: activeFg,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: syncBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              syncLabel(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: bodyColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  entry.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),

                // Icon Details Row
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: mutedIcon,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.dateLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: bodyColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      entry.entryType == 'holiday'
                          ? Icons.beach_access_rounded
                          : Icons.category_rounded,
                      size: 14,
                      color: mutedIcon,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.category.isNotEmpty
                            ? entry.category
                            : (entry.entryType == 'holiday'
                                  ? 'Holiday'
                                  : 'N/A'),
                        style: TextStyle(
                          fontSize: 13,
                          color: bodyColor,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                if (canManage) ...[
                  const Spacer(),
                  // Bottom Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: TextButton.icon(
                          onPressed: onSyncToggle,
                          icon: Icon(
                            entry.syncStatus == 'synced'
                                ? Icons.cloud_off
                                : Icons.cloud_upload_outlined,
                            size: 16,
                          ),
                          label: Text(
                            entry.syncStatus == 'synced' ? 'Unsync' : 'Sync',
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          color: const Color(0xFF3B82F6),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Edit',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                          ),
                          color: Colors.red.shade600,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Delete',
                        ),
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
}
