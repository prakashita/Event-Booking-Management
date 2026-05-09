import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
  final _facilityToController = TextEditingController();
  final _itToController = TextEditingController();
  final _marketingToController = TextEditingController();
  final _transportToController = TextEditingController();
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
  bool _routingEmailsLoading = false;

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
    _loadDepartmentRoutingEmails();
  }

  @override
  void dispose() {
    _facilityToController.dispose();
    _itToController.dispose();
    _marketingToController.dispose();
    _transportToController.dispose();
    super.dispose();
  }

  String _trimmed(dynamic value) => value?.toString().trim() ?? '';

  Future<void> _loadDepartmentRoutingEmails() async {
    if (!mounted) return;
    setState(() {
      _routingEmailsLoading = true;
    });

    try {
      final results = await Future.wait<dynamic>([
        _api.get<Map<String, dynamic>>('/auth/facility-manager-email'),
        _api.get<Map<String, dynamic>>('/auth/it-email'),
        _api.get<Map<String, dynamic>>('/auth/marketing-email'),
        _api.get<Map<String, dynamic>>('/auth/transport-email'),
      ]);

      _applyRoutingEmail(
        controller: _facilityToController,
        form: _facilityForm,
        key: 'to',
        email: (results[0] as Map<String, dynamic>)['email']?.toString() ?? '',
      );
      _applyRoutingEmail(
        controller: _itToController,
        form: _itForm,
        key: 'to',
        email: (results[1] as Map<String, dynamic>)['email']?.toString() ?? '',
      );
      _applyRoutingEmail(
        controller: _marketingToController,
        form: _marketingForm,
        key: 'to',
        email: (results[2] as Map<String, dynamic>)['email']?.toString() ?? '',
      );
      _applyRoutingEmail(
        controller: _transportToController,
        form: _transportForm,
        key: 'to',
        email: (results[3] as Map<String, dynamic>)['email']?.toString() ?? '',
      );
    } catch (_) {
      // Keep the fields editable and fall back to manual entry if routing
      // emails are unavailable for this user or environment.
    } finally {
      if (mounted) {
        setState(() {
          _routingEmailsLoading = false;
        });
      }
    }
  }

  void _applyRoutingEmail({
    required TextEditingController controller,
    required Map<String, dynamic> form,
    required String key,
    required String email,
  }) {
    final normalized = email.trim();
    if (normalized.isEmpty) return;
    if (_trimmed(form[key]).isNotEmpty || controller.text.trim().isNotEmpty) {
      return;
    }
    form[key] = normalized;
    controller.text = normalized;
  }

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
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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

    final formData = FormData();
    for (final file in _marketingAttachments) {
      final multipart = await _multipartFromPlatformFile(file);
      if (multipart != null) {
        formData.files.add(MapEntry('files', multipart));
      }
    }

    if (formData.files.isEmpty) return;

    await _api.postMultipart(
      '/marketing/requests/$requestId/requester-attachments',
      formData,
    );
  }

  Future<MultipartFile?> _multipartFromPlatformFile(PlatformFile file) async {
    final path = file.path;
    if (path != null && path.trim().isNotEmpty) {
      return MultipartFile.fromFile(path, filename: file.name);
    }
    final bytes = file.bytes;
    if (bytes != null) {
      return MultipartFile.fromBytes(bytes, filename: file.name);
    }
    final readStream = file.readStream;
    if (readStream != null) {
      return MultipartFile.fromStream(
        () => readStream,
        file.size,
        filename: file.name,
      );
    }
    return null;
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
      withData: kIsWeb,
      withReadStream: !kIsWeb,
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

  EdgeInsets get _stepPadding => EdgeInsets.all(_isCompactLayout ? 28 : 32);

  // ---- UI Helper Widgets ----

  InputDecoration _buildInputDecoration(String label, {String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      filled: true,
      fillColor: const Color(0xFFF7F8FA),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 18,
        vertical: _isCompactLayout ? 14 : 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade300, width: 1.0),
      ),
      labelStyle: TextStyle(
        fontSize: _isCompactLayout ? 13 : 14,
        color: Colors.grey[600],
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        fontSize: _isCompactLayout ? 13 : 14,
        color: Colors.grey[400],
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 14,
        color: Theme.of(context).primaryColor,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSectionHeader(String title, String emoji) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(_isCompactLayout ? 10 : 12),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            emoji,
            style: TextStyle(fontSize: _isCompactLayout ? 20 : 24),
          ),
        ),
        SizedBox(width: _isCompactLayout ? 14 : 16),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: _isCompactLayout ? 16 : 22,
              fontWeight: FontWeight.w600,
              color: Colors.grey[900],
              letterSpacing: -0.5,
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
    final primaryColor = Theme.of(context).primaryColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: value ? primaryColor.withValues(alpha: 0.04) : Colors.white,
        border: Border.all(
          color: value
              ? primaryColor.withValues(alpha: 0.5)
              : Colors.grey[200]!,
          width: value ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: value
            ? [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _isCompactLayout ? 16 : 20,
              vertical: _isCompactLayout ? 14 : 16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: _isCompactLayout ? 12 : 14,
                      fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                      color: value ? primaryColor : Colors.grey[800],
                    ),
                  ),
                ),
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      checkboxTheme: CheckboxThemeData(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        side: BorderSide(
                          color: value ? primaryColor : Colors.grey[400]!,
                          width: 1.5,
                        ),
                      ),
                    ),
                    child: Checkbox(
                      value: value,
                      onChanged: onChanged,
                      activeColor: primaryColor,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                dialogTheme: DialogThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
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
          style: TextStyle(
            fontSize: _isCompactLayout ? 13 : 14,
            fontWeight: FontWeight.w500,
          ),
          decoration:
              _buildInputDecoration(
                label,
                hintText: hintText ?? 'Select date',
              ).copyWith(
                prefixIcon: const Icon(Icons.calendar_month_rounded, size: 18),
                suffixIcon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                ),
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
                timePickerTheme: TimePickerThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
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
          style: TextStyle(
            fontSize: _isCompactLayout ? 13 : 14,
            fontWeight: FontWeight.w500,
          ),
          decoration:
              _buildInputDecoration(
                label,
                hintText: hintText ?? 'Select time',
              ).copyWith(
                prefixIcon: const Icon(Icons.access_time_rounded, size: 18),
                suffixIcon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildEventSummary() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1.0),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(_isCompactLayout ? 16 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.event.title,
                      style: GoogleFonts.poppins(
                        fontSize: _isCompactLayout ? 15 : 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[900],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month_rounded,
                          size: 16,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.event.startTime.toString().split(' ')[0]} - ${widget.event.endTime.toString().split(' ')[0]}',
                          style: TextStyle(
                            fontSize: _isCompactLayout ? 12 : 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_formatTime(widget.event.startTime)} to ${_formatTime(widget.event.endTime)}',
                          style: TextStyle(
                            fontSize: _isCompactLayout ? 11 : 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
          _buildSectionHeader('FACILITY MANAGER REQUEST', '🏢'),
          const SizedBox(height: 20),
          _buildEventSummary(),
          const SizedBox(height: 32),
          Text(
            'Message Details',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            readOnly: true,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration: _buildInputDecoration('From').copyWith(
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
              hintText: widget.requesterEmail.isEmpty
                  ? 'Your account'
                  : widget.requesterEmail,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _facilityToController,
            onChanged: (v) => _facilityForm['to'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration:
                _buildInputDecoration(
                  'To',
                  hintText: _routingEmailsLoading
                      ? 'Loading facility manager email...'
                      : 'facilitymanager@campus.edu',
                ).copyWith(
                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
                ),
          ),
          const SizedBox(height: 32),
          Text(
            'Requirements:',
            style: GoogleFonts.poppins(
              fontSize: _isCompactLayout ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          _buildCheckboxCard(
            title: 'Venue setup',
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
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => _facilityForm['other_notes'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration: _buildInputDecoration(
              'Others',
              hintText: 'Add additional notes for the facility manager.',
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
          _buildSectionHeader('IT SUPPORT REQUEST', '💻'),
          const SizedBox(height: 20),
          _buildEventSummary(),
          const SizedBox(height: 32),
          Text(
            'Message Details',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            readOnly: true,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration: _buildInputDecoration('From').copyWith(
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 18),
              hintText: widget.requesterEmail.isEmpty
                  ? 'Your account'
                  : widget.requesterEmail,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _itToController,
            onChanged: (v) => _itForm['to'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration:
                _buildInputDecoration(
                  'To',
                  hintText: _routingEmailsLoading
                      ? 'Loading IT department email...'
                      : 'it@campus.edu',
                ).copyWith(
                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
                ),
          ),
          const SizedBox(height: 32),
          Text(
            'Event mode',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment<String>(
                    value: 'online',
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Online',
                        style: TextStyle(
                          fontSize: _isCompactLayout ? 12 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.wifi_rounded, size: 18),
                  ),
                  ButtonSegment<String>(
                    value: 'offline',
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Offline',
                        style: TextStyle(
                          fontSize: _isCompactLayout ? 12 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.wifi_off_rounded, size: 18),
                  ),
                ],
                selected: {(_itForm['event_mode'] ?? 'offline').toString()},
                onSelectionChanged: (selection) {
                  setState(() => _itForm['event_mode'] = selection.first);
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith<Color>((
                    Set<WidgetState> states,
                  ) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context).primaryColor;
                    }
                    return Colors.transparent;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith<Color>((
                    Set<WidgetState> states,
                  ) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return Colors.grey[600]!;
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  side: WidgetStateProperty.all(BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Requirements:',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          _buildCheckboxCard(
            title: 'Audio System',
            value: _itForm['pa_system'],
            onChanged: (v) => setState(() => _itForm['pa_system'] = v ?? false),
          ),
          _buildCheckboxCard(
            title: 'Projection',
            value: _itForm['projection'],
            onChanged: (v) =>
                setState(() => _itForm['projection'] = v ?? false),
          ),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) => _itForm['other_notes'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration: _buildInputDecoration(
              'Others',
              hintText: 'Add additional notes for IT.',
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
          _buildSectionHeader('MARKETING REQUEST', '📢'),
          const SizedBox(height: 20),
          _buildEventSummary(),
          const SizedBox(height: 32),
          TextField(
            controller: _marketingToController,
            onChanged: (v) => _marketingForm['to'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration:
                _buildInputDecoration(
                  'To',
                  hintText: _routingEmailsLoading
                      ? 'Loading marketing email...'
                      : 'marketing@campus.edu',
                ).copyWith(
                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
                ),
          ),
          const SizedBox(height: 32),
          Text(
            'Requirements:',
            style: GoogleFonts.poppins(
              fontSize: _isCompactLayout ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          _buildPhaseGroup('Pre-Event', [
            _buildCheckboxCard(
              title: 'Poster',
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
          const SizedBox(height: 20),
          _buildPhaseGroup('During Event', [
            _buildCheckboxCard(
              title: 'Photography',
              value: req['during_event']['photo'],
              onChanged: (v) =>
                  setState(() => req['during_event']['photo'] = v ?? false),
            ),
            _buildCheckboxCard(
              title: 'Videography',
              value: req['during_event']['video'],
              onChanged: (v) =>
                  setState(() => req['during_event']['video'] = v ?? false),
            ),
          ]),
          const SizedBox(height: 20),
          _buildPhaseGroup('Post-Event', [
            _buildCheckboxCard(
              title: 'Social Media Post',
              value: req['post_event']['social_media'],
              onChanged: (v) => setState(
                () => req['post_event']['social_media'] = v ?? false,
              ),
            ),
            _buildCheckboxCard(
              title: 'Photo Upload',
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
          const SizedBox(height: 20),
          TextField(
            onChanged: (v) => _marketingForm['other_notes'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration: _buildInputDecoration(
              'Others',
              hintText: 'Add additional notes for the marketing team.',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Any necessary documents (optional)',
                  style: GoogleFonts.poppins(
                    fontSize: _isCompactLayout ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Max $_maxMarketingRequesterFiles',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Up to $_maxMarketingRequesterFiles files, $_maxMarketingRequesterFileMb MB each (PDF, Word, images, text). Files upload after the request is created; Google must be connected.',
            style: TextStyle(
              fontSize: _isCompactLayout ? 11 : 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _status == 'loading'
                  ? null
                  : _pickMarketingAttachments,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(
                'Browse Files',
                style: TextStyle(
                  fontSize: _isCompactLayout ? 13 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _marketingAttachments.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Column(
                      children: List.generate(_marketingAttachments.length, (
                        index,
                      ) {
                        final file = _marketingAttachments[index];
                        final sizeMb = file.size / (1024 * 1024);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.insert_drive_file_rounded,
                                  color: Theme.of(context).primaryColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${sizeMb.toStringAsFixed(1)} MB',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: _status == 'loading'
                                    ? null
                                    : () => _removeMarketingAttachmentAt(index),
                                icon: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red.shade400,
                                    size: 18,
                                  ),
                                ),
                                tooltip: 'Remove',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseGroup(String title, List<Widget> children) {
    return Container(
      padding: EdgeInsets.all(_isCompactLayout ? 16 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  letterSpacing: 1.0,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  // UPDATED: Completely revamped Transport UI logic with visual timelines and grouped sections
  Widget _buildTransportStep() {
    return SingleChildScrollView(
      padding: _stepPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('TRANSPORT REQUEST', '🚕'),
          const SizedBox(height: 20),
          _buildEventSummary(),
          const SizedBox(height: 32),
          TextField(
            controller: _transportToController,
            onChanged: (v) => _transportForm['to'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration:
                _buildInputDecoration(
                  'To',
                  hintText: _routingEmailsLoading
                      ? 'Loading transport email...'
                      : 'transport@campus.edu',
                ).copyWith(
                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
                ),
          ),
          const SizedBox(height: 32),
          Text(
            'Transport arrangement (you can select both)',
            style: GoogleFonts.poppins(
              fontSize: _isCompactLayout ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          _buildCheckboxCard(
            title: 'Cab for guest',
            value: _transportForm['include_guest_cab'],
            onChanged: (v) => setState(
              () => _transportForm['include_guest_cab'] = v ?? false,
            ),
          ),
          _buildCheckboxCard(
            title: 'Students (off-campus event)',
            value: _transportForm['include_students'],
            onChanged: (v) =>
                setState(() => _transportForm['include_students'] = v ?? false),
          ),

          if (_transportForm['include_guest_cab']) ...[
            const SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(_isCompactLayout ? 16 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade100, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.05),
                    blurRadius: 10,
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
                        Icons.local_taxi_rounded,
                        size: 18,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Guest cab',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.0,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Pickup Timeline Section
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Icon(
                            Icons.trip_origin_rounded,
                            size: 16,
                            color: Theme.of(context).primaryColor,
                          ),
                          Container(
                            height: 60, // visual connection line
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              onChanged: (v) =>
                                  _transportForm['guest_pickup_location'] = v,
                              style: TextStyle(
                                fontSize: _isCompactLayout ? 13 : 14,
                              ),
                              decoration:
                                  _buildInputDecoration(
                                    'Pick up location',
                                    hintText: 'Address or landmark',
                                  ).copyWith(
                                    prefixIcon: Icon(
                                      Icons.my_location_rounded,
                                      size: 18,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildDatePickerField(
                                    label: 'Pick up date',
                                    formKey: 'guest_pickup_date',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: _buildTimePickerField(
                                    label: 'Pick up time',
                                    formKey: 'guest_pickup_time',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Dropoff Timeline Section
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 18,
                        color: Colors.redAccent.shade400,
                      ),
                      const SizedBox(
                        width: 14,
                      ), // slightly less due to icon size difference
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              onChanged: (v) =>
                                  _transportForm['guest_dropoff_location'] = v,
                              style: TextStyle(
                                fontSize: _isCompactLayout ? 13 : 14,
                              ),
                              decoration:
                                  _buildInputDecoration(
                                    'Drop off location',
                                    hintText: 'Address or landmark',
                                  ).copyWith(
                                    prefixIcon: Icon(
                                      Icons.flag_rounded,
                                      size: 18,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _buildDatePickerField(
                                    label: 'Drop off date (optional)',
                                    formKey: 'guest_dropoff_date',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: _buildTimePickerField(
                                    label: 'Drop off time',
                                    formKey: 'guest_dropoff_time',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (_transportForm['include_students']) ...[
            const SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(_isCompactLayout ? 16 : 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange.shade100, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.05),
                    blurRadius: 10,
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
                        Icons.groups_rounded,
                        size: 18,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Student transport',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.0,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => _transportForm['student_count'] = v,
                          style: TextStyle(
                            fontSize: _isCompactLayout ? 13 : 14,
                          ),
                          decoration:
                              _buildInputDecoration(
                                'Number of students',
                                hintText: 'e.g. 50',
                              ).copyWith(
                                prefixIcon: Icon(
                                  Icons.people_alt_rounded,
                                  size: 18,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          onChanged: (v) =>
                              _transportForm['student_transport_kind'] = v,
                          style: TextStyle(
                            fontSize: _isCompactLayout ? 13 : 14,
                          ),
                          decoration:
                              _buildInputDecoration(
                                'Kind of transport',
                                hintText: 'e.g. bus, van',
                              ).copyWith(
                                prefixIcon: Icon(
                                  Icons.directions_bus_rounded,
                                  size: 18,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (v) =>
                        _transportForm['student_pickup_point'] = v,
                    style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
                    decoration:
                        _buildInputDecoration(
                          'Pick up point',
                          hintText: 'Meeting point for students',
                        ).copyWith(
                          prefixIcon: Icon(
                            Icons.meeting_room_rounded,
                            size: 18,
                            color: Colors.grey.shade500,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            onChanged: (v) => _transportForm['other_notes'] = v,
            style: TextStyle(fontSize: _isCompactLayout ? 13 : 14),
            decoration: _buildInputDecoration(
              'Additional notes',
              hintText: 'Any other details for transport.',
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
          _buildSectionHeader('Review & Submit', '📝'),
          const SizedBox(height: 20),
          _buildEventSummary(),
          const SizedBox(height: 32),
          Text(
            'Request Summary',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade200, width: 1.0),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red[700],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'All departments were skipped. Go back to include at least one request, or close to cancel.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red[900],
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
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
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.do_not_disturb_alt_rounded,
              color: Colors.grey[500],
              size: 18,
            ),
          ),
          const SizedBox(width: 16),
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
              const SizedBox(height: 4),
              Text(
                'Skipped — No request will be sent.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItemCard(String dept) {
    final title = _getDeptReviewLabel(dept);
    final primaryColor = Theme.of(context).primaryColor;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(
                  color: primaryColor.withValues(alpha: 0.1),
                  width: 1.0,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: primaryColor, size: 18),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey[900],
                  ),
                ),
              ],
            ),
          ),
          // Card Body
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dept == 'facility') ...[
                  _buildReviewLine(
                    'To',
                    _facilityForm['to'].isEmpty
                        ? 'Default facility desk'
                        : _facilityForm['to'],
                  ),
                  _buildReviewLine(
                    'Venue setup',
                    _facilityForm['venue_required'] ? 'Yes' : 'No',
                  ),
                  _buildReviewLine(
                    'Refreshments',
                    _facilityForm['refreshments'] ? 'Yes' : 'No',
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
                    _itForm['event_mode'] == 'online' ? 'Online' : 'Offline',
                  ),
                  _buildReviewLine(
                    'Audio System',
                    _itForm['pa_system'] ? 'Yes' : 'No',
                  ),
                  _buildReviewLine(
                    'Projection',
                    _itForm['projection'] ? 'Yes' : 'No',
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
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                    _transportForm['include_guest_cab'] ? 'Yes' : 'No',
                  ),
                  _buildReviewLine(
                    'Students',
                    _transportForm['include_students'] ? 'Yes' : 'No',
                  ),
                  if (_transportForm['include_guest_cab'])
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.shade100,
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.local_taxi_rounded,
                                size: 14,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'GUEST ITINERARY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.trip_origin_rounded,
                                size: 14,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_transportForm['guest_pickup_location'] ?? '—'}\n(${_transportForm['guest_pickup_date'] ?? '—'} at ${_transportForm['guest_pickup_time'] ?? ''})',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(
                              left: 6.0,
                              top: 4,
                              bottom: 4,
                            ),
                            child: SizedBox(
                              height: 12,
                              child: VerticalDivider(
                                width: 2,
                                thickness: 1.5,
                                color: Colors.black26,
                              ),
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 14,
                                color: Colors.redAccent.shade400,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_transportForm['guest_dropoff_location'] ?? '—'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (_transportForm['include_students'])
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.shade100,
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.directions_bus_rounded,
                                size: 14,
                                color: Colors.orange.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'STUDENT LOGISTICS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${_transportForm['student_count'] ?? '—'} Students via ${_transportForm['student_transport_kind'] ?? '—'}\nOn ${_transportForm['student_date'] ?? '—'} at ${_transportForm['student_time'] ?? ''}\nPickup: ${_transportForm['student_pickup_point'] ?? '—'}',
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
          ),
        ],
      ),
    );
  }

  String _getDeptReviewLabel(String dept) {
    switch (dept) {
      case 'facility':
        return 'Facility manager';
      case 'it':
        return 'IT';
      case 'marketing':
        return 'Marketing';
      case 'transport':
        return 'Transport';
      default:
        return dept;
    }
  }

  Widget _buildReviewLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w600,
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
      out.add('Pre-Event: Poster');
    }
    if (req['pre_event']['social_media'] == true) {
      out.add('Pre-Event: Social Media Post');
    }
    if (req['during_event']['photo'] == true) {
      out.add('During Event: Photography');
    }
    if (req['during_event']['video'] == true) {
      out.add('During Event: Videography');
    }
    if (req['post_event']['social_media'] == true) {
      out.add('Post-Event: Social Media Post');
    }
    if (req['post_event']['photo_upload'] == true) {
      out.add('Post-Event: Photo Upload');
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
    final isCompact = _isCompactLayout;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF111827) : Colors.white;
    final headerBg = isDark ? const Color(0xFF111827) : Colors.white;
    final titleColor = isDark ? const Color(0xFFE2E8F0) : Colors.grey[900]!;
    final mutedColor = isDark ? const Color(0xFF94A3B8) : Colors.black87;

    if (_departments.isEmpty) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: dialogBg,
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 24 : 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send Requirements',
                style: GoogleFonts.poppins(
                  fontSize: isCompact ? 18 : 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'All department requests are already active. No new requirement can be sent right now.',
                style: TextStyle(
                  fontSize: isCompact ? 13 : 14,
                  height: 1.5,
                  color: mutedColor,
                ),
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  label: Text(
                    'Close',
                    style: TextStyle(
                      fontSize: isCompact ? 13 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 24,
      backgroundColor: dialogBg,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 32,
        vertical: isCompact ? 24 : 40,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          SizedBox(
            width: isCompact ? media.size.width - 32 : 720,
            height: media.size.height * (isCompact ? 0.92 : 0.9),
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 20 : 28,
                    vertical: isCompact ? 16 : 22,
                  ),
                  color: headerBg,
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
                              color: titleColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _phase == 'review'
                                ? 'Finalize your requests'
                                : 'Step ${_currentStep + 1} of $_totalSteps',
                            style: TextStyle(
                              fontSize: isCompact ? 11 : 12,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.grey[600],
                          iconSize: 20,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress Bar
                Stack(
                  children: [
                    Container(
                      height: 4,
                      width: double.infinity,
                      color: Colors.grey[100],
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOutCubic,
                      height: 4,
                      width: media.size.width * progress,
                      decoration: BoxDecoration(
                        color: theme.primaryColor,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(4),
                          bottomRight: Radius.circular(4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primaryColor.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Animated Error Banner
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _errorMessage.isNotEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          color: Colors.red.shade50,
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                color: Colors.red[700],
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _errorMessage,
                                  style: TextStyle(
                                    color: Colors.red[900],
                                    fontSize: isCompact ? 12 : 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),

                // Body (Animated Switcher for smooth step transitions)
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.02, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                      child: KeyedSubtree(
                        key: ValueKey<String>('$_phase-$_currentStep'),
                        child: _buildStep(),
                      ),
                    ),
                  ),
                ),

                // Bottom Navigation Area
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 20 : 28,
                    vertical: isCompact ? 16 : 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        offset: const Offset(0, -8),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        if (_phase == 'edit' && _currentStep > 0 ||
                            _phase == 'review')
                          TextButton.icon(
                            onPressed: _goPrev,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                            ),
                            label: const Text('Back'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              textStyle: TextStyle(
                                fontSize: isCompact ? 13 : 14,
                                fontWeight: FontWeight.w600,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 16 : 20,
                                vertical: isCompact ? 12 : 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          )
                        else
                          const SizedBox(
                            width: 60,
                          ), // Placeholder to balance UI
                        const Spacer(),
                        if (_phase == 'edit')
                          TextButton.icon(
                            onPressed: _skip,
                            icon: const Icon(
                              Icons.keyboard_double_arrow_right_rounded,
                              size: 18,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[500],
                              textStyle: TextStyle(
                                fontSize: isCompact ? 13 : 14,
                                fontWeight: FontWeight.w600,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 16 : 20,
                                vertical: isCompact ? 12 : 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            label: const Text('Skip'),
                          ),
                        SizedBox(width: isCompact ? 12 : 16),
                        if (_phase == 'edit')
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.primaryColor.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FilledButton.icon(
                              onPressed: _goNext,
                              icon: Icon(
                                _currentStep >= _totalSteps - 1
                                    ? Icons.fact_check_outlined
                                    : Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _currentStep >= _totalSteps - 1
                                    ? 'Review'
                                    : 'Next',
                              ),
                              style: FilledButton.styleFrom(
                                textStyle: TextStyle(
                                  fontSize: isCompact ? 13 : 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 24 : 32,
                                  vertical: isCompact ? 14 : 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        if (_phase == 'review')
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.success.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: FilledButton.icon(
                              onPressed:
                                  _status == 'loading' || !_hasAnySelected
                                  ? null
                                  : _sendAll,
                              icon: const Icon(
                                Icons.rocket_launch_rounded,
                                size: 18,
                              ),
                              label: const Text('Send Requests'),
                              style: FilledButton.styleFrom(
                                textStyle: TextStyle(
                                  fontSize: isCompact ? 13 : 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 24 : 32,
                                  vertical: isCompact ? 14 : 16,
                                ),
                                backgroundColor: AppColors.success,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
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

          // Premium Glass Loading Overlay
          if (_status == 'loading')
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.6),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 42,
                              height: 42,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                strokeCap: StrokeCap.round,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Processing Requests...',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[900],
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
        ],
      ),
    );
  }
}
