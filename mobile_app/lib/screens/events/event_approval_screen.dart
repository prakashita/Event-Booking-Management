import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import 'package:provider/provider.dart';

class EventApprovalScreen extends StatefulWidget {
  final Map<String, dynamic> eventData;
  final PlatformFile? budgetPdf;

  const EventApprovalScreen({
    super.key,
    required this.eventData,
    this.budgetPdf,
  });

  @override
  State<EventApprovalScreen> createState() => _EventApprovalScreenState();
}

class _EventApprovalScreenState extends State<EventApprovalScreen> {
  final _api = ApiService();
  static const double _budgetThreshold = 30000;

  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;

  Color get _cardBg => Theme.of(context).colorScheme.surface;

  Color get _slate50 => Theme.of(context).brightness == Brightness.dark
      ? Theme.of(context).colorScheme.surfaceContainerHighest
      : const Color(0xFFF8FAFC);

  Color get _slate100 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF334155)
      : const Color(0xFFF1F5F9);

  Color get _slate200 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF334155)
      : const Color(0xFFE2E8F0);

  Color get _slate500 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF94A3B8)
      : const Color(0xFF64748B);

  Color get _slate600 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFCBD5E1)
      : const Color(0xFF475569);

  Color get _slate700 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFE2E8F0)
      : const Color(0xFF334155);

  Color get _slate800 => Theme.of(context).colorScheme.onSurface;

  Color get _indigo600 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF6366F1)
      : const Color(0xFF521EEA);
  bool _submitting = false;
  bool _overrideConflict = false;
  bool _confirmed = false;
  bool _loadingApprovalEmails = true;

  String _deputyRegistrarEmail = "";
  String _financeTeamEmail = "";
  String _registrarEmail = "";
  String _viceChancellorEmail = "";

  void _showConflictDialog(List<dynamic> conflicts) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    final text = theme.colorScheme.onSurface;
    final softText = text.withValues(alpha: 0.7);
    final panel = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerLow;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(
                            0xFFF59E0B,
                          ).withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Icon(
                        Icons.priority_high,
                        color: Color(0xFFD97706),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Schedule Conflict',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'The following event(s) are already scheduled at the selected time:',
                  style: TextStyle(
                    color: AppColors.error.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: SingleChildScrollView(
                    child: Column(
                      children: conflicts.map((c) {
                        final mapData = c as Map<String, dynamic>;
                        final name = (mapData['name'] ?? 'Untitled').toString();
                        final date = (mapData['start_date'] ?? '').toString();
                        final time = (mapData['start_time'] ?? '').toString();
                        final venue = (mapData['venue_name'] ?? '').toString();

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _conflictMetaChip(
                                    label: 'Date',
                                    value: date,
                                    textColor: softText,
                                  ),
                                  _conflictMetaChip(
                                    label: 'Time',
                                    value: time,
                                    textColor: softText,
                                  ),
                                  _conflictMetaChip(
                                    label: 'Venue',
                                    value: venue,
                                    textColor: softText,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Would you like to reschedule your event or override this conflict?',
                  style: TextStyle(
                    color: AppColors.error.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360;
                    final children = [
                      _conflictActionButton(
                        label: 'Reschedule',
                        bg: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        fg: const Color(0xFF4F46E5),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).pop();
                        },
                      ),
                      _conflictActionButton(
                        label: 'Cancel',
                        bg: theme.colorScheme.surfaceContainerHighest,
                        fg: text,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          context.go('/events');
                        },
                      ),
                      _conflictActionButton(
                        label: 'Override',
                        bg: const Color(0xFF6366F1).withValues(alpha: 0.2),
                        fg: const Color(0xFF4F46E5),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          setState(() => _overrideConflict = true);
                          _submit();
                        },
                      ),
                    ];

                    if (compact) {
                      return Column(
                        children: [
                          for (final button in children) ...[
                            SizedBox(width: double.infinity, child: button),
                            if (button != children.last)
                              const SizedBox(height: 8),
                          ],
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: children[0]),
                        const SizedBox(width: 8),
                        Expanded(child: children[1]),
                        const SizedBox(width: 8),
                        Expanded(child: children[2]),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _conflictMetaChip({
    required String label,
    required String value,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _conflictActionButton({
    required String label,
    required Color bg,
    required Color fg,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  @override
  void initState() {
    super.initState();
    _overrideConflict = widget.eventData['override_conflict'] == true;
    _loadApprovalEmails();
  }

  Future<void> _loadApprovalEmails() async {
    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/auth/event-approval-emails',
      );
      if (!mounted) return;
      setState(() {
        _deputyRegistrarEmail = (data['deputy_registrar_email'] ?? '')
            .toString()
            .trim();
        _financeTeamEmail = (data['finance_team_email'] ?? '')
            .toString()
            .trim();
        _registrarEmail = (data['registrar_email'] ?? '').toString().trim();
        _viceChancellorEmail = (data['vice_chancellor_email'] ?? '')
            .toString()
            .trim();
        _loadingApprovalEmails = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingApprovalEmails = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_loadingApprovalEmails) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading approval routing emails. Please wait.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_deputyRegistrarEmail.isEmpty ||
        _financeTeamEmail.isEmpty ||
        _registrarEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Approval routing is not fully configured. Please ask admin to assign Deputy Registrar, Finance Team, and Registrar users.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (!_confirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please confirm you have discussed this with the programming chair.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final payload = {
        ...widget.eventData,
        'override_conflict': _overrideConflict,
        'discussedWithProgrammingChair': true,
        'requirements': const <String>[],
        'other_notes': '',
      };

      final data = await _api.post<Map<String, dynamic>>(
        '/events',
        data: payload,
      );

      String? uploadWarning;

      if (widget.budgetPdf != null &&
          data.containsKey('approval_request') &&
          data['approval_request'] != null) {
        try {
          final approvalId = data['approval_request']['id'];
          final formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              widget.budgetPdf!.path!,
              filename: widget.budgetPdf!.name,
            ),
          });
          await _api.postMultipart(
            '/approvals/$approvalId/budget-breakdown',
            formData,
          );
        } on DioException catch (e) {
          final detail = e.response?.data is Map<String, dynamic>
              ? (e.response?.data['detail']?.toString() ??
                    e.message ??
                    'Unable to upload budget breakdown PDF')
              : (e.message ?? 'Unable to upload budget breakdown PDF');
          if ((e.response?.statusCode ?? 0) == 403) {
            uploadWarning =
                'Event was sent, but budget PDF upload failed: Google not connected. Connect Google account, then upload the budget PDF from pending approval.';
          } else {
            uploadWarning =
                'Event was sent, but budget PDF upload failed: $detail';
          }
        } catch (e) {
          uploadWarning = 'Event was sent, but budget PDF upload failed: $e';
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uploadWarning ??
                  'Event submitted to Deputy Registrar for stage 1 approval.',
            ),
          ),
        );
        context.go('/events');
      }
    } on DioException catch (e) {
      if (mounted) {
        if (e.response?.statusCode == 409) {
          final conflictData = e.response?.data;
          if (conflictData is Map<String, dynamic> &&
              conflictData.containsKey('conflicts')) {
            _showConflictDialog(conflictData['conflicts'] as List<dynamic>);
            return;
          }
        }

        final detail = e.response?.data is Map<String, dynamic>
            ? (e.response?.data['detail']?.toString() ??
                  e.message ??
                  'Request failed')
            : (e.message ?? 'Request failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(detail), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userEmail = authProvider.user?.email ?? 'partha.worklife@gmail.com';

    final toEmail = _deputyRegistrarEmail;
    final ccEmails = [
      _financeTeamEmail,
      _registrarEmail,
      _viceChancellorEmail,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    final ccLabel = ccEmails.isEmpty
        ? 'Finance Team / Registrar / Vice Chancellor (as configured)'
        : ccEmails.join(', ');
    final canSend =
        !_loadingApprovalEmails &&
        _deputyRegistrarEmail.isNotEmpty &&
        _financeTeamEmail.isNotEmpty &&
        _registrarEmail.isNotEmpty &&
        _confirmed;

    final startDate = DateFormat(
      'yyyy-MM-dd',
    ).parse(widget.eventData['start_date']);
    final endDate = DateFormat(
      'yyyy-MM-dd',
    ).parse(widget.eventData['end_date']);
    final startTime = widget.eventData['start_time'];
    final endTime = widget.eventData['end_time'];

    return Scaffold(
      backgroundColor: _pageBg,
      body: LoadingOverlay(
        isLoading: _submitting,
        message: 'Submitting for approval...',
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A0F172A),
                        blurRadius: 30,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Deputy Registrar Approval (Stage 1)',
                                style: GoogleFonts.poppins(
                                  color: _slate800,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: _slate50,
                              ),
                              icon: Icon(
                                isDark ? LucideIcons.sun : LucideIcons.moon,
                                color: isDark
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF4F46E5),
                                size: 18,
                              ),
                              onPressed: () {
                                final next = isDark ? 'light' : 'dark';
                                themeProvider.setThemeModeByValue(next);
                              },
                              tooltip: isDark
                                  ? 'Switch to light mode'
                                  : 'Switch to dark mode',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: _slate50,
                              ),
                              icon: Icon(
                                LucideIcons.x,
                                color: _slate500,
                                size: 19,
                              ),
                              onPressed: () => context.pop(),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: _slate100),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildReadonlyField(
                                'FROM',
                                userEmail,
                                fullWidth: true,
                              ),
                              const SizedBox(height: 14),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final useColumns =
                                      constraints.maxWidth >= 520;
                                  final toLabel = toEmail.isEmpty
                                      ? 'Deputy Registrar email'
                                      : toEmail;
                                  if (!useColumns) {
                                    return Column(
                                      children: [
                                        _buildReadonlyField('TO', toLabel),
                                        const SizedBox(height: 12),
                                        _buildReadonlyField('CC', ccLabel),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _buildReadonlyField(
                                          'TO',
                                          toLabel,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildReadonlyField(
                                          'CC',
                                          ccLabel,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 22),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: _slate100),
                                    bottom: BorderSide(color: _slate100),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _buildEventDetailRow(
                                      'Event',
                                      widget.eventData['name']?.toString() ??
                                          '',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildEventDetailRow(
                                      'Date',
                                      '${DateFormat('yyyy-MM-dd').format(startDate)} to ${DateFormat('yyyy-MM-dd').format(endDate)}',
                                    ),
                                    const SizedBox(height: 10),
                                    _buildEventDetailRow(
                                      'Time',
                                      '$startTime to $endTime',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Stage 1 routes to Deputy Registrar. After Deputy approval, open My Events and use "Send to finance department for approval". After Finance approval, use "Send to Registrar for approval". Final approver is Registrar for budgets up to Rs ${_budgetThreshold.toStringAsFixed(0)} and Vice Chancellor for higher budgets (with Registrar in CC). Requirements can be sent only after final approval.',
                                style: TextStyle(
                                  color: _slate600,
                                  fontSize: 14,
                                  height: 1.45,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (!canSend) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Approval routing is not fully configured. Please ask admin to assign Deputy Registrar, Finance Team, and Registrar users.',
                                  style: TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              InkWell(
                                onTap: () =>
                                    setState(() => _confirmed = !_confirmed),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _confirmed
                                        ? const Color(0xFFEDE9FE)
                                        : _slate50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: _confirmed
                                          ? const Color(0xFFC4B5FD)
                                          : _slate200,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        margin: const EdgeInsets.only(top: 1),
                                        decoration: BoxDecoration(
                                          color: _confirmed
                                              ? _indigo600
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                          border: Border.all(
                                            color: _confirmed
                                                ? _indigo600
                                                : const Color(0xFFCBD5E1),
                                            width: 1.8,
                                          ),
                                        ),
                                        child: _confirmed
                                            ? const Icon(
                                                LucideIcons.check,
                                                size: 14,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Text(
                                          'I have discussed this event with the programming chair and received confirmation to proceed.',
                                          style: TextStyle(
                                            color: _slate700,
                                            fontSize: 14,
                                            height: 1.45,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                      Divider(height: 1, color: _slate100),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 26,
                                  vertical: 14,
                                ),
                                side: BorderSide(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? const Color(0xFF475569)
                                      : const Color(0xFFDADCE0),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Theme.of(context).brightness == Brightness.dark
                                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                                    : Colors.white,
                                foregroundColor: _slate600,
                              ),
                              onPressed: () => context.pop(),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.roboto(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 14,
                                ),
                                backgroundColor: const Color(0xFF1A73E8),
                                disabledBackgroundColor: const Color(
                                  0xFFB8B0D4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 8,
                                shadowColor: const Color(0x44521EEA),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: (canSend && _confirmed)
                                  ? _submit
                                  : null,
                              child: Text(
                                'Send',
                                style: GoogleFonts.roboto(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadonlyField(
    String label,
    String value, {
    bool fullWidth = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: _slate500,
            letterSpacing: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: fullWidth ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _slate200),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: _slate600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            '$label:',
            style: TextStyle(
              color: _slate800,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: _slate600,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
