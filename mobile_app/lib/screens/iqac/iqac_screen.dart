import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class IQACScreen extends StatefulWidget {
  const IQACScreen({super.key});

  @override
  State<IQACScreen> createState() => _IQACScreenState();
}

class _IQACScreenState extends State<IQACScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('IQAC Data Collection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('About IQAC'),
                  content: const Text(
                    'This section manages NAAC accreditation evidence files organized by criteria. Access is restricted to authorized roles.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: AppConstants.iqacCriteria.length,
        itemBuilder: (ctx, i) {
          final c = AppConstants.iqacCriteria[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CriterionCard(
              criterionKey: c['key']!,
              label: c['label']!,
            ),
          );
        },
      ),
    );
  }
}

class _CriterionCard extends StatefulWidget {
  final String criterionKey;
  final String label;

  const _CriterionCard({required this.criterionKey, required this.label});

  @override
  State<_CriterionCard> createState() => _CriterionCardState();
}

class _CriterionCardState extends State<_CriterionCard> {
  bool _expanded = false;
  int _fileCount = 0;

  static const _subfolders = [
    'Documents', 'Policies', 'Reports', 'Evidence', 'Supporting Material'
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        'C${widget.criterionKey}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Criterion ${widget.criterionKey}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ..._subfolders.map((sf) => _SubfolderTile(
                  criterionKey: widget.criterionKey,
                  subfolder: sf,
                )),
          ],
        ],
      ),
    );
  }
}

class _SubfolderTile extends StatefulWidget {
  final String criterionKey;
  final String subfolder;

  const _SubfolderTile({
    required this.criterionKey,
    required this.subfolder,
  });

  @override
  State<_SubfolderTile> createState() => _SubfolderTileState();
}

class _SubfolderTileState extends State<_SubfolderTile> {
  final _api = ApiService();
  bool _expanded = false;
  List<IQACFile> _files = [];
  bool _loading = false;
  bool _loaded = false;

  Future<void> _loadFiles() async {
    if (_loaded) return;
    setState(() => _loading = true);
    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/iqac/files',
        params: {
          'criterion': widget.criterionKey,
          'subfolder': widget.subfolder,
        },
      );
      setState(() {
        _files = (data['items'] as List? ?? [])
            .map((f) => IQACFile.fromJson(f))
            .toList();
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _uploadFile() async {
    // File picker integration
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('File upload coming soon...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (!_loaded) _loadFiles();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.subfolder,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (_files.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${_files.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            ..._files.map((f) => _FileTile(file: f)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
              child: GestureDetector(
                onTap: _uploadFile,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                        style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.primaryContainer,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.upload_outlined,
                          size: 16, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        'Upload File',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
        const Divider(height: 1, indent: 20),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  final IQACFile file;
  const _FileTile({required this.file});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 16, 4),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              file.filename,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.download_outlined,
                size: 18, color: AppColors.primary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
