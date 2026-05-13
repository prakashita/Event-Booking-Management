import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/approval_ui.dart';
import '../../services/api_service.dart';
import '../../widgets/common/approval_widgets.dart';
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
      : ApprovalUi.panel;

  Color get _slate100 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF334155)
      : const Color(0xFFF1F5F9);

  Color get _slate200 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF475569)
      : ApprovalUi.border;

  Color get _slate500 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF94A3B8)
      : ApprovalUi.muted;

  Color get _slate600 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFCBD5E1)
      : ApprovalUi.text;

  Color get _slate700 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFE2E8F0)
      : const Color(0xFF334155);

  Color get _slate800 => Theme.of(context).brightness == Brightness.dark
      ? Theme.of(context).colorScheme.onSurface
      : ApprovalUi.heading;

  Color get _indigo600 => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF818CF8)
      : ApprovalUi.accent;

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
          elevation: 24,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFFFEF3C7,
                        ).withValues(alpha: isDark ? 0.1 : 1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.alertTriangle,
                        color: Color(0xFFD97706),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Schedule Conflict',
                        style: GoogleFonts.poppins(
                          color: text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'The following event(s) are already scheduled at the selected time:',
                  style: TextStyle(
                    color: softText,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
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
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.15,
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
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _conflictMetaChip(
                                    label: 'Date',
                                    value: date,
                                    icon: LucideIcons.calendar,
                                    textColor: softText,
                                  ),
                                  _conflictMetaChip(
                                    label: 'Time',
                                    value: time,
                                    icon: LucideIcons.clock,
                                    textColor: softText,
                                  ),
                                  _conflictMetaChip(
                                    label: 'Venue',
                                    value: venue,
                                    icon: LucideIcons.mapPin,
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
                const SizedBox(height: 8),
                Text(
                  'Would you like to reschedule your event or override this conflict?',
                  style: TextStyle(
                    color: softText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360;
                    final children = [
                      _conflictActionButton(
                        label: 'Reschedule',
                        bg: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                        fg: text,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).pop();
                        },
                      ),
                      _conflictActionButton(
                        label: 'Cancel',
                        bg: Colors.transparent,
                        fg: softText,
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          context.go('/events');
                        },
                      ),
                      _conflictActionButton(
                        label: 'Override',
                        bg: const Color(0xFFEF4444).withValues(alpha: 0.1),
                        fg: const Color(0xFFEF4444),
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
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        children[1],
                        const SizedBox(width: 8),
                        children[0],
                        const SizedBox(width: 8),
                        children[2],
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
    required IconData icon,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
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

  Future<void> _connectGoogle() async {
    final res = await _api.get<Map<String, dynamic>>('/calendar/connect-url');
    final url = res['url']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw Exception('Failed to obtain Google connect URL.');
    }

    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!opened) {
      throw Exception('Could not open the Google consent page.');
    }
  }

  Future<bool> _ensureGoogleConnectedForBudgetPdf() async {
    if (widget.budgetPdf == null) return true;

    try {
      final status = await _api.get<Map<String, dynamic>>(
        '/auth/google/status',
      );
      final connected = status['connected'] == true;
      if (connected) return true;

      final missing = List<String>.from(status['missing_scopes'] ?? const []);
      if (!mounted) return false;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Connect Google',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(
              missing.isEmpty
                  ? 'A Google connection is required before submitting an event with a budget PDF.'
                  : 'A Google connection is required before submitting an event with a budget PDF.\n\nMissing scopes: ${missing.join(', ')}',
              style: const TextStyle(height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  try {
                    await _connectGoogle();
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
                },
                child: const Text('Connect Google'),
              ),
            ],
          );
        },
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not verify Google connection: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  Future<void> _submit() async {
    if (_loadingApprovalEmails) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading approval routing emails. Please wait.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
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
          behavior: SnackBarBehavior.floating,
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
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final googleReady = await _ensureGoogleConnectedForBudgetPdf();
    if (!googleReady) return;

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
            throw Exception(
              'Google connection is required to upload the budget PDF.',
            );
          }
          uploadWarning =
              'Event was sent, but budget PDF upload failed: $detail';
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
            behavior: SnackBarBehavior.floating,
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
          SnackBar(
            content: Text(detail),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 430;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userEmail = authProvider.user?.email ?? 'partha.worklife@gmail.com';

    final toEmail = _deputyRegistrarEmail;
    final ccEmails = [
      _financeTeamEmail,
      _registrarEmail,
      _viceChancellorEmail,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    final ccLabel = ccEmails.isEmpty
        ? 'Finance Team / Registrar / VC (auto-configured)'
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
      resizeToAvoidBottomInset: false,
      backgroundColor: _pageBg,
      body: LoadingOverlay(
        isLoading: _submitting,
        message: 'Submitting for approval...',
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: isCompact ? 8 : 16,
                  vertical: isCompact ? 12 : 24,
                ),
                child: ApprovalCardShell(
                  padding: EdgeInsets.zero,
                  backgroundColor: _cardBg,
                  borderColor: isDark
                      ? _slate100.withValues(alpha: 0.5)
                      : ApprovalUi.border,
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.4)
                          : const Color(0x0A0F172A),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                    BoxShadow(
                      color: isDark
                          ? Colors.transparent
                          : const Color(0x050F172A),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Section
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          isCompact ? 20 : 28,
                          isCompact ? 20 : 24,
                          isCompact ? 14 : 20,
                          isCompact ? 16 : 20,
                        ),
                        child: Row(
                          children: [
                            ApprovalIconTile(
                              icon: LucideIcons.send,
                              size: isCompact ? 38 : 40,
                              iconSize: 20,
                              backgroundColor: _indigo600.withValues(
                                alpha: 0.1,
                              ),
                              foregroundColor: _indigo600,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                'Deputy Registrar Approval',
                                style: GoogleFonts.plusJakartaSans(
                                  color: _slate800,
                                  fontSize: isCompact ? 17 : 20,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                isDark ? LucideIcons.sun : LucideIcons.moon,
                                color: isDark
                                    ? const Color(0xFFFBBF24)
                                    : _slate600,
                                size: 20,
                              ),
                              onPressed: () {
                                final next = isDark ? 'light' : 'dark';
                                themeProvider.setThemeModeByValue(next);
                              },
                              tooltip: isDark ? 'Light mode' : 'Dark mode',
                            ),
                            IconButton(
                              icon: Icon(
                                LucideIcons.x,
                                color: _slate500,
                                size: 22,
                              ),
                              onPressed: () => context.pop(),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: _slate100, thickness: 1),

                      // Body Section
                      Flexible(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 20 : 28,
                            vertical: isCompact ? 20 : 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Email Routing Info
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final useColumns =
                                      constraints.maxWidth >= 520;
                                  final toLabel = toEmail.isEmpty
                                      ? 'Pending config...'
                                      : toEmail;

                                  if (!useColumns) {
                                    return Column(
                                      children: [
                                        _buildRoutingField(
                                          'FROM',
                                          userEmail,
                                          LucideIcons.user,
                                          compact: isCompact,
                                        ),
                                        SizedBox(height: isCompact ? 10 : 12),
                                        _buildRoutingField(
                                          'TO',
                                          toLabel,
                                          LucideIcons.mail,
                                          compact: isCompact,
                                        ),
                                        SizedBox(height: isCompact ? 10 : 12),
                                        _buildRoutingField(
                                          'CC',
                                          ccLabel,
                                          LucideIcons.copy,
                                          compact: isCompact,
                                        ),
                                      ],
                                    );
                                  }
                                  return Column(
                                    children: [
                                      _buildRoutingField(
                                        'FROM',
                                        userEmail,
                                        LucideIcons.user,
                                        compact: isCompact,
                                      ),
                                      SizedBox(height: isCompact ? 10 : 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildRoutingField(
                                              'TO',
                                              toLabel,
                                              LucideIcons.mail,
                                              compact: isCompact,
                                            ),
                                          ),
                                          SizedBox(width: isCompact ? 10 : 12),
                                          Expanded(
                                            child: _buildRoutingField(
                                              'CC',
                                              ccLabel,
                                              LucideIcons.copy,
                                              compact: isCompact,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                              SizedBox(height: isCompact ? 20 : 28),

                              // Event Summary Card
                              ApprovalPanelBox(
                                padding: EdgeInsets.all(isCompact ? 16 : 20),
                                borderColor: _slate200.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(16),
                                backgroundColor: _slate50,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Event Summary',
                                      style: TextStyle(
                                        fontSize: isCompact ? 11 : 12,
                                        fontWeight: FontWeight.w700,
                                        color: _slate500,
                                        letterSpacing: 1.2,
                                        // textTransform: uppercase (simulated visually)
                                      ),
                                    ),
                                    SizedBox(height: isCompact ? 12 : 16),
                                    _buildEventDetailRow(
                                      LucideIcons.tag,
                                      'Event Name',
                                      widget.eventData['name']?.toString() ??
                                          '',
                                      compact: isCompact,
                                    ),
                                    SizedBox(height: isCompact ? 10 : 12),
                                    _buildEventDetailRow(
                                      LucideIcons.calendar,
                                      'Date',
                                      '${DateFormat('MMM d, yyyy').format(startDate)} — ${DateFormat('MMM d, yyyy').format(endDate)}',
                                      compact: isCompact,
                                    ),
                                    SizedBox(height: isCompact ? 10 : 12),
                                    _buildEventDetailRow(
                                      LucideIcons.clock,
                                      'Time',
                                      '$startTime to $endTime',
                                      compact: isCompact,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: isCompact ? 18 : 24),

                              // Information Callout Banner
                              Container(
                                padding: EdgeInsets.all(isCompact ? 14 : 16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFBFDBFE),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      LucideIcons.info,
                                      size: 20,
                                      color: isDark
                                          ? const Color(0xFF60A5FA)
                                          : const Color(0xFF2563EB),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Stage 1 routes to Deputy Registrar. Subsequent stages involve Finance, and finally the Registrar/Vice Chancellor depending on the budget (Threshold: Rs ${_budgetThreshold.toStringAsFixed(0)}).',
                                        style: TextStyle(
                                          color: isDark
                                              ? const Color(0xFFE2E8F0)
                                              : const Color(0xFF1E3A8A),
                                          fontSize: isCompact ? 12.5 : 13.5,
                                          height: 1.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Error Callout Banner (if config missing)
                              if (!canSend && !_loadingApprovalEmails) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: EdgeInsets.all(isCompact ? 14 : 16),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF451A1A)
                                        : const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF7F1D1D)
                                          : const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        LucideIcons.alertCircle,
                                        size: 20,
                                        color: isDark
                                            ? const Color(0xFFFCA5A5)
                                            : const Color(0xFFDC2626),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Approval routing is not fully configured. Please contact the administrator to assign the necessary roles.',
                                          style: TextStyle(
                                            color: isDark
                                                ? const Color(0xFFFECACA)
                                                : const Color(0xFF991B1B),
                                            fontSize: isCompact ? 12.5 : 13.5,
                                            height: 1.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              SizedBox(height: isCompact ? 18 : 24),

                              // Confirmation Checkbox
                              InkWell(
                                onTap: () =>
                                    setState(() => _confirmed = !_confirmed),
                                borderRadius: BorderRadius.circular(16),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: double.infinity,
                                  padding: EdgeInsets.all(isCompact ? 14 : 16),
                                  decoration: BoxDecoration(
                                    color: _confirmed
                                        ? (isDark
                                              ? _indigo600.withValues(
                                                  alpha: 0.15,
                                                )
                                              : const Color(0xFFEEF2FF))
                                        : _slate50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: _confirmed
                                          ? _indigo600.withValues(alpha: 0.5)
                                          : _slate200,
                                      width: _confirmed ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        width: 24,
                                        height: 24,
                                        margin: const EdgeInsets.only(top: 2),
                                        decoration: BoxDecoration(
                                          color: _confirmed
                                              ? _indigo600
                                              : (isDark
                                                    ? _cardBg
                                                    : Colors.white),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: _confirmed
                                                ? _indigo600
                                                : _slate500.withValues(
                                                    alpha: 0.5,
                                                  ),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: _confirmed
                                            ? const Icon(
                                                LucideIcons.check,
                                                size: 16,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Text(
                                          'I have discussed this event with the programming chair and received confirmation to proceed.',
                                          style: TextStyle(
                                            color: _confirmed
                                                ? _slate800
                                                : _slate700,
                                            fontSize: isCompact ? 13 : 14.5,
                                            height: 1.5,
                                            fontWeight: _confirmed
                                                ? FontWeight.w600
                                                : FontWeight.w500,
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
                      ),

                      Divider(height: 1, color: _slate100, thickness: 1),

                      // Bottom Action Bar
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 16 : 28,
                          vertical: isCompact ? 12 : 20,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? _slate50 : const Color(0xFFFAFAFA),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(24),
                            bottomRight: Radius.circular(24),
                          ),
                        ),
                        child: isCompact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Primary action — full width on mobile
                                  SizedBox(
                                    height: 52,
                                    child: FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _indigo600,
                                        disabledBackgroundColor: _indigo600
                                            .withValues(alpha: 0.4),
                                        foregroundColor: Colors.white,
                                        disabledForegroundColor: Colors.white
                                            .withValues(alpha: 0.5),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed: (canSend && _confirmed)
                                          ? _submit
                                          : null,
                                      icon: const Icon(
                                        LucideIcons.send,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'Send Request',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  // Secondary action — full width outlined on mobile
                                  SizedBox(
                                    height: 48,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _slate600,
                                        side: BorderSide(
                                          color: _slate200,
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      onPressed: () => context.pop(),
                                      child: Text(
                                        'Cancel',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 16,
                                      ),
                                      foregroundColor: _slate600,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () => context.pop(),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 28,
                                        vertical: 16,
                                      ),
                                      backgroundColor: _indigo600,
                                      disabledBackgroundColor: _slate200,
                                      foregroundColor: Colors.white,
                                      disabledForegroundColor: _slate500,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: (canSend && _confirmed)
                                        ? _submit
                                        : null,
                                    icon: const Icon(
                                      LucideIcons.send,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Send Request',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
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

  Widget _buildRoutingField(
    String label,
    String value,
    IconData icon, {
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 16,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: _slate50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _slate200.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 5 : 6),
            decoration: BoxDecoration(
              color: _slate200.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: compact ? 13 : 14, color: _slate500),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    color: _slate500,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: compact ? 1 : 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    color: _slate700,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventDetailRow(
    IconData icon,
    String label,
    String value, {
    bool compact = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: compact ? 16 : 18, color: _slate500),
        SizedBox(width: compact ? 10 : 12),
        SizedBox(
          width: compact ? 72 : 80,
          child: Text(
            label,
            style: TextStyle(
              color: _slate600,
              fontWeight: FontWeight.w500,
              fontSize: compact ? 13 : 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: _slate800,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 13 : 14,
            ),
          ),
        ),
      ],
    );
  }
}
