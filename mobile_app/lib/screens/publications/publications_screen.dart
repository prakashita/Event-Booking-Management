import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../home_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class PublicationsScreen extends StatefulWidget {
  const PublicationsScreen({super.key});

  @override
  State<PublicationsScreen> createState() => _PublicationsScreenState();
}

class _PublicationsScreenState extends State<PublicationsScreen> {
  final _api = ApiService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _pubs = [];
  bool _isLoading = true;
  String? _error;
  String _typeFilter = '';
  String _sort = 'date_desc';
  String _searchTerm = '';

  static const List<String> _publicationTypes = [
    'webpage',
    'journal_article',
    'book',
    'report',
    'video',
    'online_newspaper',
  ];

  static const Map<String, String> _typeLabels = {
    'webpage': 'Webpage',
    'journal_article': 'Journal Article',
    'book': 'Book',
    'report': 'Report',
    'video': 'Video',
    'online_newspaper': 'Online Newspaper',
    'newspaper': 'Online Newspaper',
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchTerm = _searchController.text.trim().toLowerCase());
    });
    _loadPublications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPublications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sortParts = _sort.split('_');
      final sortBy = sortParts.isNotEmpty ? sortParts.first : 'date';
      final order = sortParts.length > 1 ? sortParts.last : 'desc';
      final data = await _api.get<dynamic>(
        '/publications',
        params: {'sort': sortBy, 'order': order},
      );

      final List<dynamic> rawItems = data is List
          ? data
          : (data['items'] as List? ?? const []);
      setState(() {
        _pubs = rawItems
            .whereType<Map>()
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredPubs = _filteredPublications();
    final media = MediaQuery.of(context);
    final responsiveScale = _responsiveTextScale(media.size.width);

    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(responsiveScale)),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Publications')),
        body: RefreshIndicator(
          onRefresh: _loadPublications,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              _buildHeader(filteredPubs.length),
              const SizedBox(height: 12),
              _buildControls(),
              const SizedBox(height: 14),
              if (_isLoading)
                _buildLoading()
              else if (_error != null)
                ErrorState(message: _error!, onRetry: _loadPublications)
              else if (_pubs.isEmpty)
                EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'No publications yet',
                  message: 'Tap + New Publication to add your first one.',
                  actionLabel: 'New Publication',
                  onAction: () => _startPublicationCreateFlow(context),
                )
              else if (filteredPubs.isEmpty)
                const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching publications',
                  message: 'Try changing search, type, or sorting filters.',
                )
              else
                ...filteredPubs.map(
                  (pub) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PublicationCard(
                      pub: pub,
                      typeLabel: _labelForType(
                        (pub['pub_type'] ?? pub['type'] ?? '').toString(),
                      ),
                      onOpenLink: () => _openPublicationLink(pub),
                    ),
                  ),
                ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _startPublicationCreateFlow(context),
          icon: const Icon(Icons.add),
          label: const Text(
            'New Publication',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  double _responsiveTextScale(double width) {
    if (width <= 320) return 0.84;
    if (width <= 360) return 0.9;
    if (width <= 390) return 0.96;
    return 1.0;
  }

  Widget _buildHeader(int count) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Publications',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fieldFill = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
        : theme.colorScheme.surface;
    final fieldBorder = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.5)
        : AppColors.border;

    final typeDropdown = DropdownButtonFormField<String>(
      value: _typeFilter,
      isExpanded: true,
      decoration: _filterInputDecoration('All types', fieldFill, fieldBorder),
      items: [
        const DropdownMenuItem(value: '', child: Text('All types')),
        ..._publicationTypes.map(
          (type) => DropdownMenuItem(
            value: type,
            child: Text(_labelForType(type), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: (value) {
        setState(() => _typeFilter = value ?? '');
      },
    );

    final sortDropdown = DropdownButtonFormField<String>(
      value: _sort,
      isExpanded: true,
      decoration: _filterInputDecoration('Sort by', fieldFill, fieldBorder),
      items: const [
        DropdownMenuItem(value: 'date_desc', child: Text('Newest first')),
        DropdownMenuItem(value: 'date_asc', child: Text('Oldest first')),
        DropdownMenuItem(value: 'title_asc', child: Text('Title (A-Z)')),
        DropdownMenuItem(value: 'title_desc', child: Text('Title (Z-A)')),
      ],
      onChanged: (value) {
        final selected = value ?? 'date_desc';
        if (selected == _sort) return;
        setState(() => _sort = selected);
        _loadPublications();
      },
    );

    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search publications...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchTerm.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: fieldFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: fieldBorder),
            ),
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 430;
            if (stacked) {
              return Column(
                children: [
                  typeDropdown,
                  const SizedBox(height: 10),
                  sortDropdown,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: typeDropdown),
                const SizedBox(width: 10),
                Expanded(child: sortDropdown),
              ],
            );
          },
        ),
      ],
    );
  }

  InputDecoration _filterInputDecoration(
    String hintText,
    Color fillColor,
    Color borderColor,
  ) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
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

  Widget _buildLoading() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerBox(width: double.infinity, height: 130, radius: 16),
      ),
    );
  }

  List<Map<String, dynamic>> _filteredPublications() {
    final searched = _searchTerm.isEmpty
        ? _pubs
        : _pubs.where((pub) {
            final values = [
              pub['title'],
              pub['name'],
              pub['file_name'],
              pub['pub_type'],
              pub['author'],
              pub['url'],
              pub['others'],
              pub['article_title'],
              pub['book_title'],
              pub['report_title'],
              pub['video_title'],
            ];
            return values
                .whereType<String>()
                .map((v) => v.toLowerCase())
                .any((v) => v.contains(_searchTerm));
          }).toList();

    if (_typeFilter.isEmpty) {
      return searched;
    }
    return searched
        .where(
          (pub) =>
              (pub['pub_type'] ?? pub['type'] ?? '').toString() == _typeFilter,
        )
        .toList();
  }

  String _labelForType(String type) {
    return _typeLabels[type] ?? type.replaceAll('_', ' ').trim();
  }

  Future<void> _openPublicationLink(Map<String, dynamic> pub) async {
    final link = (pub['web_view_link'] ?? pub['url'] ?? '').toString().trim();
    if (link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _startPublicationCreateFlow(BuildContext context) async {
    final chatFabVisibility = ChatFabVisibilityScope.maybeOf(context);
    chatFabVisibility?.value = false;

    try {
      final selectedType = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add New Publication',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select the type of publication you want to add',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _publicationTypes.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 88,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final type = _publicationTypes[index];
                    return _PublicationTypeTile(
                      label: _labelForType(type),
                      icon: _typeIconFor(type),
                      color: _typeColorFor(type),
                      onTap: () => Navigator.of(ctx).pop(type),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      if (!context.mounted || selectedType == null) return;
      await _showPublicationFormDialog(context, selectedType);
    } finally {
      chatFabVisibility?.value = true;
    }
  }

  Future<void> _showPublicationFormDialog(
    BuildContext context,
    String selectedType,
  ) async {
    final draft = _PublicationDraft(pubType: selectedType);
    bool submitting = false;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickPdf() async {
              final picked = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: const ['pdf'],
                withData: false,
              );
              if (picked == null || picked.files.isEmpty) return;
              setModalState(() => draft.file = picked.files.first);
            }

            Future<void> submit() async {
              final validationError = _validatePublicationDraft(draft);
              if (validationError != null) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(validationError),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              setModalState(() => submitting = true);
              try {
                final formData = await _buildPublicationFormData(draft);
                await _api.postMultipart('/publications', formData);
                if (!context.mounted || !ctx.mounted) return;
                Navigator.of(ctx).pop();
                await _loadPublications();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Publication submitted.')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(e.toString()),
                    backgroundColor: AppColors.error,
                  ),
                );
              } finally {
                if (ctx.mounted) {
                  setModalState(() => submitting = false);
                }
              }
            }

            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  MediaQuery.of(ctx).viewInsets.bottom + 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _typeColorFor(
                              draft.pubType,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _typeIconFor(draft.pubType),
                            color: _typeColorFor(draft.pubType),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_labelForType(draft.pubType)} Citation',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(ctx).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: submitting
                              ? null
                              : () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildTextField(
                      label: 'Record Label *',
                      hint: 'Short identifier, e.g. Smith2024',
                      initialValue: draft.name,
                      enabled: !submitting,
                      onChanged: (v) => draft.name = v,
                    ),
                    if (draft.pubType == 'webpage')
                      ..._buildWebpageFields(draft, !submitting),
                    if (draft.pubType == 'journal_article')
                      ..._buildJournalFields(draft, !submitting),
                    if (draft.pubType == 'book')
                      ..._buildBookFields(draft, !submitting),
                    if (draft.pubType == 'report')
                      ..._buildReportFields(draft, !submitting),
                    if (draft.pubType == 'video')
                      ..._buildVideoFields(draft, !submitting),
                    if (draft.pubType == 'online_newspaper')
                      ..._buildNewspaperFields(draft, !submitting),
                    _buildTextArea(
                      label: 'Additional Notes',
                      hint: 'Any extra details...',
                      initialValue: draft.others,
                      enabled: !submitting,
                      onChanged: (v) => draft.others = v,
                    ),
                    if (_supportsPdfUpload(draft.pubType)) ...[
                      const SizedBox(height: 12),
                      Text(
                        'PDF File (optional, max 10 MB)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: submitting ? null : pickPdf,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: Text(
                          draft.file?.name ?? 'Choose PDF file',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: submitting
                                    ? null
                                    : () => Navigator.of(ctx).pop(),
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text(
                                  'Back',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: submitting
                                    ? null
                                    : () => Navigator.of(ctx).pop(),
                                child: const Text(
                                  'Cancel',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: submitting ? null : submit,
                                child: Text(
                                  submitting ? 'Submitting...' : 'Submit',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    } finally {}
  }

  List<Widget> _buildWebpageFields(_PublicationDraft draft, bool enabled) {
    return [
      _buildTwoCol(
        _buildTextField(
          label: 'Author First Name *',
          hint: 'e.g. John',
          initialValue: draft.authorFirstName,
          enabled: enabled,
          onChanged: (v) => draft.authorFirstName = v,
        ),
        _buildTextField(
          label: 'Author Last Name *',
          hint: 'e.g. Smith',
          initialValue: draft.authorLastName,
          enabled: enabled,
          onChanged: (v) => draft.authorLastName = v,
        ),
      ),
      _buildTextField(
        label: 'Page Title *',
        hint: 'Title of the specific page',
        initialValue: draft.pageTitle,
        enabled: enabled,
        onChanged: (v) => draft.pageTitle = v,
      ),
      _buildTextField(
        label: 'Website Name *',
        hint: 'e.g. Wikipedia',
        initialValue: draft.websiteName,
        enabled: enabled,
        onChanged: (v) => draft.websiteName = v,
      ),
      _buildTextField(
        label: 'URL *',
        hint: 'https://...',
        initialValue: draft.url,
        enabled: enabled,
        keyboardType: TextInputType.url,
        onChanged: (v) => draft.url = v,
      ),
      _buildTextField(
        label: 'Publication Date',
        hint: 'e.g. 15 Jan 2024',
        initialValue: draft.publicationDate,
        enabled: enabled,
        onChanged: (v) => draft.publicationDate = v,
      ),
    ];
  }

  List<Widget> _buildJournalFields(_PublicationDraft draft, bool enabled) {
    return [
      _buildTwoCol(
        _buildTextField(
          label: 'Author First Name *',
          hint: 'e.g. John',
          initialValue: draft.authorFirstName,
          enabled: enabled,
          onChanged: (v) => draft.authorFirstName = v,
        ),
        _buildTextField(
          label: 'Author Last Name *',
          hint: 'e.g. Smith',
          initialValue: draft.authorLastName,
          enabled: enabled,
          onChanged: (v) => draft.authorLastName = v,
        ),
      ),
      _buildTextField(
        label: 'Article Title *',
        hint: 'Full title of the article',
        initialValue: draft.articleTitle,
        enabled: enabled,
        onChanged: (v) => draft.articleTitle = v,
      ),
      _buildTextField(
        label: 'Journal Name *',
        hint: 'e.g. Nature',
        initialValue: draft.journalName,
        enabled: enabled,
        onChanged: (v) => draft.journalName = v,
      ),
      _buildTextField(
        label: 'Year *',
        hint: 'e.g. 2024',
        initialValue: draft.year,
        enabled: enabled,
        onChanged: (v) => draft.year = v,
      ),
      _buildThreeCol(
        _buildTextField(
          label: 'Volume',
          hint: 'e.g. 12',
          initialValue: draft.volume,
          enabled: enabled,
          onChanged: (v) => draft.volume = v,
        ),
        _buildTextField(
          label: 'Issue',
          hint: 'e.g. 3',
          initialValue: draft.issue,
          enabled: enabled,
          onChanged: (v) => draft.issue = v,
        ),
        _buildTextField(
          label: 'Pages',
          hint: 'e.g. 45-60',
          initialValue: draft.pages,
          enabled: enabled,
          onChanged: (v) => draft.pages = v,
        ),
      ),
      _buildTextField(
        label: 'DOI',
        hint: 'e.g. 10.1000/xyz123',
        initialValue: draft.doi,
        enabled: enabled,
        onChanged: (v) => draft.doi = v,
      ),
    ];
  }

  List<Widget> _buildBookFields(_PublicationDraft draft, bool enabled) {
    return [
      _buildTwoCol(
        _buildTextField(
          label: 'Author First Name *',
          hint: 'e.g. John',
          initialValue: draft.authorFirstName,
          enabled: enabled,
          onChanged: (v) => draft.authorFirstName = v,
        ),
        _buildTextField(
          label: 'Author Last Name *',
          hint: 'e.g. Smith',
          initialValue: draft.authorLastName,
          enabled: enabled,
          onChanged: (v) => draft.authorLastName = v,
        ),
      ),
      _buildTextField(
        label: 'Book Title *',
        hint: 'Full title of the book',
        initialValue: draft.bookTitle,
        enabled: enabled,
        onChanged: (v) => draft.bookTitle = v,
      ),
      _buildTextField(
        label: 'Publisher *',
        hint: 'e.g. Oxford University Press',
        initialValue: draft.publisher,
        enabled: enabled,
        onChanged: (v) => draft.publisher = v,
      ),
      _buildTextField(
        label: 'Year *',
        hint: 'e.g. 2022',
        initialValue: draft.year,
        enabled: enabled,
        onChanged: (v) => draft.year = v,
      ),
      _buildTwoCol(
        _buildTextField(
          label: 'Edition',
          hint: 'e.g. 3rd',
          initialValue: draft.edition,
          enabled: enabled,
          onChanged: (v) => draft.edition = v,
        ),
        _buildTextField(
          label: 'Page Number',
          hint: 'e.g. 142',
          initialValue: draft.pageNumber,
          enabled: enabled,
          onChanged: (v) => draft.pageNumber = v,
        ),
      ),
    ];
  }

  List<Widget> _buildReportFields(_PublicationDraft draft, bool enabled) {
    return [
      _buildTextField(
        label: 'Organization *',
        hint: 'e.g. WHO, UNESCO',
        initialValue: draft.organization,
        enabled: enabled,
        onChanged: (v) => draft.organization = v,
      ),
      _buildTextField(
        label: 'Report Title *',
        hint: 'Full title of the report',
        initialValue: draft.reportTitle,
        enabled: enabled,
        onChanged: (v) => draft.reportTitle = v,
      ),
      _buildTextField(
        label: 'Publisher *',
        hint: 'e.g. World Health Organization',
        initialValue: draft.publisher,
        enabled: enabled,
        onChanged: (v) => draft.publisher = v,
      ),
      _buildTextField(
        label: 'Year *',
        hint: 'e.g. 2023',
        initialValue: draft.year,
        enabled: enabled,
        onChanged: (v) => draft.year = v,
      ),
    ];
  }

  List<Widget> _buildVideoFields(_PublicationDraft draft, bool enabled) {
    return [
      _buildTextField(
        label: 'Creator / Uploader *',
        hint: 'e.g. Khan Academy',
        initialValue: draft.creator,
        enabled: enabled,
        onChanged: (v) => draft.creator = v,
      ),
      _buildTextField(
        label: 'Video Title *',
        hint: 'Full title of the video',
        initialValue: draft.videoTitle,
        enabled: enabled,
        onChanged: (v) => draft.videoTitle = v,
      ),
      _buildTextField(
        label: 'Platform *',
        hint: 'e.g. YouTube, Vimeo',
        initialValue: draft.platform,
        enabled: enabled,
        onChanged: (v) => draft.platform = v,
      ),
      _buildTextField(
        label: 'Date *',
        hint: 'e.g. 5 March 2024',
        initialValue: draft.publicationDate,
        enabled: enabled,
        onChanged: (v) => draft.publicationDate = v,
      ),
      _buildTextField(
        label: 'URL *',
        hint: 'https://...',
        initialValue: draft.url,
        enabled: enabled,
        keyboardType: TextInputType.url,
        onChanged: (v) => draft.url = v,
      ),
    ];
  }

  List<Widget> _buildNewspaperFields(_PublicationDraft draft, bool enabled) {
    return [
      _buildTwoCol(
        _buildTextField(
          label: 'Author First Name *',
          hint: 'e.g. Jane',
          initialValue: draft.authorFirstName,
          enabled: enabled,
          onChanged: (v) => draft.authorFirstName = v,
        ),
        _buildTextField(
          label: 'Author Last Name *',
          hint: 'e.g. Doe',
          initialValue: draft.authorLastName,
          enabled: enabled,
          onChanged: (v) => draft.authorLastName = v,
        ),
      ),
      _buildTextField(
        label: 'Article Title *',
        hint: 'Full title of the article',
        initialValue: draft.articleTitle,
        enabled: enabled,
        onChanged: (v) => draft.articleTitle = v,
      ),
      _buildTextField(
        label: 'Newspaper Name *',
        hint: 'e.g. The Guardian',
        initialValue: draft.newspaperName,
        enabled: enabled,
        onChanged: (v) => draft.newspaperName = v,
      ),
      _buildTextField(
        label: 'Publication Date *',
        hint: 'e.g. 10 Feb 2024',
        initialValue: draft.publicationDate,
        enabled: enabled,
        onChanged: (v) => draft.publicationDate = v,
      ),
      _buildTextField(
        label: 'URL *',
        hint: 'https://...',
        initialValue: draft.url,
        enabled: enabled,
        keyboardType: TextInputType.url,
        onChanged: (v) => draft.url = v,
      ),
    ];
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required String initialValue,
    required bool enabled,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fillColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
        : theme.colorScheme.surface;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.5)
        : AppColors.border;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        initialValue: initialValue,
        enabled: enabled,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
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
        ),
      ),
    );
  }

  Widget _buildTextArea({
    required String label,
    required String hint,
    required String initialValue,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fillColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
        : theme.colorScheme.surface;
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.5)
        : AppColors.border;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        initialValue: initialValue,
        enabled: enabled,
        minLines: 2,
        maxLines: 4,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
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
        ),
      ),
    );
  }

  Widget _buildTwoCol(Widget left, Widget right) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildThreeCol(Widget one, Widget two, Widget three) {
    return Row(
      children: [
        Expanded(child: one),
        const SizedBox(width: 8),
        Expanded(child: two),
        const SizedBox(width: 8),
        Expanded(child: three),
      ],
    );
  }

  String? _validatePublicationDraft(_PublicationDraft d) {
    final pt = d.pubType;

    bool has(String value) => value.trim().isNotEmpty;

    if (!has(d.name)) return 'Please provide a label/name for this record.';

    if (pt == 'webpage' &&
        (!has(d.authorFirstName) ||
            !has(d.authorLastName) ||
            !has(d.pageTitle) ||
            !has(d.websiteName) ||
            !has(d.url))) {
      return 'Please fill all required fields.';
    }

    if (pt == 'journal_article' &&
        (!has(d.authorFirstName) ||
            !has(d.authorLastName) ||
            !has(d.articleTitle) ||
            !has(d.journalName) ||
            !has(d.year))) {
      return 'Please fill all required fields.';
    }

    if (pt == 'book' &&
        (!has(d.authorFirstName) ||
            !has(d.authorLastName) ||
            !has(d.bookTitle) ||
            !has(d.publisher) ||
            !has(d.year))) {
      return 'Please fill all required fields.';
    }

    if (pt == 'report' &&
        (!has(d.organization) ||
            !has(d.reportTitle) ||
            !has(d.year) ||
            !has(d.publisher))) {
      return 'Please fill all required fields.';
    }

    if (pt == 'video' &&
        (!has(d.creator) ||
            !has(d.videoTitle) ||
            !has(d.platform) ||
            !has(d.publicationDate) ||
            !has(d.url))) {
      return 'Please fill all required fields.';
    }

    if (pt == 'online_newspaper' &&
        (!has(d.authorFirstName) ||
            !has(d.authorLastName) ||
            !has(d.articleTitle) ||
            !has(d.newspaperName) ||
            !has(d.publicationDate) ||
            !has(d.url))) {
      return 'Please fill all required fields.';
    }

    return null;
  }

  Future<FormData> _buildPublicationFormData(_PublicationDraft d) async {
    final title = _deriveTitle(d);
    final map = <String, dynamic>{
      'name': d.name.trim(),
      'title': title,
      'pub_type': d.pubType,
    };

    void addIfNotEmpty(String key, String value) {
      final v = value.trim();
      if (v.isNotEmpty) map[key] = v;
    }

    addIfNotEmpty('others', d.others);
    addIfNotEmpty('author_first_name', d.authorFirstName);
    addIfNotEmpty('author_last_name', d.authorLastName);
    addIfNotEmpty('publication_date', d.publicationDate);
    addIfNotEmpty('url', d.url);
    addIfNotEmpty('article_title', d.articleTitle);
    addIfNotEmpty('journal_name', d.journalName);
    addIfNotEmpty('volume', d.volume);
    addIfNotEmpty('issue', d.issue);
    addIfNotEmpty('pages', d.pages);
    addIfNotEmpty('doi', d.doi);
    addIfNotEmpty('year', d.year);
    addIfNotEmpty('book_title', d.bookTitle);
    addIfNotEmpty('publisher', d.publisher);
    addIfNotEmpty('edition', d.edition);
    addIfNotEmpty('page_number', d.pageNumber);
    addIfNotEmpty('organization', d.organization);
    addIfNotEmpty('report_title', d.reportTitle);
    addIfNotEmpty('creator', d.creator);
    addIfNotEmpty('video_title', d.videoTitle);
    addIfNotEmpty('platform', d.platform);
    addIfNotEmpty('newspaper_name', d.newspaperName);
    addIfNotEmpty('website_name', d.websiteName);
    addIfNotEmpty('page_title', d.pageTitle);

    final author = [
      d.authorFirstName.trim(),
      d.authorLastName.trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    addIfNotEmpty('author', author);

    if (d.file != null && d.file!.path != null) {
      map['file'] = await MultipartFile.fromFile(
        d.file!.path!,
        filename: d.file!.name,
      );
    }

    return FormData.fromMap(map);
  }

  String _deriveTitle(_PublicationDraft d) {
    final candidates = [
      d.pageTitle,
      d.articleTitle,
      d.bookTitle,
      d.reportTitle,
      d.videoTitle,
      d.name,
    ];

    for (final candidate in candidates) {
      final value = candidate.trim();
      if (value.isNotEmpty) return value;
    }
    return d.name.trim();
  }

  bool _supportsPdfUpload(String type) {
    return type == 'journal_article' || type == 'book' || type == 'report';
  }

  IconData _typeIconFor(String type) {
    switch (type) {
      case 'webpage':
        return Icons.language_rounded;
      case 'journal_article':
        return Icons.description_outlined;
      case 'book':
        return Icons.menu_book_outlined;
      case 'report':
        return Icons.bar_chart_rounded;
      case 'video':
        return Icons.play_circle_outline_rounded;
      case 'online_newspaper':
      case 'newspaper':
        return Icons.newspaper_outlined;
      default:
        return Icons.library_books_outlined;
    }
  }

  Color _typeColorFor(String type) {
    switch (type) {
      case 'webpage':
        return const Color(0xFF0F9D58);
      case 'journal_article':
        return const Color(0xFF6A1B9A);
      case 'book':
        return const Color(0xFFF57C00);
      case 'report':
        return AppColors.primary;
      case 'video':
        return const Color(0xFFD81B60);
      case 'online_newspaper':
      case 'newspaper':
        return const Color(0xFF00796B);
      default:
        return AppColors.textSecondary;
    }
  }
}

class _PublicationTypeTile extends StatelessWidget {
  const _PublicationTypeTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? theme.colorScheme.outline.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicationDraft {
  _PublicationDraft({required this.pubType});

  final String pubType;

  String name = '';
  String others = '';

  String authorFirstName = '';
  String authorLastName = '';
  String publicationDate = '';
  String url = '';

  String articleTitle = '';
  String journalName = '';
  String volume = '';
  String issue = '';
  String pages = '';
  String doi = '';
  String year = '';

  String bookTitle = '';
  String publisher = '';
  String edition = '';
  String pageNumber = '';

  String organization = '';
  String reportTitle = '';

  String creator = '';
  String videoTitle = '';
  String platform = '';

  String newspaperName = '';
  String websiteName = '';
  String pageTitle = '';

  PlatformFile? file;
}

class _PublicationCard extends StatelessWidget {
  final Map<String, dynamic> pub;
  final String typeLabel;
  final VoidCallback onOpenLink;

  const _PublicationCard({
    required this.pub,
    required this.typeLabel,
    required this.onOpenLink,
  });

  IconData get _typeIcon {
    final type = (pub['pub_type'] ?? pub['type'] ?? '').toString();
    switch (type) {
      case 'journal_article':
        return Icons.article_outlined;
      case 'book':
        return Icons.menu_book_outlined;
      case 'video':
        return Icons.video_library_outlined;
      case 'webpage':
        return Icons.language;
      case 'online_newspaper':
      case 'newspaper':
        return Icons.newspaper_outlined;
      default:
        return Icons.description_outlined;
    }
  }

  Color get _typeColor {
    final type = (pub['pub_type'] ?? pub['type'] ?? '').toString();
    switch (type) {
      case 'journal_article':
        return AppColors.primary;
      case 'book':
        return AppColors.success;
      case 'video':
        return AppColors.error;
      case 'webpage':
        return AppColors.info;
      case 'online_newspaper':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  String get _displayTitle {
    final title = (pub['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;

    final articleTitle = (pub['article_title'] ?? '').toString().trim();
    if (articleTitle.isNotEmpty) return articleTitle;

    final bookTitle = (pub['book_title'] ?? '').toString().trim();
    if (bookTitle.isNotEmpty) return bookTitle;

    final reportTitle = (pub['report_title'] ?? '').toString().trim();
    if (reportTitle.isNotEmpty) return reportTitle;

    final videoTitle = (pub['video_title'] ?? '').toString().trim();
    if (videoTitle.isNotEmpty) return videoTitle;

    return (pub['name'] ?? 'Untitled publication').toString();
  }

  String? get _metaText {
    final author = (pub['author'] ?? '').toString().trim();
    final context = _contextText();
    final date =
        (pub['publication_date'] ??
                pub['uploaded_at'] ??
                pub['created_at'] ??
                '')
            .toString()
            .trim();

    final parts = <String>[];
    if (author.isNotEmpty) parts.add(author);
    if (context.isNotEmpty) parts.add(context);
    if (date.isNotEmpty) parts.add(_formatDate(date));

    if (parts.isEmpty) return null;
    return parts.join(' • ');
  }

  String _contextText() {
    for (final key in const [
      'website_name',
      'journal_name',
      'publisher',
      'organization',
      'platform',
      'newspaper_name',
      'file_name',
    ]) {
      final value = (pub[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasFileLink = (pub['web_view_link'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    final hasUrlLink = (pub['url'] ?? '').toString().trim().isNotEmpty;
    final hasLink = hasFileLink || hasUrlLink;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_typeIcon, size: 22, color: _typeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (_metaText != null) ...[
            const SizedBox(height: 8),
            Text(
              _metaText!,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if ((pub['others'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              (pub['others'] ?? '').toString().trim(),
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _typeColor,
                  ),
                ),
              ),
              if (hasLink)
                OutlinedButton.icon(
                  onPressed: onOpenLink,
                  icon: Icon(
                    hasFileLink
                        ? Icons.download_rounded
                        : Icons.open_in_new_rounded,
                    size: 16,
                  ),
                  label: Text(hasFileLink ? 'View File' : 'Visit URL'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _typeColor,
                    side: BorderSide(color: _typeColor.withValues(alpha: 0.35)),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
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
