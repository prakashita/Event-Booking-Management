import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

typedef MarketingDeliverableLock =
    ({bool locked, String hint}) Function(String type);

typedef MarketingDeliverablesUpload =
    Future<String?> Function({
      required Map<String, bool> naByType,
      required Map<String, MultipartFile?> filesByType,
    });

const int _maxDeliverableFileBytes = 25 * 1024 * 1024;
const String _maxDeliverableFileLabel = '25MB';
const int _maxDeliverablePdfBytes = 15 * 1024 * 1024;
const String _maxDeliverablePdfLabel = '15MB';

bool _isPdfUpload(PlatformFile file) {
  return (file.extension ?? '').toLowerCase() == 'pdf' ||
      file.name.toLowerCase().endsWith('.pdf');
}

Future<void> showMarketingDeliverablesUploadDialog({
  required BuildContext context,
  required List<Map<String, String>> enabledOptions,
  required Map<String, bool> initialNaByType,
  required Map<String, String> initialFileNameByType,
  required MarketingDeliverableLock rowLock,
  required MarketingDeliverablesUpload onUpload,
  required Future<void> Function() onConnectGoogle,
  required String Function(Object error) extractErrorMessage,
  String title = 'Upload Deliverables',
  String eventTitle = '',
}) {
  final naByType = Map<String, bool>.from(initialNaByType);
  final filesByType = <String, MultipartFile?>{
    for (final opt in enabledOptions) opt['type']!: null,
  };
  final fileNameByType = Map<String, String>.from(initialFileNameByType);
  var submitStatus = 'idle';
  var submitError = '';

  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final surface = theme.colorScheme.surface;
        final onSurface = theme.colorScheme.onSurface;
        final muted = isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B);
        final border = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0);
        final panel = isDark ? const Color(0xFF111827) : Colors.white;
        final blue = isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0);
        final hasSelection = enabledOptions.any((opt) {
          final type = opt['type']!;
          final lock = rowLock(type);
          if (lock.locked) return false;
          return naByType[type] == true || filesByType[type] != null;
        });

        Future<void> pickFile(String type) async {
          final picked = await FilePicker.platform.pickFiles(
            withData: kIsWeb,
            withReadStream: !kIsWeb,
          );
          final file = picked?.files.first;
          if (file == null) return;
          final maxBytes = _isPdfUpload(file)
              ? _maxDeliverablePdfBytes
              : _maxDeliverableFileBytes;
          final maxLabel = _isPdfUpload(file)
              ? _maxDeliverablePdfLabel
              : _maxDeliverableFileLabel;
          if (file.size > maxBytes) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(
                  '${file.name} is larger than $maxLabel.',
                  style: GoogleFonts.inter(),
                ),
              ),
            );
            return;
          }

          MultipartFile? multipart;
          if (file.path != null && file.path!.trim().isNotEmpty) {
            multipart = await MultipartFile.fromFile(
              file.path!,
              filename: file.name,
            );
          } else if (file.bytes != null) {
            multipart = MultipartFile.fromBytes(
              file.bytes!,
              filename: file.name,
            );
          } else if (file.readStream != null) {
            multipart = MultipartFile.fromStream(
              () => file.readStream!,
              file.size,
              filename: file.name,
            );
          }

          if (multipart == null) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(
                  'Unable to read selected file.',
                  style: GoogleFonts.inter(),
                ),
              ),
            );
            return;
          }

          setLocal(() {
            filesByType[type] = multipart;
            fileNameByType[type] = file.name;
            naByType[type] = false;
          });
        }

        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 18, 0),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: submitStatus == 'loading'
                    ? null
                    : () => Navigator.of(ctx).pop(),
                icon: Icon(LucideIcons.x, color: muted, size: 20),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (eventTitle.trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF172033)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Text(
                        eventTitle.trim(),
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF101A2A)
                          : const Color(0xFFF7FAFF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? border.withValues(alpha: 0.9)
                            : const Color(0xFFD9E6FA),
                      ),
                    ),
                    child: Text(
                      'Upload pre-event items (poster, pre-event social) before the event starts. Post-event items (video upload, post social, post-event photos) after the event ends. Videography and on-site photography are handled during the event and do not use this form. You can save in multiple visits (PDF max 15MB, other files max 25MB).',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        height: 1.5,
                        color: muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  for (final opt in enabledOptions) ...[
                    Builder(
                      builder: (_) {
                        final type = opt['type']!;
                        final lock = rowLock(type);
                        final fileName = fileNameByType[type] ?? '';
                        final isNa = naByType[type] == true;
                        final hasFile = fileName.isNotEmpty && !isNa;
                        final helperText = _deliverableHelperText(type);

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: panel,
                            border: Border.all(
                              color: lock.locked
                                  ? border.withValues(alpha: 0.55)
                                  : border,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              if (!isDark)
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
                                ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      opt['label']!,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: onSurface,
                                      ),
                                    ),
                                  ),
                                  _NaToggle(
                                    value: isNa,
                                    enabled: !lock.locked,
                                    onChanged: (value) {
                                      setLocal(() {
                                        naByType[type] = value;
                                        if (value) {
                                          filesByType[type] = null;
                                          fileNameByType[type] = 'N/A';
                                        } else if (fileNameByType[type] ==
                                            'N/A') {
                                          fileNameByType.remove(type);
                                        }
                                      });
                                    },
                                    muted: muted,
                                  ),
                                ],
                              ),
                              if (lock.locked) ...[
                                const SizedBox(height: 8),
                                Text(
                                  lock.hint,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    height: 1.35,
                                    color: muted,
                                  ),
                                ),
                              ] else if (helperText.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  helperText,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: muted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 12),
                              ],
                              if (!lock.locked) ...[
                                if (helperText.isNotEmpty)
                                  const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: OutlinedButton.icon(
                                    onPressed: isNa
                                        ? null
                                        : () => pickFile(type),
                                    icon: Icon(
                                      hasFile
                                          ? LucideIcons.refreshCw
                                          : LucideIcons.uploadCloud,
                                      size: 18,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: blue,
                                      disabledForegroundColor: muted,
                                      side: BorderSide(
                                        color: isNa ? border : blue,
                                        width: 1.2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      textStyle: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    label: Text(
                                      hasFile ? 'Replace file' : 'Choose file',
                                    ),
                                  ),
                                ),
                                if (hasFile) ...[
                                  const SizedBox(height: 10),
                                  _SelectedFilePill(
                                    fileName: fileName,
                                    border: border,
                                    muted: muted,
                                    onSurface: onSurface,
                                    surface: surface,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  if (submitStatus == 'error') ...[
                    const SizedBox(height: 4),
                    _ErrorPanel(
                      message: submitError,
                      showConnect: submitError == 'Google not connected',
                      onConnect: () async {
                        try {
                          await onConnectGoogle();
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setLocal(() {
                            submitError = extractErrorMessage(e);
                          });
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitStatus == 'loading'
                  ? null
                  : () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: submitStatus == 'loading' || !hasSelection
                  ? null
                  : () async {
                      setLocal(() {
                        submitStatus = 'loading';
                        submitError = '';
                      });
                      final error = await onUpload(
                        naByType: naByType,
                        filesByType: filesByType,
                      );
                      if (!ctx.mounted) return;
                      if (error == null) {
                        Navigator.of(ctx).pop();
                        return;
                      }
                      setLocal(() {
                        submitStatus = 'error';
                        submitError = error;
                      });
                    },
              style: FilledButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF9CA3AF),
                minimumSize: const Size(98, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
              ),
              child: submitStatus == 'loading'
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

String _deliverableHelperText(String type) {
  switch (type) {
    case 'photography':
      return 'POST-EVENT PHOTO: UPLOAD AFTER THE EVENT HAS ENDED.';
    case 'recording':
      return 'POST-EVENT VIDEO: UPLOAD AFTER THE EVENT HAS ENDED.';
    default:
      return '';
  }
}

class _NaToggle extends StatelessWidget {
  const _NaToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.muted,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? () => onChanged(!value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: enabled ? (next) => onChanged(next == true) : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'N/A',
              style: GoogleFonts.inter(
                color: enabled
                    ? Theme.of(context).colorScheme.onSurface
                    : muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedFilePill extends StatelessWidget {
  const _SelectedFilePill({
    required this.fileName,
    required this.border,
    required this.muted,
    required this.onSurface,
    required this.surface,
  });

  final String fileName;
  final Color border;
  final Color muted;
  final Color onSurface;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileText, size: 15, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: onSurface,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.showConnect,
    required this.onConnect,
  });

  final String message;
  final bool showConnect;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  LucideIcons.alertCircle,
                  size: 16,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    color: const Color(0xFFB91C1C),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (showConnect) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onConnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                side: const BorderSide(color: Color(0xFFEF4444)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              child: const Text('Connect Google'),
            ),
          ],
        ],
      ),
    );
  }
}
