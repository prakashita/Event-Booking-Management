import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class PublicationsScreen extends StatefulWidget {
  const PublicationsScreen({super.key});

  @override
  State<PublicationsScreen> createState() => _PublicationsScreenState();
}

class _PublicationsScreenState extends State<PublicationsScreen> {
  final _api = ApiService();
  List<Publication> _pubs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPublications();
  }

  Future<void> _loadPublications() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/publications');
      setState(() {
        _pubs = (data['items'] as List? ?? [])
            .map((p) => Publication.fromJson(p))
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Publications')),
      body: _isLoading
          ? _buildLoading()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _loadPublications)
              : _pubs.isEmpty
                  ? EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'No publications',
                      message: 'Research publications will appear here.',
                      actionLabel: 'Add Publication',
                      onAction: () => _showAddDialog(context),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPublications,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _pubs.length,
                        itemBuilder: (ctx, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _PublicationCard(pub: _pubs[i]),
                        ),
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Publication'),
      ),
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ShimmerBox(width: double.infinity, height: 110, radius: 12),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    String type = AppConstants.publicationTypes.first;
    final titleCtrl = TextEditingController();
    final authorsCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final journalCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Publication',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: AppConstants.publicationTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.replaceAll('_', ' ').toUpperCase()),
                        ))
                    .toList(),
                onChanged: (v) => setS(() => type = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: authorsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Authors (comma-separated)',
                  hintText: 'John Doe, Jane Smith',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: yearCtrl,
                      decoration: const InputDecoration(labelText: 'Year'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: journalCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Journal/Publisher'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                decoration: const InputDecoration(labelText: 'URL'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await _api.post('/publications', data: {
                        'type': type,
                        'title': titleCtrl.text.trim(),
                        'authors': authorsCtrl.text
                            .split(',')
                            .map((a) => a.trim())
                            .where((a) => a.isNotEmpty)
                            .toList(),
                        'year': int.tryParse(yearCtrl.text),
                        'url': urlCtrl.text.trim(),
                        'journal': journalCtrl.text.trim(),
                      });
                      _loadPublications();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Publication added!')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(e.toString()),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  child: const Text('Add Publication'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicationCard extends StatelessWidget {
  final Publication pub;
  const _PublicationCard({required this.pub});

  IconData get _typeIcon {
    switch (pub.type) {
      case 'journal_article': return Icons.article_outlined;
      case 'book': return Icons.menu_book_outlined;
      case 'video': return Icons.video_library_outlined;
      case 'webpage': return Icons.language;
      case 'newspaper': return Icons.newspaper_outlined;
      default: return Icons.description_outlined;
    }
  }

  Color get _typeColor {
    switch (pub.type) {
      case 'journal_article': return AppColors.primary;
      case 'book': return AppColors.success;
      case 'video': return AppColors.error;
      case 'webpage': return AppColors.info;
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _typeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon, size: 22, color: _typeColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pub.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (pub.authors.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    pub.authors.join(', '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _typeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        pub.type.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _typeColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (pub.year != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${pub.year}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
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
    );
  }
}
