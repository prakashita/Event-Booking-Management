import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

import '../../constants/app_colors.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';
import '../../providers/auth_provider.dart';
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
  bool _confirmed = false;
  bool _loadingApprovalEmails = true;

  String _registrarEmail = "";
  String _viceChancellorEmail = "";

  @override
  void initState() {
    super.initState();
    _loadApprovalEmails();
  }

  Future<void> _loadApprovalEmails() async {
    try {
      final data = await _api.get<Map<String, dynamic>>(
        '/auth/event-approval-emails',
      );
      if (!mounted) return;
      setState(() {
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
    final budget = widget.eventData['budget'] as num? ?? 0;
    final isHighBudget = budget > _budgetThreshold;

    if (_loadingApprovalEmails) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Loading approval routing emails. Please wait.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_registrarEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Registrar email is not configured. Please ask admin to assign a registrar user.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (isHighBudget && _viceChancellorEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vice Chancellor email is not configured for events above Rs 30,000.',
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
      final toEmail = isHighBudget ? _viceChancellorEmail : _registrarEmail;
      final payload = {
        ...widget.eventData,
        'approval_to': toEmail,
        'discussedWithProgrammingChair': true,
        'submit_for_approval': true,
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
            content: Text(uploadWarning ?? 'Event submitted successfully!'),
          ),
        );
        context.go('/events');
      }
    } on DioException catch (e) {
      if (mounted) {
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userEmail = authProvider.user?.email ?? 'partha.worklife@gmail.com';

    final budget = widget.eventData['budget'] as num? ?? 0;
    final isHighBudget = budget > _budgetThreshold;
    final toEmail = isHighBudget ? _viceChancellorEmail : _registrarEmail;
    final ccEmail = isHighBudget ? _registrarEmail : _viceChancellorEmail;
    final canSend =
        !_loadingApprovalEmails &&
        _registrarEmail.isNotEmpty &&
        (!isHighBudget || _viceChancellorEmail.isNotEmpty);

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
                                isHighBudget
                                    ? 'Vice Chancellor Approval'
                                    : 'Registrar Approval',
                                style: TextStyle(
                                  color: _slate800,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
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
                                      ? (isHighBudget
                                            ? 'Vice Chancellor email'
                                            : 'Registrar email')
                                      : toEmail;
                                  final ccLabel = ccEmail.isEmpty
                                      ? (isHighBudget
                                            ? 'Registrar (not configured)'
                                            : 'Vice Chancellor (optional)')
                                      : ccEmail;
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
                                isHighBudget
                                    ? 'Budget is above Rs ${_budgetThreshold.toStringAsFixed(0)}. The Vice Chancellor will approve or reject this event in the portal. The Registrar is copied on the email for information only. After approval, you can send requirements to Facility, IT, Marketing, and Transport.'
                                    : 'Budget is Rs ${_budgetThreshold.toStringAsFixed(0)} or below. The Registrar will approve or reject this event in the portal. The Vice Chancellor is copied on the email when configured. After approval, you can send requirements to Facility, IT, Marketing, and Transport.',
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
                                  'Approval routing is not fully configured. Please ask admin to assign Registrar/Vice Chancellor users.',
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
                                side: BorderSide(color: _slate200),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                foregroundColor: _slate600,
                              ),
                              onPressed: () => context.pop(),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
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
                                backgroundColor: _indigo600,
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
                              child: const Text(
                                'Send',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
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
