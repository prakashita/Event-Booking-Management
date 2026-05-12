import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';

const _pubBg = Color(0xFFF3F4F6);
const _pubSurface = Color(0xFFFFFFFF);
const _pubBorder = Color(0xFFE5E7EB);
const _pubText = Color(0xFF111827);
const _pubMuted = Color(0xFF6B7280);
const _pubAccentBg = Color(0xFFEEF2FF);
const _pubAccent = Color(0xFF4F46E5);
const _pubDangerBg = Color(0xFFFEF2F2);
const _pubDanger = Color(0xFFEF4444);

class PublicationsScreen extends StatefulWidget {
  const PublicationsScreen({super.key});

  @override
  State<PublicationsScreen> createState() => _PublicationsScreenState();
}

class _PublicationsScreenState extends State<PublicationsScreen> {
  final _api = ApiService();
  final _searchController = TextEditingController();

  var _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _typeFilter = '';
  String _citationFormat = 'mla';
  String _sort = 'date_desc';
  DateTime? _dateStart;
  DateTime? _dateEnd;

  bool get _isAdmin {
    final role = (context.read<AuthProvider>().user?.roleKey ?? '')
        .trim()
        .toLowerCase();
    return role == 'admin';
  }

  String get _userId => context.read<AuthProvider>().user?.id ?? '';

  bool _isOwner(Map<String, dynamic> item) =>
      _string(item['created_by']) == _userId ||
      _string(item['user_id']) == _userId ||
      _string(item['owner_id']) == _userId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadPublications();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPublications() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final parts = _sort.split('_');
      final data = await _api.get<dynamic>(
        '/publications',
        params: {
          'sort': parts.first,
          'order': parts.length > 1 ? parts.last : 'desc',
        },
      );
      final raw = data is List ? data : (data is Map ? data['items'] : null);
      if (!mounted) return;
      setState(() {
        _items = raw is List
            ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : <Map<String, dynamic>>[];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageFromError(e);
        _loading = false;
      });
    }
  }

  Future<void> _openCreateFlow() async {
    HapticFeedback.mediumImpact();
    final source = await Navigator.of(context, rootNavigator: true)
        .push<_SourceTypeConfig>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const _SourceTypePickerScreen(),
          ),
        );
    if (!mounted || source == null) return;

    final created = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PublicationFormScreen(
          api: _api,
          source: source,
          citationFormat: _citationFormat,
        ),
      ),
    );
    if (created == true) {
      await _loadPublications();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Publication submitted successfully.')),
      );
    }
  }

  Future<void> _openEditFlow(Map<String, dynamic> item) async {
    HapticFeedback.mediumImpact();
    final source = _sourceConfig(_sourceKey(item));
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PublicationFormScreen(
          api: _api,
          source: source,
          citationFormat: _citationFormat,
          initialItem: item,
        ),
      ),
    );
    if (changed == true) {
      await _loadPublications();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Publication updated.')));
    }
  }

  Future<void> _deletePublication(Map<String, dynamic> item) async {
    final title = _displayTitle(item);
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete publication?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: _inputDecoration(context, 'Type DELETE'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: controller.text == 'DELETE'
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true) return;

    try {
      await _api.delete<dynamic>('/publications/${item['id']}');
      if (!mounted) return;
      setState(() {
        _items = _items.where((entry) => entry['id'] != item['id']).toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Publication deleted.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFromError(e))));
    }
  }

  void _openFiltersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterBottomSheet(
        type: _typeFilter,
        format: _citationFormat,
        sort: _sort,
        dateStart: _dateStart,
        dateEnd: _dateEnd,
        onApply: (type, format, sort, start, end) {
          setState(() {
            _typeFilter = type;
            _citationFormat = format;
            _sort = sort;
            _dateStart = start;
            _dateEnd = end;
          });
          _loadPublications();
        },
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final canEdit = !_isAdmin && _isOwner(item);
    final canDelete = _isAdmin || _isOwner(item);
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _PublicationDetailSheet(
        item: item,
        citationFormat: _citationFormat,
        canEdit: canEdit,
        canDelete: canDelete,
        onOpenLink: () => _openPublicationLink(item),
        onEdit: () async {
          Navigator.of(context).pop(false);
          await _openEditFlow(item);
        },
        onDelete: () async {
          Navigator.of(context).pop(false);
          await _deletePublication(item);
          return true;
        },
      ),
    );
    if (changed == true) await _loadPublications();
  }

  List<Map<String, dynamic>> get _visibleItems {
    final needle = _searchController.text.trim().toLowerCase();
    final result = _items.where((item) {
      if (_typeFilter.isNotEmpty && _sourceKey(item) != _typeFilter) {
        return false;
      }
      final date = _sortDate(item);
      if (_dateStart != null &&
          (date == null || date.isBefore(_dateOnly(_dateStart!)))) {
        return false;
      }
      if (_dateEnd != null &&
          (date == null || date.isAfter(_dateOnly(_dateEnd!)))) {
        return false;
      }
      if (needle.isEmpty) return true;
      final haystack = [
        _displayTitle(item),
        _field(item, 'contributors'),
        _field(item, 'container_title'),
        _field(item, 'doi'),
        _field(item, 'url'),
        item['author'],
        item['publisher'],
        item['journal_name'],
        item['website_name'],
        item['newspaper_name'],
        item['others'],
      ].map(_string).join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList();

    result.sort((a, b) {
      if (_sort.startsWith('title')) {
        final dir = _sort.endsWith('desc') ? -1 : 1;
        return _displayTitle(
              a,
            ).toLowerCase().compareTo(_displayTitle(b).toLowerCase()) *
            dir;
      }
      final dir = _sort.endsWith('asc') ? 1 : -1;
      final ad = _sortDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _sortDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd) * dir;
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;

    return Scaffold(
      backgroundColor: _pubBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadPublications,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Publications',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: _pubText,
                            letterSpacing: 0,
                            height: 1.1,
                          ),
                        ),
                      ),
                      _CountBadge(count: visible.length),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: _ModernFilterPanel(
                    searchController: _searchController,
                    typeFilter: _typeFilter,
                    citationFormat: _citationFormat,
                    sort: _sort,
                    dateStart: _dateStart,
                    dateEnd: _dateEnd,
                    onOpenFilters: _openFiltersSheet,
                    onSearchClear: _searchController.clear,
                    onPreset: (preset) {
                      final now = _dateOnly(DateTime.now());
                      setState(() {
                        if (preset == 'today') {
                          _dateStart = now;
                          _dateEnd = now;
                        } else if (preset == '7days') {
                          _dateStart = now.subtract(const Duration(days: 7));
                          _dateEnd = now;
                        } else if (preset == '30days') {
                          _dateStart = now.subtract(const Duration(days: 30));
                          _dateEnd = now;
                        } else if (preset == 'year') {
                          _dateStart = DateTime(now.year);
                          _dateEnd = now;
                        } else {
                          _dateStart = null;
                          _dateEnd = null;
                        }
                      });
                    },
                  ),
                ),
              ),
              if (_loading)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: 4,
                    itemBuilder: (context, index) => const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: _PublicationSkeletonCard(),
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _MessageState(
                    icon: Icons.error_outline_rounded,
                    title: 'Unable to load publications',
                    message: _error!,
                    actionLabel: 'Try Again',
                    onAction: _loadPublications,
                  ),
                )
              else if (_items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _MessageState(
                    icon: Icons.library_books_rounded,
                    title: 'No Publications Yet',
                    message:
                        'Add citations and organize your publication records.',
                    actionLabel: 'Add First Publication',
                    onAction: _openCreateFlow,
                  ),
                )
              else if (visible.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _MessageState(
                    icon: Icons.search_off_rounded,
                    title: 'No Matches Found',
                    message: 'Try adjusting your search or filters.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final canEdit = !_isAdmin && _isOwner(item);
                      final canDelete = _isAdmin || _isOwner(item);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _PublicationCard(
                          item: item,
                          citationFormat: _citationFormat,
                          canEdit: canEdit,
                          canDelete: canDelete,
                          onTap: () => _openDetail(item),
                          onView: () => _openDetail(item),
                          onEdit: canEdit ? () => _openEditFlow(item) : null,
                          onDelete: canDelete
                              ? () => _deletePublication(item)
                              : null,
                          onOpenLink: () => _openPublicationLink(item),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateFlow,
        elevation: 6,
        backgroundColor: _pubAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New Publication',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _openPublicationLink(Map<String, dynamic> item) async {
    final link = _string(item['web_view_link']).isNotEmpty
        ? _string(item['web_view_link'])
        : _field(item, 'url').isNotEmpty
        ? _field(item, 'url')
        : _string(item['url']);
    final uri = Uri.tryParse(link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _PublicationCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String citationFormat;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onView;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onOpenLink;

  const _PublicationCard({
    required this.item,
    required this.citationFormat,
    required this.canEdit,
    required this.canDelete,
    required this.onTap,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final source = _sourceConfig(_sourceKey(item));
    final date = _sortDate(item);
    final link = _publicationLink(item);
    final submitter = _submitterName(item);
    final citationText = _citation(item, citationFormat);

    return Container(
      decoration: BoxDecoration(
        color: _pubSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _pubBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(child: _SourceTypeBadge(source: source)),
                    if (date != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 10, top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 13,
                              color: _pubMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _dateLabel(date),
                              style: const TextStyle(
                                color: _pubMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _displayTitle(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _pubText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 14,
                      color: _pubMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(
                            color: _pubMuted,
                            fontSize: 14,
                          ),
                          children: [
                            const TextSpan(text: 'Submitted by '),
                            TextSpan(
                              text: submitter,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: const Border(
                        left: BorderSide(color: _pubAccent, width: 4),
                        top: BorderSide(color: _pubBorder),
                        right: BorderSide(color: _pubBorder),
                        bottom: BorderSide(color: _pubBorder),
                      ),
                    ),
                    child: Text(
                      citationText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: _pubMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                if (_string(item['others']).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _pubBorder),
                    ),
                    child: Text(
                      _string(item['others']),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _pubMuted,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Divider(height: 1, color: _pubBorder),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _CardActionButton(
                      icon: Icons.visibility_outlined,
                      label: 'View',
                      onPressed: onView,
                      isPrimary: true,
                    ),
                    if (link.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _CardActionButton(
                        icon: _string(item['web_view_link']).isNotEmpty
                            ? Icons.description_outlined
                            : Icons.open_in_new_rounded,
                        label: _string(item['web_view_link']).isNotEmpty
                            ? 'File'
                            : 'URL',
                        onPressed: onOpenLink,
                      ),
                    ],
                    if (canEdit) ...[
                      const SizedBox(width: 8),
                      _CardActionButton(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                        onPressed: onEdit,
                      ),
                    ],
                    const Spacer(),
                    if (canDelete)
                      Container(
                        decoration: BoxDecoration(
                          color: _pubDangerBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(),
                          tooltip: 'Delete',
                          onPressed: onDelete,
                          color: _pubDanger,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
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
    );
  }
}

class _PublicationDetailSheet extends StatelessWidget {
  final Map<String, dynamic> item;
  final String citationFormat;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onOpenLink;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;

  const _PublicationDetailSheet({
    required this.item,
    required this.citationFormat,
    required this.canEdit,
    required this.canDelete,
    required this.onOpenLink,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final source = _sourceConfig(_sourceKey(item));
    final fields = _detailsFor(item);
    final hasLink =
        _string(item['web_view_link']).isNotEmpty ||
        _field(item, 'url').isNotEmpty ||
        _string(item['url']).isNotEmpty;
    final createdAt = _auditDate(item, const ['created_at', 'uploaded_at']);
    final updatedAt = _auditDate(item, const ['updated_at', 'modified_at']);

    return Container(
      decoration: const BoxDecoration(
        color: _pubSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.96,
        minChildSize: 0.5,
        builder: (context, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceTypeBadge(source: source),
                        const SizedBox(height: 10),
                        Text(
                          _displayTitle(item),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1.18,
                            letterSpacing: 0,
                            color: _pubText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(false),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF3F4F6),
                      foregroundColor: _pubMuted,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _pubBorder),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  _PublicationMetaStrip(item: item),
                  const SizedBox(height: 16),
                  _SubmitterPanel(item: item),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    'Citation (${citationFormat.toUpperCase()})',
                    icon: Icons.menu_book_outlined,
                  ),
                  _SoftPanel(
                    child: SelectableText(
                      _citation(item, citationFormat),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: _pubText,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    'Publication Details',
                    icon: Icons.format_list_bulleted_rounded,
                  ),
                  _SoftPanel(
                    padding: EdgeInsets.zero,
                    child: _DetailGrid(fields: fields),
                  ),
                  if (hasLink) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle('Links', icon: Icons.link_rounded),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: onOpenLink,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(
                          _string(item['web_view_link']).isNotEmpty
                              ? 'Open File'
                              : 'Visit URL',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _pubAccent,
                          side: const BorderSide(color: Color(0xFFC7D2FE)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _SectionTitle(
                    'Audit Information',
                    icon: Icons.schedule_rounded,
                  ),
                  _SoftPanel(
                    child: _AuditGrid(
                      entries: [
                        MapEntry('Created by', _submitterName(item)),
                        MapEntry('Created at', createdAt),
                        MapEntry('Last updated by', _updatedBy(item)),
                        MapEntry('Last updated at', updatedAt),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                decoration: const BoxDecoration(
                  color: _pubSurface,
                  border: Border(top: BorderSide(color: _pubBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _pubText,
                        side: const BorderSide(color: _pubBorder),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (canEdit) ...[
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _pubAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                    if (canDelete) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async => onDelete(),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _pubDanger,
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernFilterPanel extends StatelessWidget {
  final TextEditingController searchController;
  final String typeFilter;
  final String citationFormat;
  final String sort;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final VoidCallback onOpenFilters;
  final VoidCallback onSearchClear;
  final ValueChanged<String> onPreset;

  const _ModernFilterPanel({
    required this.searchController,
    required this.typeFilter,
    required this.citationFormat,
    required this.sort,
    required this.dateStart,
    required this.dateEnd,
    required this.onOpenFilters,
    required this.onSearchClear,
    required this.onPreset,
  });

  @override
  Widget build(BuildContext context) {
    final activeCount = [
      typeFilter.isNotEmpty,
      citationFormat != 'mla',
      sort != 'date_desc',
      dateStart != null || dateEnd != null,
    ].where((value) => value).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: _pubSurface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _pubBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search title, author, DOI, URL...',
                    hintStyle: const TextStyle(color: _pubMuted, fontSize: 14),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: _pubMuted,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: onSearchClear,
                            icon: const Icon(Icons.cancel_rounded, size: 20),
                            color: _pubMuted,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: activeCount > 0 ? _pubAccentBg : _pubSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: activeCount > 0 ? const Color(0xFFC7D2FE) : _pubBorder,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: onOpenFilters,
                icon: Badge(
                  isLabelVisible: activeCount > 0,
                  label: Text('$activeCount'),
                  child: Icon(
                    Icons.tune_rounded,
                    color: activeCount > 0 ? _pubAccent : _pubMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _FilterChipWidget(
                label: 'Today',
                value: 'today',
                onTap: onPreset,
              ),
              _FilterChipWidget(label: '7d', value: '7days', onTap: onPreset),
              _FilterChipWidget(label: '30d', value: '30days', onTap: onPreset),
              _FilterChipWidget(
                label: 'This year',
                value: 'year',
                onTap: onPreset,
              ),
              if (dateStart != null || dateEnd != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton.icon(
                    onPressed: () => onPreset(''),
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Clear Dates'),
                    style: TextButton.styleFrom(
                      foregroundColor: _pubDanger,
                      visualDensity: VisualDensity.compact,
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

class _FilterChipWidget extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onTap;

  const _FilterChipWidget({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: _pubSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _pubBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onTap(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _pubText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  const _CardActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
          backgroundColor: _pubAccent.withValues(alpha: 0.08),
          foregroundColor: _pubAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        foregroundColor: _pubText,
        side: const BorderSide(color: _pubBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _PublicationSkeletonCard extends StatelessWidget {
  const _PublicationSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget line(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [line(80, 26), line(60, 16)],
          ),
          const SizedBox(height: 20),
          line(double.infinity, 22),
          const SizedBox(height: 8),
          line(200, 22),
          const SizedBox(height: 20),
          line(double.infinity, 70),
        ],
      ),
    );
  }
}

class _SourceTypePickerScreen extends StatefulWidget {
  const _SourceTypePickerScreen();

  @override
  State<_SourceTypePickerScreen> createState() =>
      _SourceTypePickerScreenState();
}

class _SourceTypePickerScreenState extends State<_SourceTypePickerScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needle = _searchController.text.trim().toLowerCase();
    final featured = _sourceTypes
        .where((source) => _featuredSourceKeys.contains(source.key))
        .toList();
    final more = _sourceTypes
        .where((source) => !_featuredSourceKeys.contains(source.key))
        .where(
          (source) =>
              needle.isEmpty ||
              source.label.toLowerCase().contains(needle) ||
              source.description.toLowerCase().contains(needle),
        )
        .toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Add Publication',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search source type...',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (needle.isEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Text(
                  'POPULAR',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.1,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _SourceGridTile(source: featured[index]),
                  childCount: featured.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                needle.isEmpty ? 'ALL SOURCES' : 'SEARCH RESULTS',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.1,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _SourceGridTile(source: more[index]),
                childCount: more.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceGridTile extends StatelessWidget {
  final _SourceTypeConfig source;

  const _SourceGridTile({required this.source});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pop(context, source),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: source.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(source.icon, color: source.color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                source.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicationFormScreen extends StatefulWidget {
  final ApiService api;
  final _SourceTypeConfig source;
  final String citationFormat;
  final Map<String, dynamic>? initialItem;

  const _PublicationFormScreen({
    required this.api,
    required this.source,
    required this.citationFormat,
    this.initialItem,
  });

  @override
  State<_PublicationFormScreen> createState() => _PublicationFormScreenState();
}

class _PublicationFormScreenState extends State<_PublicationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _enabledFlags = {};
  late _SourceTypeConfig _selectedSource;
  late String _citationFormat;
  bool _saving = false;
  bool _noteVisible = false;
  String? _error;

  bool get _isEdit => widget.initialItem != null;

  List<String> get _fields => _unique([
    ..._selectedSource.requiredFields,
    ..._selectedSource.recommendedFields,
    ..._selectedSource.optionalFields,
  ]);

  List<_PublicationFormRow> get _rows => _formRowsFor(_selectedSource);

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.source;
    _citationFormat = widget.citationFormat;
    _ensureControllersForSource(_selectedSource);
    _hydrateFromItem();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final formData = _buildFormData();
      if (_isEdit) {
        await widget.api.patch<Map<String, dynamic>>(
          '/publications/${widget.initialItem!['id']}',
          data: formData,
        );
      } else {
        await widget.api.postMultipart('/publications', formData);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFromError(e);
      });
    }
  }

  FormData _buildFormData() {
    final values = <String, String>{};
    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) values[entry.key] = value;
    }

    final title = _firstValue(values, const [
      'title',
      'content',
      'collection_title',
    ]);
    final container = _firstValue(values, const [
      'container_title',
      'collection_title',
      'source',
    ]);
    final issuedDate =
        values['issued_date'] ??
        values['composed_date'] ??
        values['submitted_date'] ??
        '';
    final contributorsText = values['contributors'] ?? '';
    final recordLabel = values['record_label']?.trim().isNotEmpty == true
        ? values['record_label']!.trim()
        : title.isNotEmpty
        ? title
        : _selectedSource.label;

    final details = <String, dynamic>{};
    for (final key in {..._fields, ..._rowFieldKeys(_rows)}) {
      final value = values[key];
      if (value != null && value.isNotEmpty) details[key] = value;
    }
    for (final flag in _enabledFlags) {
      details[flag] = true;
    }

    final map = <String, dynamic>{
      'name': recordLabel,
      'title': title.isNotEmpty ? title : recordLabel,
      'pub_type': _selectedSource.key,
      'source_type': _selectedSource.key,
      'citation_format': _citationFormat,
      'details': jsonEncode(details),
    };

    void add(String key, String? value) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) map[key] = normalized;
    }

    add('others', values['note']);
    add('author', contributorsText);
    add('container_title', container);
    add('publication_date', issuedDate);
    add('issued_date', values['issued_date']);
    add('accessed_date', values['accessed_date']);
    add('composed_date', values['composed_date']);
    add('submitted_date', values['submitted_date']);
    add('content', values['content']);
    add('source', values['source']);
    add('url', values['url']);
    add('pdf_url', values['pdf_url']);
    add('doi', values['doi']);
    add('publisher', values['publisher']);
    add('edition', values['edition']);
    add('volume', values['volume']);
    add('issue', values['issue']);
    add('pages', values['pages']);
    add('year', _yearFrom(issuedDate));
    add(
      'article_title',
      _selectedSource.key.contains('article') ? title : null,
    );
    add(
      'journal_name',
      _selectedSource.key == 'journal_article' ? container : null,
    );
    add('book_title', _selectedSource.key == 'book' ? title : null);
    add('report_title', _selectedSource.key == 'report' ? title : null);
    add('video_title', _selectedSource.key == 'video' ? title : null);
    add('platform', _selectedSource.key == 'video' ? container : null);
    add(
      'newspaper_name',
      _selectedSource.key.contains('newspaper') ? container : null,
    );
    add('website_name', _selectedSource.key == 'webpage' ? container : null);
    add('page_title', _selectedSource.key == 'webpage' ? title : null);
    add(
      'organization',
      _selectedSource.key == 'report' ? contributorsText : null,
    );

    if (contributorsText.isNotEmpty) {
      map['contributors'] = jsonEncode([
        {'kind': 'organization', 'name': contributorsText},
      ]);
    }
    return FormData.fromMap(map);
  }

  void _hydrateFromItem() {
    final item = widget.initialItem;
    if (item == null) return;
    _controller('record_label').text = _string(item['name']);
    for (final key in {..._fields, ..._rowFieldKeys(_rows)}) {
      final value = _field(item, key);
      if (value.isNotEmpty) _controller(key).text = value;
    }
    final contributors = _field(item, 'contributors').isNotEmpty
        ? _field(item, 'contributors')
        : _string(item['author']);
    if (contributors.isNotEmpty) {
      _controller('contributors').text = contributors;
    }
    final note = _field(item, 'note').isNotEmpty
        ? _field(item, 'note')
        : _string(item['others']);
    if (note.isNotEmpty) {
      _controller('note').text = note;
      _noteVisible = true;
    }
    for (final row in _rows) {
      if (row.flag == null) continue;
      final details = _detailsMap(item);
      final flagValue = details[row.flag];
      if (flagValue == true || flagValue.toString().toLowerCase() == 'true') {
        _enabledFlags.add(row.flag!);
      } else if (row.field != null && _field(item, row.field!).isNotEmpty) {
        _enabledFlags.add(row.flag!);
      }
    }
  }

  void _ensureControllersForSource(_SourceTypeConfig source) {
    final rows = _formRowsFor(source);
    for (final field in {
      ...source.requiredFields,
      ...source.recommendedFields,
      ...source.optionalFields,
      ..._rowFieldKeys(rows),
      'record_label',
    }) {
      _controller(field);
    }
  }

  Future<void> _changeSource() async {
    if (_saving) return;
    HapticFeedback.selectionClick();
    final source = await Navigator.of(context, rootNavigator: true)
        .push<_SourceTypeConfig>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const _SourceTypePickerScreen(),
          ),
        );
    if (!mounted || source == null || source.key == _selectedSource.key) {
      return;
    }

    setState(() {
      _selectedSource = source;
      _ensureControllersForSource(source);
      final validFlags = _flagKeys(_rows);
      _enabledFlags.removeWhere((flag) => !validFlags.contains(flag));
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Edit Publication' : 'Add ${_selectedSource.label}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    _SelectedPublicationSourceCard(
                      source: _selectedSource,
                      onTap: _changeSource,
                    ),
                    const SizedBox(height: 24),
                    ..._rows.map(_buildRow),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
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
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : Text(
                        _isEdit ? 'Save Changes' : 'Submit Publication',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(_PublicationFormRow row) {
    switch (row.type) {
      case _PublicationRowType.contributors:
        return _PublicationFormShell(
          label: 'Contributors',
          child: _ModernTextField(
            controller: _controller('contributors'),
            label: 'Contributors',
            hint: 'Authors, creators, editors, organizations',
            maxLines: 3,
          ),
        );
      case _PublicationRowType.date:
        return _PublicationFormShell(
          label: row.label,
          required: row.required,
          child: _PublicationDateInput(
            controller: _controller(row.field!),
            required: row.required,
            todayShortcut: row.todayShortcut,
            enabled: !_saving,
          ),
        );
      case _PublicationRowType.range:
        return _PublicationFormShell(
          label: row.label,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ModernTextField(
                  controller: _controller(row.field!),
                  label: row.label,
                  hint: row.placeholder,
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Range'),
                selected: _enabledFlags.contains(row.flag),
                onSelected: _saving
                    ? null
                    : (selected) => setState(() {
                        if (selected) {
                          _enabledFlags.add(row.flag!);
                        } else {
                          _enabledFlags.remove(row.flag);
                        }
                      }),
              ),
            ],
          ),
        );
      case _PublicationRowType.radio:
        return _PublicationFormShell(
          label: row.label,
          required: row.required,
          child: _PublicationChoiceGroup(
            options: row.options,
            value: _controller(row.field!).text.isNotEmpty
                ? _controller(row.field!).text
                : row.options.first,
            onChanged: _saving
                ? null
                : (value) =>
                      setState(() => _controller(row.field!).text = value),
          ),
        );
      case _PublicationRowType.toggleDate:
        final enabled = _enabledFlags.contains(row.flag);
        return _PublicationToggleShell(
          label: row.label,
          value: enabled,
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  if (value) {
                    _enabledFlags.add(row.flag!);
                  } else {
                    _enabledFlags.remove(row.flag);
                    _controller(row.field!).clear();
                  }
                }),
          child: enabled
              ? _PublicationDateInput(
                  controller: _controller(row.field!),
                  enabled: !_saving,
                )
              : null,
        );
      case _PublicationRowType.toggleField:
        final enabled = _enabledFlags.contains(row.flag);
        return _PublicationToggleShell(
          label: row.toggleLabel ?? row.label,
          value: enabled,
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  if (value) {
                    _enabledFlags.add(row.flag!);
                  } else {
                    _enabledFlags.remove(row.flag);
                    _controller(row.field!).clear();
                  }
                }),
          child: enabled
              ? _ModernTextField(
                  controller: _controller(row.field!),
                  label: row.fieldLabel ?? row.label,
                  hint: row.placeholder,
                )
              : null,
        );
      case _PublicationRowType.archiveGroup:
        return _PublicationFormShell(
          label: row.label,
          child: Column(
            children: row.subFields
                .map(
                  (field) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ModernTextField(
                      controller: _controller(field.field),
                      label: field.label,
                      hint: '',
                    ),
                  ),
                )
                .toList(),
          ),
        );
      case _PublicationRowType.annotation:
        return _PublicationFormShell(
          label: 'Annotation',
          child: _noteVisible || _controller('note').text.isNotEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ModernTextField(
                      controller: _controller('note'),
                      label: 'Annotation',
                      hint: 'Add a short citation note',
                      maxLines: 3,
                    ),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _controller('note').clear();
                              _noteVisible = false;
                            }),
                      child: const Text('Remove annotation'),
                    ),
                  ],
                )
              : OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _noteVisible = true),
                  child: const Text('Add annotation'),
                ),
        );
      case _PublicationRowType.field:
        final config =
            _fieldDefinitions[row.field] ?? _FieldConfig(row.field!, row.label);
        return _PublicationFormShell(
          label: row.label,
          required: row.required,
          child: _ModernTextField(
            controller: _controller(row.field!),
            label: '${row.label}${row.required ? ' *' : ''}',
            hint: row.placeholder.isNotEmpty ? row.placeholder : config.hint,
            required: row.required,
            maxLines: config.multiline ? 4 : 1,
            keyboardType: row.inputType == 'url'
                ? TextInputType.url
                : config.keyboardType,
          ),
        );
    }
  }

  TextEditingController _controller(String field) =>
      _controllers.putIfAbsent(field, TextEditingController.new);
}

class _FilterBottomSheet extends StatefulWidget {
  final String type;
  final String format;
  final String sort;
  final DateTime? dateStart;
  final DateTime? dateEnd;
  final void Function(
    String type,
    String format,
    String sort,
    DateTime? start,
    DateTime? end,
  )
  onApply;

  const _FilterBottomSheet({
    required this.type,
    required this.format,
    required this.sort,
    required this.onApply,
    this.dateStart,
    this.dateEnd,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late String _type = widget.type;
  late String _format = widget.format;
  late String _sort = widget.sort;
  late DateTime? _start = widget.dateStart;
  late DateTime? _end = widget.dateEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Filters',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _type = '';
                      _format = 'mla';
                      _sort = 'date_desc';
                      _start = null;
                      _end = null;
                    }),
                    child: const Text(
                      'Reset',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _PublicationInlineSelect(
                label: 'Publication Type',
                value: _type,
                options: {
                  '': 'All Types',
                  for (final source in _sourceTypes) source.key: source.label,
                },
                onChanged: (value) => setState(() => _type = value),
              ),
              const SizedBox(height: 16),
              _PublicationInlineSelect(
                label: 'Citation Format',
                value: _format,
                options: _citationOptions,
                onChanged: (value) => setState(() => _format = value),
              ),
              const SizedBox(height: 16),
              _PublicationInlineSelect(
                label: 'Sort By',
                value: _sort,
                options: const {
                  'date_desc': 'Newest First',
                  'date_asc': 'Oldest First',
                  'title_asc': 'Title (A-Z)',
                  'title_desc': 'Title (Z-A)',
                },
                onChanged: (value) => setState(() => _sort = value),
              ),
              const SizedBox(height: 24),
              _SectionTitle('Date Range'),
              Row(
                children: [
                  Expanded(
                    child: _DateFilterButton(
                      label: 'From',
                      value: _start,
                      onChanged: (value) => setState(() => _start = value),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DateFilterButton(
                      label: 'To',
                      value: _end,
                      onChanged: (value) => setState(() => _end = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Today'),
                    onPressed: () {
                      final now = _dateOnly(DateTime.now());
                      setState(() {
                        _start = now;
                        _end = now;
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('7d'),
                    onPressed: () {
                      final now = _dateOnly(DateTime.now());
                      setState(() {
                        _start = now.subtract(const Duration(days: 7));
                        _end = now;
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('30d'),
                    onPressed: () {
                      final now = _dateOnly(DateTime.now());
                      setState(() {
                        _start = now.subtract(const Duration(days: 30));
                        _end = now;
                      });
                    },
                  ),
                  ActionChip(
                    label: const Text('This year'),
                    onPressed: () {
                      final now = _dateOnly(DateTime.now());
                      setState(() {
                        _start = DateTime(now.year);
                        _end = now;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: () {
                  widget.onApply(_type, _format, _sort, _start, _end);
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateFilterButton extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _DateFilterButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(1800),
          lastDate: DateTime(2200),
        );
        if (picked != null) onChanged(_dateOnly(picked));
      },
      onLongPress: value == null ? null : () => onChanged(null),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value == null ? label : _dateLabel(value!),
                style: TextStyle(
                  fontWeight: value == null
                      ? FontWeight.normal
                      : FontWeight.bold,
                  color: value == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedPublicationSourceCard extends StatelessWidget {
  final _SourceTypeConfig source;
  final VoidCallback? onTap;

  const _SelectedPublicationSourceCard({required this.source, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: source.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(source.icon, size: 32, color: source.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      source.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.swap_horiz_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicationFormShell extends StatelessWidget {
  final String label;
  final Widget child;
  final bool required;

  const _PublicationFormShell({
    required this.label,
    required this.child,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (required)
                Text(
                  ' *',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PublicationToggleShell extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? child;

  const _PublicationToggleShell({
    required this.label,
    required this.value,
    required this.onChanged,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Switch(
                      value: value,
                      onChanged: onChanged,
                      activeThumbColor: theme.colorScheme.primary,
                    ),
                  ],
                ),
                if (child != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: child!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicationInlineSelect extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;

  const _PublicationInlineSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonFormField<String>(
      initialValue: options.containsKey(value) ? value : options.keys.first,
      decoration: _inputDecoration(context, label).copyWith(
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.3,
        ),
      ),
      icon: const Icon(Icons.expand_more_rounded),
      items: options.entries
          .map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(
                entry.value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged == null
          ? null
          : (next) {
              if (next != null) onChanged!(next);
            },
    );
  }
}

class _PublicationDateInput extends StatelessWidget {
  final TextEditingController controller;
  final bool required;
  final bool todayShortcut;
  final bool enabled;

  const _PublicationDateInput({
    required this.controller,
    this.required = false,
    this.todayShortcut = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            readOnly: true,
            enabled: enabled,
            decoration: _inputDecoration(context, 'YYYY-MM-DD').copyWith(
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              suffixIcon: Icon(
                Icons.calendar_today_rounded,
                color: theme.colorScheme.primary,
              ),
            ),
            validator: required
                ? (value) => (value?.trim().isEmpty ?? true) ? 'Required' : null
                : null,
            onTap: enabled ? () => _pickDate(context) : null,
          ),
        ),
        if (todayShortcut) ...[
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: enabled
                ? () => controller.text = _dateLabel(DateTime.now())
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Today',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final initial = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1800),
      lastDate: DateTime(2200),
    );
    if (picked != null) controller.text = _dateLabel(picked);
  }
}

class _PublicationChoiceGroup extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String>? onChanged;

  const _PublicationChoiceGroup({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: options
          .map(
            (option) => ChoiceChip(
              label: Text(
                option,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              selected: value == option,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onSelected: onChanged == null ? null : (_) => onChanged!(option),
            ),
          )
          .toList(),
    );
  }
}

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;

  const _ModernTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.required = false,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration(context, label).copyWith(
        hintText: hint,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.3,
        ),
      ),
      validator: required
          ? (value) => (value?.trim().isEmpty ?? true)
                ? 'This field is required'
                : null
          : null,
    );
  }
}

class _SourceTypeBadge extends StatelessWidget {
  final _SourceTypeConfig source;

  const _SourceTypeBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _pubAccentBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.icon, size: 13, color: _pubAccent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              source.label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _pubAccent,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: _pubAccentBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count Total',
        style: const TextStyle(
          color: _pubAccent,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;

  const _SectionTitle(this.title, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: _pubMuted),
            const SizedBox(width: 6),
          ],
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              color: _pubMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SoftPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEFF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SubmitterPanel extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SubmitterPanel({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = _submitterName(item);
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    final createdAt = _auditDate(item, const ['created_at', 'uploaded_at']);
    final published = _field(item, 'issued_date').isNotEmpty
        ? _field(item, 'issued_date')
        : _string(item['publication_date']);

    return _SoftPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _pubAccent.withValues(alpha: 0.10),
            child: Text(
              initial,
              style: const TextStyle(
                color: _pubAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: const TextStyle(color: _pubMuted, fontSize: 14),
                    children: [
                      const TextSpan(text: 'Submitted by '),
                      TextSpan(
                        text: name,
                        style: const TextStyle(
                          color: _pubText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 13,
                      color: _pubMuted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        [
                          if (createdAt.isNotEmpty) createdAt,
                          if (published.isNotEmpty) 'Published $published',
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _pubMuted,
                          fontSize: 12,
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
    );
  }
}

class _AuditGrid extends StatelessWidget {
  final List<MapEntry<String, String>> entries;

  const _AuditGrid({required this.entries});

  @override
  Widget build(BuildContext context) {
    final filtered = entries
        .map(
          (entry) =>
              MapEntry(entry.key, entry.value.isEmpty ? '-' : entry.value),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 14) / 2;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: filtered
              .map(
                (entry) => SizedBox(
                  width: itemWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key,
                        style: const TextStyle(
                          color: _pubMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _pubText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DetailGrid extends StatelessWidget {
  final List<MapEntry<String, String>> fields;

  const _DetailGrid({required this.fields});

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No details available.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 560;
        final urlFields = fields
            .where((entry) => entry.key.toLowerCase().contains('url'))
            .toList();
        final nonUrlFields = fields
            .where((entry) => !entry.key.toLowerCase().contains('url'))
            .toList();
        final ordered = _orderedDetailFields(
          useTwoColumns ? nonUrlFields : fields,
        );
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: useTwoColumns ? 22 : 18,
            vertical: 18,
          ),
          child: useTwoColumns
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _DetailColumn(fields: ordered.left)),
                        const SizedBox(width: 44),
                        Expanded(child: _DetailColumn(fields: ordered.right)),
                      ],
                    ),
                    if (urlFields.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      for (var i = 0; i < urlFields.length; i++) ...[
                        _DetailField(entry: urlFields[i]),
                        if (i != urlFields.length - 1)
                          const SizedBox(height: 18),
                      ],
                    ],
                  ],
                )
              : _DetailColumn(fields: ordered.vertical),
        );
      },
    );
  }
}

class _DetailColumn extends StatelessWidget {
  final List<MapEntry<String, String>> fields;

  const _DetailColumn({required this.fields});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          _DetailField(entry: fields[i]),
          if (i != fields.length - 1) const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _DetailField extends StatelessWidget {
  final MapEntry<String, String> entry;

  const _DetailField({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isUrl = entry.key.toLowerCase().contains('url');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.key,
          style: const TextStyle(
            color: _pubMuted,
            fontSize: 12,
            height: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                entry.value,
                style: TextStyle(
                  color: isUrl ? _pubAccent : _pubText,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isUrl) ...[
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: _pubAccent,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

({
  List<MapEntry<String, String>> left,
  List<MapEntry<String, String>> right,
  List<MapEntry<String, String>> vertical,
})
_orderedDetailFields(List<MapEntry<String, String>> fields) {
  MapEntry<String, String>? take(String label) {
    final index = fields.indexWhere(
      (entry) => entry.key.toLowerCase() == label.toLowerCase(),
    );
    if (index == -1) return null;
    return fields[index];
  }

  final preferredLeft = [
    take('Title'),
    take('Accessed'),
    take('URL'),
    take('Website Name'),
  ].whereType<MapEntry<String, String>>().toList();
  final preferredRight = [
    take('Issued'),
    take('Container Title'),
    take('Page Title'),
    take('Year'),
  ].whereType<MapEntry<String, String>>().toList();

  final used = {
    for (final entry in [...preferredLeft, ...preferredRight]) entry.key,
  };
  final rest = fields.where((entry) => !used.contains(entry.key)).toList();

  final left = [...preferredLeft];
  final right = [...preferredRight];
  for (var i = 0; i < rest.length; i++) {
    if (left.length <= right.length) {
      left.add(rest[i]);
    } else {
      right.add(rest[i]);
    }
  }

  final vertical = <MapEntry<String, String>>[];
  final maxLength = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < maxLength; i++) {
    if (i < left.length) vertical.add(left[i]);
    if (i < right.length) vertical.add(right[i]);
  }
  return (left: left, right: right, vertical: vertical);
}

class _PublicationMetaStrip extends StatelessWidget {
  final Map<String, dynamic> item;

  const _PublicationMetaStrip({required this.item});

  @override
  Widget build(BuildContext context) {
    final source = _sourceConfig(_sourceKey(item));
    final issued = _publicationIssued(item);
    final accessed = _field(item, 'accessed_date');
    final year = _publicationYear(item);
    final chips = [
      MapEntry(source.label, source.icon),
      if (issued.isNotEmpty) const MapEntry('Issued', Icons.event_rounded),
      if (accessed.isNotEmpty)
        const MapEntry('Accessed', Icons.visibility_outlined),
      if (year.isNotEmpty) const MapEntry('Year', Icons.calendar_view_month),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips.map((chip) {
        final value = switch (chip.key) {
          'Issued' => issued,
          'Accessed' => accessed,
          'Year' => year,
          _ => chip.key,
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _pubAccentBg.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDDE3FF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chip.value, size: 14, color: _pubAccent),
              const SizedBox(width: 6),
              Text(
                value,
                style: const TextStyle(
                  color: _pubAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

enum _PublicationRowType {
  field,
  date,
  range,
  radio,
  toggleDate,
  toggleField,
  archiveGroup,
  annotation,
  contributors,
}

class _PublicationFormRow {
  final _PublicationRowType type;
  final String label;
  final String? field;
  final String? flag;
  final String? toggleLabel;
  final String? fieldLabel;
  final String placeholder;
  final String? inputType;
  final bool required;
  final bool todayShortcut;
  final List<String> options;
  final List<_ArchiveSubField> subFields;

  const _PublicationFormRow.field(
    this.field,
    this.label, {
    this.required = false,
    this.placeholder = '',
    this.inputType,
  }) : type = _PublicationRowType.field,
       flag = null,
       toggleLabel = null,
       fieldLabel = null,
       todayShortcut = false,
       options = const [],
       subFields = const [];

  const _PublicationFormRow.date(
    this.field,
    this.label, {
    this.required = false,
    this.todayShortcut = false,
  }) : type = _PublicationRowType.date,
       flag = null,
       toggleLabel = null,
       fieldLabel = null,
       placeholder = '',
       inputType = null,
       options = const [],
       subFields = const [];

  const _PublicationFormRow.range(this.field, this.flag, this.label)
    : type = _PublicationRowType.range,
      required = false,
      placeholder = '',
      inputType = null,
      toggleLabel = null,
      fieldLabel = null,
      todayShortcut = false,
      options = const [],
      subFields = const [];

  const _PublicationFormRow.radio(this.field, this.label, this.options)
    : type = _PublicationRowType.radio,
      flag = null,
      required = false,
      placeholder = '',
      inputType = null,
      toggleLabel = null,
      fieldLabel = null,
      todayShortcut = false,
      subFields = const [];

  const _PublicationFormRow.toggleDate(this.flag, this.field, this.label)
    : type = _PublicationRowType.toggleDate,
      required = false,
      placeholder = '',
      inputType = null,
      toggleLabel = null,
      fieldLabel = null,
      todayShortcut = false,
      options = const [],
      subFields = const [];

  const _PublicationFormRow.toggleField(
    this.flag,
    this.field,
    this.label, {
    this.fieldLabel,
  }) : toggleLabel = null,
       type = _PublicationRowType.toggleField,
       required = false,
       placeholder = '',
       inputType = null,
       todayShortcut = false,
       options = const [],
       subFields = const [];

  const _PublicationFormRow.archive(this.label, this.subFields)
    : type = _PublicationRowType.archiveGroup,
      field = null,
      flag = null,
      required = false,
      placeholder = '',
      inputType = null,
      toggleLabel = null,
      fieldLabel = null,
      todayShortcut = false,
      options = const [];

  const _PublicationFormRow.annotation()
    : type = _PublicationRowType.annotation,
      label = 'Annotation',
      field = 'note',
      flag = null,
      required = false,
      placeholder = '',
      inputType = null,
      toggleLabel = null,
      fieldLabel = null,
      todayShortcut = false,
      options = const [],
      subFields = const [];

  const _PublicationFormRow.contributors()
    : type = _PublicationRowType.contributors,
      label = 'Contributors',
      field = 'contributors',
      flag = null,
      required = false,
      placeholder = '',
      inputType = null,
      toggleLabel = null,
      fieldLabel = null,
      todayShortcut = false,
      options = const [],
      subFields = const [];
}

class _ArchiveSubField {
  final String field;
  final String label;

  const _ArchiveSubField(this.field, this.label);
}

class _SourceTypeConfig {
  final String key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> requiredFields;
  final List<String> recommendedFields;
  final List<String> optionalFields;

  const _SourceTypeConfig({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.requiredFields,
    required this.recommendedFields,
    required this.optionalFields,
  });
}

class _FieldConfig {
  final String key;
  final String label;
  final String hint;
  final bool multiline;
  final String type;
  final List<String> options;
  final TextInputType? keyboardType;

  const _FieldConfig(
    this.key,
    this.label, {
    this.hint = '',
    this.multiline = false,
    this.type = 'text',
    this.options = const [],
    this.keyboardType,
  });
}

const _citationOptions = {
  'mla': 'MLA',
  'apa': 'APA',
  'harvard': 'Harvard',
  'chicago': 'Chicago',
  'ieee': 'IEEE',
};

const _featuredSourceKeys = {
  'webpage',
  'journal_article',
  'book',
  'report',
  'video',
  'online_newspaper_article',
};

const _commonWebOptional = ['accessed_date', 'note'];
const _placeFields = ['place_country', 'place_region', 'place_locality'];

const _fieldDefinitions = {
  'title': _FieldConfig('title', 'Title', hint: 'Main title of the cited item'),
  'content': _FieldConfig(
    'content',
    'Content',
    hint: 'Post or comment text',
    multiline: true,
    type: 'textarea',
  ),
  'contributors': _FieldConfig(
    'contributors',
    'Contributors',
    hint: 'Authors, creators, editors, organizations',
    multiline: true,
    type: 'textarea',
  ),
  'issued_date': _FieldConfig('issued_date', 'Issued', type: 'date'),
  'accessed_date': _FieldConfig('accessed_date', 'Accessed', type: 'date'),
  'composed_date': _FieldConfig('composed_date', 'Composed', type: 'date'),
  'submitted_date': _FieldConfig('submitted_date', 'Submitted', type: 'date'),
  'container_title': _FieldConfig(
    'container_title',
    'Container title',
    hint: 'Website, journal, book, platform, or publication name',
  ),
  'collection_title': _FieldConfig(
    'collection_title',
    'Collection title',
    hint: 'Podcast or TV series name',
  ),
  'medium': _FieldConfig(
    'medium',
    'Medium',
    hint: 'e.g. Painting, PDF, Video, Slides',
  ),
  'archive_collection': _FieldConfig(
    'archive_collection',
    'Archive / museum / collection',
  ),
  'place_country': _FieldConfig('place_country', 'Country'),
  'place_region': _FieldConfig('place_region', 'Region'),
  'place_locality': _FieldConfig('place_locality', 'Locality'),
  'publisher': _FieldConfig(
    'publisher',
    'Publisher',
    hint: 'Publisher, producer, institution, or organization',
  ),
  'publisher_place': _FieldConfig('publisher_place', 'Publisher place'),
  'source': _FieldConfig(
    'source',
    'Source',
    hint: 'Database, channel, platform, or source',
  ),
  'url': _FieldConfig(
    'url',
    'URL',
    hint: 'https://...',
    keyboardType: TextInputType.url,
  ),
  'doi': _FieldConfig('doi', 'DOI', hint: '10.1000/example'),
  'pdf_url': _FieldConfig(
    'pdf_url',
    'PDF URL',
    hint: 'https://...',
    keyboardType: TextInputType.url,
  ),
  'note': _FieldConfig(
    'note',
    'Note',
    hint: 'Optional citation note',
    multiline: true,
    type: 'textarea',
  ),
  'edition': _FieldConfig('edition', 'Edition', hint: 'e.g. 3rd'),
  'volume': _FieldConfig('volume', 'Volume'),
  'issue': _FieldConfig('issue', 'Issue'),
  'number': _FieldConfig('number', 'Number / article number'),
  'pages': _FieldConfig('pages', 'Page / page range', hint: 'e.g. 45-60'),
  'original_publication_date': _FieldConfig(
    'original_publication_date',
    'Original publication date',
    type: 'date',
  ),
  'event': _FieldConfig(
    'event',
    'Event',
    hint: 'Conference, talk, class, or event',
  ),
  'event_name': _FieldConfig('event_name', 'Event name'),
  'version': _FieldConfig('version', 'Version'),
  'status': _FieldConfig(
    'status',
    'Status',
    type: 'select',
    options: ['Published', 'In press', 'Unpublished'],
  ),
  'jurisdiction': _FieldConfig('jurisdiction', 'Jurisdiction'),
  'authority': _FieldConfig('authority', 'Authority'),
  'season': _FieldConfig('season', 'Season'),
  'episode': _FieldConfig('episode', 'Episode'),
  'genre': _FieldConfig(
    'genre',
    'Genre',
    hint: "e.g. PhD dissertation, Master's thesis",
  ),
  'section': _FieldConfig('section', 'Section'),
  'description': _FieldConfig('description', 'Description', multiline: true),
  'subtitle': _FieldConfig('subtitle', 'Subtitle'),
};

_SourceTypeConfig _source(
  String key,
  String label,
  String desc,
  IconData icon,
  Color color,
  List<String> req,
  List<String> rec,
  List<String> opt,
) => _SourceTypeConfig(
  key: key,
  label: label,
  description: desc,
  icon: icon,
  color: color,
  requiredFields: req,
  recommendedFields: rec,
  optionalFields: opt,
);

final _sourceTypes = <_SourceTypeConfig>[
  _source(
    'artwork',
    'Artwork',
    'Artwork, museum objects, and collection items',
    Icons.palette_outlined,
    const Color(0xFF7C3AED),
    ['title'],
    ['contributors', 'composed_date'],
    ['medium', 'archive_collection', ..._placeFields, 'note'],
  ),
  _source(
    'blog_post',
    'Blog Post',
    'Posts from blogs and editorial feeds',
    Icons.edit_note_rounded,
    const Color(0xFF0F766E),
    ['title', 'container_title'],
    ['contributors', 'issued_date', 'url'],
    _commonWebOptional,
  ),
  _source(
    'book',
    'Book',
    'Printed books and e-books',
    Icons.menu_book_outlined,
    const Color(0xFFC05621),
    ['title'],
    ['contributors', 'medium', 'issued_date', 'publisher'],
    [
      'edition',
      'volume',
      'original_publication_date',
      'publisher_place',
      'doi',
      'pdf_url',
      'url',
      'note',
    ],
  ),
  _source(
    'book_chapter',
    'Book Chapter',
    'A chapter or section within a book',
    Icons.auto_stories_outlined,
    const Color(0xFFA16207),
    ['title', 'container_title'],
    ['contributors', 'pages'],
    [
      'edition',
      'volume',
      'medium',
      'issued_date',
      'original_publication_date',
      'publisher',
      'publisher_place',
      'doi',
      'pdf_url',
      'url',
      'note',
    ],
  ),
  _source(
    'comment',
    'Comment',
    'Comments on posts, articles, videos, or threads',
    Icons.mode_comment_outlined,
    const Color(0xFF64748B),
    ['content'],
    ['container_title', 'contributors', 'issued_date', 'source', 'url'],
    _commonWebOptional,
  ),
  _source(
    'conference_proceeding',
    'Conference Proceeding',
    'Papers published in proceedings',
    Icons.description_outlined,
    const Color(0xFF4F46E5),
    ['title'],
    ['contributors', 'issued_date'],
    [
      'container_title',
      'edition',
      'volume',
      'medium',
      'publisher',
      'publisher_place',
      'doi',
      'pdf_url',
      'url',
      'note',
    ],
  ),
  _source(
    'conference_session',
    'Conference Session',
    'Talks, sessions, and conference presentations',
    Icons.mic_none_rounded,
    const Color(0xFF0891B2),
    ['title'],
    ['contributors', 'medium', 'event', 'url'],
    ['container_title', 'event_name', ..._placeFields, 'note'],
  ),
  _source(
    'dataset',
    'Dataset',
    'Datasets from repositories or projects',
    Icons.storage_rounded,
    const Color(0xFF047857),
    ['title'],
    ['contributors', 'url'],
    [
      'container_title',
      'version',
      'medium',
      'status',
      'issued_date',
      'publisher',
      'doi',
      'pdf_url',
      'note',
    ],
  ),
  _source(
    'film',
    'Film',
    'Films and movies',
    Icons.movie_outlined,
    const Color(0xFFB91C1C),
    ['title'],
    ['contributors', 'issued_date', 'publisher'],
    ['version', 'medium', 'url', 'note'],
  ),
  _source(
    'forum_post',
    'Forum Post',
    'Posts from forums and discussion boards',
    Icons.forum_outlined,
    const Color(0xFF475569),
    ['title'],
    ['container_title', 'contributors', 'issued_date', 'url'],
    _commonWebOptional,
  ),
  _source(
    'image',
    'Image',
    'Online images, figures, and photographs',
    Icons.image_outlined,
    const Color(0xFF7C2D12),
    ['title'],
    ['contributors', 'issued_date', 'url'],
    ['container_title', 'note'],
  ),
  _source(
    'journal_article',
    'Journal Article',
    'Peer-reviewed academic and scholarly articles',
    Icons.article_outlined,
    const Color(0xFF553C9A),
    ['title', 'container_title'],
    ['contributors', 'status', 'issued_date', 'pages', 'doi'],
    ['volume', 'issue', 'number', 'source', 'pdf_url', 'url', 'note'],
  ),
  _source(
    'online_dictionary_entry',
    'Online Dictionary Entry',
    'Dictionary entries published online',
    Icons.spellcheck_rounded,
    const Color(0xFF2563EB),
    ['title'],
    ['issued_date', 'url'],
    ['container_title', 'contributors', 'accessed_date', 'note'],
  ),
  _source(
    'online_encyclopedia_entry',
    'Online Encyclopedia Entry',
    'Online encyclopedia entries',
    Icons.public_rounded,
    const Color(0xFF1D4ED8),
    ['title'],
    ['issued_date', 'url'],
    ['container_title', 'contributors', 'accessed_date', 'note'],
  ),
  _source(
    'online_magazine_article',
    'Online Magazine Article',
    'Magazine articles published online',
    Icons.newspaper_rounded,
    const Color(0xFFBE123C),
    ['title', 'container_title'],
    ['contributors', 'issued_date', 'url'],
    ['original_publication_date', 'accessed_date', 'publisher', 'note'],
  ),
  _source(
    'online_newspaper_article',
    'Online Newspaper Article',
    'News articles published online',
    Icons.newspaper_outlined,
    const Color(0xFF276749),
    ['title', 'container_title'],
    ['contributors', 'issued_date', 'url'],
    ['publisher', 'note'],
  ),
  _source(
    'patent',
    'Patent',
    'Patents with number, jurisdiction, and authority',
    Icons.settings_outlined,
    const Color(0xFF0F172A),
    [
      'title',
      'contributors',
      'number',
      'jurisdiction',
      'authority',
      'issued_date',
    ],
    [],
    ['container_title', 'url', 'note'],
  ),
  _source(
    'podcast',
    'Podcast',
    'A podcast series',
    Icons.podcasts_rounded,
    const Color(0xFF9333EA),
    ['title'],
    ['contributors', 'url'],
    ['publisher', 'source', 'note'],
  ),
  _source(
    'podcast_episode',
    'Podcast Episode',
    'One episode from a podcast',
    Icons.headphones_rounded,
    const Color(0xFF7E22CE),
    ['collection_title'],
    ['contributors', 'issued_date', 'url'],
    [
      'title',
      'season',
      'episode',
      'accessed_date',
      'publisher',
      'source',
      'note',
    ],
  ),
  _source(
    'presentation_slides',
    'Presentation Slides',
    'Slide decks and presentation materials',
    Icons.slideshow_rounded,
    const Color(0xFF0369A1),
    ['title'],
    ['contributors', 'medium', 'issued_date', 'event', 'url'],
    [
      'container_title',
      'original_publication_date',
      'event_name',
      ..._placeFields,
      'pages',
      'note',
    ],
  ),
  _source(
    'press_release',
    'Press Release',
    'Organization announcements and press releases',
    Icons.campaign_outlined,
    const Color(0xFFB45309),
    ['title'],
    ['contributors', 'issued_date', 'url'],
    _commonWebOptional,
  ),
  _source(
    'print_dictionary_entry',
    'Print Dictionary Entry',
    'Dictionary entries in print sources',
    Icons.menu_book_outlined,
    const Color(0xFF334155),
    ['title', 'container_title'],
    ['contributors', 'issued_date', 'publisher'],
    [
      'edition',
      'volume',
      'number',
      'original_publication_date',
      'publisher_place',
      'pages',
      'note',
    ],
  ),
  _source(
    'print_encyclopedia_entry',
    'Print Encyclopedia Entry',
    'Encyclopedia entries in print sources',
    Icons.local_library_outlined,
    const Color(0xFF1E40AF),
    ['title', 'container_title'],
    ['contributors', 'issued_date', 'publisher'],
    [
      'edition',
      'volume',
      'original_publication_date',
      'publisher_place',
      'note',
    ],
  ),
  _source(
    'print_magazine_article',
    'Print Magazine Article',
    'Magazine articles from print issues',
    Icons.article_outlined,
    const Color(0xFF9F1239),
    ['title', 'container_title'],
    ['contributors', 'issued_date', 'pages'],
    ['issue', 'original_publication_date', 'source', 'note'],
  ),
  _source(
    'print_newspaper_article',
    'Print Newspaper Article',
    'Newspaper articles from print editions',
    Icons.newspaper_outlined,
    const Color(0xFF166534),
    ['title', 'container_title'],
    ['contributors', 'issued_date', 'pages'],
    [
      'edition',
      'section',
      'original_publication_date',
      'publisher',
      'publisher_place',
      'note',
    ],
  ),
  _source(
    'report',
    'Report',
    'Research, policy, and organization reports',
    Icons.bar_chart_rounded,
    const Color(0xFF2B6CB0),
    ['title'],
    ['contributors', 'issued_date', 'url'],
    [
      'container_title',
      'number',
      'accessed_date',
      'publisher',
      'publisher_place',
      'doi',
      'pdf_url',
      'note',
    ],
  ),
  _source(
    'social_media_post',
    'Social Media Post',
    'Posts from social platforms',
    Icons.alternate_email_rounded,
    const Color(0xFF0EA5E9),
    ['content'],
    ['contributors', 'issued_date', 'url'],
    ['container_title', 'accessed_date', 'note'],
  ),
  _source(
    'software',
    'Software',
    'Software packages, apps, and tools',
    Icons.code_rounded,
    const Color(0xFF0F766E),
    ['title'],
    ['contributors', 'version', 'issued_date'],
    ['container_title', 'publisher', 'url', 'note'],
  ),
  _source(
    'speech',
    'Speech',
    'Speeches and public addresses',
    Icons.record_voice_over_outlined,
    const Color(0xFFC2410C),
    ['title'],
    ['contributors', 'event', 'url'],
    ['container_title', 'issued_date', 'event_name', ..._placeFields, 'note'],
  ),
  _source(
    'thesis',
    'Thesis',
    'Theses and dissertations',
    Icons.school_outlined,
    const Color(0xFF4338CA),
    ['title'],
    ['contributors', 'genre', 'submitted_date', 'publisher'],
    ['doi', 'pdf_url', 'note'],
  ),
  _source(
    'tv_show',
    'TV Show',
    'A television show or series',
    Icons.tv_outlined,
    const Color(0xFFBE123C),
    ['title'],
    ['contributors', 'issued_date', 'publisher'],
    ['medium', 'source', 'url', 'note'],
  ),
  _source(
    'tv_show_episode',
    'TV Show Episode',
    'One episode from a TV series',
    Icons.live_tv_outlined,
    const Color(0xFFE11D48),
    ['collection_title'],
    ['contributors', 'issued_date'],
    [
      'title',
      'season',
      'episode',
      'medium',
      'accessed_date',
      'publisher',
      'source',
      'url',
      'note',
    ],
  ),
  _source(
    'video',
    'Video',
    'Online videos from YouTube, Vimeo, or platforms',
    Icons.play_circle_outline_rounded,
    const Color(0xFFC53030),
    ['title'],
    ['container_title', 'contributors', 'issued_date'],
    ['accessed_date', 'url', 'note'],
  ),
  _source(
    'webpage',
    'Webpage',
    'A specific page on a website',
    Icons.language_rounded,
    const Color(0xFF2C7A7B),
    ['title'],
    ['contributors', 'issued_date', 'url'],
    ['container_title', 'accessed_date', 'note'],
  ),
  _source(
    'website',
    'Website',
    'A full website, not just one page',
    Icons.public_rounded,
    const Color(0xFF0284C7),
    ['title'],
    ['issued_date', 'accessed_date', 'url'],
    ['publisher', 'note'],
  ),
  _source(
    'wiki_entry',
    'Wiki Entry',
    'Wiki or Wikipedia articles',
    Icons.travel_explore_outlined,
    const Color(0xFF475569),
    ['title'],
    ['container_title', 'issued_date', 'url'],
    ['accessed_date', 'note'],
  ),
];

final _formLabelOverrides = <String, Map<String, String>>{
  'webpage': {
    'container_title': 'Website name',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'blog_post': {
    'container_title': 'Blog name',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'book_chapter': {
    'title': 'Chapter title',
    'container_title': 'Book title',
    'volume': 'Volume number',
    'issued_date': 'Publication date',
    'publisher_place': 'Place of publication',
    'pages': 'Page',
  },
  'comment': {
    'container_title': 'Comment on',
    'accessed_date': 'Access date',
    'source': 'Website name',
  },
  'journal_article': {
    'title': 'Article title',
    'container_title': 'Journal name',
    'volume': 'Volume number',
    'issue': 'Issue number',
    'number': 'Article number or eLocator',
    'status': 'Publication status',
    'issued_date': 'Publication date',
    'source': 'Library database',
    'pages': 'Page',
  },
  'book': {
    'volume': 'Volume number',
    'issued_date': 'Publication date',
    'publisher_place': 'Place of publication',
  },
  'report': {
    'container_title': 'Website or database name',
    'number': 'Identifying number',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
    'publisher_place': 'Place of publication',
  },
  'video': {
    'container_title': 'Website name',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'online_newspaper_article': {
    'title': 'Article title',
    'container_title': 'Newspaper name',
    'issued_date': 'Publication date',
  },
  'conference_proceeding': {
    'volume': 'Volume number',
    'issued_date': 'Publication date',
    'publisher_place': 'Place of publication',
  },
  'conference_session': {'medium': 'Type of contribution'},
  'dataset': {
    'status': 'Publication status',
    'issued_date': 'Publication date',
  },
  'film': {
    'publisher': 'Production company',
    'issued_date': 'Publication date',
  },
  'forum_post': {
    'container_title': 'Website name',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'image': {
    'container_title': 'Website name',
    'issued_date': 'Publication date',
  },
  'online_dictionary_entry': {
    'title': 'Entry title',
    'container_title': 'Website name',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'online_magazine_article': {
    'container_title': 'Website name',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'patent': {'authority': 'Issuing body', 'issued_date': 'Publication date'},
  'podcast': {'title': 'Name'},
  'podcast_episode': {
    'collection_title': 'Podcast name',
    'season': 'Season number',
    'episode': 'Episode number',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
    'publisher': 'Production company',
    'source': 'Platform name',
  },
  'presentation_slides': {
    'issued_date': 'Publication date',
    'pages': 'Slide number',
  },
  'print_dictionary_entry': {
    'container_title': 'Dictionary name',
    'volume': 'Volume number',
    'number': 'Identifying number',
    'issued_date': 'Publication date',
    'publisher_place': 'Place of publication',
    'pages': 'Page',
  },
  'print_encyclopedia_entry': {
    'container_title': 'Encyclopedia name',
    'volume': 'Volume number',
    'issued_date': 'Publication date',
    'publisher_place': 'Place of publication',
  },
  'print_magazine_article': {
    'container_title': 'Magazine name',
    'issue': 'Issue number',
    'issued_date': 'Publication date',
    'pages': 'Page',
  },
  'print_newspaper_article': {
    'title': 'Article title',
    'container_title': 'Newspaper name',
    'issued_date': 'Publication date',
    'publisher_place': 'Place of publication',
    'pages': 'Page',
  },
  'social_media_post': {
    'container_title': 'Website name',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'software': {'issued_date': 'Publication date'},
  'speech': {'issued_date': 'Publication date'},
  'thesis': {'submitted_date': 'Year of submission', 'publisher': 'University'},
  'tv_show': {
    'publisher': 'Production company',
    'source': 'Platform name',
    'issued_date': 'Publication date',
  },
  'tv_show_episode': {
    'collection_title': 'TV show name',
    'season': 'Season number',
    'episode': 'Episode number',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
    'publisher': 'Production company',
    'source': 'Platform name',
  },
  'website': {
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
  'wiki_entry': {
    'container_title': 'Wiki title',
    'issued_date': 'Publication date',
    'accessed_date': 'Access date',
  },
};

final _extraToggleRows = <String, List<_PublicationFormRow>>{
  'artwork': const [
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
  ],
  'blog_post': const [
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'book_chapter': const [
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'dataset': const [
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'image': const [
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'online_newspaper_article': const [
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'online_magazine_article': const [
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'print_magazine_article': const [
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'print_newspaper_article': const [
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'report': const [
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
  'speech': const [
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
  ],
};

const _websitePublicationFormRows = <String, List<_PublicationFormRow>>{
  'artwork': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.date('composed_date', 'Composed date'),
    _PublicationFormRow.field('medium', 'Medium'),
    _PublicationFormRow.archive('Archive / Library / Museum', [
      _ArchiveSubField('archive_collection', 'Name'),
      _ArchiveSubField('place_country', 'Country'),
      _ArchiveSubField('place_region', 'Region'),
      _ArchiveSubField('place_locality', 'City'),
    ]),
    _PublicationFormRow.annotation(),
  ],
  'blog_post': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field('container_title', 'Blog name', required: true),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'book_chapter': [
    _PublicationFormRow.field('title', 'Chapter title', required: true),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field('container_title', 'Book title', required: true),
    _PublicationFormRow.field('edition', 'Edition', placeholder: 'e.g. 2'),
    _PublicationFormRow.range('volume', 'volume_is_range', 'Volume number'),
    _PublicationFormRow.field('medium', 'Medium'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.field(
      'publisher',
      'Publisher',
      placeholder: 'e.g. Grove Press',
    ),
    _PublicationFormRow.toggleField(
      'show_publisher_place',
      'publisher_place',
      'Show place of publication',
      fieldLabel: 'Place of publication',
    ),
    _PublicationFormRow.range('pages', 'pages_is_range', 'Page'),
    _PublicationFormRow.field(
      'doi',
      'DOI',
      placeholder: 'e.g. 10.1037/a0040251',
    ),
    _PublicationFormRow.field(
      'pdf_url',
      'PDF',
      inputType: 'url',
      placeholder: 'Link to PDF',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'comment': [
    _PublicationFormRow.field('content', 'Content', required: true),
    _PublicationFormRow.field('container_title', 'Comment on'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('source', 'Website name'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'webpage': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field('container_title', 'Website name'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'journal_article': [
    _PublicationFormRow.field('title', 'Article title', required: true),
    _PublicationFormRow.field(
      'container_title',
      'Journal name',
      required: true,
    ),
    _PublicationFormRow.range('volume', 'volume_is_range', 'Volume number'),
    _PublicationFormRow.field('issue', 'Issue number'),
    _PublicationFormRow.field(
      'number',
      'Article number or eLocator',
      placeholder: 'e.g. e0209899',
    ),
    _PublicationFormRow.radio('status', 'Publication status', [
      'Published',
      'In press',
    ]),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field(
      'source',
      'Library database',
      placeholder: 'e.g. JSTOR, ProQuest, or EBSCO',
    ),
    _PublicationFormRow.range('pages', 'pages_is_range', 'Page'),
    _PublicationFormRow.field(
      'doi',
      'DOI',
      placeholder: 'e.g. 10.1037/a0040251',
    ),
    _PublicationFormRow.field(
      'pdf_url',
      'PDF',
      inputType: 'url',
      placeholder: 'Link to PDF',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'book': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field('edition', 'Edition', placeholder: 'e.g. 2'),
    _PublicationFormRow.range('volume', 'volume_is_range', 'Volume number'),
    _PublicationFormRow.field('medium', 'Medium'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.toggleField(
      'show_publisher_place',
      'publisher_place',
      'Show place of publication',
      fieldLabel: 'Place of publication',
    ),
    _PublicationFormRow.field(
      'doi',
      'DOI',
      placeholder: 'e.g. 10.1037/a0040251',
    ),
    _PublicationFormRow.field(
      'pdf_url',
      'PDF',
      inputType: 'url',
      placeholder: 'Link to PDF',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'report': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field('container_title', 'Website or database name'),
    _PublicationFormRow.field(
      'number',
      'Identifying number',
      placeholder: 'e.g. WA-RD 896.4',
    ),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field(
      'publisher',
      'Publisher',
      placeholder: 'e.g. Washington State Department of Transportation',
    ),
    _PublicationFormRow.toggleField(
      'show_publisher_place',
      'publisher_place',
      'Show place of publication',
      fieldLabel: 'Place of publication',
    ),
    _PublicationFormRow.field(
      'doi',
      'DOI',
      placeholder: 'e.g. 10.1037/a0040251',
    ),
    _PublicationFormRow.field(
      'pdf_url',
      'PDF',
      inputType: 'url',
      placeholder: 'Link to PDF',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'video': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field(
      'container_title',
      'Website name',
      placeholder: 'e.g. YouTube or Vimeo',
    ),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'online_newspaper_article': [
    _PublicationFormRow.field('title', 'Article title', required: true),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field(
      'container_title',
      'Newspaper name',
      required: true,
    ),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'conference_proceeding': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field('container_title', 'Container title'),
    _PublicationFormRow.field('edition', 'Edition', placeholder: 'e.g. 2'),
    _PublicationFormRow.range('volume', 'volume_is_range', 'Volume number'),
    _PublicationFormRow.field('medium', 'Medium'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.toggleField(
      'show_publisher_place',
      'publisher_place',
      'Show place of publication',
      fieldLabel: 'Place of publication',
    ),
    _PublicationFormRow.field(
      'doi',
      'DOI',
      placeholder: 'e.g. 10.1037/a0040251',
    ),
    _PublicationFormRow.field(
      'pdf_url',
      'PDF',
      inputType: 'url',
      placeholder: 'Link to PDF',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'conference_session': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field('medium', 'Type of contribution'),
    _PublicationFormRow.archive('Event', [
      _ArchiveSubField('event', 'Name'),
      _ArchiveSubField('place_country', 'Country'),
      _ArchiveSubField('place_region', 'Region'),
      _ArchiveSubField('place_locality', 'City'),
    ]),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'dataset': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field(
      'version',
      'Version',
      placeholder: 'e.g. V2, 1.1.67',
    ),
    _PublicationFormRow.field('medium', 'Medium'),
    _PublicationFormRow.radio('status', 'Publication status', [
      'Published',
      'Unpublished',
    ]),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.field(
      'doi',
      'DOI',
      placeholder: 'e.g. 10.1037/a0040251',
    ),
    _PublicationFormRow.field(
      'pdf_url',
      'PDF',
      inputType: 'url',
      placeholder: 'Link to PDF',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'film': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field(
      'medium',
      'Medium',
      placeholder: 'e.g. four-disc special extended ed. on DVDs',
    ),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field('publisher', 'Production company'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'forum_post': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field('container_title', 'Website name'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'image': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field('container_title', 'Website name'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'print_newspaper_article': [
    _PublicationFormRow.field('title', 'Article title', required: true),
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field(
      'container_title',
      'Newspaper name',
      required: true,
    ),
    _PublicationFormRow.field(
      'edition',
      'Edition',
      placeholder: 'e.g. New York',
    ),
    _PublicationFormRow.field('section', 'Section', placeholder: 'e.g. Sports'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.toggleField(
      'show_publisher_place',
      'publisher_place',
      'Show place of publication',
      fieldLabel: 'Place of publication',
    ),
    _PublicationFormRow.range('pages', 'pages_is_range', 'Page'),
    _PublicationFormRow.annotation(),
  ],
  'online_dictionary_entry': [
    _PublicationFormRow.field('title', 'Entry title', required: true),
    _PublicationFormRow.field('container_title', 'Website name'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'online_encyclopedia_entry': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'online_magazine_article': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field('container_title', 'Website name'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'patent': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field('container_title', 'Container title'),
    _PublicationFormRow.field('jurisdiction', 'Jurisdiction', required: true),
    _PublicationFormRow.field(
      'authority',
      'Issuing body',
      required: true,
      placeholder: 'e.g., U.S. Patent and Trademark Office',
    ),
    _PublicationFormRow.date('issued_date', 'Publication date', required: true),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'podcast': [
    _PublicationFormRow.field('title', 'Name', required: true),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'podcast_episode': [
    _PublicationFormRow.field('title', 'Title'),
    _PublicationFormRow.field(
      'collection_title',
      'Podcast name',
      required: true,
    ),
    _PublicationFormRow.field('season', 'Season number'),
    _PublicationFormRow.field('episode', 'Episode number'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('publisher', 'Production company'),
    _PublicationFormRow.field(
      'source',
      'Platform name',
      placeholder: 'e.g. Apple Podcasts',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'presentation_slides': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field('container_title', 'Website name'),
    _PublicationFormRow.field('medium', 'Medium'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.archive('Event', [
      _ArchiveSubField('event', 'Name'),
      _ArchiveSubField('place_country', 'Country'),
      _ArchiveSubField('place_region', 'Region'),
      _ArchiveSubField('place_locality', 'City'),
    ]),
    _PublicationFormRow.range('pages', 'pages_is_range', 'Slide number'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'press_release': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'print_dictionary_entry': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field(
      'container_title',
      'Dictionary name',
      required: true,
    ),
    _PublicationFormRow.range('volume', 'volume_is_range', 'Volume number'),
    _PublicationFormRow.field('number', 'Identifying number'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.toggleField(
      'show_publisher_place',
      'publisher_place',
      'Show place of publication',
      fieldLabel: 'Place of publication',
    ),
    _PublicationFormRow.range('pages', 'pages_is_range', 'Page'),
    _PublicationFormRow.annotation(),
  ],
  'print_encyclopedia_entry': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field(
      'container_title',
      'Encyclopedia name',
      required: true,
    ),
    _PublicationFormRow.range('volume', 'volume_is_range', 'Volume number'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.toggleField(
      'show_publisher_place',
      'publisher_place',
      'Show place of publication',
      fieldLabel: 'Place of publication',
    ),
    _PublicationFormRow.annotation(),
  ],
  'print_magazine_article': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field(
      'container_title',
      'Magazine name',
      required: true,
    ),
    _PublicationFormRow.field('issue', 'Issue number'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.toggleDate(
      'show_original_publication_date',
      'original_publication_date',
      'Show original publication date',
    ),
    _PublicationFormRow.field('source', 'Source'),
    _PublicationFormRow.range('pages', 'pages_is_range', 'Page'),
    _PublicationFormRow.annotation(),
  ],
  'social_media_post': [
    _PublicationFormRow.field('content', 'Content', required: true),
    _PublicationFormRow.field('container_title', 'Website name'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'software': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.field('container_title', 'Container title'),
    _PublicationFormRow.field(
      'version',
      'Version',
      placeholder: 'e.g. V3, 1.1.6.7',
    ),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'speech': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.toggleField(
      'show_description',
      'description',
      'Show description',
      fieldLabel: 'Description',
    ),
    _PublicationFormRow.toggleField(
      'show_subtitle',
      'subtitle',
      'Show subtitle',
      fieldLabel: 'Subtitle',
    ),
    _PublicationFormRow.field('container_title', 'Container title'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.archive('Event', [
      _ArchiveSubField('event', 'Name'),
      _ArchiveSubField('place_country', 'Country'),
      _ArchiveSubField('place_region', 'Region'),
      _ArchiveSubField('place_locality', 'City'),
    ]),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'thesis': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.date('submitted_date', 'Year of submission'),
    _PublicationFormRow.field(
      'publisher',
      'University',
      placeholder: 'e.g. University of Chicago',
    ),
    _PublicationFormRow.field(
      'doi',
      'DOI',
      placeholder: 'e.g. 10.1037/a0040251',
    ),
    _PublicationFormRow.field(
      'pdf_url',
      'PDF',
      inputType: 'url',
      placeholder: 'Link to PDF',
    ),
    _PublicationFormRow.annotation(),
  ],
  'tv_show': [
    _PublicationFormRow.field('title', 'Title', required: true),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.field('publisher', 'Production company'),
    _PublicationFormRow.field(
      'source',
      'Platform name',
      placeholder: 'e.g. Netflix',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'tv_show_episode': [
    _PublicationFormRow.field('title', 'Title'),
    _PublicationFormRow.field(
      'collection_title',
      'TV show name',
      required: true,
    ),
    _PublicationFormRow.field('season', 'Season number'),
    _PublicationFormRow.field('episode', 'Episode number'),
    _PublicationFormRow.field(
      'medium',
      'Medium',
      placeholder: 'e.g. Blu-ray edition',
    ),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('publisher', 'Production company'),
    _PublicationFormRow.field(
      'source',
      'Platform name',
      placeholder: 'e.g. Netflix',
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'website': [
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('publisher', 'Publisher'),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
  'wiki_entry': [
    _PublicationFormRow.field('title', 'Title'),
    _PublicationFormRow.field('container_title', 'Wiki title'),
    _PublicationFormRow.date('issued_date', 'Publication date'),
    _PublicationFormRow.date(
      'accessed_date',
      'Access date',
      todayShortcut: true,
    ),
    _PublicationFormRow.field('url', 'URL', inputType: 'url'),
    _PublicationFormRow.annotation(),
  ],
};

List<_PublicationFormRow> _formRowsFor(_SourceTypeConfig source) {
  final websiteRows = _websitePublicationFormRows[source.key];
  if (websiteRows != null) return websiteRows;

  final requiredSet = source.requiredFields.toSet();
  final rows = <_PublicationFormRow>[];
  rows.addAll(_extraToggleRows[source.key] ?? const []);
  for (final field in _unique([
    ...source.requiredFields,
    ...source.recommendedFields,
    ...source.optionalFields,
  ])) {
    if (field == 'note') continue;
    if (field == 'contributors') {
      rows.add(const _PublicationFormRow.contributors());
      continue;
    }
    if (field == 'archive_collection') {
      rows.add(
        const _PublicationFormRow.archive('Archive / Library / Museum', [
          _ArchiveSubField('archive_collection', 'Name'),
          _ArchiveSubField('place_country', 'Country'),
          _ArchiveSubField('place_region', 'Region'),
          _ArchiveSubField('place_locality', 'City'),
        ]),
      );
      continue;
    }
    if (field == 'event' && _usesEventGroup(source.key)) {
      rows.add(
        const _PublicationFormRow.archive('Event', [
          _ArchiveSubField('event', 'Name'),
          _ArchiveSubField('place_country', 'Country'),
          _ArchiveSubField('place_region', 'Region'),
          _ArchiveSubField('place_locality', 'City'),
        ]),
      );
      continue;
    }
    if (_placeFields.contains(field)) continue;
    if (field == 'publisher_place') {
      rows.add(
        const _PublicationFormRow.toggleField(
          'show_publisher_place',
          'publisher_place',
          'Show place of publication',
          fieldLabel: 'Place of publication',
        ),
      );
      continue;
    }
    if (field == 'original_publication_date') {
      rows.add(
        const _PublicationFormRow.toggleDate(
          'show_original_publication_date',
          'original_publication_date',
          'Show original publication date',
        ),
      );
      continue;
    }
    if (field == 'volume') {
      rows.add(
        _PublicationFormRow.range(
          'volume',
          'volume_is_range',
          _labelForField(source.key, field),
        ),
      );
      continue;
    }
    if (field == 'pages') {
      rows.add(
        _PublicationFormRow.range(
          'pages',
          'pages_is_range',
          _labelForField(source.key, field),
        ),
      );
      continue;
    }
    if (field == 'status') {
      final options = source.key == 'dataset'
          ? const ['Published', 'Unpublished']
          : const ['Published', 'In press'];
      rows.add(
        _PublicationFormRow.radio(
          'status',
          _labelForField(source.key, field),
          options,
        ),
      );
      continue;
    }
    final config = _fieldDefinitions[field] ?? _FieldConfig(field, field);
    final label = _labelForField(source.key, field);
    if (config.type == 'date') {
      rows.add(
        _PublicationFormRow.date(
          field,
          label,
          required: requiredSet.contains(field),
          todayShortcut: field == 'accessed_date',
        ),
      );
    } else {
      rows.add(
        _PublicationFormRow.field(
          field,
          label,
          required: requiredSet.contains(field),
          placeholder: config.hint,
          inputType: config.keyboardType == TextInputType.url ? 'url' : null,
        ),
      );
    }
  }
  rows.add(const _PublicationFormRow.annotation());
  return rows;
}

bool _usesEventGroup(String key) =>
    key == 'conference_session' ||
    key == 'presentation_slides' ||
    key == 'speech';

String _labelForField(String sourceKey, String field) =>
    _formLabelOverrides[sourceKey]?[field] ??
    _fieldDefinitions[field]?.label ??
    field;

List<String> _rowFieldKeys(List<_PublicationFormRow> rows) {
  final keys = <String>{};
  for (final row in rows) {
    if (row.field != null) keys.add(row.field!);
    for (final subField in row.subFields) {
      keys.add(subField.field);
    }
  }
  return keys.toList();
}

Set<String> _flagKeys(List<_PublicationFormRow> rows) {
  return {
    for (final row in rows)
      if (row.flag != null) row.flag!,
  };
}

List<T> _unique<T>(Iterable<T> values) {
  final seen = <T>{};
  return [
    for (final value in values)
      if (seen.add(value)) value,
  ];
}

_SourceTypeConfig _sourceConfig(String key) {
  return _sourceTypes.firstWhere(
    (source) =>
        source.key == key ||
        (key == 'online_newspaper' && source.key == 'online_newspaper_article'),
    orElse: () => _sourceTypes.firstWhere((source) => source.key == 'webpage'),
  );
}

String _sourceKey(Map<String, dynamic> item) {
  final key = _string(item['source_type']).isNotEmpty
      ? _string(item['source_type'])
      : _string(item['pub_type']);
  if (key == 'newspaper' || key == 'online_newspaper') {
    return 'online_newspaper_article';
  }
  return key.isEmpty ? 'webpage' : key;
}

Map<String, dynamic> _detailsMap(Map<String, dynamic> item) {
  final details = item['details'];
  if (details is Map) return Map<String, dynamic>.from(details);
  if (details is String && details.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(details);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const {};
    }
  }
  return const {};
}

String _field(Map<String, dynamic> item, String key) {
  final direct = _string(item[key]);
  if (direct.isNotEmpty) return direct;
  final details = _detailsMap(item);
  if (details.isNotEmpty) return _string(details[key]);
  return '';
}

String _contributorsText(Map<String, dynamic> item) {
  final raw = item['contributors'];
  if (raw is List) {
    return raw
        .map((entry) {
          if (entry is Map) {
            final name = _string(entry['name']);
            if (name.isNotEmpty) return name;
            return [
              _string(entry['first_name']),
              _string(entry['last_name']),
            ].where((value) => value.isNotEmpty).join(' ');
          }
          return _string(entry);
        })
        .where((value) => value.isNotEmpty)
        .join(', ');
  }
  if (raw is String && raw.trim().startsWith('[')) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map(
              (entry) => entry is Map ? _string(entry['name']) : _string(entry),
            )
            .where((value) => value.isNotEmpty)
            .join(', ');
      }
    } catch (_) {
      return raw;
    }
  }
  final detailed = _field(item, 'contributors');
  if (detailed.isNotEmpty) return detailed;
  return _string(item['author']);
}

String _submitterName(Map<String, dynamic> item) {
  for (final key in const [
    'created_by_name',
    'submitted_by_name',
    'user_name',
    'owner_name',
    'creator_name',
    'created_by_email',
    'submitted_by_email',
    'user_email',
  ]) {
    final value = _string(item[key]);
    if (value.isNotEmpty) return value;
  }
  final author = _contributorsText(item);
  return author.isNotEmpty ? author : 'Unknown user';
}

String _updatedBy(Map<String, dynamic> item) {
  for (final key in const [
    'updated_by_name',
    'modified_by_name',
    'last_updated_by_name',
    'updated_by_email',
    'modified_by_email',
  ]) {
    final value = _string(item[key]);
    if (value.isNotEmpty) return value;
  }
  return _submitterName(item);
}

String _auditDate(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final raw = _string(item[key]);
    if (raw.isEmpty) continue;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return _dateLabel(parsed.toLocal());
    return raw;
  }
  return '';
}

String _publicationLink(Map<String, dynamic> item) {
  if (_string(item['web_view_link']).isNotEmpty) {
    return _string(item['web_view_link']);
  }
  if (_field(item, 'url').isNotEmpty) return _field(item, 'url');
  return _string(item['url']);
}

String _displayTitle(Map<String, dynamic> item) {
  for (final key in const [
    'title',
    'content',
    'article_title',
    'book_title',
    'report_title',
    'video_title',
    'page_title',
    'name',
  ]) {
    final value = _field(item, key).isNotEmpty
        ? _field(item, key)
        : _string(item[key]);
    if (value.isNotEmpty) return value;
  }
  return 'Untitled publication';
}

String _citation(Map<String, dynamic> item, String format) {
  final author = _contributorsText(item);
  final title = _displayTitle(item);
  final container = _field(item, 'container_title').isNotEmpty
      ? _field(item, 'container_title')
      : _string(item['publisher']);
  final issued = _field(item, 'issued_date').isNotEmpty
      ? _field(item, 'issued_date')
      : _string(item['publication_date']).isNotEmpty
      ? _string(item['publication_date'])
      : _string(item['year']);
  final doi = _field(item, 'doi').isNotEmpty
      ? _field(item, 'doi')
      : _string(item['doi']);
  final url = doi.isNotEmpty
      ? 'https://doi.org/${doi.replaceFirst(RegExp(r'^https?://doi.org/?', caseSensitive: false), '')}'
      : (_field(item, 'url').isNotEmpty
            ? _field(item, 'url')
            : _string(item['url']));

  final parts = switch (format) {
    'apa' => [
      author,
      if (issued.isNotEmpty) '($issued)',
      title,
      container,
      url,
    ],
    'harvard' => [
      author,
      if (issued.isNotEmpty) '($issued)',
      title,
      container,
      if (url.isNotEmpty) 'Available at: $url',
    ],
    'chicago' => [author, '"$title."', container, issued, url],
    'ieee' => [author, '"$title,"', container, issued, url],
    _ => [
      if (author.isNotEmpty) '$author.',
      '"$title."',
      if (container.isNotEmpty) '$container,',
      issued,
      url,
    ],
  };
  return parts.where((part) => part.trim().isNotEmpty).join(' ');
}

DateTime? _sortDate(Map<String, dynamic> item) {
  for (final key in const [
    'issued_date',
    'publication_date',
    'uploaded_at',
    'created_at',
  ]) {
    final raw = _field(item, key).isNotEmpty
        ? _field(item, key)
        : _string(item[key]);
    if (raw.isEmpty) continue;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return _dateOnly(parsed.toLocal());
    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(raw)?.group(0);
    if (year != null) return DateTime(int.parse(year));
  }
  return null;
}

List<MapEntry<String, String>> _detailsFor(Map<String, dynamic> item) {
  final sourceKey = _sourceKey(item);
  final entries = <MapEntry<String, String>>[];
  final seen = <String>{};

  void add(String label, String value, {String? key}) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    final uniqueKey = key ?? label.toLowerCase();
    if (!seen.add(uniqueKey)) return;
    entries.add(MapEntry(label, normalized));
  }

  add('Title', _displayTitle(item), key: 'title');
  add('Issued', _publicationIssued(item), key: 'issued_date');
  add('Accessed', _field(item, 'accessed_date'), key: 'accessed_date');
  add(
    'Container Title',
    _field(item, 'container_title'),
    key: 'container_title',
  );
  add('URL', _publicationLink(item), key: 'url');
  add('Page Title', _field(item, 'page_title'), key: 'page_title');
  add(
    'Website Name',
    _firstNonEmpty([
      _field(item, 'website_name'),
      sourceKey == 'webpage' || sourceKey == 'website'
          ? _field(item, 'container_title')
          : '',
    ]),
    key: 'website_name',
  );
  add('Year', _publicationYear(item), key: 'year');

  final rows = _formRowsFor(_sourceConfig(sourceKey));
  for (final row in rows) {
    if (row.type == _PublicationRowType.annotation ||
        row.type == _PublicationRowType.contributors) {
      continue;
    }
    final fields = row.subFields.isNotEmpty
        ? row.subFields.map((field) => MapEntry(field.label, field.field))
        : [MapEntry(row.fieldLabel ?? row.label, row.field ?? '')];
    for (final field in fields) {
      if (field.value.isEmpty) continue;
      final value = _field(item, field.value);
      add(_websiteDetailLabel(field.value, field.key), value, key: field.value);
    }
  }
  final note = _field(item, 'note').isNotEmpty
      ? _field(item, 'note')
      : _string(item['others']);
  add('Annotation', note, key: 'note');
  return entries;
}

String _websiteDetailLabel(String field, String fallback) {
  if (field == 'issued_date') return 'Issued';
  if (field == 'accessed_date') return 'Accessed';
  if (field == 'container_title') return 'Container Title';
  if (field == 'page_title') return 'Page Title';
  if (field == 'website_name') return 'Website Name';
  if (field == 'url') return 'URL';
  if (field == 'pdf_url') return 'PDF URL';
  if (field == 'submitted_date') return 'Submitted';
  if (field == 'composed_date') return 'Composed';
  return fallback;
}

String _publicationIssued(Map<String, dynamic> item) {
  return _firstNonEmpty([
    _field(item, 'issued_date'),
    _string(item['publication_date']),
    _field(item, 'submitted_date'),
    _field(item, 'composed_date'),
  ]);
}

String _publicationYear(Map<String, dynamic> item) {
  final explicit = _string(item['year']);
  if (explicit.isNotEmpty) return explicit;
  final issued = _publicationIssued(item);
  return _yearFrom(issued);
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

InputDecoration _inputDecoration(BuildContext context, String label) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
      borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
    ),
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateLabel(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _firstValue(Map<String, String> values, List<String> keys) {
  for (final key in keys) {
    if ((values[key]?.trim() ?? '').isNotEmpty) return values[key]!.trim();
  }
  return '';
}

String _yearFrom(String value) =>
    RegExp(r'\b(19|20)\d{2}\b').firstMatch(value)?.group(0) ?? '';

String _string(dynamic value) => (value ?? '').toString().trim();

String _messageFromError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    if (error.message != null) return error.message!;
  }
  final text = error.toString();
  return text.isEmpty ? 'Something went wrong.' : text;
}
