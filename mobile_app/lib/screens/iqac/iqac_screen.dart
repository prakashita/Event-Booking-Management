import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/friendly_error.dart';

const Color _deepBlue = Color(0xFF312E81); // indigo-900
const Color _indigo600 = Color(0xFF4F46E5); // indigo-600 – primary accent
const Color _indigo500 = Color(0xFF6366F1); // indigo-500
const Color _indigo100 = Color(0xFFE0E7FF); // indigo-100
const Color _indigo50 = Color(0xFFEEF2FF); // indigo-50
const Color _slate50 = Color(0xFFF8FAFC);
const Color _slate100 = Color(0xFFF1F5F9);
const Color _slate200 = Color(0xFFE2E8F0);
const Color _slate300 = Color(0xFFCBD5E1);
const Color _slate400 = Color(0xFF94A3B8);
const Color _slate500 = Color(0xFF64748B);
const Color _slate800 = Color(0xFF1E293B);
const Color _slate900 = Color(0xFF0F172A);
const Color _emerald600 = Color(0xFF059669);
const Color _emerald50 = Color(0xFFECFDF5);
const Color _blue50 = Color(0xFFEFF6FF);
const Color _blue100 = Color(0xFFDBEAFE);
const Color _blue600 = Color(0xFF2563EB);
const Color _blue800 = Color(0xFF1E3A8A);
const int _maxIqacUploadBytes = 10 * 1024 * 1024;
const String _maxIqacUploadLabel = '10 MB';
const List<String> _campusTypeOptions = [
  'Urban',
  'Semi Urban',
  'Rural',
  'Tribal',
  'Hill',
];

enum _SsrExportFormat { pdf, docx }

class IQACScreen extends StatefulWidget {
  const IQACScreen({super.key});

  @override
  State<IQACScreen> createState() => _IQACScreenState();
}

class _IQACScreenState extends State<IQACScreen> {
  final _api = ApiService();

  List<_IqacCriterion> _criteria = [];
  Map<String, dynamic> _counts = {};
  List<IqacTemplate> _templates = [];
  List<_SsrCardInfo> _ssrSections = [];
  final Map<String, Map<String, dynamic>> _ssrRawData = {};
  Map<String, Map<String, dynamic>> _ssrData = {};
  Map<String, Map<String, dynamic>> _ssrSavedData = {};
  bool _loading = true;
  bool _templatesLoading = true;
  bool _ssrLoading = true;
  bool _pdfExporting = false;
  bool _docxExporting = false;
  String? _error;
  String? _templatesError;
  String? _ssrError;
  String? _pdfExportError;
  String? _docxExportError;

  bool get _canAccess {
    final role = (context.read<AuthProvider>().user?.roleKey ?? '')
        .toLowerCase()
        .trim();
    return AppConstants.iqacAllowedRoles.contains(role);
  }

  @override
  void initState() {
    super.initState();
    if (_canAccess) {
      _loadData();
      _loadTemplates();
      _loadSsrSections();
    } else {
      _loading = false;
      _templatesLoading = false;
      _ssrLoading = false;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final criteriaResp = await _api.get<dynamic>('/iqac/criteria');
      final countsResp = await _api.get<dynamic>('/iqac/counts');

      final criteriaRaw = criteriaResp is List ? criteriaResp : <dynamic>[];
      setState(() {
        _criteria = criteriaRaw
            .whereType<Map>()
            .map((e) => _IqacCriterion.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _counts = countsResp is Map
            ? Map<String, dynamic>.from(countsResp)
            : {};
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(
          e,
          fallback: 'Could not load IQAC data. Please try again.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _templatesLoading = true;
      _templatesError = null;
    });
    try {
      final templatesResp = await _api.get<dynamic>('/iqac/templates');
      final templatesRaw = templatesResp is List ? templatesResp : <dynamic>[];
      setState(() {
        _templates = templatesRaw
            .whereType<Map>()
            .map((e) => IqacTemplate.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _templatesLoading = false;
      });
    } catch (e) {
      setState(() {
        _templatesError = friendlyErrorMessage(
          e,
          fallback: 'Could not load templates. Please try again.',
        );
        _templatesLoading = false;
      });
    }
  }

  Future<void> _loadSsrSections() async {
    setState(() {
      _ssrLoading = true;
      _ssrError = null;
    });
    try {
      final resp = await _api.get<dynamic>('/iqac/ssr-sections');
      final raw = resp is List ? resp : <dynamic>[];
      final metaByKey = <String, _SsrSectionMeta>{};
      final rawDataByKey = <String, Map<String, dynamic>>{};
      for (final item in raw.whereType<Map>()) {
        final itemMap = Map<String, dynamic>.from(item);
        final rawData = itemMap['data'];
        if (rawData is Map) {
          rawDataByKey[(itemMap['section_key'] ?? '').toString()] =
              Map<String, dynamic>.from(rawData);
        }
        itemMap['data'] = const <String, dynamic>{};
        final meta = _SsrSectionMeta.fromJson(itemMap);
        metaByKey[meta.sectionKey] = meta;
      }

      setState(() {
        _ssrRawData
          ..clear()
          ..addAll(rawDataByKey);
        _ssrData.clear();
        _ssrSavedData.clear();
        _ssrSections = _defaultSsrCards
            .map((card) => card.copyWith(meta: metaByKey[card.key]))
            .toList();
        _ssrLoading = false;
      });
    } catch (e) {
      setState(() {
        _ssrSections = _defaultSsrCards;
        _ssrError = friendlyErrorMessage(
          e,
          fallback: 'Could not load SSR sections. Please try again.',
        );
        _ssrLoading = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadData(), _loadTemplates(), _loadSsrSections()]);
  }

  bool get _ssrExporting => _pdfExporting || _docxExporting;

  Future<void> _exportSsrReport(_SsrExportFormat format) async {
    if (_ssrExporting) return;

    final isPdf = format == _SsrExportFormat.pdf;
    setState(() {
      if (isPdf) {
        _pdfExporting = true;
        _pdfExportError = null;
      } else {
        _docxExporting = true;
        _docxExportError = null;
      }
    });

    try {
      final extension = isPdf ? 'pdf' : 'docx';
      final bytes = await _api.getBytes(
        '/iqac/ssr-export/$extension',
        receiveTimeout: const Duration(minutes: 2),
      );
      final tempDir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final file = File(
        '${tempDir.path}/IQAC_SSR_NAAC_Report_$date.$extension',
      );
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPdf
                ? 'PDF report exported successfully'
                : 'Word report exported successfully',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      final message = _friendlySsrExportError(e, isPdf: isPdf);
      if (!mounted) return;
      setState(() {
        if (isPdf) {
          _pdfExportError = message;
        } else {
          _docxExportError = message;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          if (isPdf) {
            _pdfExporting = false;
          } else {
            _docxExporting = false;
          }
        });
      }
    }
  }

  String _friendlySsrExportError(Object error, {required bool isPdf}) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final type = isPdf ? 'PDF' : 'Word';
    if (raw.toLowerCase().contains('reportlab')) {
      return '$type export is unavailable because the server is missing reportlab.';
    }
    if (raw.toLowerCase().contains('python-docx') ||
        raw.toLowerCase().contains('no module named') ||
        raw.toLowerCase().contains('docx')) {
      return '$type export is unavailable because the server is missing python-docx.';
    }
    if (raw.toLowerCase().contains('500') ||
        raw.toLowerCase().contains('failed to fulfill')) {
      return '$type export failed on the server. Please try again after the backend is restarted.';
    }
    return friendlyErrorMessage(
      error,
      fallback: '$type export failed. Please try again.',
    );
  }

  int _subFolderCount(int criterionId, String subId) {
    final criterionMap = _counts['$criterionId'];
    if (criterionMap is! Map) return 0;
    final subMap = criterionMap[subId];
    if (subMap is! Map) return 0;

    var total = 0;
    for (final value in subMap.values) {
      if (value is int) total += value;
    }
    return total;
  }

  int _itemCount(int criterionId, String subId, String itemId) {
    final criterionMap = _counts['$criterionId'];
    if (criterionMap is! Map) return 0;
    final subMap = criterionMap[subId];
    if (subMap is! Map) return 0;
    final v = subMap[itemId];
    return v is int ? v : 0;
  }

  bool _canDeleteIqacFiles(BuildContext context) {
    final role = context.read<AuthProvider>().user?.roleKey ?? '';
    return role == 'iqac';
  }

  Future<void> _openCriterionPanel(
    BuildContext context,
    _IqacCriterion criterion, {
    required bool readOnly,
  }) async {
    var step = _IqacPanelStep.subFolders;
    _IqacSubFolder? selectedSubFolder;
    _IqacItem? selectedItem;

    List<_IqacFileDoc> files = [];
    bool filesLoading = false;
    bool uploading = false;
    String? uploadError;
    PlatformFile? pickedFile;
    final descriptionCtrl = TextEditingController();
    var panelOpen = true;
    var shouldRefreshCounts = false;

    final canDelete = _canDeleteIqacFiles(context);

    void updateModal(StateSetter setModalState, VoidCallback update) {
      if (!panelOpen) return;
      setModalState(update);
    }

    Future<void> loadFiles(StateSetter setModalState) async {
      if (selectedSubFolder == null || selectedItem == null) return;
      updateModal(setModalState, () => filesLoading = true);
      try {
        final resp = await _api.get<dynamic>(
          '/iqac/folders/${criterion.id}/${Uri.encodeComponent(selectedSubFolder!.id)}/${Uri.encodeComponent(selectedItem!.id)}/files',
        );
        final raw = resp is List ? resp : <dynamic>[];
        updateModal(setModalState, () {
          files = raw
              .whereType<Map>()
              .map((e) => _IqacFileDoc.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          filesLoading = false;
        });
      } catch (_) {
        updateModal(setModalState, () {
          files = [];
          filesLoading = false;
        });
      }
    }

    Future<void> viewOrDownload(
      _IqacFileDoc file, {
      required bool download,
    }) async {
      try {
        final bytes = await _api.getBytes('/iqac/files/${file.id}/download');
        final tempDir = await getTemporaryDirectory();
        final safeName =
            '${DateTime.now().millisecondsSinceEpoch}_${file.fileName}';
        final out = File('${tempDir.path}/$safeName');
        await out.writeAsBytes(bytes, flush: true);

        final openResult = await OpenFile.open(out.path);
        if (openResult.type != ResultType.done) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyErrorMessage(
                  openResult.message,
                  fallback: 'Could not open the file.',
                ),
              ),
            ),
          );
          return;
        }
        if (download) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File downloaded to temporary storage.'),
            ),
          );
        }
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }

    Future<void> uploadFile(StateSetter setModalState) async {
      if (selectedSubFolder == null ||
          selectedItem == null ||
          pickedFile?.path == null) {
        return;
      }
      updateModal(setModalState, () {
        uploading = true;
        uploadError = null;
      });

      try {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            pickedFile!.path!,
            filename: pickedFile!.name,
          ),
          'description': descriptionCtrl.text.trim(),
        });

        await _api.postMultipart(
          '/iqac/folders/${criterion.id}/${Uri.encodeComponent(selectedSubFolder!.id)}/${Uri.encodeComponent(selectedItem!.id)}/files',
          formData,
        );

        shouldRefreshCounts = true;
        updateModal(setModalState, () {
          uploading = false;
          pickedFile = null;
          descriptionCtrl.clear();
        });

        await loadFiles(setModalState);
      } catch (e) {
        updateModal(setModalState, () {
          uploading = false;
          uploadError = friendlyErrorMessage(
            e,
            fallback: 'Could not upload file. Please try again.',
          );
        });
      }
    }

    Future<void> deleteFile(String fileId, StateSetter setModalState) async {
      try {
        await _api.delete('/iqac/files/$fileId');
        shouldRefreshCounts = true;
        updateModal(setModalState, () {
          files = files.where((f) => f.id != fileId).toList();
        });
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final theme = Theme.of(ctx);
          final isDark = theme.brightness == Brightness.dark;
          final borderColor = isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.1)
              : AppColors.border.withValues(alpha: 0.5);

          String title;
          if (step == _IqacPanelStep.subFolders) {
            title =
                'Criterion ${criterion.id}: ${criterion.title}${readOnly ? ' (View only)' : ''}';
          } else if (step == _IqacPanelStep.items) {
            title =
                '${selectedSubFolder?.id ?? ''}: ${selectedSubFolder?.title ?? ''}${readOnly ? ' (View only)' : ''}';
          } else {
            title =
                '${selectedSubFolder?.id ?? ''} -> ${selectedItem?.title ?? selectedItem?.id ?? ''}${readOnly ? ' (View only)' : ''}';
          }

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.90,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(bottom: BorderSide(color: borderColor)),
                  ),
                  child: Row(
                    children: [
                      if (step != _IqacPanelStep.subFolders)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: IconButton(
                            onPressed: () {
                              setModalState(() {
                                if (step == _IqacPanelStep.files) {
                                  step = _IqacPanelStep.items;
                                  selectedItem = null;
                                  files = [];
                                } else {
                                  step = _IqacPanelStep.subFolders;
                                  selectedSubFolder = null;
                                  selectedItem = null;
                                }
                              });
                            },
                            icon: const Icon(Icons.arrow_back_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor: theme
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                            height: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(ctx).pop();
                        },
                        icon: const Icon(Icons.close_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: theme
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: _buildPanelBody(
                      context: ctx,
                      step: step,
                      criterion: criterion,
                      readOnly: readOnly,
                      selectedSubFolder: selectedSubFolder,
                      selectedItem: selectedItem,
                      files: files,
                      filesLoading: filesLoading,
                      pickedFile: pickedFile,
                      descriptionCtrl: descriptionCtrl,
                      uploadError: uploadError,
                      uploading: uploading,
                      canDelete: canDelete,
                      itemCount: (subId, itemId) =>
                          _itemCount(criterion.id, subId, itemId),
                      onPickSubFolder: (sub) {
                        setModalState(() {
                          step = _IqacPanelStep.items;
                          selectedSubFolder = sub;
                          selectedItem = null;
                        });
                      },
                      onPickItem: (item) async {
                        setModalState(() {
                          step = _IqacPanelStep.files;
                          selectedItem = item;
                          files = [];
                          filesLoading = true;
                          uploadError = null;
                          pickedFile = null;
                          descriptionCtrl.clear();
                        });
                        await loadFiles(setModalState);
                      },
                      onPickUploadFile: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const ['pdf', 'doc', 'docx'],
                          withData: false,
                        );
                        if (picked == null || picked.files.isEmpty) return;
                        final file = picked.files.first;
                        if (file.size > _maxIqacUploadBytes) {
                          updateModal(
                            setModalState,
                            () => uploadError =
                                '${file.name} is larger than $_maxIqacUploadLabel.',
                          );
                          return;
                        }
                        updateModal(setModalState, () {
                          pickedFile = file;
                          uploadError = null;
                        });
                      },
                      onUpload: () => uploadFile(setModalState),
                      onView: (f) => viewOrDownload(f, download: false),
                      onDownload: (f) => viewOrDownload(f, download: true),
                      onDelete: (f) => deleteFile(f.id, setModalState),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    panelOpen = false;
    descriptionCtrl.dispose();
    if (shouldRefreshCounts && mounted) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iqacTextTheme = GoogleFonts.poppinsTextTheme(theme.textTheme);

    return Theme(
      data: theme.copyWith(
        textTheme: iqacTextTheme,
        primaryTextTheme: GoogleFonts.poppinsTextTheme(theme.primaryTextTheme),
      ),
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    if (!_canAccess) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Access Denied',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You do not have permission to view IQAC data.',
                style: GoogleFonts.poppins(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? theme.colorScheme.surface : _slate50,
      appBar: AppBar(
        title: Text(
          'IQAC Portal',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: isDark ? Colors.white : _slate900,
          ),
        ),
        centerTitle: false,
        backgroundColor: isDark ? theme.colorScheme.surface : _slate50,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: _refreshAll,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: _indigo50,
                foregroundColor: _indigo600,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 36,
                      color: AppColors.error.withValues(alpha: 0.8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: AppColors.error,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refreshAll,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Retry'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                children: [
                  // Hero Card – indigo gradient matching React design
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_indigo600, _indigo500],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _indigo600.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.analytics_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Data Collection',
                                style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Manage SSR & NAAC data entry, download templates, and upload criterion-wise evidence files efficiently.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Badge(
                              icon: Icons.lock_outline_rounded,
                              text: 'Committee Only',
                              bgColor: Colors.white.withValues(alpha: 0.2),
                              iconColor: Colors.white,
                              textColor: Colors.white,
                              borderColor: Colors.transparent,
                            ),
                            _Badge(
                              icon: Icons.folder_open_rounded,
                              text: '7 Criteria',
                              bgColor: Colors.white.withValues(alpha: 0.2),
                              iconColor: Colors.white,
                              textColor: Colors.white,
                              borderColor: Colors.transparent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildIqacTemplateDownloadCard(),
                  const SizedBox(height: 16),

                  _buildSsrSection(),
                  const SizedBox(height: 32),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _indigo600,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Criteria Structure',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? theme.colorScheme.onSurface
                                : _slate900,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      int crossAxisCount = 1;
                      if (width >= 600) {
                        crossAxisCount = 2;
                      } else if (width >= 900) {
                        crossAxisCount = 3;
                      }

                      return GridView.builder(
                        itemCount: _criteria.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisExtent: 240,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemBuilder: (_, i) {
                          final c = _criteria[i];
                          final subPreviewCount = 2;
                          final visibleSubs = c.subFolders
                              .take(subPreviewCount)
                              .toList();
                          final more = c.subFolders.length - visibleSubs.length;

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isDark
                                    ? theme.colorScheme.outline.withValues(
                                        alpha: 0.1,
                                      )
                                    : _slate200,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _indigo50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.folder_shared_rounded,
                                        color: _indigo600,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Criterion ${c.id}',
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: _indigo600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            c.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? theme.colorScheme.onSurface
                                                  : _slate800,
                                              height: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ...visibleSubs.map((sub) {
                                  final total = _subFolderCount(c.id, sub.id);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? theme
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.3)
                                            : _slate50,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: 14,
                                            color: _slate400,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${sub.id} ${sub.title}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: _slate500,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _indigo50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '$total',
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: _indigo600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                if (more > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      left: 2,
                                    ),
                                    child: Text(
                                      '... +$more more folders',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _indigo600.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _openCriterionPanel(
                                          context,
                                          c,
                                          readOnly: true,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          side: BorderSide(color: _slate300),
                                        ),
                                        child: Text(
                                          'View',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _slate500,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _openCriterionPanel(
                                          context,
                                          c,
                                          readOnly: false,
                                        ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          backgroundColor: _indigo600,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                        ),
                                        child: Text(
                                          'Open',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSsrSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.1)
              : _slate200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: _indigo600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SSR / NAAC Entry',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? theme.colorScheme.onSurface : _slate900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Badge(
                    icon: Icons.fact_check_outlined,
                    text: 'Portal Only',
                    bgColor: _emerald50,
                    iconColor: _emerald600,
                    textColor: _emerald600,
                    borderColor: Colors.transparent,
                  ),
                  _buildSsrExportMenu(compact: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Same sections as the official portal, arranged as native touch-friendly continuous forms for easy mobile editing.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              height: 1.5,
              color: _slate500,
            ),
          ),
          if (_pdfExportError != null || _docxExportError != null) ...[
            const SizedBox(height: 12),
            if (_pdfExportError != null)
              _InlineMessage(
                icon: Icons.error_outline_rounded,
                text: _pdfExportError!,
                color: theme.colorScheme.error,
              ),
            if (_pdfExportError != null && _docxExportError != null)
              const SizedBox(height: 8),
            if (_docxExportError != null)
              _InlineMessage(
                icon: Icons.error_outline_rounded,
                text: _docxExportError!,
                color: theme.colorScheme.error,
              ),
          ],
          if (_ssrError != null) ...[
            const SizedBox(height: 16),
            _InlineMessage(
              icon: Icons.error_outline_rounded,
              text: 'Error loading SSR sections: $_ssrError',
              color: theme.colorScheme.error,
            ),
          ],
          const SizedBox(height: 16),
          if (_ssrLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Column(
              children: _ssrSections
                  .map(
                    (card) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SsrMobileCard(
                        card: card,
                        onTap: () => _openSsrCard(card),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSsrExportMenu({required bool compact}) {
    final exporting = _ssrExporting;
    final size = compact ? 44.0 : 48.0;
    return PopupMenuButton<_SsrExportFormat>(
      enabled: !exporting && !_ssrLoading,
      tooltip: 'Export full SSR report',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      onSelected: _exportSsrReport,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SsrExportFormat.pdf,
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 18),
              const SizedBox(width: 10),
              Text(
                'Export as PDF',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _SsrExportFormat.docx,
          child: Row(
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(width: 10),
              Text(
                'Export as Word (.docx)',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
      child: _SsrIconActionShell(
        icon: Icons.file_download_outlined,
        size: size,
        disabled: exporting || _ssrLoading,
        busy: exporting,
      ),
    );
  }

  Widget _buildSsrHistoryAction(
    VoidCallback onPressed, {
    required bool compact,
  }) {
    final size = compact ? 44.0 : 48.0;
    return Tooltip(
      message: 'History',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: _SsrIconActionShell(icon: Icons.history_rounded, size: size),
        ),
      ),
    );
  }

  Future<void> _openSsrCard(_SsrCardInfo card) async {
    var activeIndex = _defaultSsrCards.indexWhere((c) => c.key == card.key);
    if (activeIndex < 0) activeIndex = 0;
    var activeCard = _defaultSsrCards[activeIndex];
    Map<String, dynamic> activeDataFor(String sectionKey) {
      final cached = _ssrData[sectionKey];
      if (cached != null) return cached;
      final normalized = _normalizeSsrData(
        sectionKey,
        _ssrRawData[sectionKey] ?? const <String, dynamic>{},
      );
      _ssrData[sectionKey] = _deepCopyMap(normalized);
      _ssrSavedData[sectionKey] = _deepCopyMap(normalized);
      return _ssrData[sectionKey]!;
    }

    var draft = _deepCopyMap(activeDataFor(activeCard.key));
    var saving = false;
    var message = '';
    var messageIsError = false;
    var dirty = false;

    final scrollController = ScrollController();

    bool hasUnsavedChanges() => dirty;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent, // Transparent to allow rounded container
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final theme = Theme.of(ctx);

          Future<bool> save({bool silent = false}) async {
            final validationError = _validateSsrSection(activeCard.key, draft);
            if (validationError != null) {
              setModalState(() {
                message = validationError;
                messageIsError = true;
              });
              return false;
            }
            if (!hasUnsavedChanges()) {
              setModalState(() {
                message = 'No changes detected.';
                messageIsError = false;
              });
              return true;
            }
            setModalState(() {
              saving = true;
              message = '';
              messageIsError = false;
            });
            try {
              final payload = await _api.put<dynamic>(
                '/iqac/ssr-sections/${activeCard.key}',
                data: {'data': draft},
              );
              final payloadMap = payload is Map
                  ? Map<String, dynamic>.from(payload)
                  : <String, dynamic>{};
              final normalized = _normalizeSsrData(
                activeCard.key,
                payloadMap['data'] is Map
                    ? Map<String, dynamic>.from(payloadMap['data'] as Map)
                    : draft,
              );
              final nextMeta = _SsrSectionMeta.fromJson(payloadMap);
              setState(() {
                _ssrData = {
                  ..._ssrData,
                  activeCard.key: _deepCopyMap(normalized),
                };
                _ssrSavedData = {
                  ..._ssrSavedData,
                  activeCard.key: _deepCopyMap(normalized),
                };
                _ssrSections = _ssrSections
                    .map(
                      (item) => item.key == activeCard.key
                          ? item.copyWith(meta: nextMeta)
                          : item,
                    )
                    .toList();
              });
              setModalState(() {
                draft = _deepCopyMap(normalized);
                dirty = false;
                saving = false;
                message = payloadMap['no_changes'] == true
                    ? 'No changes detected.'
                    : (silent ? 'Saved before moving.' : 'Saved successfully.');
                messageIsError = false;
              });
              return true;
            } catch (e) {
              setModalState(() {
                saving = false;
                message = friendlyErrorMessage(
                  e,
                  fallback: 'Could not save changes. Please try again.',
                );
                messageIsError = true;
              });
              return false;
            }
          }

          Future<void> openHistoryWizard() async {
            var historyLoading = true;
            var restoringId = '';
            var historyDetailLoadingId = '';
            var activeHistoryId = '';
            var historyMessage = '';
            var historyMessageIsError = false;
            var history = <_SsrHistoryEntry>[];
            final historyCard = activeCard;
            var historyRequested = false;

            await showModalBottomSheet<void>(
              context: ctx,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (historyCtx) => StatefulBuilder(
                builder: (historyCtx, setHistoryState) {
                  Future<void> loadHistory() async {
                    setHistoryState(() {
                      historyLoading = true;
                      activeHistoryId = '';
                      historyMessage = '';
                      historyMessageIsError = false;
                    });
                    try {
                      final resp = await _api.get<dynamic>(
                        '/iqac/ssr-sections/${historyCard.key}/history',
                      );
                      final raw = resp is List ? resp : <dynamic>[];
                      final entries =
                          raw
                              .whereType<Map>()
                              .map(
                                (item) => _SsrHistoryEntry.fromJson(
                                  Map<String, dynamic>.from(item),
                                ),
                              )
                              .toList()
                            ..sort((a, b) {
                              final aDate = a.editedAt;
                              final bDate = b.editedAt;
                              if (aDate == null && bDate == null) return 0;
                              if (aDate == null) return 1;
                              if (bDate == null) return -1;
                              return bDate.compareTo(aDate);
                            });
                      setHistoryState(() {
                        history = entries;
                        historyLoading = false;
                      });
                    } catch (e) {
                      setHistoryState(() {
                        historyLoading = false;
                        historyMessage = friendlyErrorMessage(
                          e,
                          fallback: 'Could not load history. Please try again.',
                        );
                        historyMessageIsError = true;
                      });
                    }
                  }

                  Future<void> toggleHistoryDetails(
                    _SsrHistoryEntry item,
                  ) async {
                    if (activeHistoryId == item.id &&
                        item.fieldDiffs.isNotEmpty) {
                      setHistoryState(() => activeHistoryId = '');
                      return;
                    }
                    setHistoryState(() {
                      activeHistoryId = item.id;
                      historyDetailLoadingId = item.id;
                      historyMessage = '';
                    });
                    try {
                      final resp = await _api.get<dynamic>(
                        '/iqac/ssr-sections/${historyCard.key}/history/${item.id}',
                      );
                      final detail = resp is Map
                          ? _SsrHistoryEntry.fromJson(
                              Map<String, dynamic>.from(resp),
                            )
                          : item;
                      setHistoryState(() {
                        history = history
                            .map(
                              (entry) => entry.id == item.id ? detail : entry,
                            )
                            .toList();
                        historyDetailLoadingId = '';
                      });
                    } catch (e) {
                      setHistoryState(() {
                        historyDetailLoadingId = '';
                        historyMessage = friendlyErrorMessage(
                          e,
                          fallback: 'Could not load history. Please try again.',
                        );
                        historyMessageIsError = true;
                      });
                    }
                  }

                  Future<void> restore(_SsrHistoryEntry item) async {
                    final shouldRestore = await showDialog<bool>(
                      context: historyCtx,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Restore this version?'),
                        content: const Text(
                          'This will replace the current section and create a new history entry.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Restore'),
                          ),
                        ],
                      ),
                    );
                    if (shouldRestore != true) return;
                    setHistoryState(() {
                      restoringId = item.id;
                      historyMessage = '';
                    });
                    try {
                      final payload = await _api.post<dynamic>(
                        '/iqac/ssr-sections/${historyCard.key}/restore/${item.id}',
                        data: {},
                      );
                      final payloadMap = payload is Map
                          ? Map<String, dynamic>.from(payload)
                          : <String, dynamic>{};
                      final normalized = _normalizeSsrData(
                        historyCard.key,
                        payloadMap['data'] is Map
                            ? Map<String, dynamic>.from(
                                payloadMap['data'] as Map,
                              )
                            : {},
                      );
                      final nextMeta = _SsrSectionMeta.fromJson(payloadMap);
                      setState(() {
                        _ssrData = {..._ssrData, historyCard.key: normalized};
                        _ssrSavedData = {
                          ..._ssrSavedData,
                          historyCard.key: normalized,
                        };
                        _ssrSections = _ssrSections
                            .map(
                              (entry) => entry.key == historyCard.key
                                  ? entry.copyWith(meta: nextMeta)
                                  : entry,
                            )
                            .toList();
                      });
                      setModalState(() {
                        if (activeCard.key == historyCard.key) {
                          draft = _deepCopyMap(normalized);
                          dirty = false;
                          message = 'Version restored.';
                          messageIsError = false;
                        }
                      });
                      setHistoryState(() {
                        restoringId = '';
                        historyMessage = 'Version restored.';
                        historyMessageIsError = false;
                      });
                      await loadHistory();
                    } catch (e) {
                      setHistoryState(() {
                        restoringId = '';
                        historyMessage = friendlyErrorMessage(
                          e,
                          fallback:
                              'Could not restore version. Please try again.',
                        );
                        historyMessageIsError = true;
                      });
                    }
                  }

                  if (!historyRequested) {
                    historyRequested = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (historyCtx.mounted) loadHistory();
                    });
                  }

                  final isCompactHistory =
                      MediaQuery.of(historyCtx).size.width < 380;
                  return Container(
                    margin: EdgeInsets.only(
                      top:
                          MediaQuery.of(historyCtx).padding.top +
                          (isCompactHistory ? 8 : 18),
                    ),
                    decoration: const BoxDecoration(
                      color: _slate50,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.fromLTRB(
                            isCompactHistory ? 20 : 24,
                            10,
                            isCompactHistory ? 16 : 20,
                            isCompactHistory ? 18 : 20,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(historyCtx).colorScheme.surface,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: _slate200,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              SizedBox(height: isCompactHistory ? 16 : 20),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'HISTORY',
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: _indigo600,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Container(
                                              width: 20,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: _indigo600,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: _slate200,
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          historyCard.title,
                                          style: GoogleFonts.poppins(
                                            fontSize: isCompactHistory
                                                ? 16
                                                : 17,
                                            fontWeight: FontWeight.w800,
                                            height: 1.15,
                                            color: _slate900,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: historyLoading
                                        ? null
                                        : () => loadHistory(),
                                    tooltip: 'Refresh history',
                                    icon: const Icon(Icons.refresh_rounded),
                                    color: _slate500,
                                    style: IconButton.styleFrom(
                                      backgroundColor: _slate100,
                                      fixedSize: const Size(44, 44),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.of(historyCtx).pop(),
                                    icon: const Icon(Icons.close_rounded),
                                    color: _slate500,
                                    style: IconButton.styleFrom(
                                      backgroundColor: _slate100,
                                      fixedSize: const Size(44, 44),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        if (historyMessage.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              isCompactHistory ? 20 : 24,
                              12,
                              isCompactHistory ? 20 : 24,
                              0,
                            ),
                            child: _InlineMessage(
                              icon: historyMessageIsError
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              text: historyMessage,
                              color: historyMessageIsError
                                  ? Theme.of(historyCtx).colorScheme.error
                                  : const Color(0xFF047857),
                            ),
                          ),
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(
                              isCompactHistory ? 20 : 24,
                              18,
                              isCompactHistory ? 20 : 24,
                              MediaQuery.of(historyCtx).padding.bottom + 24,
                            ),
                            children: [
                              _SsrHistoryPanel(
                                loading: historyLoading,
                                history: history,
                                restoringId: restoringId,
                                detailLoadingId: historyDetailLoadingId,
                                activeHistoryId: activeHistoryId,
                                onToggleDetails: toggleHistoryDetails,
                                onRestore: restore,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }

          Future<void> moveStep(int direction) async {
            final nextIndex = activeIndex + direction;
            if (nextIndex < 0 || nextIndex >= _defaultSsrCards.length) return;
            if (hasUnsavedChanges()) {
              final ok = await save(silent: true);
              if (!ok) return;
            }
            setModalState(() {
              activeIndex = nextIndex;
              activeCard = _defaultSsrCards[activeIndex];
              draft = _deepCopyMap(activeDataFor(activeCard.key));
              dirty = false;
              message = '';
              messageIsError = false;
            });
          }

          final isCompactScreen = MediaQuery.of(ctx).size.width < 380;
          final bodyHorizontalPadding = isCompactScreen ? 14.0 : 18.0;
          return Container(
            margin: EdgeInsets.only(
              top: MediaQuery.of(ctx).padding.top + (isCompactScreen ? 8 : 18),
            ),
            decoration: BoxDecoration(
              color: _slate50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              children: [
                // ── Header ──
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    isCompactScreen ? 20 : 24,
                    10,
                    isCompactScreen ? 16 : 20,
                    isCompactScreen ? 18 : 20,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _slate200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      SizedBox(height: isCompactScreen ? 16 : 20),
                      // Step indicator row + title + actions
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Step label + animated dots
                                Row(
                                  children: [
                                    Text(
                                      'STEP ${activeIndex + 1} OF ${_defaultSsrCards.length}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: _indigo600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Row(
                                      children: List.generate(
                                        _defaultSsrCards.length,
                                        (i) => AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          margin: const EdgeInsets.only(
                                            right: 5,
                                          ),
                                          width: i == activeIndex ? 20 : 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: i == activeIndex
                                                ? _indigo600
                                                : i < activeIndex
                                                ? _indigo600.withValues(
                                                    alpha: 0.4,
                                                  )
                                                : _slate200,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  activeCard.title,
                                  style: GoogleFonts.poppins(
                                    fontSize: isCompactScreen ? 19 : 21,
                                    fontWeight: FontWeight.w700,
                                    height: 1.18,
                                    color: _slate900,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _buildSsrExportMenu(compact: true),
                          ),
                          const SizedBox(width: 8),
                          // History button
                          _buildSsrHistoryAction(
                            openHistoryWizard,
                            compact: true,
                          ),
                          const SizedBox(width: 8),
                          // Close button
                          IconButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    if (hasUnsavedChanges()) await save();
                                    if (!ctx.mounted) return;
                                    Navigator.of(ctx).pop();
                                  },
                            icon: Icon(
                              Icons.close_rounded,
                              size: isCompactScreen ? 20 : 22,
                            ),
                            color: _slate500,
                            style: IconButton.styleFrom(
                              backgroundColor: _slate100,
                              fixedSize: const Size(44, 44),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (message.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isCompactScreen ? 20 : 24,
                      12,
                      isCompactScreen ? 20 : 24,
                      0,
                    ),
                    child: _InlineMessage(
                      icon: messageIsError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      text: message,
                      color: messageIsError
                          ? theme.colorScheme.error
                          : const Color(0xFF047857),
                    ),
                  ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      bodyHorizontalPadding,
                      18,
                      bodyHorizontalPadding,
                      118,
                    ),
                    children: [
                      _SsrDataEditor(
                        sectionKey: activeCard.key,
                        data: draft,
                        onChanged: (next, {rebuild = false}) {
                          draft = _deepCopyMap(next);
                          dirty = true;
                          message = '';
                          if (rebuild) setModalState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(0),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        isCompactScreen ? 20 : 24,
                        16,
                        isCompactScreen ? 20 : 24,
                        MediaQuery.of(ctx).padding.bottom + 18,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: 0.82,
                        ),
                        border: Border(
                          top: BorderSide(
                            color: const Color(
                              0xFFE2E8F0,
                            ).withValues(alpha: 0.9),
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 20,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: activeIndex == 0 || saving
                                      ? null
                                      : () => moveStep(-1),
                                  style: OutlinedButton.styleFrom(
                                    elevation: 0,
                                    backgroundColor: activeIndex == 0
                                        ? const Color(0xFFF8FAFC)
                                        : Colors.white,
                                    disabledForegroundColor: const Color(
                                      0xFFCBD5E1,
                                    ),
                                    foregroundColor: const Color(0xFF334155),
                                    side: BorderSide(
                                      color: activeIndex == 0
                                          ? Colors.transparent
                                          : const Color(0xFFE2E8F0),
                                      width: 1.4,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Text(
                                    'Previous',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: saving ? null : () => save(),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _slate800,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: _slate800
                                        .withValues(alpha: 0.55),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          'Save',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed:
                                      activeIndex ==
                                              _defaultSsrCards.length - 1 ||
                                          saving
                                      ? null
                                      : () => moveStep(1),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _indigo600,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: _indigo600
                                        .withValues(alpha: 0.45),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 8,
                                    shadowColor: _indigo600.withValues(
                                      alpha: 0.25,
                                    ),
                                  ),
                                  child: Text(
                                    activeIndex == _defaultSsrCards.length - 1
                                        ? 'Finish'
                                        : 'Next',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
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
                ),
              ],
            ),
          );
        },
      ),
    );

    scrollController.dispose();
  }

  Widget _buildPanelBody({
    required BuildContext context,
    required _IqacPanelStep step,
    required _IqacCriterion criterion,
    required bool readOnly,
    required _IqacSubFolder? selectedSubFolder,
    required _IqacItem? selectedItem,
    required List<_IqacFileDoc> files,
    required bool filesLoading,
    required PlatformFile? pickedFile,
    required TextEditingController descriptionCtrl,
    required String? uploadError,
    required bool uploading,
    required bool canDelete,
    required int Function(String subId, String itemId) itemCount,
    required ValueChanged<_IqacSubFolder> onPickSubFolder,
    required ValueChanged<_IqacItem> onPickItem,
    required VoidCallback onPickUploadFile,
    required VoidCallback onUpload,
    required ValueChanged<_IqacFileDoc> onView,
    required ValueChanged<_IqacFileDoc> onDownload,
    required ValueChanged<_IqacFileDoc> onDelete,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.1)
        : AppColors.border.withValues(alpha: 0.5);
    final panelColor = theme.colorScheme.surface;

    if (step == _IqacPanelStep.subFolders) {
      return LayoutBuilder(
        builder: (_, constraints) {
          final columns = constraints.maxWidth < 560 ? 1 : 2;
          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: criterion.subFolders.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 96,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (_, i) {
              final sub = criterion.subFolders[i];
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onPickSubFolder(sub),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.folder_open_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          '${sub.id} - ${sub.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    }

    if (step == _IqacPanelStep.items) {
      final items = selectedSubFolder?.items ?? const <_IqacItem>[];
      return LayoutBuilder(
        builder: (_, constraints) {
          final columns = constraints.maxWidth < 560 ? 1 : 2;
          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 120,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (_, i) {
              final item = items[i];
              final n = itemCount(selectedSubFolder!.id, item.id);
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onPickItem(item),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.description_outlined,
                            color: AppColors.primary,
                            size: 22,
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$n File${n == 1 ? '' : 's'}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '${item.id} ${item.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (readOnly)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.4,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Viewing in read-only mode. Use "Open" on the main card to upload${canDelete ? ' or delete' : ''} files.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (_, constraints) {
                    final stacked = constraints.maxWidth < 580;
                    if (stacked) {
                      return Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: uploading ? null : onPickUploadFile,
                              icon: const Icon(
                                Icons.upload_file_rounded,
                                size: 18,
                              ),
                              label: Text(
                                pickedFile?.name ?? 'Choose File...',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                side: BorderSide(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.05),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: descriptionCtrl,
                            decoration: InputDecoration(
                              hintText: 'Add a description (optional)',
                              hintStyle: const TextStyle(fontSize: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: uploading ? null : onPickUploadFile,
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 18,
                            ),
                            label: Text(
                              pickedFile?.name ?? 'Choose File...',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              backgroundColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.05),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: descriptionCtrl,
                            decoration: InputDecoration(
                              hintText: 'Add a description (optional)',
                              hintStyle: const TextStyle(fontSize: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surface,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Max 10 MB. PDF, DOC, DOCX only.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: (uploading || pickedFile == null)
                          ? null
                          : onUpload,
                      icon: uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_rounded, size: 18),
                      style: FilledButton.styleFrom(
                        backgroundColor: _deepBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      label: Text(
                        uploading ? 'Uploading...' : 'Upload File',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (uploadError != null && uploadError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      uploadError,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Uploaded Files',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filesLoading
              ? const Center(child: CircularProgressIndicator())
              : files.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_off_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No documents uploaded yet.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final f = files[i];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: panelColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
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
                          Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file_rounded,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  f.fileName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_formatBytes(f.size)} • ${_formatDate(f.uploadedAt)}${f.description.isNotEmpty ? '\n${f.description}' : ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              height: 1.4,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => onView(f),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  size: 16,
                                ),
                                label: const Text(
                                  'View',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4F46E5),
                                  side: const BorderSide(
                                    color: Color(0xFF4F46E5),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => onDownload(f),
                                icon: const Icon(
                                  Icons.download_outlined,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Download',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4F46E5),
                                  side: const BorderSide(
                                    color: Color(0xFF4F46E5),
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              if (!readOnly && canDelete)
                                OutlinedButton.icon(
                                  onPressed: () => onDelete(f),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Delete',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(
                                      color: AppColors.error,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildIqacTemplateDownloadCard() {
    final theme = Theme.of(context);
    final primaryTemplate = _templates.isNotEmpty ? _templates.first : null;
    final cardMeta = _templatesLoading
        ? 'Checking available template documents...'
        : _templatesError != null
        ? 'Unable to load template documents.'
        : _templates.isEmpty
        ? 'No template documents are available yet.'
        : _templates.length == 1
        ? '${_templates.first.type.isEmpty ? 'Document' : _templates.first.type.toUpperCase()}${_templates.first.size > 0 ? ' • ${_formatBytes(_templates.first.size)}' : ''}'
        : '${_templates.length} template documents available';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.description_outlined,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IQAC Data Templates',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cardMeta,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _templatesLoading || primaryTemplate == null
                    ? null
                    : () => _downloadIqacTemplate(primaryTemplate),
                icon: _templatesLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: Text(
                  _templatesLoading ? 'Checking' : 'Download',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _indigo600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _slate200,
                  disabledForegroundColor: _slate500,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          if (_templatesError != null) ...[
            const SizedBox(height: 14),
            _InlineMessage(
              icon: Icons.error_outline_rounded,
              text: 'Error loading templates: $_templatesError',
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loadTemplates,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ),
          ] else if (!_templatesLoading && _templates.isEmpty) ...[
            const SizedBox(height: 14),
            _InlineMessage(
              icon: Icons.info_outline_rounded,
              text: 'Template documents will appear here once uploaded.',
              color: _slate500,
            ),
          ] else if (_templates.length > 1) ...[
            const SizedBox(height: 16),
            for (var i = 0; i < _templates.length; i++) ...[
              _buildIqacTemplateRow(_templates[i]),
              if (i != _templates.length - 1) const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildIqacTemplateRow(IqacTemplate template) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _downloadIqacTemplate(template),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.22,
          ),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.file_download_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${template.type.isEmpty ? 'Document' : template.type.toUpperCase()}${template.size > 0 ? ' • ${_formatBytes(template.size)}' : ''}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Download',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadIqacTemplate(IqacTemplate template) async {
    try {
      final bytes = await _api.getBytes(
        template.downloadUrl,
        receiveTimeout: const Duration(minutes: 2),
      );
      final tempDir = await getApplicationDocumentsDirectory();
      final safeName = _downloadFileName(
        template.fileName.isNotEmpty ? template.fileName : template.name,
        fallbackExtension: template.type,
      );
      final file = File('${tempDir.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              friendlyErrorMessage(
                result.message,
                fallback: 'Could not open the downloaded file.',
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Template downloaded successfully'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Could not download template. Please try again.',
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _downloadFileName(
    String rawName, {
    required String fallbackExtension,
  }) {
    final cleaned = rawName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final baseName = cleaned.isEmpty ? 'IQAC_Data_Template' : cleaned;
    if (baseName.contains('.') && !baseName.endsWith('.')) {
      return '${DateTime.now().millisecondsSinceEpoch}_$baseName';
    }
    final ext = fallbackExtension.replaceAll('.', '').trim().toLowerCase();
    return '${DateTime.now().millisecondsSinceEpoch}_$baseName.${ext.isEmpty ? 'docx' : ext}';
  }

  String _formatBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '-';
    final local = d.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$mi';
  }
}

enum _IqacPanelStep { subFolders, items, files }

class _IqacCriterion {
  final int id;
  final String title;
  final List<_IqacSubFolder> subFolders;

  const _IqacCriterion({
    required this.id,
    required this.title,
    required this.subFolders,
  });

  factory _IqacCriterion.fromJson(Map<String, dynamic> json) {
    final subRaw = json['subFolders'] as List? ?? const [];
    return _IqacCriterion(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      title: (json['title'] ?? '').toString(),
      subFolders: subRaw
          .whereType<Map>()
          .map((e) => _IqacSubFolder.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
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

  factory _IqacSubFolder.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'] as List? ?? const [];
    return _IqacSubFolder(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      items: itemsRaw
          .whereType<Map>()
          .map((e) => _IqacItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class _IqacItem {
  final String id;
  final String title;

  const _IqacItem({required this.id, required this.title});

  factory _IqacItem.fromJson(Map<String, dynamic> json) {
    return _IqacItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
    );
  }
}

class _IqacFileDoc {
  final String id;
  final String fileName;
  final String description;
  final int size;
  final DateTime? uploadedAt;

  const _IqacFileDoc({
    required this.id,
    required this.fileName,
    required this.description,
    required this.size,
    required this.uploadedAt,
  });

  factory _IqacFileDoc.fromJson(Map<String, dynamic> json) {
    return _IqacFileDoc(
      id: (json['id'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      size: json['size'] is int
          ? json['size'] as int
          : int.tryParse('${json['size']}') ?? 0,
      uploadedAt: DateTime.tryParse((json['uploadedAt'] ?? '').toString()),
    );
  }
}

class IqacTemplate {
  final int id;
  final String name;
  final String fileName;
  final String type;
  final String downloadUrl;
  final int size;

  const IqacTemplate({
    required this.id,
    required this.name,
    required this.fileName,
    required this.type,
    required this.downloadUrl,
    required this.size,
  });

  factory IqacTemplate.fromJson(Map<String, dynamic> json) {
    return IqacTemplate(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
      fileName: (json['fileName'] ?? json['file_name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      downloadUrl: (json['download_url'] ?? json['downloadUrl'] ?? '')
          .toString(),
      size: json['size'] is int
          ? json['size'] as int
          : int.tryParse('${json['size']}') ?? 0,
    );
  }
}

const List<_SsrCardInfo> _defaultSsrCards = [
  _SsrCardInfo(
    key: 'executive_summary',
    title: 'Executive Summary',
    description:
        'Narrative summary, criterion notes, SWOC, additional information, and conclusion.',
    icon: Icons.article_outlined,
  ),
  _SsrCardInfo(
    key: 'university_profile',
    title: 'Profile of the University',
    description:
        'Basic information, recognition, campus, academic, staff, student, and department details.',
    icon: Icons.account_balance_outlined,
  ),
  _SsrCardInfo(
    key: 'extended_profile',
    title: 'Extended Profile',
    description:
        'Five-year programme, student, academic, admission, infrastructure, and expenditure data.',
    icon: Icons.bar_chart_rounded,
  ),
  _SsrCardInfo(
    key: 'qif',
    title: 'Quality Indicator Framework',
    description:
        'QIF preparation notes connected to the seven criteria evidence structure below.',
    icon: Icons.fact_check_outlined,
  ),
];

Map<String, dynamic> _defaultSsrDataFor(String sectionKey) {
  switch (sectionKey) {
    case 'executive_summary':
      return {
        'introductory_note': '',
        'criteria_summary': '',
        'swoc_analysis': '',
        'additional_information': '',
        'conclusive_explication': '',
      };
    case 'university_profile':
      return {
        'basic_information': {
          'name': '',
          'address': '',
          'city': '',
          'pin': '',
          'state': '',
          'website': '',
        },
        'contacts': [
          {
            'designation': '',
            'name': '',
            'telephone': '',
            'mobile': '',
            'fax': '',
            'email': '',
          },
        ],
        'institution': {'nature': '', 'status': '', 'type': ''},
        'establishment': {
          'establishment_date': '',
          'status_prior': '',
          'establishment_date_if_applicable': '',
        },
        'recognition': {
          'ugc_2f_date': '',
          'ugc_12b_date': '',
          'other_agency_name': '',
          'other_agency_date': '',
        },
        'upe_recognized': '',
        'campuses': [
          {
            'campus_type': '',
            'address': '',
            'location': '',
            'campus_area_acres': '',
            'built_up_area_sq_mts': '',
            'programmes_offered': '',
            'establishment_date': '',
            'recognition_date': '',
          },
        ],
        'academic_information': {
          'affiliated_institutions': [
            {
              'college_type': 'Education/Teachers Training',
              'permanent_affiliation': '',
              'temporary_affiliation': '',
            },
            {
              'college_type':
                  'Business administration/Commerce/Management/Finance',
              'permanent_affiliation': '',
              'temporary_affiliation': '',
            },
            {
              'college_type': 'Universal/Common to all Disciplines',
              'permanent_affiliation': '',
              'temporary_affiliation': '',
            },
          ],
          'college_details': [
            {'label': 'Constituent Colleges', 'value': ''},
            {'label': 'Affiliated Colleges', 'value': ''},
            {'label': 'Colleges Under 2(f)', 'value': ''},
            {'label': 'Colleges Under 2(f) and 12B', 'value': ''},
            {'label': 'NAAC Accredited Colleges', 'value': ''},
            {
              'label': 'Colleges with Potential for Excellence (UGC)',
              'value': '',
            },
            {'label': 'Autonomous Colleges', 'value': ''},
            {'label': 'Colleges with Postgraduate Departments', 'value': ''},
            {'label': 'Colleges with Research Departments', 'value': ''},
            {
              'label': 'University Recognized Research Institutes/Centers',
              'value': '',
            },
          ],
          'sra_recognized': '',
          'sra_details': '',
        },
        'staff': {
          'teaching': _staffRows([
            for (final role in _teachingRoles)
              for (final gender in _genderColumns) '${role}_$gender',
          ]),
          'non_teaching': _staffRows(_genderColumns),
          'technical': _staffRows(_genderColumns),
        },
        'qualification_details': {
          'permanent_teachers': _qualificationRows(),
          'temporary_teachers': _qualificationRows(),
          'part_time_teachers': _qualificationRows(),
        },
        'distinguished_academicians': [
          {
            'role': 'Emeritus Professor',
            'male': '',
            'female': '',
            'others': '',
            'total': '',
          },
          {
            'role': 'Adjunct Professor',
            'male': '',
            'female': '',
            'others': '',
            'total': '',
          },
          {
            'role': 'Visiting Professor',
            'male': '',
            'female': '',
            'others': '',
            'total': '',
          },
        ],
        'chairs': [
          {'sl_no': '', 'department': '', 'chair': '', 'sponsor': ''},
        ],
        'student_enrolment': [
          for (final programme in [
            'PG',
            'UG',
            'PG Diploma recognized by statutory authority including university',
          ])
            for (final gender in ['Male', 'Female', 'Others'])
              {
                'programme': programme,
                'gender': gender,
                'from_state': '',
                'from_other_states': '',
                'nri': '',
                'foreign': '',
                'total': '',
              },
        ],
        'integrated_programmes': {
          'offered': '',
          'total_programmes': '',
          'enrolment': [
            for (final gender in ['Male', 'Female', 'Others'])
              {
                'gender': gender,
                'from_state': '',
                'from_other_states': '',
                'nri': '',
                'foreign': '',
                'total': '',
              },
          ],
        },
        'hrdc': {
          'year_of_establishment': '',
          'orientation_programmes': '',
          'refresher_courses': '',
          'own_programmes': '',
          'total_programmes_last_five_years': '',
        },
        'department_reports': [
          {'department_name': '', 'report_reference': ''},
        ],
      };
    case 'extended_profile':
      return {
        'year_labels': [..._academicYearLabels],
        'departments_offering_programmes': '',
        'total_classrooms_seminar_halls': '',
        'total_computers_academic': '',
        'metrics': {
          for (final metric in _extendedProfileMetrics)
            metric.key: ['', '', '', '', ''],
        },
      };
    case 'qif':
      return {
        'preparation_notes': '',
        'qualitative_metrics_notes': '',
        'quantitative_metrics_notes': '',
        'file_description_notes': '',
      };
    default:
      return {};
  }
}

const _staffStatuses = [
  'Sanctioned',
  'Recruited',
  'Yet to Recruit',
  'On Contract',
];
const _teachingRoles = [
  'Professor',
  'Associate Professor',
  'Assistant Professor',
];
const _genderColumns = ['Male', 'Female', 'Others', 'Total'];
const _qualifications = ['D.Sc/D.Litt', 'Ph.D.', 'M.Phil.', 'PG'];
const _academicYearLabels = ['Year 1', 'Year 2', 'Year 3', 'Year 4', 'Year 5'];

List<Map<String, dynamic>> _staffRows(List<String> columns) {
  return [
    for (final status in _staffStatuses)
      {'status': status, for (final column in columns) column: ''},
  ];
}

List<Map<String, dynamic>> _qualificationRows() {
  return [
    for (final qualification in _qualifications)
      {
        'qualification': qualification,
        for (final role in _teachingRoles)
          for (final gender in _genderColumns.take(3)) '${role}_$gender': '',
        'Total': '',
      },
  ];
}

const _extendedProfileMetrics = [
  _Metric(
    'programmes_offered',
    '1.1',
    'Number of programmes offered year-wise for last five years',
  ),
  _Metric(
    'students',
    '2.1',
    'Number of students year-wise during last five years',
  ),
  _Metric(
    'outgoing_students',
    '2.2',
    'Number of outgoing / final year students year-wise during last five years',
  ),
  _Metric(
    'exam_appeared',
    '2.3',
    'Number of students appeared in university examination year-wise during last five years',
  ),
  _Metric(
    'revaluation_applications',
    '2.4',
    'Number of revaluation applications year-wise during last five years',
  ),
  _Metric(
    'courses',
    '3.1',
    'Number of courses in all programmes year-wise during last five years',
  ),
  _Metric(
    'full_time_teachers',
    '3.2',
    'Number of full-time teachers year-wise during last five years',
  ),
  _Metric(
    'sanctioned_posts',
    '3.3',
    'Number of sanctioned posts year-wise during last five years',
  ),
  _Metric(
    'eligible_applications',
    '4.1',
    'Eligible applications received for admissions year-wise',
  ),
  _Metric('reserved_seats', '4.2', 'Reserved category seats year-wise'),
  _Metric(
    'expenditure_excluding_salary',
    '4.5',
    'Total expenditure excluding salary year-wise in INR Lakhs',
  ),
];

class _Metric {
  const _Metric(this.key, this.code, this.label);

  final String key;
  final String code;
  final String label;
}

Map<String, dynamic> _normalizeSsrData(
  String sectionKey,
  Map<String, dynamic> raw,
) {
  final defaults = _defaultSsrDataFor(sectionKey);
  return _mergeDefaults(defaults, raw);
}

Map<String, dynamic> _mergeDefaults(
  Map<String, dynamic> defaults,
  Map<String, dynamic> raw,
) {
  final next = _deepCopyMap(defaults);
  for (final entry in raw.entries) {
    final defaultValue = next[entry.key];
    if (defaultValue is Map && entry.value is Map) {
      next[entry.key] = _mergeDefaults(
        Map<String, dynamic>.from(defaultValue),
        Map<String, dynamic>.from(entry.value as Map),
      );
    } else {
      next[entry.key] = _deepCopyValue(entry.value);
    }
  }
  return next;
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
  return Map<String, dynamic>.from(_deepCopyValue(value) as Map);
}

dynamic _deepCopyValue(dynamic value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _deepCopyValue(entry.value),
    };
  }
  if (value is List) return value.map(_deepCopyValue).toList();
  return value;
}

Map<String, dynamic> _emptyLike(Map<String, dynamic> source) {
  return {
    for (final entry in source.entries)
      entry.key: entry.value is Map
          ? _emptyLike(Map<String, dynamic>.from(entry.value as Map))
          : entry.value is List
          ? <dynamic>[]
          : '',
  };
}

String _titleForKey(String key) {
  final cleaned = key
      .replaceAll('.', ' ')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return key;
  const overrides = {
    'Non Teaching': 'Non-teaching',
    'Part Time Teachers': 'Part-time Teachers',
    'Qualification Details': 'Qualification Details',
  };
  final overridden = overrides[cleaned];
  if (overridden != null) return overridden;
  return cleaned
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

bool _isNumericLabel(String label) {
  final lower = label.toLowerCase();
  return lower.contains('number') ||
      lower.contains('total') ||
      lower.contains('year') ||
      lower.contains('pin') ||
      lower.contains('area') ||
      lower.contains('acres') ||
      lower.contains('sq') ||
      lower.contains('expenditure') ||
      lower.contains('male') ||
      lower.contains('female') ||
      lower.contains('others');
}

bool _isDateLabel(String label) {
  final lower = label.toLowerCase();
  return lower.contains('date');
}

DateTime? _parseSsrDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;

  final isoDate = DateTime.tryParse(trimmed);
  if (isoDate != null) return isoDate;

  final match = RegExp(
    r'^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{4})$',
  ).firstMatch(trimmed);
  if (match == null) return null;

  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) return null;

  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

String _formatSsrDate(DateTime date) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
}

bool _isEmailLabel(String label) {
  return label.toLowerCase().contains('email');
}

bool _isUrlLabel(String label) {
  final lower = label.toLowerCase();
  return lower.contains('website') || lower.contains('url');
}

bool _isYesNoLabel(String label) {
  final lower = label.toLowerCase();
  return lower.contains('recognized') ||
      lower.contains('recognised') ||
      lower.contains('programmes recognized') ||
      lower.contains('offer integrated') ||
      lower.contains('upe');
}

List<String> _optionsForLabel(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('campus type')) {
    return _campusTypeOptions;
  }
  if (_isYesNoLabel(label)) return const ['Yes', 'No'];
  return const [];
}

String _compactValuePreview(dynamic value) {
  if (value is Map) {
    final meaningful = value.entries
        .where((entry) => _SsrSectionMeta._hasMeaningfulValue(entry.value))
        .take(2)
        .map(
          (entry) =>
              '${_titleForKey(entry.key.toString())}: ${_compactPreviewValue(entry.value)}',
        )
        .join('\n');
    return meaningful.isEmpty ? 'No content yet' : meaningful;
  }
  if (value is List) {
    return '${value.length} entr${value.length == 1 ? 'y' : 'ies'}';
  }
  final text = (value ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return 'Blank';
  return text.length > 80 ? '${text.substring(0, 80)}...' : text;
}

String _compactPreviewValue(dynamic value) {
  if (value is List) {
    return '${value.length} ${value.length == 1 ? 'entry' : 'entries'}';
  }
  if (value is Map) {
    final filled = value.values
        .where((item) => _SsrSectionMeta._hasMeaningfulValue(item))
        .length;
    if (filled == 0) return 'No content';
    return '$filled ${filled == 1 ? 'field' : 'fields'} filled';
  }
  final text = (value ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return 'Blank';
  return text.length > 36 ? '${text.substring(0, 36)}...' : text;
}

int _countWords(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
}

String _singularListLabel(String label) {
  final normalized = label.trim();
  const explicit = {
    'Contacts': 'Contact',
    'Campuses': 'Campus',
    'Location, Area and Activity of Campus': 'Campus',
    'Chairs': 'Chair',
    'Chairs Instituted by the University': 'Chair',
    'Student Enrolment': 'Student enrolment',
    'Distinguished Academicians': 'Distinguished academician',
    'Department Reports': 'Department report',
    'Evaluative Report of the Departments': 'Department report',
    'Affiliated Institutions': 'Affiliated institution',
    'Affiliated Institutions to the University': 'Affiliated institution',
    'College Details': 'College detail',
    'Details of Colleges under University': 'College detail',
    'Teaching': 'Teaching faculty',
    'Non Teaching': 'Non-teaching staff',
    'Technical': 'Technical staff',
    'Permanent Teachers': 'Permanent teacher qualification',
    'Temporary Teachers': 'Temporary teacher qualification',
    'Part Time Teachers': 'Part-time teacher qualification',
    'Enrolment': 'Enrolment',
    'Year Labels': 'Year',
  };
  final match = explicit[normalized];
  if (match != null) return match;
  if (normalized.endsWith('ies') && normalized.length > 3) {
    return '${normalized.substring(0, normalized.length - 3)}y';
  }
  if (normalized.endsWith('s') && normalized.length > 1) {
    return normalized.substring(0, normalized.length - 1);
  }
  return normalized.isEmpty ? 'Item' : normalized;
}

bool _canAddListItem(String label) {
  return label == 'Contacts' ||
      label == 'Location, Area and Activity of Campus' ||
      label == 'Chairs Instituted by the University' ||
      label == 'Evaluative Report of the Departments';
}

String _listItemTitle({
  required String label,
  required int index,
  required dynamic value,
  required List<String>? itemLabels,
}) {
  final explicit = itemLabels != null && index < itemLabels.length
      ? itemLabels[index].trim()
      : '';
  if (explicit.isNotEmpty) return explicit;
  if (value is Map && label == 'Contacts') {
    final designation = value['designation']?.toString().trim() ?? '';
    if (designation.isNotEmpty) return designation;
  }
  if (value is Map &&
      (label == 'Campuses' ||
          label == 'Location, Area and Activity of Campus')) {
    final String type = value['campus_type']?.toString().trim() ?? '';
    if (_campusTypeOptions.contains(type)) return type;
    return 'Campus Type';
  }
  if (value is Map) {
    final rowTitle = _listRowTitleFromColumns(
      label,
      Map<String, dynamic>.from(value),
    );
    if (rowTitle.isNotEmpty) return rowTitle;
  }
  if (value is! Map) return 'Year ${index + 1}';
  return '${_singularListLabel(label)} ${index + 1}';
}

String _listRowTitleFromColumns(String label, Map<String, dynamic> row) {
  final priorityKeys = _listTitlePriorityKeys(label);
  for (final key in priorityKeys) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }

  return row.values
      .map((item) => item?.toString().trim() ?? '')
      .firstWhere((item) => item.isNotEmpty, orElse: () => '');
}

List<String> _listTitlePriorityKeys(String label) {
  switch (label) {
    case 'Contacts':
      return const ['designation', 'name', 'email', 'mobile'];
    case 'Location, Area and Activity of Campus':
    case 'Campuses':
      return const ['campus_type', 'location', 'address'];
    case 'Affiliated Institutions to the University':
    case 'Affiliated Institutions':
      return const ['college_type'];
    case 'Details of Colleges under University':
    case 'College Details':
      return const ['label'];
    case 'Teaching':
    case 'Non Teaching':
    case 'Technical':
      return const ['status'];
    case 'Permanent Teachers':
    case 'Temporary Teachers':
    case 'Part Time Teachers':
      return const ['qualification'];
    case 'Distinguished Academicians Appointed':
    case 'Distinguished Academicians':
      return const ['role'];
    case 'Chairs Instituted by the University':
    case 'Chairs':
      return const ['department', 'chair', 'sponsor', 'sl_no'];
    case 'Students Enrolled during the Current Academic Year':
    case 'Student Enrolment':
      return const ['programme', 'gender'];
    case 'Integrated Programme Enrolment':
    case 'Enrolment':
      return const ['gender', 'programme'];
    case 'Evaluative Report of the Departments':
    case 'Department Reports':
      return const ['department_name', 'report_reference'];
    default:
      return const [];
  }
}

List<String> _valueToLines(dynamic value) {
  if (value == null || value == '') return const ['(blank)'];
  if (value is String) {
    final lines = value
        .split(RegExp(r'\n{2,}|\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.isEmpty ? const ['(blank)'] : lines;
  }
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value).split('\n');
}

String? _validateSsrSection(String sectionKey, Map<String, dynamic> data) {
  if (sectionKey != 'university_profile') return null;
  final contacts = data['contacts'];
  if (contacts is! List) return null;
  final invalidRows = <String>[];
  final emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  for (var i = 0; i < contacts.length; i++) {
    final row = contacts[i];
    if (row is! Map) continue;
    final email = (row['email'] ?? '').toString().trim();
    if (email.isNotEmpty && !emailRe.hasMatch(email)) {
      invalidRows.add('${i + 1}');
    }
  }
  if (invalidRows.isEmpty) return null;
  return 'Fix invalid contact email address in row(s): ${invalidRows.join(', ')}.';
}

class _SsrCardInfo {
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final _SsrSectionMeta? meta;

  const _SsrCardInfo({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    this.meta,
  });

  _SsrCardInfo copyWith({_SsrSectionMeta? meta}) {
    return _SsrCardInfo(
      key: key,
      title: title,
      description: description,
      icon: icon,
      meta: meta,
    );
  }
}

class _SsrSectionMeta {
  final String sectionKey;
  final Map<String, dynamic> data;
  final String? updatedByName;
  final String? updatedByEmail;
  final DateTime? updatedAt;

  const _SsrSectionMeta({
    required this.sectionKey,
    required this.data,
    required this.updatedByName,
    required this.updatedByEmail,
    required this.updatedAt,
  });

  bool get hasData => data.values.any(_hasMeaningfulValue);

  String? get editorName {
    final name = updatedByName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = updatedByEmail?.trim();
    return email == null || email.isEmpty ? null : email;
  }

  factory _SsrSectionMeta.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    return _SsrSectionMeta(
      sectionKey: (json['section_key'] ?? '').toString(),
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : {},
      updatedByName: json['updated_by_name']?.toString(),
      updatedByEmail: json['updated_by_email']?.toString(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    );
  }

  static bool _hasMeaningfulValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is num || value is bool) return value != 0 && value != false;
    if (value is Iterable) return value.any(_hasMeaningfulValue);
    if (value is Map) return value.values.any(_hasMeaningfulValue);
    return true;
  }
}

class _SsrHistoryEntry {
  final String id;
  final String changeSummary;
  final String editorName;
  final String editorEmail;
  final DateTime? editedAt;
  final List<String> changedFields;
  final Map<String, dynamic> fieldDiffs;

  const _SsrHistoryEntry({
    required this.id,
    required this.changeSummary,
    required this.editorName,
    required this.editorEmail,
    required this.editedAt,
    required this.changedFields,
    required this.fieldDiffs,
  });

  factory _SsrHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawFields = json['changed_fields'];
    final rawDiffs = json['field_diffs'];
    return _SsrHistoryEntry(
      id: (json['id'] ?? '').toString(),
      changeSummary: (json['change_summary'] ?? '').toString(),
      editorName:
          (json['edited_by_name'] ?? json['edited_by_email'] ?? 'IQAC user')
              .toString(),
      editorEmail: (json['edited_by_email'] ?? '').toString(),
      editedAt: DateTime.tryParse((json['edited_at'] ?? '').toString()),
      changedFields: rawFields is List
          ? rawFields.map((field) => field.toString()).toList()
          : const [],
      fieldDiffs: rawDiffs is Map ? Map<String, dynamic>.from(rawDiffs) : {},
    );
  }

  _SsrHistoryEntry copyWith({Map<String, dynamic>? fieldDiffs}) {
    return _SsrHistoryEntry(
      id: id,
      changeSummary: changeSummary,
      editorName: editorName,
      editorEmail: editorEmail,
      editedAt: editedAt,
      changedFields: changedFields,
      fieldDiffs: fieldDiffs ?? this.fieldDiffs,
    );
  }
}

class _SsrMobileCard extends StatelessWidget {
  const _SsrMobileCard({required this.card, required this.onTap});

  final _SsrCardInfo card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.1)
        : AppColors.border;
    final editedBy = card.meta?.editorName;
    final editedAt = card.meta?.updatedAt;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SsrIconBubble(icon: card.icon, size: 44),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.4,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        editedBy == null
                            ? Icons.pending_actions_rounded
                            : Icons.check_circle_rounded,
                        size: 16,
                        color: editedBy == null
                            ? theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              )
                            : const Color(0xFF047857),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          editedBy == null
                              ? 'Not edited yet'
                              : 'Edited by $editedBy',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: editedBy == null
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (editedAt != null)
                        Text(
                          _compactDate(editedAt),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _compactDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _SsrIconBubble extends StatelessWidget {
  const _SsrIconBubble({required this.icon, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: AppColors.primary, size: size * 0.5),
    );
  }
}

class _SsrIconActionShell extends StatelessWidget {
  const _SsrIconActionShell({
    required this.icon,
    required this.size,
    this.disabled = false,
    this.busy = false,
  });

  final IconData icon;
  final double size;
  final bool disabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.62 : 1,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _indigo50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _indigo100),
          boxShadow: [
            BoxShadow(
              color: _indigo600.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _indigo600,
                ),
              )
            : Icon(icon, color: _indigo600, size: 21),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12,
                height: 1.3,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _SsrDraftChanged<T> = void Function(T value, {bool rebuild});

class _SsrDataEditor extends StatelessWidget {
  const _SsrDataEditor({
    required this.sectionKey,
    required this.data,
    required this.onChanged,
  });

  final String sectionKey;
  final Map<String, dynamic> data;
  final _SsrDraftChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (sectionKey == 'qif') {
      return const _QifGuidanceEditor();
    }
    if (sectionKey == 'executive_summary') {
      return _ExecutiveSummaryEditor(data: data, onChanged: onChanged);
    }
    if (sectionKey == 'university_profile') {
      return _UniversityProfileEditor(data: data, onChanged: onChanged);
    }
    final entries = data.entries.toList();
    final yearLabels = (data['year_labels'] is List)
        ? (data['year_labels'] as List)
              .map((value) => value.toString())
              .toList()
        : const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _SsrValueEditor(
            label: _titleForKey(entry.key),
            value: entry.value,
            itemLabels: entry.key == 'metrics' ? yearLabels : null,
            onChanged: (value, {rebuild = false}) {
              final next = _deepCopyMap(data);
              next[entry.key] = value;
              onChanged(next, rebuild: rebuild);
            },
          ),
        );
      }).toList(),
    );
  }
}

class _ExecutiveSummaryEditor extends StatefulWidget {
  const _ExecutiveSummaryEditor({required this.data, required this.onChanged});

  final Map<String, dynamic> data;
  final _SsrDraftChanged<Map<String, dynamic>> onChanged;

  @override
  State<_ExecutiveSummaryEditor> createState() =>
      _ExecutiveSummaryEditorState();
}

class _ExecutiveSummaryEditorState extends State<_ExecutiveSummaryEditor> {
  late Map<String, dynamic> _draft;

  static const _fields = [
    (
      key: 'introductory_note',
      label: 'Introductory Note on the Institution',
      guidance: 'Location, vision, mission, type of institution, etc.',
      minLines: 6,
    ),
    (
      key: 'criteria_summary',
      label: 'Criterion-wise Summary',
      guidance:
          "Summarise the institution's functioning criterion-wise in not more than 250 words for each criterion.",
      minLines: 8,
    ),
    (
      key: 'swoc_analysis',
      label: 'SWOC Analysis',
      guidance:
          'Brief note on Strengths, Weaknesses, Opportunities and Challenges.',
      minLines: 7,
    ),
    (
      key: 'additional_information',
      label: 'Additional Information about the Institution',
      guidance:
          'Any additional information about the institution other than already stated.',
      minLines: 6,
    ),
    (
      key: 'conclusive_explication',
      label: 'Overall Conclusive Explication',
      guidance:
          "Overall conclusive explication about the institution's functioning.",
      minLines: 6,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _draft = _deepCopyMap(widget.data);
  }

  @override
  void didUpdateWidget(covariant _ExecutiveSummaryEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _draft = _deepCopyMap(widget.data);
    }
  }

  void _update(String key, String value) {
    setState(() => _draft = {..._draft, key: value});
    widget.onChanged(_draft);
  }

  int get _totalWords => _fields.fold<int>(
    0,
    (total, field) => total + _countWords((_draft[field.key] ?? '').toString()),
  );

  @override
  Widget build(BuildContext context) {
    final wordCount = _totalWords;
    final overLimit = wordCount > 5000;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExecutiveSummaryIntro(wordCount: wordCount, overLimit: overLimit),
        const SizedBox(height: 12),
        _ExecutiveSummaryWordCount(wordCount: wordCount, overLimit: overLimit),
        const SizedBox(height: 22),
        for (final field in _fields) ...[
          _ExecutiveSummaryField(
            key: ValueKey(field.key),
            label: field.label,
            guidance: field.guidance,
            value: (_draft[field.key] ?? '').toString(),
            minLines: field.minLines,
            onChanged: (value) => _update(field.key, value),
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }
}

class _ExecutiveSummaryWordCount extends StatelessWidget {
  const _ExecutiveSummaryWordCount({
    required this.wordCount,
    required this.overLimit,
  });

  final int wordCount;
  final bool overLimit;

  @override
  Widget build(BuildContext context) {
    final color = overLimit ? Theme.of(context).colorScheme.error : _blue800;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: overLimit
            ? Theme.of(context).colorScheme.error.withValues(alpha: 0.08)
            : _blue50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: overLimit
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.22)
              : _blue100,
        ),
      ),
      child: Text(
        'The Executive summary shall not be more than 5000 words. Current count: $wordCount/5000 words.',
        style: GoogleFonts.poppins(
          fontSize: 13,
          height: 1.35,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ExecutiveSummaryIntro extends StatelessWidget {
  const _ExecutiveSummaryIntro({
    required this.wordCount,
    required this.overLimit,
  });

  final int wordCount;
  final bool overLimit;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 380;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(isCompact ? 14 : 16),
          decoration: BoxDecoration(
            color: _blue50,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _blue100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: isCompact ? 36 : 40,
                height: isCompact ? 36 : 40,
                decoration: BoxDecoration(
                  color: _blue100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: _blue600,
                  size: isCompact ? 20 : 22,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 12),
              Expanded(
                child: Text(
                  'Every HEI applying for the A&A process shall prepare an Executive Summary highlighting the main features of the Institution.',
                  style: GoogleFonts.poppins(
                    fontSize: isCompact ? 13 : 14,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: _blue800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExecutiveSummaryField extends StatefulWidget {
  const _ExecutiveSummaryField({
    super.key,
    required this.label,
    required this.guidance,
    required this.value,
    required this.minLines,
    required this.onChanged,
  });

  final String label;
  final String guidance;
  final String value;
  final int minLines;
  final ValueChanged<String> onChanged;

  @override
  State<_ExecutiveSummaryField> createState() => _ExecutiveSummaryFieldState();
}

class _ExecutiveSummaryFieldState extends State<_ExecutiveSummaryField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _ExecutiveSummaryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = _countWords(_controller.text);
    final isCompact = MediaQuery.of(context).size.width < 380;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: GoogleFonts.poppins(
                  fontSize: isCompact ? 14 : 15,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  color: const Color(0xFF111827),
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (words > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$words words',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF94A3B8),
                    letterSpacing: 0,
                  ),
                ),
              ),
          ],
        ),
        if (widget.guidance.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.guidance,
            style: GoogleFonts.poppins(
              fontSize: 12,
              height: 1.35,
              color: const Color(0xFF64748B),
              letterSpacing: 0,
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextFormField(
          controller: _controller,
          minLines: widget.minLines,
          maxLines: widget.minLines + 4,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: 'Enter ${widget.label.toLowerCase()}',
            hintStyle: GoogleFonts.poppins(
              color: const Color(0xFF94A3B8),
              fontSize: isCompact ? 14 : 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _blue600, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.all(isCompact ? 14 : 16),
          ),
          style: GoogleFonts.poppins(
            fontSize: isCompact ? 14 : 15,
            height: 1.45,
            color: const Color(0xFF1E293B),
            letterSpacing: 0,
          ),
          onChanged: (value) {
            setState(() {});
            widget.onChanged(value);
          },
        ),
      ],
    );
  }
}

class _UniversityProfileEditor extends StatefulWidget {
  const _UniversityProfileEditor({required this.data, required this.onChanged});

  final Map<String, dynamic> data;
  final _SsrDraftChanged<Map<String, dynamic>> onChanged;

  @override
  State<_UniversityProfileEditor> createState() =>
      _UniversityProfileEditorState();
}

class _UniversityProfileEditorState extends State<_UniversityProfileEditor> {
  int? _activeSectionIndex;

  void _update(String key, dynamic value, {bool rebuild = false}) {
    final next = _deepCopyMap(widget.data);
    next[key] = value;
    widget.onChanged(next, rebuild: rebuild);
  }

  Map<String, dynamic> _mapFor(String key) {
    final value = widget.data[key];
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  List<dynamic> _listFor(String key) {
    final value = widget.data[key];
    return value is List ? List<dynamic>.from(value) : <dynamic>[];
  }

  dynamic _academicValue(String key) {
    return _mapFor('academic_information')[key];
  }

  void _updateAcademic(String key, dynamic value, {bool rebuild = false}) {
    final nextAcademic = _mapFor('academic_information');
    nextAcademic[key] = value;
    _update('academic_information', nextAcademic, rebuild: rebuild);
  }

  void _updateIntegrated(String key, dynamic value, {bool rebuild = false}) {
    final nextIntegrated = _mapFor('integrated_programmes');
    nextIntegrated[key] = value;
    _update('integrated_programmes', nextIntegrated, rebuild: rebuild);
  }

  List<_ProfileSectionConfig> get _sections {
    return [
      _ProfileSectionConfig(
        title: 'Basic Information',
        icon: Icons.space_dashboard_outlined,
        value: _mapFor('basic_information'),
        onChanged: (value, {rebuild = false}) {
          _update('basic_information', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Contacts',
        icon: Icons.people_outline_rounded,
        value: _listFor('contacts'),
        onChanged: (value, {rebuild = false}) {
          _update('contacts', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Nature and Status',
        icon: Icons.business_outlined,
        value: _mapFor('institution'),
        onChanged: (value, {rebuild = false}) {
          _update('institution', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Establishment Details',
        icon: Icons.calendar_month_outlined,
        value: _mapFor('establishment'),
        onChanged: (value, {rebuild = false}) {
          _update('establishment', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Recognition Details',
        icon: Icons.workspace_premium_outlined,
        value: {
          ..._mapFor('recognition'),
          'upe_recognized': widget.data['upe_recognized'] ?? '',
        },
        onChanged: (value, {rebuild = false}) {
          final nextValue = Map<String, dynamic>.from(value as Map);
          final recognition = Map<String, dynamic>.from(nextValue)
            ..remove('upe_recognized');
          final next = _deepCopyMap(widget.data);
          next['recognition'] = recognition;
          next['upe_recognized'] = nextValue['upe_recognized'] ?? '';
          widget.onChanged(next, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Location, Area and Activity of Campus',
        icon: Icons.location_on_outlined,
        value: _listFor('campuses'),
        onChanged: (value, {rebuild = false}) {
          _update('campuses', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Affiliated Institutions to the University',
        icon: Icons.local_library_outlined,
        value: _academicValue('affiliated_institutions') ?? const [],
        onChanged: (value, {rebuild = false}) {
          _updateAcademic('affiliated_institutions', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Details of Colleges under University',
        icon: Icons.menu_book_outlined,
        value: _academicValue('college_details') ?? const [],
        onChanged: (value, {rebuild = false}) {
          _updateAcademic('college_details', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Statutory Regulatory Authority Recognition',
        icon: Icons.verified_outlined,
        value: {
          'sra_recognized': _academicValue('sra_recognized') ?? '',
          'sra_details': _academicValue('sra_details') ?? '',
        },
        onChanged: (value, {rebuild = false}) {
          final nextValue = Map<String, dynamic>.from(value as Map);
          final nextAcademic = _mapFor('academic_information');
          nextAcademic['sra_recognized'] = nextValue['sra_recognized'] ?? '';
          nextAcademic['sra_details'] = nextValue['sra_details'] ?? '';
          _update('academic_information', nextAcademic, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Staff Details',
        icon: Icons.school_outlined,
        value: {
          'staff': widget.data['staff'],
          'qualification_details': widget.data['qualification_details'],
        },
        intro:
            'Use the cards below to enter staff counts and teacher qualification details.',
        onChanged: (value, {rebuild = false}) {
          final grouped = Map<String, dynamic>.from(value as Map);
          final next = _deepCopyMap(widget.data);
          next['staff'] = grouped['staff'];
          next['qualification_details'] = grouped['qualification_details'];
          widget.onChanged(next, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Distinguished Academicians Appointed',
        icon: Icons.workspace_premium_outlined,
        value: _listFor('distinguished_academicians'),
        onChanged: (value, {rebuild = false}) {
          _update('distinguished_academicians', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Chairs Instituted by the University',
        icon: Icons.event_seat_outlined,
        value: _listFor('chairs'),
        onChanged: (value, {rebuild = false}) {
          _update('chairs', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Students Enrolled during the Current Academic Year',
        icon: Icons.groups_outlined,
        value: _listFor('student_enrolment'),
        onChanged: (value, {rebuild = false}) {
          _update('student_enrolment', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Integrated Programmes',
        icon: Icons.menu_book_outlined,
        value: {
          'offered': _mapFor('integrated_programmes')['offered'] ?? '',
          'total_programmes':
              _mapFor('integrated_programmes')['total_programmes'] ?? '',
        },
        onChanged: (value, {rebuild = false}) {
          final nextValue = Map<String, dynamic>.from(value as Map);
          final nextIntegrated = _mapFor('integrated_programmes');
          nextIntegrated['offered'] = nextValue['offered'] ?? '';
          nextIntegrated['total_programmes'] =
              nextValue['total_programmes'] ?? '';
          _update('integrated_programmes', nextIntegrated, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Integrated Programme Enrolment',
        icon: Icons.how_to_reg_outlined,
        value: _mapFor('integrated_programmes')['enrolment'] ?? const [],
        onChanged: (value, {rebuild = false}) {
          _updateIntegrated('enrolment', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'UGC Human Resource Development Centre',
        icon: Icons.business_center_outlined,
        value: _mapFor('hrdc'),
        onChanged: (value, {rebuild = false}) {
          _update('hrdc', value, rebuild: rebuild);
        },
      ),
      _ProfileSectionConfig(
        title: 'Evaluative Report of the Departments',
        icon: Icons.description_outlined,
        value: _listFor('department_reports'),
        onChanged: (value, {rebuild = false}) {
          _update('department_reports', value, rebuild: rebuild);
        },
      ),
    ];
  }

  void _openSection(int index) {
    setState(() => _activeSectionIndex = index);
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: 0,
    );
  }

  void _moveSection(int direction) {
    final index = _activeSectionIndex;
    if (index == null) return;
    final nextIndex = index + direction;
    if (nextIndex < 0 || nextIndex >= _sections.length) return;
    _openSection(nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final activeIndex = _activeSectionIndex;

    if (activeIndex != null && activeIndex < sections.length) {
      final section = sections[activeIndex];
      return _ProfileSectionPage(
        section: section,
        index: activeIndex,
        total: sections.length,
        onBack: () => setState(() => _activeSectionIndex = null),
        onPrevious: activeIndex == 0 ? null : () => _moveSection(-1),
        onNext: activeIndex == sections.length - 1
            ? null
            : () => _moveSection(1),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileSectionIndex(sections: sections, onSelected: _openSection),
      ],
    );
  }
}

class _ProfileSectionConfig {
  const _ProfileSectionConfig({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.intro,
  });

  final String title;
  final IconData icon;
  final dynamic value;
  final String? intro;
  final _SsrDraftChanged<dynamic> onChanged;
}

class _ProfileSectionIndex extends StatelessWidget {
  const _ProfileSectionIndex({
    required this.sections,
    required this.onSelected,
  });

  final List<_ProfileSectionConfig> sections;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileShell(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ProfileIcon(icon: Icons.dashboard_customize_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile Sections',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: _slate900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Open one section at a time to edit the university profile.',
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: _slate500,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < sections.length; i++) ...[
          _ProfileSectionTile(
            index: i,
            section: sections[i],
            onTap: () => onSelected(i),
          ),
          if (i != sections.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ProfileSectionTile extends StatelessWidget {
  const _ProfileSectionTile({
    required this.index,
    required this.section,
    required this.onTap,
  });

  final int index;
  final _ProfileSectionConfig section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = _compactValuePreview(section.value);
    final hasPreview = preview != 'Blank' && preview != 'No content yet';

    return _ProfileShell(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              _ProfileIcon(icon: section.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}. ${section.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        height: 1.25,
                        color: _slate900,
                        letterSpacing: 0,
                      ),
                    ),
                    if (hasPreview) ...[
                      const SizedBox(height: 5),
                      Text(
                        preview.replaceAll('\n', '  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _slate500,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _indigo50,
                  shape: BoxShape.circle,
                  border: Border.all(color: _indigo100),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: _indigo600,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSectionPage extends StatelessWidget {
  const _ProfileSectionPage({
    required this.section,
    required this.index,
    required this.total,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
  });

  final _ProfileSectionConfig section;
  final int index;
  final int total;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProfileShell(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: onBack,
                      tooltip: 'Back to sections',
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: _slate500,
                      style: IconButton.styleFrom(
                        backgroundColor: _slate100,
                        fixedSize: const Size(42, 42),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'SECTION ${index + 1} OF $total',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _indigo600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProfileIcon(icon: section.icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        section.title,
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: _slate900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPrevious,
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('Previous'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _slate800,
                          disabledForegroundColor: _slate300,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: const BorderSide(color: _slate200),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onNext,
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: Text(index == total - 1 ? 'Last' : 'Next'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _indigo600,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _indigo600.withValues(
                            alpha: 0.38,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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
        const SizedBox(height: 14),
        _ProfileAccordionCard(
          title: section.title,
          icon: section.icon,
          value: section.value,
          intro: section.intro,
          initiallyExpanded: true,
          onChanged: section.onChanged,
        ),
      ],
    );
  }
}

class _ProfileAccordionCard extends StatelessWidget {
  const _ProfileAccordionCard({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.intro,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final dynamic value;
  final String? intro;
  final bool initiallyExpanded;
  final _SsrDraftChanged<dynamic> onChanged;

  Widget _mapField(
    Map<String, dynamic> mapValue,
    MapEntry<String, dynamic> entry,
  ) {
    return _SsrValueEditor(
      label: _titleForKey(entry.key),
      value: entry.value,
      onChanged: (nextValue, {rebuild = false}) {
        final next = _deepCopyMap(mapValue);
        next[entry.key] = nextValue;
        onChanged(next, rebuild: rebuild);
      },
    );
  }

  List<Widget> _mapChildren() {
    final mapValue = Map<String, dynamic>.from(value as Map);
    if (title != 'Basic Information') {
      return [for (final entry in mapValue.entries) _mapField(mapValue, entry)];
    }

    final children = <Widget>[];
    for (final entry in mapValue.entries) {
      if (entry.key == 'pin') continue;
      if (entry.key == 'city' && mapValue.containsKey('pin')) {
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _mapField(mapValue, entry)),
              const SizedBox(width: 12),
              Expanded(
                child: _mapField(mapValue, MapEntry('pin', mapValue['pin'])),
              ),
            ],
          ),
        );
      } else {
        children.add(_mapField(mapValue, entry));
      }
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    return _ProfileShell(
      child: _LazyExpansionCard(
        title: title,
        subtitle: '',
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        childrenPadding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        leading: _ProfileIcon(icon: icon),
        childrenBuilder: () => [
          if (intro != null) ...[
            _ProfileInfoBox(text: intro!),
            const SizedBox(height: 14),
          ],
          if (value is Map)
            ..._mapChildren()
          else
            _SsrValueEditor(label: title, value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ProfileShell extends StatelessWidget {
  const _ProfileShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDE6F3)),
        boxShadow: [
          BoxShadow(
            color: _slate900.withValues(alpha: 0.055),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.9),
            blurRadius: 1,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ProfileIcon extends StatelessWidget {
  const _ProfileIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F7FF), _indigo50],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _indigo100),
      ),
      child: Icon(icon, color: _indigo600, size: 20),
    );
  }
}

class _ProfileInfoBox extends StatelessWidget {
  const _ProfileInfoBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE8FA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDE8FA)),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: _blue600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF24406F),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SsrValueEditor extends StatefulWidget {
  const _SsrValueEditor({
    required this.label,
    required this.value,
    required this.onChanged,
    this.itemLabels,
  });

  final String label;
  final dynamic value;
  final _SsrDraftChanged<dynamic> onChanged;
  final List<String>? itemLabels;

  @override
  State<_SsrValueEditor> createState() => _SsrValueEditorState();
}

class _SsrValueEditorState extends State<_SsrValueEditor> {
  int _visibleRows = 6;

  @override
  void didUpdateWidget(covariant _SsrValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value is! List) _visibleRows = 6;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.value;

    if (value is Map) {
      final mapValue = Map<String, dynamic>.from(value);
      final entries = mapValue.entries.toList();
      if (widget.label == 'Metrics') {
        return _SsrMetricsEditor(
          metrics: mapValue,
          yearLabels: widget.itemLabels ?? _academicYearLabels,
          onChanged: widget.onChanged,
        );
      }
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _LazyExpansionCard(
          title: widget.label,
          subtitle: _compactValuePreview(value),
          initiallyExpanded:
              widget.label == 'Basic Information' ||
              widget.label == 'Infrastructure Summary',
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _indigo50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _iconForSsrGroup(widget.label),
              color: _indigo600,
              size: 20,
            ),
          ),
          childrenBuilder: () => entries
              .map(
                (entry) => _SsrValueEditor(
                  label: _titleForKey(entry.key),
                  value: entry.value,
                  itemLabels: widget.label == 'Metrics'
                      ? widget.itemLabels
                      : null,
                  onChanged: (nextValue, {rebuild = false}) {
                    final next = _deepCopyMap(mapValue);
                    next[entry.key] = nextValue;
                    widget.onChanged(next, rebuild: rebuild);
                  },
                ),
              )
              .toList(),
        ),
      );
    }

    if (value is List) {
      if (widget.label == 'Year Labels' &&
          value.every((item) => item is! Map)) {
        return _SsrYearLabelsEditor(
          values: value.map((item) => item.toString()).toList(),
          onChanged: widget.onChanged,
        );
      }
      final visibleItems = value.take(_visibleRows).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              widget.label,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          for (var i = 0; i < visibleItems.length; i++) ...[
            _SsrListItemEditor(
              label: widget.label,
              index: i,
              value: visibleItems[i],
              itemTitle: _listItemTitle(
                label: widget.label,
                index: i,
                value: visibleItems[i],
                itemLabels: widget.itemLabels,
              ),
              onChanged: (nextValue, {rebuild = false}) {
                final next = List<dynamic>.from(value);
                next[i] = nextValue;
                widget.onChanged(next, rebuild: rebuild);
              },
              onRemove: value.length <= 1
                  ? null
                  : () {
                      final next = List<dynamic>.from(value)..removeAt(i);
                      widget.onChanged(next, rebuild: true);
                    },
            ),
            const SizedBox(height: 12),
          ],
          if (_visibleRows < value.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _visibleRows += 6),
                icon: const Icon(Icons.expand_more_rounded),
                label: Text(
                  'Show ${value.length - _visibleRows} more cards',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          if (value.isNotEmpty &&
              value.first is Map &&
              _canAddListItem(widget.label))
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    widget.onChanged([
                      ...value,
                      _emptyLike(Map<String, dynamic>.from(value.first as Map)),
                    ], rebuild: true);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _indigo600,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    side: BorderSide(color: _indigo100, width: 1.5),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    'Add ${_singularListLabel(widget.label)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final textValue = value?.toString() ?? '';
    final options = _optionsForLabel(widget.label);
    final multiLine =
        textValue.length > 70 ||
        widget.label.toLowerCase().contains('summary') ||
        widget.label.toLowerCase().contains('address') ||
        widget.label.toLowerCase().contains('note') ||
        widget.label.toLowerCase().contains('analysis') ||
        widget.label.toLowerCase().contains('information');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              widget.label,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF536179),
                letterSpacing: 0,
              ),
            ),
          ),
          if (options.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: options.contains(textValue) ? textValue : null,
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('Select'),
                ),
                ...options.map(
                  (option) => DropdownMenuItem<String>(
                    value: option,
                    child: Text(option),
                  ),
                ),
              ],
              onChanged: (next) => widget.onChanged(next ?? ''),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFDCE5F1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _indigo500, width: 2),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFD),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 17,
                ),
              ),
              style: GoogleFonts.poppins(
                fontSize: 15.5,
                color: theme.colorScheme.onSurface,
                height: 1.35,
                letterSpacing: 0,
              ),
            )
          else if (_isDateLabel(widget.label))
            _SsrDatePickerField(value: textValue, onChanged: widget.onChanged)
          else
            TextFormField(
              initialValue: textValue,
              minLines: multiLine ? 4 : 1,
              maxLines: multiLine ? 8 : 1,
              keyboardType: _isNumericLabel(widget.label)
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : _isEmailLabel(widget.label)
                  ? TextInputType.emailAddress
                  : _isUrlLabel(widget.label)
                  ? TextInputType.url
                  : TextInputType.text,
              decoration: InputDecoration(
                alignLabelWithHint: multiLine,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFDCE5F1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _indigo500, width: 2),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFD),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 17,
                ),
              ),
              style: GoogleFonts.poppins(
                fontSize: 15.5,
                height: 1.45,
                color: _slate800,
                letterSpacing: 0,
              ),
              onChanged: (next) => widget.onChanged(
                _isNumericLabel(widget.label)
                    ? next.replaceAll(RegExp(r'[^\d.]'), '')
                    : next,
              ),
            ),
        ],
      ),
    );
  }
}

class _SsrListItemEditor extends StatelessWidget {
  const _SsrListItemEditor({
    required this.label,
    required this.itemTitle,
    required this.index,
    required this.value,
    required this.onChanged,
    required this.onRemove,
  });

  final String label;
  final String itemTitle;
  final int index;
  final dynamic value;
  final _SsrDraftChanged<dynamic> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowTitle = value is Map
        ? _compactValuePreview(value)
        : _compactValuePreview(value).replaceAll('\n', ' ');
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _LazyExpansionCard(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: _indigo50, shape: BoxShape.circle),
          child: Text(
            '${index + 1}',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: _indigo600,
            ),
          ),
        ),
        title: itemTitle,
        subtitle: rowTitle == 'Blank' || rowTitle == 'No content yet'
            ? label
            : rowTitle,
        trailingLeading: onRemove == null
            ? const []
            : [
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: AppColors.error,
                  tooltip: 'Remove Entry',
                ),
              ],
        childrenBuilder: () => [
          const SizedBox(height: 8),
          if (value is Map)
            for (final entry in Map<String, dynamic>.from(value as Map).entries)
              _SsrValueEditor(
                label: _titleForKey(entry.key),
                value: entry.value,
                onChanged: (nextValue, {rebuild = false}) {
                  final next = _deepCopyMap(
                    Map<String, dynamic>.from(value as Map),
                  );
                  next[entry.key] = nextValue;
                  onChanged(next, rebuild: rebuild);
                },
              )
          else
            _SsrValueEditor(
              label: itemTitle,
              value: value,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _LazyExpansionCard extends StatefulWidget {
  const _LazyExpansionCard({
    required this.title,
    required this.subtitle,
    required this.childrenBuilder,
    this.leading,
    this.initiallyExpanded = false,
    this.trailingLeading = const [],
    this.tilePadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.childrenPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final bool initiallyExpanded;
  final List<Widget> trailingLeading;
  final EdgeInsetsGeometry tilePadding;
  final EdgeInsetsGeometry childrenPadding;
  final List<Widget> Function() childrenBuilder;

  @override
  State<_LazyExpansionCard> createState() => _LazyExpansionCardState();
}

class _LazyExpansionCardState extends State<_LazyExpansionCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        maintainState: false,
        onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
        tilePadding: widget.tilePadding,
        childrenPadding: widget.childrenPadding,
        leading: widget.leading,
        title: Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 15.5,
            height: 1.25,
            color: _slate900,
            letterSpacing: 0,
          ),
        ),
        subtitle: widget.subtitle.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  widget.subtitle,
                  maxLines: widget.subtitle.contains('\n') ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: _slate500,
                    letterSpacing: 0,
                  ),
                ),
              ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        iconColor: _slate400,
        collapsedIconColor: _slate400,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...widget.trailingLeading,
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _expanded ? _indigo50 : const Color(0xFFF8FAFC),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _expanded ? _indigo100 : Colors.transparent,
                ),
              ),
              child: Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _expanded ? _indigo600 : _slate400,
                size: 23,
              ),
            ),
          ],
        ),
        children: _expanded ? widget.childrenBuilder() : const <Widget>[],
      ),
    );
  }
}

IconData _iconForSsrGroup(String label) {
  switch (label) {
    case 'Basic Information':
      return Icons.space_dashboard_outlined;
    case 'Contacts':
      return Icons.people_outline_rounded;
    case 'Institution':
      return Icons.business_outlined;
    case 'Establishment':
      return Icons.calendar_month_outlined;
    case 'Recognition':
      return Icons.workspace_premium_outlined;
    case 'Campuses':
      return Icons.location_on_outlined;
    case 'Academic Information':
      return Icons.local_library_outlined;
    case 'Staff':
    case 'Qualification Details':
      return Icons.school_outlined;
    case 'Integrated Programmes':
      return Icons.menu_book_outlined;
    case 'Hrdc':
      return Icons.business_center_outlined;
    case 'Department Reports':
      return Icons.description_outlined;
    case 'Infrastructure Summary':
      return Icons.apartment_outlined;
    default:
      return Icons.dashboard_customize_rounded;
  }
}

class _SsrDatePickerField extends StatelessWidget {
  const _SsrDatePickerField({required this.value, required this.onChanged});

  final String value;
  final _SsrDraftChanged<dynamic> onChanged;

  Future<void> _pickDate(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final selectedDate = _parseSsrDate(value);
    final initialDate = selectedDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1800),
      lastDate: DateTime(now.year + 20, 12, 31),
      helpText: 'Select date',
      fieldLabelText: 'Date',
      fieldHintText: 'YYYY-MM-DD',
    );

    if (picked != null) {
      onChanged(_formatSsrDate(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = value.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _pickDate(context),
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: 'Select date',
          prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
          suffixIcon: text.isEmpty
              ? const Icon(Icons.expand_more_rounded)
              : IconButton(
                  tooltip: 'Clear date',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => onChanged(''),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFDCE5F1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _indigo500, width: 2),
          ),
          filled: true,
          fillColor: const Color(0xFFF8FAFD),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
        ),
        child: Text(
          text.isEmpty ? 'YYYY-MM-DD' : text,
          style: GoogleFonts.poppins(
            fontSize: 15.5,
            height: 1.45,
            color: text.isEmpty ? _slate400 : _slate800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _SsrYearLabelsEditor extends StatelessWidget {
  const _SsrYearLabelsEditor({required this.values, required this.onChanged});

  final List<String> values;
  final _SsrDraftChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, color: _indigo600),
              const SizedBox(width: 10),
              Text(
                'Year Labels',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _slate800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < values.length; i++)
                  Container(
                    width: 108,
                    margin: EdgeInsets.only(
                      right: i == values.length - 1 ? 0 : 10,
                    ),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _slate50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _slate200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YEAR ${i + 1}',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _slate400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: values[i],
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _slate800,
                          ),
                          onChanged: (next) {
                            final updated = List<dynamic>.from(values);
                            updated[i] = next;
                            onChanged(updated);
                          },
                        ),
                      ],
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

class _SsrMetricsEditor extends StatelessWidget {
  const _SsrMetricsEditor({
    required this.metrics,
    required this.yearLabels,
    required this.onChanged,
  });

  final Map<String, dynamic> metrics;
  final List<String> yearLabels;
  final _SsrDraftChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
          child: Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: _indigo600, size: 20),
              const SizedBox(width: 8),
              Text(
                '5-Year Metrics Data',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _slate800,
                ),
              ),
            ],
          ),
        ),
        for (final metric in _extendedProfileMetrics)
          _MetricInputCard(
            metric: metric,
            values: metrics[metric.key] is List
                ? List<dynamic>.from(metrics[metric.key] as List)
                : const ['', '', '', '', ''],
            yearLabels: yearLabels,
            onChanged: (nextValues) {
              final updated = _deepCopyMap(metrics);
              updated[metric.key] = nextValues;
              onChanged(updated);
            },
          ),
      ],
    );
  }
}

class _MetricInputCard extends StatelessWidget {
  const _MetricInputCard({
    required this.metric,
    required this.values,
    required this.yearLabels,
    required this.onChanged,
  });

  final _Metric metric;
  final List<dynamic> values;
  final List<String> yearLabels;
  final ValueChanged<List<dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFBFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: _slate100)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _indigo100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    metric.code,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: _deepBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    metric.label,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: _slate800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                for (var i = 0; i < 5; i++)
                  SizedBox(
                    width: 92,
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 4 ? 0 : 10),
                      child: Column(
                        children: [
                          Text(
                            i < yearLabels.length
                                ? yearLabels[i]
                                : 'Year ${i + 1}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _slate500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: i < values.length
                                ? values[i].toString()
                                : '',
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: GoogleFonts.poppins(color: _slate400),
                              filled: true,
                              fillColor: _slate50,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: _slate200),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: _indigo500,
                                  width: 2,
                                ),
                              ),
                            ),
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _slate800,
                            ),
                            onChanged: (next) {
                              final updated = List<dynamic>.filled(5, '');
                              for (var j = 0; j < 5; j++) {
                                updated[j] = j < values.length ? values[j] : '';
                              }
                              updated[i] = next.replaceAll(
                                RegExp(r'[^\d.]'),
                                '',
                              );
                              onChanged(updated);
                            },
                          ),
                        ],
                      ),
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

class _QifGuidanceEditor extends StatelessWidget {
  const _QifGuidanceEditor();

  static const _notes = [
    (
      title: 'Connected Criteria',
      text:
          'QIF is connected to the seven IQAC criteria below, where the final evidence upload and document flow continues.',
    ),
    (
      title: 'Key Indicators and Metrics',
      text:
          'The framework contains Key Indicators and metric-wise requirements under each criterion.',
    ),
    (
      title: 'Qualitative and Quantitative Metrics',
      text:
          'Qualitative metrics require descriptive information, while quantitative metrics use specified data and calculations.',
    ),
    (
      title: 'Data, Formulas, Files and Weightage',
      text:
          'Each metric may include data requirements, formulas where applicable, file descriptions for evidence upload, and metric-wise weightage.',
    ),
    (
      title: 'Online Format Note',
      text:
          'The actual online format may vary slightly for IT design compatibility, so this section is kept as read-only guidance for now.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _indigo50,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _indigo100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.fact_check_outlined,
                color: _indigo600,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QIF Guidance',
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _deepBlue,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "The SSR is filled in NAAC's online format. QIF presents the metrics under each Key Indicator for all seven criteria and helps the institution prepare data before entering the online SSR.",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: _deepBlue.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final bullet in const [
                      'Data required for each metric',
                      'Formula guidance wherever required',
                      'File descriptions for upload evidence',
                      'Qualitative and quantitative metric preparation notes',
                      'Metric-wise weightage and IT-format compatibility changes',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 7),
                              child: Icon(
                                Icons.circle,
                                size: 5,
                                color: _indigo600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                bullet,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: _deepBlue.withValues(alpha: 0.72),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        for (final note in _notes)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _slate200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _slate900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  note.text,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: _slate500,
                  ),
                ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _emerald50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: _emerald600,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Read-only guidance',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF065F46),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SsrHistoryPanel extends StatelessWidget {
  const _SsrHistoryPanel({
    required this.loading,
    required this.history,
    required this.restoringId,
    required this.detailLoadingId,
    required this.activeHistoryId,
    required this.onToggleDetails,
    required this.onRestore,
  });

  final bool loading;
  final List<_SsrHistoryEntry> history;
  final String restoringId;
  final String detailLoadingId;
  final String activeHistoryId;
  final ValueChanged<_SsrHistoryEntry> onToggleDetails;
  final ValueChanged<_SsrHistoryEntry> onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            'Edit History (Last 5 Days)',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
        ),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (history.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(20),
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
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'No edits in the last 5 days.',
                    style: GoogleFonts.poppins(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Stack(
            children: [
              Positioned(
                left: 23,
                top: 24,
                bottom: 24,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.5),
                        AppColors.primary.withValues(alpha: 0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  for (var i = 0; i < history.length; i++)
                    Builder(
                      builder: (context) {
                        final item = history[i];
                        final isActive = activeHistoryId == item.id;
                        final isDetailsLoading = detailLoadingId == item.id;
                        final isLast = i == history.length - 1;

                        return Container(
                          margin: EdgeInsets.only(bottom: isLast ? 0 : 24),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.15,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    child: Text(
                                      item.editorName.isNotEmpty
                                          ? item.editorName[0].toUpperCase()
                                          : '?',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isActive
                                          ? AppColors.primary.withValues(
                                              alpha: 0.3,
                                            )
                                          : theme.colorScheme.outline
                                                .withValues(alpha: 0.1),
                                      width: isActive ? 1.5 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.03,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.editorName,
                                                  style: GoogleFonts.poppins(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15,
                                                    color: isDark
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF0F172A,
                                                          ),
                                                  ),
                                                ),
                                                if (item.editorEmail.isNotEmpty)
                                                  Text(
                                                    item.editorEmail,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 12,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.5),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              item.editedAt == null
                                                  ? 'Unknown Date'
                                                  : _formatRelativeTime(
                                                      item.editedAt!,
                                                    ),
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item.changeSummary.isNotEmpty) ...[
                                        const SizedBox(height: 14),
                                        Text(
                                          item.changeSummary,
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            height: 1.4,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                      if (item.changedFields.isNotEmpty) ...[
                                        const SizedBox(height: 16),
                                        Text(
                                          'Modified Fields:',
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: item.changedFields
                                              .take(5)
                                              .map(
                                                (field) => Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFEFF6FF,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFDBEAFE,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    _titleForKey(field),
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: const Color(
                                                        0xFF1E40AF,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      const Divider(height: 1),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextButton.icon(
                                              onPressed: isDetailsLoading
                                                  ? null
                                                  : () => onToggleDetails(item),
                                              icon: Icon(
                                                isActive
                                                    ? Icons.unfold_less_rounded
                                                    : Icons.unfold_more_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isDetailsLoading
                                                    ? 'Loading...'
                                                    : isActive
                                                    ? 'Hide Diff'
                                                    : 'View Diff',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                foregroundColor: isActive
                                                    ? AppColors.primary
                                                    : theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: FilledButton.tonalIcon(
                                              onPressed: restoringId == item.id
                                                  ? null
                                                  : () => onRestore(item),
                                              icon: const Icon(
                                                Icons.restore_rounded,
                                                size: 18,
                                              ),
                                              label: Text(
                                                restoringId == item.id
                                                    ? 'Restoring...'
                                                    : 'Restore',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isActive) ...[
                                        const SizedBox(height: 16),
                                        if (isDetailsLoading)
                                          const LinearProgressIndicator(
                                            minHeight: 2,
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(2),
                                            ),
                                          )
                                        else if (item.fieldDiffs.isEmpty)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: theme
                                                  .colorScheme
                                                  .surfaceContainerHighest
                                                  .withValues(alpha: 0.3),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              'No individual field changes detected.',
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          )
                                        else
                                          Column(
                                            children: [
                                              for (final diffEntry
                                                  in item.fieldDiffs.entries)
                                                _HistoryDiffBlock(
                                                  field: diffEntry.key,
                                                  diff: diffEntry.value is Map
                                                      ? Map<
                                                          String,
                                                          dynamic
                                                        >.from(
                                                          diffEntry.value
                                                              as Map,
                                                        )
                                                      : const {},
                                                ),
                                            ],
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  String _formatRelativeTime(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);

    if (difference.inDays == 0) {
      if (difference.inHours > 0) return '${difference.inHours}h ago';
      if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
      return 'Just now';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _HistoryDiffBlock extends StatelessWidget {
  const _HistoryDiffBlock({required this.field, required this.diff});

  final String field;
  final Map<String, dynamic> diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.code_rounded,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _titleForKey(field),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.robotoMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _DiffLines(
                    label: 'Previous',
                    color: const Color(0xFFEF4444),
                    icon: Icons.remove,
                    lines: _valueToLines(diff['previous']),
                  ),
                  const SizedBox(height: 8),
                  _DiffLines(
                    label: 'New',
                    color: const Color(0xFF10B981),
                    icon: Icons.add,
                    lines: _valueToLines(diff['new']),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffLines extends StatelessWidget {
  const _DiffLines({
    required this.label,
    required this.color,
    required this.icon,
    required this.lines,
  });

  final String label;
  final Color color;
  final IconData icon;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? color.withValues(alpha: 0.15)
        : color.withValues(alpha: 0.05);
    final borderColor = isDark
        ? color.withValues(alpha: 0.3)
        : color.withValues(alpha: 0.15);
    final headerBgColor = isDark
        ? color.withValues(alpha: 0.25)
        : color.withValues(alpha: 0.1);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: headerBgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  padding: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: borderColor)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      lines.take(12).length,
                      (i) => Text(
                        '${i + 1}',
                        style: GoogleFonts.robotoMono(
                          fontSize: 12,
                          height: 1.5,
                          color: color.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in lines.take(12))
                          Text(
                            line.isEmpty ? ' ' : line,
                            style: GoogleFonts.robotoMono(
                              fontSize: 12,
                              height: 1.5,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF334155),
                            ),
                          ),
                        if (lines.length > 12)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${lines.length - 12} more lines',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ),
                      ],
                    ),
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

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.text,
    this.bgColor = AppColors.surface,
    this.iconColor = AppColors.textSecondary,
    this.textColor = AppColors.textSecondary,
    this.borderColor = AppColors.border,
  });

  final IconData icon;
  final String text;
  final Color bgColor;
  final Color iconColor;
  final Color textColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
