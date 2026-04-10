import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class IqacScreen extends StatefulWidget {
  const IqacScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<IqacScreen> createState() => _IqacScreenState();
}

class _IqacScreenState extends State<IqacScreen> {
  late Future<List<dynamic>> _future;
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final res = await widget.api.get('/iqac/criteria');
    return asList(res);
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'IQAC Data Collection',
      subtitle: 'Criteria and metadata from IQAC endpoints.',
      action: IconButton(
        icon: const Icon(Icons.refresh_rounded),
        onPressed: () => setState(() {
          _future = _load();
          _expandedIndex = null;
        }),
      ),
      child: FutureBuilder<List<dynamic>>(
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

          final criteria = snap.data ?? [];
          if (criteria.isEmpty) {
            return const EmptyCard(
              message: 'No IQAC criteria available.',
              icon: Icons.folder_copy_rounded,
            );
          }

          return Column(
            children: List.generate(criteria.length, (i) {
              final m = asMap(criteria[i]);
              final name = m['name']?.toString() ??
                  m['title']?.toString() ??
                  'Criterion ${i + 1}';
              final desc = m['description']?.toString() ?? '';
              final isExpanded = _expandedIndex == i;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isExpanded
                        ? AppColors.primary
                        : AppColors.divider,
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withAlpha(22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      trailing: AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      onTap: () => setState(
                            () => _expandedIndex = isExpanded ? null : i,
                      ),
                    ),
                    if (isExpanded && desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          desc,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.55,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
