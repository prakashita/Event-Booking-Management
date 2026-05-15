import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/common/app_widgets.dart';
import 'package:mobile_app/screens/events/event_approval_screen.dart';
import 'package:provider/provider.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  static const int _maxBudgetPdfBytes = 10 * 1024 * 1024;
  static const String _maxBudgetPdfLabel = '10MB';

  final _nameCtrl = TextEditingController();
  final _facilitatorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _audienceOtherCtrl = TextEditingController();

  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;

  String? _selectedVenueName;
  List<Venue> _venues = [];
  bool _loadingVenues = false;

  final List<String> _selectedAudiences = [];
  PlatformFile? _budgetPdf;
  final bool _submitting = false;

  static const List<String> _audienceOptions = [
    'Students',
    'Faculty',
    'PhD Scholars',
    'Staffs',
    'Everyone at VU',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    final userName =
        Provider.of<AuthProvider>(context, listen: false).user?.name ?? '';
    _facilitatorCtrl.text = userName;
    _loadVenues();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _facilitatorCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _audienceOtherCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVenues() async {
    setState(() => _loadingVenues = true);
    try {
      final data = await _api.get<List<dynamic>>('/venues');
      setState(() {
        _venues = data.map((v) => Venue.fromJson(v)).toList();
        _loadingVenues = false;
      });
    } catch (_) {
      setState(() => _loadingVenues = false);
    }
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      final picked = result.files.first;
      if (picked.size > _maxBudgetPdfBytes) {
        _showErrorSnackBar(
          'Budget PDF must be $_maxBudgetPdfLabel or smaller.',
        );
        return;
      }
      setState(() {
        _budgetPdf = picked;
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
    if (_budgetPdf == null) return true;

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
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
              'Connect Google',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: Text(
              missing.isEmpty
                  ? 'A Google connection is required before continuing with an event that has a budget PDF.'
                  : 'A Google connection is required before continuing with an event that has a budget PDF.\n\nMissing scopes: ${missing.join(', ')}',
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
                    borderRadius: BorderRadius.circular(100),
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
                        content: Text(friendlyErrorMessage(e)),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return false;
    }
  }

  Future<void> _selectAudienceOptions() async {
    final selected = Set<String>.from(_selectedAudiences);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.2)
                              : Colors.black.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Intended Audience',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _selectedAudiences
                                  ..clear()
                                  ..addAll(selected);
                                if (!_selectedAudiences.contains('Others')) {
                                  _audienceOtherCtrl.clear();
                                }
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _audienceOptions.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: theme.dividerColor.withValues(alpha: 0.1),
                          ),
                          itemBuilder: (context, index) {
                            final value = _audienceOptions[index];
                            final checked = selected.contains(value);
                            return CheckboxListTile(
                              value: checked,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 4,
                              ),
                              activeColor: const Color(0xFF2563EB),
                              title: Text(
                                value,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: checked
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.trailing,
                              onChanged: (v) {
                                setSheetState(() {
                                  if (v == true) {
                                    selected.add(value);
                                  } else {
                                    selected.remove(value);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null ||
        _startTime == null ||
        _endDate == null ||
        _endTime == null) {
      _showErrorSnackBar('Please select all dates and times.');
      return;
    }

    if (_selectedVenueName == null) {
      _showErrorSnackBar('Please select a venue.');
      return;
    }

    if (_selectedAudiences.isEmpty) {
      _showErrorSnackBar('Please select an intended audience.');
      return;
    }

    if (_selectedAudiences.contains('Others') &&
        _audienceOtherCtrl.text.trim().isEmpty) {
      _showErrorSnackBar('Please specify the audience in Others.');
      return;
    }

    final budgetVal = double.tryParse(_budgetCtrl.text.trim()) ?? 0.0;
    if (budgetVal > 0 && _budgetPdf == null) {
      _showErrorSnackBar(
        'A Budget Breakdown PDF is required for events with a budget.',
      );
      return;
    }

    final df = DateFormat('yyyy-MM-dd');
    final tf = DateFormat('HH:mm:ss');
    final tStart = DateTime(0, 1, 1, _startTime!.hour, _startTime!.minute);
    final tEnd = DateTime(0, 1, 1, _endTime!.hour, _endTime!.minute);

    final eventData = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'facilitator': _facilitatorCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'venue_name': _selectedVenueName!,
      'intendedAudience': List<String>.from(_selectedAudiences),
      'intendedAudienceOther': _selectedAudiences.contains('Others')
          ? _audienceOtherCtrl.text.trim()
          : null,
      'budget': budgetVal > 0 ? budgetVal : null,
      'start_date': df.format(_startDate!),
      'start_time': tf.format(tStart),
      'end_date': df.format(_endDate!),
      'end_time': tf.format(tEnd),
      'override_conflict': false,
    };

    try {
      final conflictRes = await _api.post<Map<String, dynamic>>(
        '/events/conflicts',
        data: eventData,
      );
      if (!mounted) return;
      final conflicts = conflictRes['conflicts'];
      if (conflicts is List && conflicts.isNotEmpty) {
        _showConflictDialog(eventData: eventData, conflicts: conflicts);
        return;
      }
    } on DioException catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
        friendlyErrorMessage(
          e,
          fallback: 'Unable to check schedule conflicts.',
        ),
      );
      return;
    }

    if (!mounted) return;
    _openApprovalScreen(eventData, overrideConflict: false);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatConflictTime(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    try {
      final parsed = DateFormat('HH:mm:ss').parseStrict(raw);
      return DateFormat('h:mm a').format(parsed);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _openApprovalScreen(
    Map<String, dynamic> eventData, {
    required bool overrideConflict,
  }) async {
    final googleReady = await _ensureGoogleConnectedForBudgetPdf();
    if (!mounted || !googleReady) return;

    final payload = {...eventData, 'override_conflict': overrideConflict};
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            EventApprovalScreen(eventData: payload, budgetPdf: _budgetPdf),
      ),
    );
  }

  void _showConflictDialog({
    required Map<String, dynamic> eventData,
    required List<dynamic> conflicts,
  }) {
    final theme = Theme.of(context);
    final text = theme.colorScheme.onSurface;
    final cardBg = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.5,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.alertTriangle,
                        color: AppColors.error,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Schedule Conflict',
                        style: GoogleFonts.poppins(
                          color: text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'The following event(s) are already scheduled at the selected time:',
                  style: GoogleFonts.inter(
                    color: text.withValues(alpha: 0.8),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: conflicts.map((c) {
                        final conflict = c is Map<String, dynamic>
                            ? c
                            : Map<String, dynamic>.from(c as Map);
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: theme.dividerColor.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (conflict['name'] ?? '').toString(),
                                style: GoogleFonts.inter(
                                  color: text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(
                                    LucideIcons.clock,
                                    size: 14,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${(conflict['start_date'] ?? '').toString()} • ${_formatConflictTime(conflict['start_time'])}',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF64748B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    LucideIcons.mapPin,
                                    size: 14,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      (conflict['venue_name'] ?? '').toString(),
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF64748B),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
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
                const SizedBox(height: 16),
                Text(
                  'Would you like to reschedule your event or override this conflict?',
                  style: GoogleFonts.inter(
                    color: text.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 360;
                    final buttons = [
                      _dialogButton(
                        label: 'Cancel',
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          context.go('/events');
                        },
                        isGhost: true,
                      ),
                      _dialogButton(
                        label: 'Reschedule',
                        onPressed: () => Navigator.of(ctx).pop(),
                        isSecondary: true,
                      ),
                      _dialogButton(
                        label: 'Override',
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _openApprovalScreen(
                            eventData,
                            overrideConflict: true,
                          );
                        },
                      ),
                    ];

                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          buttons[2],
                          const SizedBox(height: 12),
                          buttons[1],
                          const SizedBox(height: 12),
                          buttons[0],
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: buttons[0]),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: buttons[1]),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: buttons[2]),
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

  Widget _dialogButton({
    required String label,
    required VoidCallback onPressed,
    bool isSecondary = false,
    bool isGhost = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isGhost) {
      return TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final bg = isSecondary
        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
        : AppColors.error;
    final fg = isSecondary ? theme.colorScheme.onSurface : Colors.white;

    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFF64748B).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.02),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildCardHeader(IconData icon, String title) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 16),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {IconData? prefixIcon}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Soft, premium filled inputs
    final fillColor = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF1F5F9);
    final hintColor = isDark
        ? const Color(0xFF475569)
        : const Color(0xFF94A3B8);
    final iconColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: hintColor,
        fontSize: 15,
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      prefixIcon: prefixIcon != null
          ? Padding(
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Icon(prefixIcon, size: 18, color: iconColor),
            )
          : null,
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = theme.brightness == Brightness.dark;

    // Premium subtle background
    final pageBg = isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC);
    final surface = theme.colorScheme.surface;
    final heading = theme.colorScheme.onSurface;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardOpen = keyboardInset > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          padding: const EdgeInsets.only(left: 16),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/events');
            }
          },
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.arrowLeft,
              size: 20,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        title: Text(
          'Create Event',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: heading,
          ),
        ),
        actions: [
          IconButton(
            padding: const EdgeInsets.only(right: 16),
            onPressed: () {
              final next = isDark ? 'light' : 'dark';
              themeProvider.setThemeModeByValue(next);
            },
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDark ? LucideIcons.sun : LucideIcons.moon,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          ),
        ],
      ),
      body: SafeArea(
        child: LoadingOverlay(
          isLoading: _submitting,
          message: 'Creating event...',
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    24,
                    20,
                    isKeyboardOpen ? keyboardInset + 24 : 24,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // CARD 1: DATE & TIME
                        _buildCard(
                          children: [
                            _buildCardHeader(LucideIcons.calendar, 'Schedule'),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Start Date'),
                                      InkWell(
                                        onTap: () async {
                                          final d = await showDatePicker(
                                            context: context,
                                            initialDate: DateTime.now(),
                                            firstDate: DateTime.now(),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365),
                                            ),
                                          );
                                          if (d != null) {
                                            setState(() => _startDate = d);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: IgnorePointer(
                                          child: TextFormField(
                                            key: ValueKey(_startDate),
                                            initialValue: _startDate != null
                                                ? df.format(_startDate!)
                                                : '',
                                            decoration: _inputDecoration(
                                              'Select date',
                                              prefixIcon: LucideIcons.calendar,
                                            ),
                                            validator: (v) => _startDate == null
                                                ? 'Required'
                                                : null,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: heading,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('Start Time'),
                                      InkWell(
                                        onTap: () async {
                                          final t = await showTimePicker(
                                            context: context,
                                            initialTime: TimeOfDay.now(),
                                          );
                                          if (t != null) {
                                            setState(() => _startTime = t);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: IgnorePointer(
                                          child: TextFormField(
                                            key: ValueKey(_startTime),
                                            initialValue:
                                                _startTime?.format(context) ??
                                                '',
                                            decoration: _inputDecoration(
                                              'Select time',
                                              prefixIcon: LucideIcons.clock,
                                            ),
                                            validator: (v) => _startTime == null
                                                ? 'Required'
                                                : null,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: heading,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('End Date'),
                                      InkWell(
                                        onTap: () async {
                                          final d = await showDatePicker(
                                            context: context,
                                            initialDate:
                                                _startDate ?? DateTime.now(),
                                            firstDate:
                                                _startDate ?? DateTime.now(),
                                            lastDate: DateTime.now().add(
                                              const Duration(days: 365),
                                            ),
                                          );
                                          if (d != null) {
                                            setState(() => _endDate = d);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: IgnorePointer(
                                          child: TextFormField(
                                            key: ValueKey(_endDate),
                                            initialValue: _endDate != null
                                                ? df.format(_endDate!)
                                                : '',
                                            decoration: _inputDecoration(
                                              'Select date',
                                              prefixIcon: LucideIcons.calendar,
                                            ),
                                            validator: (v) => _endDate == null
                                                ? 'Required'
                                                : null,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: heading,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildLabel('End Time'),
                                      InkWell(
                                        onTap: () async {
                                          final t = await showTimePicker(
                                            context: context,
                                            initialTime:
                                                _startTime ?? TimeOfDay.now(),
                                          );
                                          if (t != null) {
                                            setState(() => _endTime = t);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: IgnorePointer(
                                          child: TextFormField(
                                            key: ValueKey(_endTime),
                                            initialValue:
                                                _endTime?.format(context) ?? '',
                                            decoration: _inputDecoration(
                                              'Select time',
                                              prefixIcon: LucideIcons.clock,
                                            ),
                                            validator: (v) => _endTime == null
                                                ? 'Required'
                                                : null,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: heading,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // CARD 2: EVENT DETAILS
                        _buildCard(
                          children: [
                            _buildCardHeader(LucideIcons.fileText, 'Details'),
                            _buildLabel('Event Name'),
                            TextFormField(
                              controller: _nameCtrl,
                              decoration: _inputDecoration(
                                'e.g. Annual Tech Conference 2026',
                              ),
                              validator: (v) => (v?.trim().isEmpty ?? true)
                                  ? 'Required'
                                  : null,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: heading,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildLabel('Facilitator'),
                            TextFormField(
                              controller: _facilitatorCtrl,
                              decoration: _inputDecoration(
                                'Facilitator Name',
                                prefixIcon: LucideIcons.user,
                              ),
                              validator: (v) => (v?.trim().isEmpty ?? true)
                                  ? 'Required'
                                  : null,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: heading,
                              ),
                            ),
                          ],
                        ),

                        // CARD 3: VENUE & AUDIENCE
                        _buildCard(
                          children: [
                            _buildCardHeader(
                              LucideIcons.mapPin,
                              'Location & Audience',
                            ),
                            _buildLabel('Venue'),
                            _loadingVenues
                                ? const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : DropdownButtonFormField<String>(
                                    initialValue: _selectedVenueName,
                                    decoration: _inputDecoration(
                                      'Select a Venue',
                                      prefixIcon: LucideIcons.mapPin,
                                    ),
                                    icon: const Icon(
                                      LucideIcons.chevronDown,
                                      size: 20,
                                      color: Color(0xFF94A3B8),
                                    ),
                                    dropdownColor: theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    items: _venues
                                        .map(
                                          (v) => DropdownMenuItem(
                                            value: v.name,
                                            child: Text(
                                              v.name,
                                              style: GoogleFonts.inter(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => _selectedVenueName = v),
                                    validator: (v) =>
                                        v == null ? 'Required' : null,
                                  ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8, left: 4),
                              child: Text(
                                'Make sure the venue is verified in DigiCampus.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildLabel('Intended Audience'),
                            InkWell(
                              onTap: _selectAudienceOptions,
                              borderRadius: BorderRadius.circular(16),
                              child: InputDecorator(
                                decoration:
                                    _inputDecoration(
                                      'Select Audience (Multi)',
                                      prefixIcon: LucideIcons.users,
                                    ).copyWith(
                                      suffixIcon: const Padding(
                                        padding: EdgeInsets.only(right: 16),
                                        child: Icon(
                                          LucideIcons.chevronDown,
                                          size: 20,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ),
                                child: Text(
                                  _selectedAudiences.isEmpty
                                      ? 'Select audience (multi)'
                                      : _selectedAudiences.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: _selectedAudiences.isEmpty
                                        ? FontWeight.w400
                                        : FontWeight.w600,
                                    color: _selectedAudiences.isEmpty
                                        ? (isDark
                                              ? const Color(0xFF475569)
                                              : const Color(0xFF94A3B8))
                                        : heading,
                                  ),
                                ),
                              ),
                            ),
                            if (_selectedAudiences.contains('Others')) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _audienceOtherCtrl,
                                decoration: _inputDecoration(
                                  'Specify other audience...',
                                ),
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: heading,
                                ),
                                maxLength: 500,
                                validator: (v) {
                                  if (_selectedAudiences.contains('Others') &&
                                      (v?.trim().isEmpty ?? true)) {
                                    return 'Required';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ],
                        ),

                        // CARD 4: DESCRIPTION & BUDGET
                        _buildCard(
                          children: [
                            _buildCardHeader(
                              LucideIcons.alignLeft,
                              'Overview & Budget',
                            ),
                            _buildLabel('Description'),
                            TextFormField(
                              controller: _descCtrl,
                              decoration: _inputDecoration(
                                'Add a short overview of the event...',
                              ),
                              maxLines: 4,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                height: 1.5,
                                color: heading,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 24,
                                right: 4,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Max 2000 chars',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ),
                            _buildLabel('Budget (RS)'),
                            TextFormField(
                              controller: _budgetCtrl,
                              keyboardType: TextInputType.number,
                              decoration: _inputDecoration('e.g. 50000')
                                  .copyWith(
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 20,
                                        right: 8,
                                      ),
                                      child: Text(
                                        '₹',
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 0,
                                      minHeight: 0,
                                    ),
                                  ),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: heading,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Row(
                              children: [
                                Text(
                                  'Budget Breakdown PDF',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'REQUIRED',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.error,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Upload a PDF with your budget breakdown. It will be stored automatically using the event name and date.',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF94A3B8),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            InkWell(
                              onTap: _pickPdf,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 32,
                                  horizontal: 20,
                                ),
                                decoration: BoxDecoration(
                                  color: _budgetPdf == null
                                      ? (isDark
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFFF1F5F9))
                                      : (isDark
                                            ? const Color(
                                                0xFF1E3A8A,
                                              ).withValues(alpha: 0.3)
                                            : const Color(0xFFEFF6FF)),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _budgetPdf == null
                                        ? (isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.1,
                                                )
                                              : Colors.black.withValues(
                                                  alpha: 0.05,
                                                ))
                                        : const Color(0xFF3B82F6),
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _budgetPdf == null
                                          ? LucideIcons.uploadCloud
                                          : LucideIcons.fileCheck,
                                      size: 36,
                                      color: _budgetPdf == null
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF2563EB),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _budgetPdf == null
                                          ? 'Tap to upload PDF'
                                          : _budgetPdf!.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: _budgetPdf == null
                                            ? (isDark
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF64748B))
                                            : const Color(0xFF2563EB),
                                      ),
                                    ),
                                  ],
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

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: isKeyboardOpen
                    ? const SizedBox.shrink()
                    : _CreateEventActionBar(
                        surface: surface,
                        isDark: isDark,
                        onSubmit: _submit,
                        onCancel: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/events');
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateEventActionBar extends StatelessWidget {
  final Color surface;
  final bool isDark;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _CreateEventActionBar({
    required this.surface,
    required this.isDark,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.6)
                : const Color(0xFF94A3B8).withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(LucideIcons.arrowRightCircle, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Continue to Approval',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Cancel & Go Back',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
