import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

class RequirementsWizardDialog extends StatefulWidget {
  final Event event;
  final VoidCallback onSuccess;
  final String requesterEmail;
  final List<String>? departments;

  const RequirementsWizardDialog({
    super.key,
    required this.event,
    required this.onSuccess,
    this.requesterEmail = '',
    this.departments,
  });

  @override
  State<RequirementsWizardDialog> createState() =>
      _RequirementsWizardDialogState();
}

class _RequirementsWizardDialogState extends State<RequirementsWizardDialog> {
  final _api = ApiService();
  static const int _maxMarketingRequesterFiles = 10;
  static const int _maxMarketingRequesterFileMb = 25;
  static const int _maxMarketingRequesterFileBytes =
      _maxMarketingRequesterFileMb * 1024 * 1024;

  static const List<String> _allDepartments = [
    'facility',
    'it',
    'marketing',
    'transport',
  ];

  late final List<String> _departments;

  int _currentStep = 0;
  String _phase = 'edit'; // 'edit' or 'review'

  // Track skipped departments
  late final Map<String, bool> _skipped;

  // Form data
  final Map<String, dynamic> _facilityForm = {
    'to': '',
    'venue_required': true,
    'refreshments': false,
    'other_notes': '',
  };

  final Map<String, dynamic> _itForm = {
    'to': '',
    'event_mode': 'offline',
    'pa_system': true,
    'projection': false,
    'other_notes': '',
  };

  final Map<String, dynamic> _marketingForm = {
    'to': '',
    'marketing_requirements': {
      'pre_event': {'poster': false, 'social_media': false},
      'during_event': {'photo': false, 'video': false},
      'post_event': {
        'social_media': false,
        'photo_upload': false,
        'video': false,
      },
    },
    'other_notes': '',
  };

  final Map<String, dynamic> _transportForm = {
    'to': '',
    'include_guest_cab': true,
    'include_students': false,
    'guest_pickup_location': '',
    'guest_pickup_date': '',
    'guest_pickup_time': '',
    'guest_dropoff_location': '',
    'guest_dropoff_date': '',
    'guest_dropoff_time': '',
    'student_count': '',
    'student_transport_kind': '',
    'student_date': '',
    'student_time': '',
    'student_pickup_point': '',
    'other_notes': '',
  };

  String _status = 'idle'; // 'idle', 'loading', 'error'
  String _errorMessage = '';
  List<PlatformFile> _marketingAttachments = [];

  String get _currentDept => _departments[_currentStep];
  bool get _hasAnySelected => _departments.any((d) => !_skipped[d]!);

  int get _totalSteps => _departments.length;

  @override
  void initState() {
    super.initState();
    final incoming = widget.departments
        ?.map((dept) => dept.trim().toLowerCase())
        .where((dept) => _allDepartments.contains(dept))
        .toSet()
        .toList();
    _departments = incoming == null || incoming.isEmpty
        ? List<String>.from(_allDepartments)
        : _allDepartments.where(incoming.contains).toList();
    _skipped = {for (final dept in _departments) dept: false};
  }

  String _trimmed(dynamic value) => value?.toString().trim() ?? '';

  String? _validateTransportForm() {
    final wantsGuest = _transportForm['include_guest_cab'] as bool;
    final wantsStudents = _transportForm['include_students'] as bool;

    if (!wantsGuest && !wantsStudents) {
      return 'Select at least one transport option.';
    }

    if (wantsGuest) {
      final missingGuest =
          _trimmed(_transportForm['guest_pickup_location']).isEmpty ||
          _trimmed(_transportForm['guest_pickup_date']).isEmpty ||
          _trimmed(_transportForm['guest_pickup_time']).isEmpty ||
          _trimmed(_transportForm['guest_dropoff_location']).isEmpty ||
          _trimmed(_transportForm['guest_dropoff_time']).isEmpty;
      if (missingGuest) {
        return 'Fill guest cab details: pickup location, pickup date & time, dropoff location, and dropoff time.';
      }
    }

    if (wantsStudents) {
      final studentCount = int.tryParse(
        _trimmed(_transportForm['student_count']),
      );
      final missingStudents =
          studentCount == null ||
          studentCount < 1 ||
          _trimmed(_transportForm['student_transport_kind']).isEmpty ||
          _trimmed(_transportForm['student_date']).isEmpty ||
          _trimmed(_transportForm['student_time']).isEmpty ||
          _trimmed(_transportForm['student_pickup_point']).isEmpty;
      if (missingStudents) {
        return 'Fill student transport details: count, transport kind, date, time, and pickup point.';
      }
    }

    return null;
  }

  void _goNext() {
    if (_phase == 'edit' && _currentDept == 'transport') {
      final validationError = _validateTransportForm();
      if (validationError != null) {
        setState(() {
          _status = 'error';
          _errorMessage = validationError;
        });
        return;
      }
    }

    if (_phase == 'edit') {
      // Un-skip current department since user is actively proceeding
      _skipped[_currentDept] = false;
      if (_currentStep < _totalSteps - 1) {
        setState(() {
          _currentStep++;
          _status = 'idle';
          _errorMessage = '';
        });
      } else {
        setState(() {
          _phase = 'review';
          _status = 'idle';
          _errorMessage = '';
        });
      }
    }
  }

  void _goPrev() {
    if (_phase == 'edit' && _currentStep > 0) {
      setState(() {
        _currentStep--;
        _skipped[_departments[_currentStep]] = false;
        _status = 'idle';
        _errorMessage = '';
      });
    } else if (_phase == 'review') {
      setState(() {
        _phase = 'edit';
        _skipped[_departments[_currentStep]] = false;
        _status = 'idle';
        _errorMessage = '';
      });
    }
  }

  void _skip() {
    setState(() {
      _skipped[_currentDept] = true;
      _status = 'idle';
      _errorMessage = '';
    });
    // Navigate directly without validation (user is intentionally skipping)
    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      setState(() {
        _phase = 'review';
      });
    }
  }

  Future<void> _sendAll() async {
    if (!_hasAnySelected) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No requirements were sent (all steps skipped).'),
          ),
        );
      }
      return;
    }

    setState(() {
      _status = 'loading';
      _errorMessage = '';
    });

    try {
      final toSend = _departments.where((d) => !_skipped[d]!).toList();

      for (final dept in toSend) {
        if (dept == 'facility') {
          await _sendFacilityRequest();
        } else if (dept == 'it') {
          await _sendItRequest();
        } else if (dept == 'marketing') {
          await _sendMarketingRequest();
        } else if (dept == 'transport') {
          await _sendTransportRequest();
        }
      }

      final labels = toSend
          .map((dept) {
            if (dept == 'facility') return 'Facility';
            if (dept == 'it') return 'IT';
            if (dept == 'marketing') return 'Marketing';
            if (dept == 'transport') return 'Transport';
            return dept;
          })
          .join(', ');

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Requirements sent to: $labels.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _status = 'error';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _sendFacilityRequest() async {
    final res = await _api.post(
      '/facility/requests',
      data: {
        'requested_to': _facilityForm['to'].isEmpty
            ? null
            : _facilityForm['to'],
        'event_id': widget.event.id,
        'event_name': widget.event.title,
        'start_date': widget.event.startTime.toString().split(' ')[0],
        'start_time': _formatTime(widget.event.startTime),
        'end_date': widget.event.endTime.toString().split(' ')[0],
        'end_time': _formatTime(widget.event.endTime),
        'venue_required': _facilityForm['venue_required'],
        'refreshments': _facilityForm['refreshments'],
        'other_notes': _facilityForm['other_notes'],
      },
    );
    if (res == null) throw Exception('Failed to send facility request');
  }

  Future<void> _sendItRequest() async {
    final res = await _api.post(
      '/it/requests',
      data: {
        'requested_to': _itForm['to'].isEmpty ? null : _itForm['to'],
        'event_id': widget.event.id,
        'event_name': widget.event.title,
        'start_date': widget.event.startTime.toString().split(' ')[0],
        'start_time': _formatTime(widget.event.startTime),
        'end_date': widget.event.endTime.toString().split(' ')[0],
        'end_time': _formatTime(widget.event.endTime),
        'event_mode': _itForm['event_mode'],
        'pa_system': _itForm['pa_system'],
        'projection': _itForm['projection'],
        'other_notes': _itForm['other_notes'],
      },
    );
    if (res == null) throw Exception('Failed to send IT request');
  }

  Future<void> _sendMarketingRequest() async {
    final res = await _api.post(
      '/marketing/requests',
      data: {
        'requested_to': _marketingForm['to'].isEmpty
            ? null
            : _marketingForm['to'],
        'event_id': widget.event.id,
        'event_name': widget.event.title,
        'start_date': widget.event.startTime.toString().split(' ')[0],
        'start_time': _formatTime(widget.event.startTime),
        'end_date': widget.event.endTime.toString().split(' ')[0],
        'end_time': _formatTime(widget.event.endTime),
        'marketing_requirements': _marketingForm['marketing_requirements'],
        'other_notes': _marketingForm['other_notes'],
      },
    );
    if (res == null) throw Exception('Failed to send marketing request');

    final requestId = (res is Map<String, dynamic> ? res['id'] : null)
        ?.toString()
        .trim();
    await _uploadMarketingRequesterAttachmentsIfAny(requestId);
  }

  Future<void> _uploadMarketingRequesterAttachmentsIfAny(
    String? requestId,
  ) async {
    if (requestId == null ||
        requestId.isEmpty ||
        _marketingAttachments.isEmpty) {
      return;
    }

    final files = <MultipartFile>[];
    for (final file in _marketingAttachments) {
      final path = file.path;
      if (path == null || path.trim().isEmpty) continue;
      files.add(await MultipartFile.fromFile(path, filename: file.name));
    }

    if (files.isEmpty) return;

    await _api.postMultipart(
      '/marketing/requests/$requestId/requester-attachments',
      FormData.fromMap({'files': files}),
    );
  }

  Future<void> _pickMarketingAttachments() async {
    final remainingSlots =
        _maxMarketingRequesterFiles - _marketingAttachments.length;
    if (remainingSlots <= 0) {
      setState(() {
        _status = 'error';
        _errorMessage =
            'You can attach at most $_maxMarketingRequesterFiles files.';
      });
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
      allowCompression: false,
    );
    final picked = result?.files ?? const <PlatformFile>[];
    if (picked.isEmpty) return;

    if (_marketingAttachments.length + picked.length >
        _maxMarketingRequesterFiles) {
      setState(() {
        _status = 'error';
        _errorMessage =
            'You can attach at most $_maxMarketingRequesterFiles files.';
      });
      return;
    }

    for (final file in picked) {
      final size = file.size;
      if (size > _maxMarketingRequesterFileBytes) {
        setState(() {
          _status = 'error';
          _errorMessage =
              '${file.name} is larger than ${_maxMarketingRequesterFileMb}MB.';
        });
        return;
      }
    }

    setState(() {
      _marketingAttachments = [..._marketingAttachments, ...picked];
      _status = 'idle';
      _errorMessage = '';
    });
  }

  void _removeMarketingAttachmentAt(int index) {
    setState(() {
      _marketingAttachments = [
        for (var i = 0; i < _marketingAttachments.length; i++)
          if (i != index) _marketingAttachments[i],
      ];
      _status = 'idle';
      _errorMessage = '';
    });
  }

  Future<void> _sendTransportRequest() async {
    final validationError = _validateTransportForm();
    if (validationError != null) {
      throw Exception(validationError);
    }

    final wantsGuest = _transportForm['include_guest_cab'] as bool;
    final wantsStudents = _transportForm['include_students'] as bool;
    final transportType = wantsGuest && wantsStudents
        ? 'both'
        : wantsGuest
        ? 'guest_cab'
        : 'students_off_campus';

    final studentCountParsed =
        int.tryParse(_transportForm['student_count'].toString()) ?? 0;

    final res = await _api.post(
      '/transport/requests',
      data: {
        'requested_to': _transportForm['to'].isEmpty
            ? null
            : _transportForm['to'],
        'event_id': widget.event.id,
        'event_name': widget.event.title,
        'start_date': widget.event.startTime.toString().split(' ')[0],
        'start_time': _formatTime(widget.event.startTime),
        'end_date': widget.event.endTime.toString().split(' ')[0],
        'end_time': _formatTime(widget.event.endTime),
        'transport_type': transportType,
        'guest_pickup_location': wantsGuest
            ? _transportForm['guest_pickup_location']
            : null,
        'guest_pickup_date': wantsGuest
            ? _transportForm['guest_pickup_date']
            : null,
        'guest_pickup_time': wantsGuest
            ? _transportForm['guest_pickup_time']
            : null,
        'guest_dropoff_location': wantsGuest
            ? _transportForm['guest_dropoff_location']
            : null,
        'guest_dropoff_date': wantsGuest
            ? _transportForm['guest_dropoff_date']
            : null,
        'guest_dropoff_time': wantsGuest
            ? _transportForm['guest_dropoff_time']
            : null,
        'student_count': wantsStudents && studentCountParsed > 0
            ? studentCountParsed
            : null,
        'student_transport_kind': wantsStudents
            ? _transportForm['student_transport_kind']
            : null,
        'student_date': wantsStudents ? _transportForm['student_date'] : null,
        'student_time': wantsStudents ? _transportForm['student_time'] : null,
        'student_pickup_point': wantsStudents
            ? _transportForm['student_pickup_point']
            : null,
        'other_notes': _transportForm['other_notes'],
      },
    );
    if (res == null) throw Exception('Failed to send transport request');
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  bool get _isCompactLayout => MediaQuery.of(context).size.width < 420;

  EdgeInsets get _stepPadding => EdgeInsets.all(_isCompactLayout ? 18 : 24);

  // ---- UI Helper Widgets ----

  InputDecoration _buildInputDecoration(String label, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(_isCompactLayout ? 7 : 8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).primaryColor,
            size: _isCompactLayout ? 20 : 24,
          ),
        ),
        SizedBox(width: _isCompactLayout ? 10 : 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: _isCompactLayout ? 17 : 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckboxCard({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: value
            ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
            : Colors.transparent,
        border: Border.all(
          color: value ? Theme.of(context).primaryColor : Colors.grey[300]!,
          width: value ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: TextStyle(
            fontSize: _isCompactLayout ? 14 : 16,
            fontWeight: value ? FontWeight.w600 : FontWeight.w400,
            color: Colors.black87,
          ),
        ),
        activeColor: Theme.of(context).primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dense: _isCompactLayout,
        visualDensity: _isCompactLayout
            ? const VisualDensity(horizontal: -2, vertical: -2)
            : VisualDensity.standard,
        controlAffinity: ListTileControlAffinity.trailing,
        checkboxShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: _isCompactLayout ? 10 : 12,
          vertical: _isCompactLayout ? 0 : 4,
        ),
      ),
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required String formKey,
    String? hintText,
  }) {
    final currentValue = _transportForm[formKey]?.toString() ?? '';
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final initial = currentValue.isNotEmpty
            ? DateTime.tryParse(currentValue) ?? now
            : now;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial.isBefore(now) ? now : initial,
          firstDate: now,
          lastDate: now.add(const Duration(days: 365 * 2)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(
                  context,
                ).colorScheme.copyWith(primary: Theme.of(context).primaryColor),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() {
            _transportForm[formKey] =
                '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
          });
        }
      },
      child: AbsorbPointer(
        child: TextField(
          controller: TextEditingController(text: currentValue),
          decoration:
              _buildInputDecoration(
                label,
                hintText: hintText ?? 'Select date',
              ).copyWith(
                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                suffixIcon: const Icon(Icons.arrow_drop_down, size: 20),
              ),
        ),
      ),
    );
  }

  Widget _buildTimePickerField({
    required String label,
    required String formKey,
    String? hintText,
  }) {
    final currentValue = _transportForm[formKey]?.toString() ?? '';
    return GestureDetector(
      onTap: () async {
        final parts = currentValue.split(':');
        final initial = currentValue.isNotEmpty && parts.length >= 2
            ? TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 0,
                minute: int.tryParse(parts[1]) ?? 0,
              )
            : TimeOfDay.now();
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(
                  context,
                ).colorScheme.copyWith(primary: Theme.of(context).primaryColor),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() {
            _transportForm[formKey] =
                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          });
        }
      },
      child: AbsorbPointer(
        child: TextField(
          controller: TextEditingController(text: currentValue),
          decoration:
              _buildInputDecoration(
                label,
                hintText: hintText ?? 'Select time',
              ).copyWith(
                prefixIcon: const Icon(Icons.access_time, size: 18),
                suffixIcon: const Icon(Icons.arrow_drop_down, size: 20),
              ),
        ),
      ),
    );
  }

  Widget _buildEventSummary() {
    return Container(
      padding: EdgeInsets.all(_isCompactLayout ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note, color: Colors.blueGrey[700], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.event.title,
                  style: GoogleFonts.poppins(
                    fontSize: _isCompactLayout ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.blueGrey[600]),
              const SizedBox(width: 8),
              Text(
                '${widget.event.startTime.toString().split(' ')[0]} - ${widget.event.endTime.toString().split(' ')[0]}',
                style: TextStyle(
                  fontSize: _isCompactLayout ? 12 : 13,
                  color: Colors.blueGrey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.blueGrey[600]),
              const SizedBox(width: 8),
              Text(
                '${_formatTime(widget.event.startTime)} to ${_formatTime(widget.event.endTime)}',
                style: TextStyle(
                  fontSize: _isCompactLayout ? 12 : 13,
                  color: Colors.blueGrey[800],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Main Step Builders ----

  Widget _buildStep() {
    if (_phase == 'review') {
      return _buildReview();
    }

    switch (_currentDept) {
      case 'facility':
        return _buildFacilityStep();
      case 'it':
        return _buildItStep();
      case 'marketing':
        return _buildMarketingStep();
      case 'transport':
        return _buildTransportStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildFacilityStep() {
    return SingleChildScrollView(
      padding: _stepPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Facility Request', Icons.domain),
          const SizedBox(height: 24),
          _buildEventSummary(),
          const SizedBox(height: 24),
          Text(
            'Message Details',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            readOnly: true,
            decoration: _buildInputDecoration('From').copyWith(
              prefixIcon: const Icon(Icons.person_outline),
              hintText: widget.requesterEmail.isEmpty
                  ? 'Your account'
                  : widget.requesterEmail,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => _facilityForm['to'] = v,
            decoration: _buildInputDecoration(
              'To',
              hintText: 'Facility manager email (Optional)',
            ).copyWith(prefixIcon: const Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 24),
          Text(
            'Requirements',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          _buildCheckboxCard(
            title: 'Venue Setup',
            value: _facilityForm['venue_required'],
            onChanged: (v) =>
                setState(() => _facilityForm['venue_required'] = v ?? false),
          ),
          _buildCheckboxCard(
            title: 'Refreshments',
            value: _facilityForm['refreshments'],
            onChanged: (v) =>
                setState(() => _facilityForm['refreshments'] = v ?? false),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => _facilityForm['other_notes'] = v,
            decoration: _buildInputDecoration(
              'Additional Notes',
              hintText: 'Any special arrangements needed?',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildItStep() {
    return SingleChildScrollView(
      padding: _stepPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('IT Support', Icons.computer),
          const SizedBox(height: 24),
          _buildEventSummary(),
          const SizedBox(height: 24),
          Text(
            'Message Details',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            readOnly: true,
            decoration: _buildInputDecoration('From').copyWith(
              prefixIcon: const Icon(Icons.person_outline),
              hintText: widget.requesterEmail.isEmpty
                  ? 'Your account'
                  : widget.requesterEmail,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => _itForm['to'] = v,
            decoration: _buildInputDecoration(
              'To',
              hintText: 'IT department email (Optional)',
            ).copyWith(prefixIcon: const Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 24),
          Text(
            'Event Mode',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'online',
                  label: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Online'),
                  ),
                  icon: Icon(Icons.wifi),
                ),
                ButtonSegment<String>(
                  value: 'offline',
                  label: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Offline'),
                  ),
                  icon: Icon(Icons.wifi_off),
                ),
              ],
              selected: {(_itForm['event_mode'] ?? 'offline').toString()},
              onSelectionChanged: (selection) {
                setState(() => _itForm['event_mode'] = selection.first);
              },
              style: ButtonStyle(
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Technical Requirements',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          _buildCheckboxCard(
            title: 'PA System',
            value: _itForm['pa_system'],
            onChanged: (v) => setState(() => _itForm['pa_system'] = v ?? false),
          ),
          _buildCheckboxCard(
            title: 'Projection',
            value: _itForm['projection'],
            onChanged: (v) =>
                setState(() => _itForm['projection'] = v ?? false),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => _itForm['other_notes'] = v,
            decoration: _buildInputDecoration(
              'Additional Notes',
              hintText: 'Microphones needed? WiFi access?',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildMarketingStep() {
    final req =
        _marketingForm['marketing_requirements'] as Map<String, dynamic>;
    return SingleChildScrollView(
      padding: _stepPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Marketing Request', Icons.campaign),
          const SizedBox(height: 24),
          _buildEventSummary(),
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => _marketingForm['to'] = v,
            decoration: _buildInputDecoration(
              'To',
              hintText: 'Marketing email (Optional)',
            ).copyWith(prefixIcon: const Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 24),
          Text(
            'Campaign Phases',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          _buildPhaseGroup('Pre-Event', [
            _buildCheckboxCard(
              title: 'Poster Design',
              value: req['pre_event']['poster'],
              onChanged: (v) =>
                  setState(() => req['pre_event']['poster'] = v ?? false),
            ),
            _buildCheckboxCard(
              title: 'Social Media Post',
              value: req['pre_event']['social_media'],
              onChanged: (v) =>
                  setState(() => req['pre_event']['social_media'] = v ?? false),
            ),
          ]),
          const SizedBox(height: 16),
          _buildPhaseGroup('During Event', [
            _buildCheckboxCard(
              title: 'Photography Coverage',
              value: req['during_event']['photo'],
              onChanged: (v) =>
                  setState(() => req['during_event']['photo'] = v ?? false),
            ),
            _buildCheckboxCard(
              title: 'Video Shoot',
              value: req['during_event']['video'],
              onChanged: (v) =>
                  setState(() => req['during_event']['video'] = v ?? false),
            ),
          ]),
          const SizedBox(height: 16),
          _buildPhaseGroup('Post-Event', [
            _buildCheckboxCard(
              title: 'Social Media Wrap-up',
              value: req['post_event']['social_media'],
              onChanged: (v) => setState(
                () => req['post_event']['social_media'] = v ?? false,
              ),
            ),
            _buildCheckboxCard(
              title: 'Photo Gallery Upload',
              value: req['post_event']['photo_upload'],
              onChanged: (v) => setState(
                () => req['post_event']['photo_upload'] = v ?? false,
              ),
            ),
            _buildCheckboxCard(
              title: 'Video Upload',
              value: req['post_event']['video'],
              onChanged: (v) =>
                  setState(() => req['post_event']['video'] = v ?? false),
            ),
          ]),
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => _marketingForm['other_notes'] = v,
            decoration: _buildInputDecoration(
              'Additional Notes',
              hintText: 'Target audience? Key messaging?',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          Text(
            'Reference Files',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Max $_maxMarketingRequesterFiles files, up to ${_maxMarketingRequesterFileMb}MB each.',
            style: TextStyle(
              fontSize: _isCompactLayout ? 12 : 13,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _status == 'loading'
                  ? null
                  : _pickMarketingAttachments,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Attachments'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_marketingAttachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...List.generate(_marketingAttachments.length, (index) {
              final file = _marketingAttachments[index];
              final sizeMb = file.size / (1024 * 1024);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[200]!),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.insert_drive_file,
                        color: Colors.blue[400],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sizeMb.toStringAsFixed(1)} MB',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _status == 'loading'
                          ? null
                          : () => _removeMarketingAttachmentAt(index),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildPhaseGroup(String title, List<Widget> children) {
    return Container(
      padding: EdgeInsets.all(_isCompactLayout ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: _isCompactLayout ? 11 : 12,
              letterSpacing: _isCompactLayout ? 0.8 : 1.2,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTransportStep() {
    return SingleChildScrollView(
      padding: _stepPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Transport Request', Icons.directions_bus),
          const SizedBox(height: 24),
          _buildEventSummary(),
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => _transportForm['to'] = v,
            decoration: _buildInputDecoration(
              'To',
              hintText: 'Transport coordinator email (Optional)',
            ).copyWith(prefixIcon: const Icon(Icons.mail_outline)),
          ),
          const SizedBox(height: 24),
          Text(
            'Arrangements Needed',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          _buildCheckboxCard(
            title: 'Guest Cab Services',
            value: _transportForm['include_guest_cab'],
            onChanged: (v) => setState(
              () => _transportForm['include_guest_cab'] = v ?? false,
            ),
          ),
          _buildCheckboxCard(
            title: 'Student Transport (Off-campus)',
            value: _transportForm['include_students'],
            onChanged: (v) =>
                setState(() => _transportForm['include_students'] = v ?? false),
          ),
          if (_transportForm['include_guest_cab']) ...[
            const SizedBox(height: 24),
            _buildPhaseGroup('Guest Cab Itinerary', [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) =>
                          _transportForm['guest_pickup_location'] = v,
                      decoration: _buildInputDecoration('Pickup Location'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildDatePickerField(
                      label: 'Pickup Date',
                      formKey: 'guest_pickup_date',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildTimePickerField(
                      label: 'Time',
                      formKey: 'guest_pickup_time',
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) =>
                          _transportForm['guest_dropoff_location'] = v,
                      decoration: _buildInputDecoration('Dropoff Location'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildDatePickerField(
                      label: 'Dropoff Date',
                      formKey: 'guest_dropoff_date',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildTimePickerField(
                      label: 'Time',
                      formKey: 'guest_dropoff_time',
                    ),
                  ),
                ],
              ),
            ]),
          ],
          if (_transportForm['include_students']) ...[
            const SizedBox(height: 24),
            _buildPhaseGroup('Student Logistics', [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => _transportForm['student_count'] = v,
                      decoration: _buildInputDecoration('Total Students'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      onChanged: (v) =>
                          _transportForm['student_transport_kind'] = v,
                      decoration: _buildInputDecoration(
                        'Vehicle Type',
                        hintText: 'Bus, Van...',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildDatePickerField(
                      label: 'Date',
                      formKey: 'student_date',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildTimePickerField(
                      label: 'Time',
                      formKey: 'student_time',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => _transportForm['student_pickup_point'] = v,
                decoration: _buildInputDecoration('Central Pickup Point'),
              ),
            ]),
          ],
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => _transportForm['other_notes'] = v,
            decoration: _buildInputDecoration(
              'Additional Notes',
              hintText: 'Any special instructions for drivers?',
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildReview() {
    return SingleChildScrollView(
      padding: _stepPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Review Requirements', Icons.fact_check),
          const SizedBox(height: 24),
          _buildEventSummary(),
          const SizedBox(height: 24),
          ..._departments.map((dept) {
            final isSkipped = _skipped[dept]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: isSkipped
                  ? _buildSkippedCard(dept)
                  : _buildReviewItemCard(dept),
            );
          }),
          if (!_hasAnySelected)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red[700],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'All departments were skipped. Go back to include at least one request, or close to cancel.',
                      style: TextStyle(fontSize: 13, color: Colors.red[800]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkippedCard(String dept) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, style: BorderStyle.solid),
      ),
      child: Row(
        children: [
          Icon(Icons.do_not_disturb_alt, color: Colors.grey[500], size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getDeptReviewLabel(dept),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Skipped — No request will be sent.',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItemCard(String dept) {
    final title = _getDeptReviewLabel(dept);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Theme.of(context).primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          if (dept == 'facility') ...[
            _buildReviewLine(
              'To',
              _facilityForm['to'].isEmpty
                  ? 'Default facility desk'
                  : _facilityForm['to'],
            ),
            _buildReviewLine(
              'Venue setup',
              _facilityForm['venue_required'] ? 'Required' : 'Not required',
            ),
            _buildReviewLine(
              'Refreshments',
              _facilityForm['refreshments'] ? 'Required' : 'Not required',
            ),
            if (_hasNotes(_facilityForm['other_notes']))
              _buildReviewLine(
                'Notes',
                _facilityForm['other_notes'].toString().trim(),
              ),
          ] else if (dept == 'it') ...[
            _buildReviewLine(
              'To',
              _itForm['to'].isEmpty ? 'Default IT desk' : _itForm['to'],
            ),
            _buildReviewLine(
              'Mode',
              _itForm['event_mode'] == 'online'
                  ? 'Online Event'
                  : 'Offline Event',
            ),
            _buildReviewLine(
              'PA system',
              _itForm['pa_system'] ? 'Required' : 'Not required',
            ),
            _buildReviewLine(
              'Projection',
              _itForm['projection'] ? 'Required' : 'Not required',
            ),
            if (_hasNotes(_itForm['other_notes']))
              _buildReviewLine(
                'Notes',
                _itForm['other_notes'].toString().trim(),
              ),
          ] else if (dept == 'marketing') ...[
            _buildReviewLine(
              'To',
              _marketingForm['to'].isEmpty
                  ? 'Default marketing desk'
                  : _marketingForm['to'],
            ),
            const SizedBox(height: 8),
            ..._selectedMarketingLines().map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_marketingAttachments.isNotEmpty)
              _buildReviewLine(
                'Attachments',
                '${_marketingAttachments.length} files attached',
              ),
            if (_hasNotes(_marketingForm['other_notes']))
              _buildReviewLine(
                'Notes',
                _marketingForm['other_notes'].toString().trim(),
              ),
          ] else if (dept == 'transport') ...[
            _buildReviewLine(
              'To',
              _transportForm['to'].isEmpty
                  ? 'Default transport desk'
                  : _transportForm['to'],
            ),
            _buildReviewLine(
              'Guest cab',
              _transportForm['include_guest_cab'] ? 'Required' : 'Not required',
            ),
            _buildReviewLine(
              'Students',
              _transportForm['include_students'] ? 'Required' : 'Not required',
            ),
            if (_transportForm['include_guest_cab'])
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Guest Itinerary:\n${_transportForm['guest_pickup_location'] ?? '—'} → ${_transportForm['guest_dropoff_location'] ?? '—'} \n(${_transportForm['guest_pickup_date'] ?? '—'} at ${_transportForm['guest_pickup_time'] ?? ''})',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            if (_transportForm['include_students'])
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Student Logistics:\n${_transportForm['student_count'] ?? '—'} Students via ${_transportForm['student_transport_kind'] ?? '—'}\nOn ${_transportForm['student_date'] ?? '—'} at ${_transportForm['student_time'] ?? ''}\nPickup: ${_transportForm['student_pickup_point'] ?? '—'}',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            if (_hasNotes(_transportForm['other_notes']))
              _buildReviewLine(
                'Notes',
                _transportForm['other_notes'].toString().trim(),
              ),
          ],
        ],
      ),
    );
  }

  String _getDeptReviewLabel(String dept) {
    switch (dept) {
      case 'facility':
        return 'Facility Management';
      case 'it':
        return 'IT & Technical';
      case 'marketing':
        return 'Marketing & Media';
      case 'transport':
        return 'Transport & Logistics';
      default:
        return dept;
    }
  }

  Widget _buildReviewLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasNotes(dynamic notes) {
    final trimmed = notes?.toString().trim();
    return trimmed != null && trimmed.isNotEmpty;
  }

  List<String> _selectedMarketingLines() {
    final req =
        _marketingForm['marketing_requirements'] as Map<String, dynamic>;
    final out = <String>[];
    if (req['pre_event']['poster'] == true) {
      out.add('Pre-Event: Poster Design');
    }
    if (req['pre_event']['social_media'] == true) {
      out.add('Pre-Event: Social Media Post');
    }
    if (req['during_event']['photo'] == true) {
      out.add('During Event: Photography');
    }
    if (req['during_event']['video'] == true) {
      out.add('During Event: Video Shoot');
    }
    if (req['post_event']['social_media'] == true) {
      out.add('Post-Event: Social Media Wrap-up');
    }
    if (req['post_event']['photo_upload'] == true) {
      out.add('Post-Event: Photo Gallery');
    }
    if (req['post_event']['video'] == true) {
      out.add('Post-Event: Video Upload');
    }
    if (out.isEmpty) {
      out.add('No specific items selected.');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_departments.isEmpty) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send Requirements',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'All department requests are already active. No new requirement can be sent right now.',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final double progress = _phase == 'review'
        ? 1.0
        : (_currentStep + 1) / _totalSteps;
    final media = MediaQuery.of(context);
    final isCompact = _isCompactLayout;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 20 : 32,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: isCompact ? media.size.width - 24 : 720,
        height: media.size.height * (isCompact ? 0.94 : 0.9),
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 18 : 24,
                vertical: isCompact ? 14 : 16,
              ),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _phase == 'review'
                            ? 'Review & Submit'
                            : 'Setup Requirements',
                        style: GoogleFonts.poppins(
                          fontSize: isCompact ? 16 : 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _phase == 'review'
                            ? 'Finalize your requests'
                            : 'Step ${_currentStep + 1} of $_totalSteps',
                        style: TextStyle(
                          fontSize: isCompact ? 12 : 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: Colors.grey[600],
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Progress Bar
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).primaryColor,
              ),
              minHeight: 3,
            ),

            // Error Banner
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                color: Colors.red[50],
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(
                          color: Colors.red[800],
                          fontSize: isCompact ? 12 : 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Body
            Expanded(
              child: Container(color: Colors.white, child: _buildStep()),
            ),

            // Bottom Navigation Area
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 16 : 24,
                vertical: isCompact ? 12 : 16,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    if (_phase == 'edit' && _currentStep > 0 ||
                        _phase == 'review')
                      TextButton.icon(
                        onPressed: _goPrev,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                        style: TextButton.styleFrom(
                          textStyle: TextStyle(fontSize: isCompact ? 13 : 14),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 12 : 16,
                            vertical: isCompact ? 10 : 12,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 80), // Placeholder to balance UI
                    const Spacer(),
                    if (_phase == 'edit')
                      TextButton(
                        onPressed: _skip,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          textStyle: TextStyle(fontSize: isCompact ? 13 : 14),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 12 : 16,
                            vertical: isCompact ? 10 : 12,
                          ),
                        ),
                        child: const Text('Skip Section'),
                      ),
                    SizedBox(width: isCompact ? 8 : 12),
                    if (_phase == 'edit')
                      FilledButton.icon(
                        onPressed: _goNext,
                        icon: Icon(
                          _currentStep >= _totalSteps - 1
                              ? Icons.fact_check_outlined
                              : Icons.arrow_forward,
                        ),
                        label: Text(
                          _currentStep >= _totalSteps - 1 ? 'Review' : 'Next',
                        ),
                        style: FilledButton.styleFrom(
                          textStyle: TextStyle(fontSize: isCompact ? 13 : 14),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 18 : 24,
                            vertical: isCompact ? 10 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    if (_phase == 'review')
                      FilledButton.icon(
                        onPressed: _status == 'loading' || !_hasAnySelected
                            ? null
                            : _sendAll,
                        icon: _status == 'loading'
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          _status == 'loading' ? 'Sending...' : 'Send Requests',
                        ),
                        style: FilledButton.styleFrom(
                          textStyle: TextStyle(fontSize: isCompact ? 13 : 14),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 18 : 24,
                            vertical: isCompact ? 10 : 12,
                          ),
                          backgroundColor: AppColors.success,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
    );
  }
}
