import 'dart:io';

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

class IQACScreen extends StatefulWidget {
  const IQACScreen({super.key});

  @override
  State<IQACScreen> createState() => _IQACScreenState();
}

class _IQACScreenState extends State<IQACScreen> {
  final _api = ApiService();
  static const Color _deepBlue = Color(0xFF1B254B);

  List<_IqacCriterion> _criteria = [];
  Map<String, dynamic> _counts = {};
  List<IqacTemplate> _templates = [];
  bool _loading = true;
  bool _templatesLoading = true;
  String? _error;
  String? _templatesError;

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
    } else {
      _loading = false;
      _templatesLoading = false;
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
        _error = e.toString();
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
        _templatesError = e.toString();
        _templatesLoading = false;
      });
    }
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
    return role == 'iqac' ||
        role == 'admin' ||
        role == 'registrar' ||
        role == 'vice_chancellor' ||
        role == 'deputy_registrar' ||
        role == 'finance_team';
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

    final canDelete = _canDeleteIqacFiles(context);

    Future<void> loadFiles(StateSetter setModalState) async {
      if (selectedSubFolder == null || selectedItem == null) return;
      setModalState(() => filesLoading = true);
      try {
        final resp = await _api.get<dynamic>(
          '/iqac/folders/${criterion.id}/${Uri.encodeComponent(selectedSubFolder!.id)}/${Uri.encodeComponent(selectedItem!.id)}/files',
        );
        final raw = resp is List ? resp : <dynamic>[];
        setModalState(() {
          files = raw
              .whereType<Map>()
              .map((e) => _IqacFileDoc.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          filesLoading = false;
        });
      } catch (_) {
        setModalState(() {
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(openResult.message)));
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
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }

    Future<void> uploadFile(StateSetter setModalState) async {
      if (selectedSubFolder == null ||
          selectedItem == null ||
          pickedFile?.path == null) {
        return;
      }
      setModalState(() {
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

        setModalState(() {
          uploading = false;
          pickedFile = null;
          descriptionCtrl.clear();
        });

        await loadFiles(setModalState);
        await _loadData();
      } catch (e) {
        setModalState(() {
          uploading = false;
          uploadError = e.toString();
        });
      }
    }

    Future<void> deleteFile(String fileId, StateSetter setModalState) async {
      try {
        await _api.delete('/iqac/files/$fileId');
        setModalState(() {
          files = files.where((f) => f.id != fileId).toList();
        });
        await _loadData();
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final theme = Theme.of(ctx);
          final isDark = theme.brightness == Brightness.dark;
          final borderColor = isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.5)
              : AppColors.border;

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

          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.88,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(bottom: BorderSide(color: borderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (step != _IqacPanelStep.subFolders)
                          IconButton(
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
                          ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
                          setModalState(() => pickedFile = picked.files.first);
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
            ),
          );
        },
      ),
    );

    descriptionCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canAccess) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Access denied. You do not have permission to view IQAC data.',
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.5)
        : AppColors.border;
    final cardColor = theme.colorScheme.surface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('IQAC Data Collection'),
        actions: [
          IconButton(
            onPressed: _loadData,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
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
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.error),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IQAC Data Collection',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Manage IQAC criteria folders and sub-folders (IQAC Committee Only)',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      _Badge(
                        icon: Icons.lock_rounded,
                        text: 'IQAC Committee Only',
                        bgColor: Color(0xFFFFF8E1),
                        iconColor: Color(0xFFF57F17),
                        textColor: Color(0xFF8A5A00),
                        borderColor: Color(0xFFFFECB3),
                      ),
                      _Badge(
                        icon: Icons.folder_open_rounded,
                        text: 'NAAC 7 Criteria',
                        bgColor: Color(0xFFE8EAF6),
                        iconColor: Color(0xFF3949AB),
                        textColor: Color(0xFF3949AB),
                        borderColor: Color(0xFFC5CAE9),
                      ),
                    ],
                   ),
                   const SizedBox(height: 16),
                   if (!_templatesLoading) ...[
                     if (_templatesError != null) ...[
                       Container(
                         width: double.infinity,
                         padding: const EdgeInsets.all(16),
                         decoration: BoxDecoration(
                           color: Theme.of(context).colorScheme.errorContainer,
                           borderRadius: BorderRadius.circular(12),
                         ),
                         child: Text(
                           'Error loading templates: $_templatesError',
                           style: GoogleFonts.inter(color: Theme.of(context).colorScheme.error),
                         ),
                       ),
                     ] else if (_templates.isNotEmpty) ...[
                       _buildIqacTemplateDownloadCard(),
                       const SizedBox(height: 16),
                     ] else ...[
                       Container(
                         width: double.infinity,
                         padding: const EdgeInsets.all(16),
                         decoration: BoxDecoration(
                           color: Theme.of(context).colorScheme.secondaryContainer,
                           borderRadius: BorderRadius.circular(12),
                         ),
                         child: const Text(
                           'No IQAC templates available',
                           textAlign: TextAlign.center,
                           style: TextStyle(fontSize: 14, color: Colors.grey),
                         ),
                       ),
                       const SizedBox(height: 16),
                     ]
                   ] else ...[
                     const SizedBox(height: 8),
                     Center(child: CircularProgressIndicator()),
                     const SizedBox(height: 8),
                   ],
                   Text(
                     'IQAC Criteria Structure',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      int crossAxisCount = 1;
                      if (width >= 1100) {
                        crossAxisCount = 4;
                      } else if (width >= 800) {
                        crossAxisCount = 3;
                      } else if (width >= 520) {
                        crossAxisCount = 2;
                      }

                      return GridView.builder(
                        itemCount: _criteria.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisExtent: crossAxisCount == 1 ? 300 : 280,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemBuilder: (_, i) {
                          final c = _criteria[i];
                          final subPreviewCount = crossAxisCount == 1 ? 2 : 3;
                          final visibleSubs = c.subFolders
                              .take(subPreviewCount)
                              .toList();
                          final more = c.subFolders.length - visibleSubs.length;

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: borderColor),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x11000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.25,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.folder_rounded,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Criterion ${c.id}: ${c.title}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                ...visibleSubs.map((sub) {
                                  final total = _subFolderCount(c.id, sub.id);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.description_outlined,
                                            size: 15,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${sub.id} ${sub.title}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cardColor,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              border: Border.all(
                                                color: borderColor,
                                              ),
                                            ),
                                            child: Text(
                                              '$total',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
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
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '... +$more more sub-folders',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                const Spacer(),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _openCriterionPanel(
                                          context,
                                          c,
                                          readOnly: true,
                                        ),
                                        icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 16,
                                        ),
                                        label: const Text('View'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _openCriterionPanel(
                                          context,
                                          c,
                                          readOnly: false,
                                        ),
                                        icon: const Icon(
                                          Icons.folder_open_rounded,
                                          size: 16,
                                        ),
                                        label: const Text('Open'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _deepBlue,
                                          foregroundColor: Colors.white,
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
        ? theme.colorScheme.outline.withValues(alpha: 0.5)
        : AppColors.border;
    final panelColor = theme.colorScheme.surface;
    final panelAlt = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: isDark ? 0.4 : 0.6,
    );

    if (step == _IqacPanelStep.subFolders) {
      return LayoutBuilder(
        builder: (_, constraints) {
          final columns = constraints.maxWidth < 560 ? 1 : 2;
          return GridView.builder(
            itemCount: criterion.subFolders.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 94,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (_, i) {
              final sub = criterion.subFolders[i];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onPickSubFolder(sub),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: panelColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_rounded,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${sub.id} - ${sub.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
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
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: 110,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (_, i) {
              final item = items[i];
              final n = itemCount(selectedSubFolder!.id, item.id);
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onPickItem(item),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: panelColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.id} ${item.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$n file${n == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              'You are viewing in read-only mode. Use Open on the card to upload files.${canDelete ? ' You can delete files from there.' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelColor,
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
                                size: 16,
                              ),
                              label: Text(
                                pickedFile?.name ?? 'Choose File',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: descriptionCtrl,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Description (optional)',
                              border: OutlineInputBorder(),
                            ),
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
                              size: 16,
                            ),
                            label: Text(
                              pickedFile?.name ?? 'Choose File',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: descriptionCtrl,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Description (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Max 10 MB. PDF, DOC, DOCX only.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton(
                      onPressed: (uploading || pickedFile == null)
                          ? null
                          : onUpload,
                      style: FilledButton.styleFrom(
                        backgroundColor: _deepBlue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(uploading ? 'Uploading...' : 'Upload'),
                    ),
                  ],
                ),
                if (uploadError != null && uploadError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      uploadError,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: filesLoading
              ? const Center(child: CircularProgressIndicator())
              : files.isEmpty
              ? Center(
                  child: Text(
                    'No documents uploaded yet.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final f = files[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: panelColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.fileName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatBytes(f.size)} - ${_formatDate(f.uploadedAt)}${f.description.isNotEmpty ? ' - ${f.description}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => onView(f),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4F46E5),
                                  side: const BorderSide(
                                    color: Color(0xFF4F46E5),
                                    width: 1.8,
                                  ),
                                  shape: const StadiumBorder(),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: const Text('View'),
                              ),
                              OutlinedButton(
                                onPressed: () => onDownload(f),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4F46E5),
                                  side: const BorderSide(
                                    color: Color(0xFF4F46E5),
                                    width: 1.8,
                                  ),
                                  shape: const StadiumBorder(),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: const Text('Download'),
                              ),
                              if (!readOnly && canDelete)
                                OutlinedButton(
                                  onPressed: () => onDelete(f),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(
                                      color: AppColors.error,
                                      width: 1.8,
                                    ),
                                    shape: const StadiumBorder(),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  child: const Text('Delete'),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'IQAC Data Templates',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_templates.length} template documents available',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _templates.map((template) {
              return _buildIqacTemplateCard(template);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildIqacTemplateCard(IqacTemplate template) {
    return InkWell(
      onTap: () => _downloadIqacTemplate(template),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${template.type} · ${_formatBytes(template.size)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.download_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

   Future<void> _downloadIqacTemplate(IqacTemplate template) async {
     try {
       final bytes = await _api.getBytes(template.downloadUrl);
       final tempDir = await getTemporaryDirectory();
       final safeName = '${DateTime.now().millisecondsSinceEpoch}_${template.name}';
       final file = File('${tempDir.path}/$safeName');
       await file.writeAsBytes(bytes, flush: true);

       if (!mounted) return;

       final result = await OpenFile.open(file.path);
       if (result.type != ResultType.done) {
         if (!mounted) return;
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Error opening file: ${result.message}'),
             backgroundColor: Theme.of(context).colorScheme.error,
           ),
         );
         return;
       }

       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Template downloaded successfully'),
           backgroundColor: Theme.of(context).colorScheme.primary,
         ),
       );
     } catch (e) {
       if (!mounted) return;
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Error downloading template: ${e.toString()}'),
           backgroundColor: Theme.of(context).colorScheme.error,
         ),
       );
     }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

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
  final String type;
  final String downloadUrl;
  final int size;
  
  const IqacTemplate({
    required this.id,
    required this.name,
    required this.type,
    required this.downloadUrl,
    required this.size,
  });
  
  factory IqacTemplate.fromJson(Map<String, dynamic> json) {
    return IqacTemplate(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      downloadUrl: (json['download_url'] ?? json['downloadUrl'] ?? '').toString(),
      size: json['size'] is int ? json['size'] as int : int.tryParse('${json['size']}') ?? 0,
    );
  }
}
