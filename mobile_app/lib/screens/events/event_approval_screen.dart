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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          isHighBudget ? 'Vice Chancellor Approval' : 'Registrar Approval',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.x),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _submitting,
        message: 'Submitting for approval...',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEmailRow('FROM', userEmail),
              const SizedBox(height: 16),
              _buildEmailRow(
                'TO',
                toEmail.isEmpty
                    ? (isHighBudget
                          ? 'Vice Chancellor email'
                          : 'Registrar email')
                    : toEmail,
              ),
              const SizedBox(height: 16),
              _buildEmailRow(
                'CC',
                ccEmail.isEmpty
                    ? (isHighBudget
                          ? 'Registrar (not configured)'
                          : 'Vice Chancellor (optional)')
                    : ccEmail,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),
              _buildEventDetail('Event:', widget.eventData['name']),
              const SizedBox(height: 12),
              _buildEventDetail(
                'Date:',
                '${DateFormat('yyyy-MM-dd').format(startDate)} to ${DateFormat('yyyy-MM-dd').format(endDate)}',
              ),
              const SizedBox(height: 12),
              _buildEventDetail('Time:', '$startTime to $endTime'),
              const SizedBox(height: 24),
              Text(
                isHighBudget
                    ? 'Budget is above Rs ${_budgetThreshold.toStringAsFixed(0)}. The Vice Chancellor will approve or reject this event in the portal. The Registrar is copied on the email for information only. After approval, you can send requirements to Facility, IT, Marketing, and Transport.'
                    : 'Budget is Rs ${_budgetThreshold.toStringAsFixed(0)} or below. The Registrar will approve or reject this event in the portal. The Vice Chancellor is copied on the email when configured. After approval, you can send requirements to Facility, IT, Marketing, and Transport.',
                style: const TextStyle(fontSize: 14, color: Colors.black54),
              ),
              if (!canSend) ...[
                const SizedBox(height: 12),
                const Text(
                  'Approval routing is not fully configured. Please ask admin to assign Registrar/Vice Chancellor users.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _confirmed,
                      onChanged: (val) =>
                          setState(() => _confirmed = val ?? false),
                    ),
                    const Expanded(
                      child: Text(
                        'I have discussed this event with the programming chair and received confirmation to proceed.',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: canSend ? _submit : null,
                    child: const Text('Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailRow(String label, String email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(email, style: const TextStyle(fontSize: 16)),
      ],
    );
  }

  Widget _buildEventDetail(String label, String value) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(child: Text(value)),
      ],
    );
  }
}
