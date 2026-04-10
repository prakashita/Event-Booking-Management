import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class PublicationsScreen extends StatefulWidget {
  const PublicationsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<PublicationsScreen> createState() => _PublicationsScreenState();
}

class _PublicationsScreenState extends State<PublicationsScreen> {
  late Future<List<dynamic>> _future;
  String _searchQuery = '';
  String _typeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final res = await widget.api.get('/publications?sort=latest');
    return asList(res);
  }

  Future<void> _create() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CreatePublicationDialog(),
    );
    if (payload == null) return;
    try {
      await widget.api.post('/publications', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publication created successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'Publications',
      subtitle: 'Publication feed and submission from website APIs.',
      action: FilledButton.icon(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add Publication'),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search publications…',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _typeFilter,
                  borderRadius: BorderRadius.circular(12),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Types')),
                    DropdownMenuItem(value: 'journal', child: Text('Journal')),
                    DropdownMenuItem(
                        value: 'conference', child: Text('Conference')),
                    DropdownMenuItem(value: 'book', child: Text('Book')),
                    DropdownMenuItem(value: 'chapter', child: Text('Chapter')),
                  ],
                  onChanged: (v) => setState(() => _typeFilter = v ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const ShimmerLoader();
              }
              if (snap.hasError) {
                return ErrorCard(
                  error: snap.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                );
              }

              final pubs = (snap.data ?? []).where((p) {
                final m = asMap(p);
                final title = (m['title'] ?? m['name'] ?? '')
                    .toString()
                    .toLowerCase();
                final type = (m['pubType'] ?? m['publication_type'] ?? '')
                    .toString()
                    .toLowerCase();
                final matchSearch = _searchQuery.isEmpty ||
                    title.contains(_searchQuery.toLowerCase());
                final matchType = _typeFilter == 'all' ||
                    type.contains(_typeFilter.toLowerCase());
                return matchSearch && matchType;
              }).toList();

              if (pubs.isEmpty) {
                return const EmptyCard(
                  message: 'No publications found.',
                  icon: Icons.menu_book_rounded,
                );
              }

              return Column(
                children: pubs.map((p) {
                  final m = asMap(p);
                  final title = m['title']?.toString() ??
                      m['name']?.toString() ??
                      'Publication';
                  final type = m['pubType']?.toString() ??
                      m['publication_type']?.toString() ??
                      '-';
                  return _PublicationCard(title: title, type: type, data: m);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PublicationCard extends StatelessWidget {
  const _PublicationCard({
    required this.title,
    required this.type,
    required this.data,
  });

  final String title;
  final String type;
  final Map<String, dynamic> data;

  static const _typeColors = {
    'journal': Color(0xFF007BFF),
    'conference': Color(0xFF8B5CF6),
    'book': Color(0xFF10B981),
    'chapter': Color(0xFFF59E0B),
  };

  @override
  Widget build(BuildContext context) {
    final color = _typeColors[type.toLowerCase()] ?? AppColors.textSecondary;
    final year = data['year']?.toString() ?? data['published_year']?.toString();
    final authors = data['authors']?.toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withAlpha(22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.article_rounded, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (authors != null)
                    Text(
                      authors,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withAlpha(22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          type.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (year != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          year,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
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

// ─── Create Publication Dialog ────────────────────────────────────────────────

class _CreatePublicationDialog extends StatefulWidget {
  const _CreatePublicationDialog();

  @override
  State<_CreatePublicationDialog> createState() =>
      _CreatePublicationDialogState();
}

class _CreatePublicationDialogState extends State<_CreatePublicationDialog> {
  final _name = TextEditingController();
  final _title = TextEditingController();
  final _authors = TextEditingController();
  final _year = TextEditingController(text: DateTime.now().year.toString());
  String _type = 'journal';

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _authors.dispose();
    _year.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Publication'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dialogInput('Name / Author Name *', _name),
              dialogInput('Title *', _title),
              dialogInput('Authors', _authors),
              dialogInput(
                'Year',
                _year,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: InputDecoration(
                  labelText: 'Publication Type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'journal', child: Text('Journal')),
                  DropdownMenuItem(
                      value: 'conference', child: Text('Conference')),
                  DropdownMenuItem(value: 'book', child: Text('Book')),
                  DropdownMenuItem(value: 'chapter', child: Text('Chapter')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'journal'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty || _title.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Name and Title are required.')),
              );
              return;
            }
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'title': _title.text.trim(),
              'authors': _authors.text.trim(),
              'year': int.tryParse(_year.text.trim()),
              'publication_type': _type,
              'pubType': _type,
            });
          },
          child: const Text('Add Publication'),
        ),
      ],
    );
  }
}
