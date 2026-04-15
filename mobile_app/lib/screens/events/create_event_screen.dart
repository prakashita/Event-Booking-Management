import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
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

  String? _selectedAudience;
  PlatformFile? _budgetPdf;
  final bool _submitting = false;

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
      setState(() {
        _budgetPdf = result.files.first;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null ||
        _startTime == null ||
        _endDate == null ||
        _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select all dates and times.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_selectedVenueName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a venue.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_selectedAudience == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an intended audience.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_selectedAudience == 'Others' &&
        _audienceOtherCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please specify the audience in Others.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final budgetVal = double.tryParse(_budgetCtrl.text.trim()) ?? 0.0;
    if (budgetVal > 0 && _budgetPdf == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A Budget Breakdown PDF is required for events with a budget.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final df = DateFormat('yyyy-MM-dd');
    final tf = DateFormat('HH:mm:ss');
    final tStart = DateTime(0, 1, 1, _startTime!.hour, _startTime!.minute);
    final tEnd = DateTime(0, 1, 1, _endTime!.hour, _endTime!.minute);

    final eventData = {
      'name': _nameCtrl.text.trim(),
      'facilitator': _facilitatorCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'venue_name': _selectedVenueName!,
      'intendedAudience': <String>[_selectedAudience!],
      'intendedAudienceOther': _selectedAudience == 'Others'
          ? _audienceOtherCtrl.text.trim()
          : null,
      'budget': budgetVal > 0 ? budgetVal : null,
      'start_date': df.format(_startDate!),
      'start_time': tf.format(tStart),
      'end_date': df.format(_endDate!),
      'end_time': tf.format(tEnd),
      'override_conflict': false,
    };

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            EventApprovalScreen(eventData: eventData, budgetPdf: _budgetPdf),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF94A3B8)), // slate-400
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: Color(0xFF475569), // slate-600
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, {IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 14,
        fontWeight: FontWeight.normal,
      ), // slate-400
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: const Color(0xFF94A3B8))
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)), // slate-200
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF3B82F6),
          width: 2,
        ), // blue-500
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444)), // red-500
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        title: Row(
          children: [
            const Icon(
              LucideIcons.calendar,
              color: Color(0xFF2563EB),
              size: 24,
            ), // blue-600
            const SizedBox(width: 12),
            const Text(
              'Create Event',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B), // slate-800
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
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
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                LucideIcons.x,
                size: 20,
                color: Color(0xFF94A3B8),
              ),
            ),
            hoverColor: const Color(0xFFF1F5F9), // slate-100
          ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: const Color(0xFFF1F5F9),
          ), // slate-100
        ),
      ),
      body: SafeArea(
        child: LoadingOverlay(
          isLoading: _submitting,
          message: 'Creating event...',
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // SECTION: DATE & TIME
                        _buildSectionHeader(
                          LucideIcons.calendar,
                          'Date & Time',
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Start'),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
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
                                    child: IgnorePointer(
                                      child: TextFormField(
                                        key: ValueKey(_startDate),
                                        initialValue: _startDate != null
                                            ? df.format(_startDate!)
                                            : '',
                                        decoration: _inputDecoration(
                                          'Date',
                                          prefixIcon: LucideIcons.calendar,
                                        ),
                                        validator: (v) => _startDate == null
                                            ? 'Required'
                                            : null,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final t = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.now(),
                                      );
                                      if (t != null) {
                                        setState(() => _startTime = t);
                                      }
                                    },
                                    child: IgnorePointer(
                                      child: TextFormField(
                                        key: ValueKey(_startTime),
                                        initialValue:
                                            _startTime?.format(context) ?? '',
                                        decoration: _inputDecoration(
                                          'Time',
                                          prefixIcon: LucideIcons.clock,
                                        ),
                                        validator: (v) => _startTime == null
                                            ? 'Required'
                                            : null,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            _buildLabel('End'),
                            Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final d = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            _startDate ?? DateTime.now(),
                                        firstDate: _startDate ?? DateTime.now(),
                                        lastDate: DateTime.now().add(
                                          const Duration(days: 365),
                                        ),
                                      );
                                      if (d != null) {
                                        setState(() => _endDate = d);
                                      }
                                    },
                                    child: IgnorePointer(
                                      child: TextFormField(
                                        key: ValueKey(_endDate),
                                        initialValue: _endDate != null
                                            ? df.format(_endDate!)
                                            : '',
                                        decoration: _inputDecoration(
                                          'Date',
                                          prefixIcon: LucideIcons.calendar,
                                        ),
                                        validator: (v) => _endDate == null
                                            ? 'Required'
                                            : null,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
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
                                    child: IgnorePointer(
                                      child: TextFormField(
                                        key: ValueKey(_endTime),
                                        initialValue:
                                            _endTime?.format(context) ?? '',
                                        decoration: _inputDecoration(
                                          'Time',
                                          prefixIcon: LucideIcons.clock,
                                        ),
                                        validator: (v) => _endTime == null
                                            ? 'Required'
                                            : null,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 40),

                        // SECTION: EVENT DETAILS
                        _buildSectionHeader(LucideIcons.edit3, 'Event Details'),
                        _buildLabel('Event Name'),
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: _inputDecoration(
                            'e.g. Annual Tech Conference 2026',
                          ),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Facilitator'),
                        TextFormField(
                          controller: _facilitatorCtrl,
                          decoration: _inputDecoration(
                            'Facilitator Name',
                          ).copyWith(fillColor: const Color(0xFFF8FAFC)),
                          validator: (v) =>
                              (v?.trim().isEmpty ?? true) ? 'Required' : null,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // SECTION: VENUE & AUDIENCE
                        _buildSectionHeader(
                          LucideIcons.mapPin,
                          'Venue & Audience',
                        ),
                        _buildLabel('Venue'),
                        _loadingVenues
                            ? const Center(child: CircularProgressIndicator())
                            : DropdownButtonFormField<String>(
                                initialValue: _selectedVenueName,
                                decoration: _inputDecoration('Select a Venue'),
                                icon: const Icon(
                                  LucideIcons.chevronDown,
                                  size: 18,
                                  color: Color(0xFF94A3B8),
                                ),
                                items: _venues
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v.name,
                                        child: Text(
                                          v.name.toUpperCase(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _selectedVenueName = v),
                                validator: (v) => v == null ? 'Required' : null,
                              ),
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Make sure the venue is verified in DigiCampus.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildLabel('Intended Audience'),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedAudience,
                          decoration: _inputDecoration('Select Audience'),
                          icon: const Icon(
                            LucideIcons.chevronDown,
                            size: 18,
                            color: Color(0xFF94A3B8),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Students',
                              child: Text(
                                'Students',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Faculty',
                              child: Text(
                                'Faculty',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'PhD Scholars',
                              child: Text(
                                'PhD Scholars',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Staffs',
                              child: Text(
                                'Staffs',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Everyone at VU',
                              child: Text(
                                'Everyone at VU',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'Others',
                              child: Text(
                                'Others',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedAudience = v),
                        ),
                        if (_selectedAudience == 'Others') ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _audienceOtherCtrl,
                            decoration: _inputDecoration(
                              'Specify other audience...',
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1E293B),
                            ),
                            maxLength: 500,
                            validator: (v) {
                              if (_selectedAudience == 'Others' &&
                                  (v?.trim().isEmpty ?? true)) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                        ],

                        const SizedBox(height: 40),

                        // SECTION: DESCRIPTION & BUDGET
                        _buildSectionHeader(
                          LucideIcons.alignLeft,
                          'Description & Budget',
                        ),
                        _buildLabel('Description'),
                        TextFormField(
                          controller: _descCtrl,
                          decoration: _inputDecoration(
                            'Add a short overview of the event...',
                          ),
                          maxLines: 4,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 4, bottom: 20),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Max 2000 chars',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),

                        _buildLabel('Budget (RS)'),
                        TextFormField(
                          controller: _budgetCtrl,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration('e.g. 50000').copyWith(
                            prefixIcon: const Padding(
                              padding: EdgeInsets.all(14.0),
                              child: Text(
                                '₹',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),

                        const SizedBox(height: 20),

                        RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'BUDGET BREAKDOWN PDF ',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              TextSpan(
                                text: '(REQUIRED)',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Upload a PDF with your budget breakdown. You can upload it with any file name. It will be stored automatically using the event name and date.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickPdf,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 20,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: _budgetPdf == null
                                  ? Colors.white
                                  : const Color(0xFFEFF6FF), // blue-50
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _budgetPdf == null
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(
                                        0xFF93C5FD,
                                      ), // slate-200 / blue-300
                                width: 2,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _budgetPdf == null
                                      ? LucideIcons.uploadCloud
                                      : LucideIcons.fileText,
                                  size: 18,
                                  color: _budgetPdf == null
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFF2563EB),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _budgetPdf == null
                                        ? 'CHOOSE PDF FILE'
                                        : _budgetPdf!.name.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                      color: _budgetPdf == null
                                          ? const Color(0xFF64748B)
                                          : const Color(0xFF2563EB),
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
              ),

              // FOOTER ACTIONS
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFF1F5F9)),
                  ), // slate-100
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/events');
                        }
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ), // slate-200
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569), // slate-600
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB), // blue-600
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.plus,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Create Event',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
