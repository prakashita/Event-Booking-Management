import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
        _status = 'idle';
        _errorMessage = '';
      });
    } else if (_phase == 'review') {
      setState(() {
        _phase = 'edit';
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
    _goNext();
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
        return Container();
    }
  }

  Widget _buildStepHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Step ${_currentStep + 1} of $_totalSteps. Use Next to continue, Prev to go back, or Skip to exclude this department.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue[700],
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityStep() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHint(),
            const SizedBox(height: 16),
            Text(
              'FACILITY MANAGER REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'From',
                border: OutlineInputBorder(),
              ),
              child: Text(
                widget.requesterEmail.isEmpty
                    ? 'Your account'
                    : widget.requesterEmail,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _facilityForm['to'] = v,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'Facility manager email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildEventSummary(),
            const SizedBox(height: 16),
            Text(
              'Requirements:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            CheckboxListTile(
              value: _facilityForm['venue_required'],
              onChanged: (v) =>
                  setState(() => _facilityForm['venue_required'] = v ?? false),
              title: const Text('Venue setup'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _facilityForm['refreshments'],
              onChanged: (v) =>
                  setState(() => _facilityForm['refreshments'] = v ?? false),
              title: const Text('Refreshments'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _facilityForm['other_notes'] = v,
              decoration: InputDecoration(
                labelText: 'Additional notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItStep() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHint(),
            const SizedBox(height: 16),
            Text(
              'IT SUPPORT REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'From',
                border: OutlineInputBorder(),
              ),
              child: Text(
                widget.requesterEmail.isEmpty
                    ? 'Your account'
                    : widget.requesterEmail,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _itForm['to'] = v,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'IT email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildEventSummary(),
            const SizedBox(height: 16),
            Text(
              'Event mode:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(value: 'online', label: Text('Online')),
                ButtonSegment<String>(value: 'offline', label: Text('Offline')),
              ],
              selected: {
                (_itForm['event_mode'] ?? 'offline').toString(),
              },
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                setState(() => _itForm['event_mode'] = selection.first);
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Requirements:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            CheckboxListTile(
              value: _itForm['pa_system'],
              onChanged: (v) =>
                  setState(() => _itForm['pa_system'] = v ?? false),
              title: const Text('PA System'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _itForm['projection'],
              onChanged: (v) =>
                  setState(() => _itForm['projection'] = v ?? false),
              title: const Text('Projection'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _itForm['other_notes'] = v,
              decoration: InputDecoration(
                labelText: 'Additional notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketingStep() {
    final req =
        _marketingForm['marketing_requirements'] as Map<String, dynamic>;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHint(),
            const SizedBox(height: 16),
            Text(
              'MARKETING REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'From',
                border: OutlineInputBorder(),
              ),
              child: Text(
                widget.requesterEmail.isEmpty
                    ? 'Your account'
                    : widget.requesterEmail,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _marketingForm['to'] = v,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'Marketing email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildEventSummary(),
            const SizedBox(height: 16),
            Text(
              'Pre-Event:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            CheckboxListTile(
              value: req['pre_event']['poster'],
              onChanged: (v) =>
                  setState(() => req['pre_event']['poster'] = v ?? false),
              title: const Text('Poster'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['pre_event']['social_media'],
              onChanged: (v) =>
                  setState(() => req['pre_event']['social_media'] = v ?? false),
              title: const Text('Social Media Post'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text(
              'During Event:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            CheckboxListTile(
              value: req['during_event']['photo'],
              onChanged: (v) =>
                  setState(() => req['during_event']['photo'] = v ?? false),
              title: const Text('Photography'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['during_event']['video'],
              onChanged: (v) =>
                  setState(() => req['during_event']['video'] = v ?? false),
              title: const Text('Videoshoot'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text(
              'Post-Event:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            CheckboxListTile(
              value: req['post_event']['social_media'],
              onChanged: (v) => setState(
                () => req['post_event']['social_media'] = v ?? false,
              ),
              title: const Text('Social Media Post'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['post_event']['photo_upload'],
              onChanged: (v) => setState(
                () => req['post_event']['photo_upload'] = v ?? false,
              ),
              title: const Text('Photo Upload'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['post_event']['video'],
              onChanged: (v) =>
                  setState(() => req['post_event']['video'] = v ?? false),
              title: const Text('Video Upload'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _marketingForm['other_notes'] = v,
              decoration: InputDecoration(
                labelText: 'Additional notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransportStep() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHint(),
            const SizedBox(height: 16),
            Text(
              'TRANSPORT REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'From',
                border: OutlineInputBorder(),
              ),
              child: Text(
                widget.requesterEmail.isEmpty
                    ? 'Your account'
                    : widget.requesterEmail,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _transportForm['to'] = v,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'Transport coordinator email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildEventSummary(),
            const SizedBox(height: 16),
            Text(
              'Transport arrangement (you can select both)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            CheckboxListTile(
              value: _transportForm['include_guest_cab'],
              onChanged: (v) => setState(
                () => _transportForm['include_guest_cab'] = v ?? false,
              ),
              title: const Text('Cab for guest'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _transportForm['include_students'],
              onChanged: (v) => setState(
                () => _transportForm['include_students'] = v ?? false,
              ),
              title: const Text('Students (off-campus event)'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_transportForm['include_guest_cab']) ...[
              const SizedBox(height: 12),
              Text(
                'Guest cab details:',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['guest_pickup_location'] = v,
                decoration: InputDecoration(
                  labelText: 'Pickup location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['guest_pickup_date'] = v,
                decoration: InputDecoration(
                  labelText: 'Pickup date',
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['guest_pickup_time'] = v,
                decoration: InputDecoration(
                  labelText: 'Pickup time',
                  hintText: 'HH:MM',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['guest_dropoff_location'] = v,
                decoration: InputDecoration(
                  labelText: 'Dropoff location',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['guest_dropoff_time'] = v,
                decoration: InputDecoration(
                  labelText: 'Dropoff time',
                  hintText: 'HH:MM',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_transportForm['include_students']) ...[
              const SizedBox(height: 12),
              Text(
                'Student transport details:',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['student_count'] = v,
                decoration: InputDecoration(
                  labelText: 'Number of students',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['student_transport_kind'] = v,
                decoration: InputDecoration(
                  labelText: 'Transport kind (e.g., bus, van)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['student_date'] = v,
                decoration: InputDecoration(
                  labelText: 'Date',
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['student_time'] = v,
                decoration: InputDecoration(
                  labelText: 'Time',
                  hintText: 'HH:MM',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => _transportForm['student_pickup_point'] = v,
                decoration: InputDecoration(
                  labelText: 'Pickup point',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => _transportForm['other_notes'] = v,
              decoration: InputDecoration(
                labelText: 'Additional notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review requirements',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildEventSummary(),
            const SizedBox(height: 16),
            ..._departments.map((dept) {
              if (_skipped[dept]!) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getDeptReviewLabel(dept),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Skipped — this request will not be sent.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildReviewItem(dept),
              );
            }),
            if (!_hasAnySelected)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.red[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'All departments were skipped. Close or go back to include at least one request.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
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

  Widget _buildReviewItem(String dept) {
    final title = _getDeptReviewLabel(dept);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (dept == 'facility') ...[
            _buildReviewLine(
              'To',
              _facilityForm['to'].isEmpty
                  ? '(default desk)'
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
              _itForm['to'].isEmpty ? '(default desk)' : _itForm['to'],
            ),
            _buildReviewLine(
              'Mode',
              _itForm['event_mode'] == 'online' ? 'Online' : 'Offline',
            ),
            _buildReviewLine('PA system', _itForm['pa_system'] ? 'Yes' : 'No'),
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
                  ? '(default desk)'
                  : _marketingForm['to'],
            ),
            ..._selectedMarketingLines().map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: const TextStyle(fontSize: 12)),
              ),
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
                  ? '(default desk)'
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
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Guest: ${_transportForm['guest_pickup_location'] ?? '—'} → ${_transportForm['guest_dropoff_location'] ?? '—'} (${_transportForm['guest_pickup_date'] ?? '—'} ${_transportForm['guest_pickup_time'] ?? ''})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (_transportForm['include_students'])
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Students: ${_transportForm['student_count'] ?? '—'} via ${_transportForm['student_transport_kind'] ?? '—'} on ${_transportForm['student_date'] ?? '—'} ${_transportForm['student_time'] ?? ''} @ ${_transportForm['student_pickup_point'] ?? '—'}',
                  style: const TextStyle(fontSize: 12),
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

  Widget _buildReviewLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
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
      out.add('During Event: Videoshoot');
    }
    if (req['post_event']['social_media'] == true) {
      out.add('Post-Event: Social Media Upload');
    }
    if (req['post_event']['photo_upload'] == true) {
      out.add('Post-Event: Photo Upload');
    }
    if (req['post_event']['video'] == true) {
      out.add('Post-Event: Video Upload');
    }
    if (out.isEmpty) {
      out.add('No marketing items selected.');
    }
    return out;
  }

  Widget _buildEventSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event: ${widget.event.title}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'Date: ${widget.event.startTime.toString().split(' ')[0]} to ${widget.event.endTime.toString().split(' ')[0]}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 2),
          Text(
            'Time: ${_formatTime(widget.event.startTime)} to ${_formatTime(widget.event.endTime)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_departments.isEmpty) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send Requirements',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'All department requests are already active. No new requirement can be sent right now.',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: 720,
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _phase == 'review'
                        ? 'Review requirements'
                        : 'Send Requirements',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildStep()),
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.red[50],
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (_phase == 'edit')
                    ElevatedButton(
                      onPressed: _currentStep > 0 ? _goPrev : null,
                      child: const Text('Prev'),
                    ),
                  if (_phase == 'review')
                    ElevatedButton(
                      onPressed: _goPrev,
                      child: const Text('Prev'),
                    ),
                  if (_phase == 'edit')
                    ElevatedButton(onPressed: _skip, child: const Text('Skip')),
                  if (_phase == 'edit')
                    ElevatedButton(
                      onPressed: _goNext,
                      child: Text(
                        _currentStep >= _totalSteps - 1 ? 'Review' : 'Next',
                      ),
                    ),
                  if (_phase == 'review')
                    ElevatedButton(
                      onPressed: _status == 'loading' || !_hasAnySelected
                          ? null
                          : _sendAll,
                      child: Text(_status == 'loading' ? 'Sending...' : 'Send'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
