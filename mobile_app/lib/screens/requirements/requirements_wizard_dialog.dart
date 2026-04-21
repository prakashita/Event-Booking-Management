import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';

class RequirementsWizardDialog extends StatefulWidget {
  final Event event;
  final VoidCallback onSuccess;

  const RequirementsWizardDialog({
    super.key,
    required this.event,
    required this.onSuccess,
  });

  @override
  State<RequirementsWizardDialog> createState() =>
      _RequirementsWizardDialogState();
}

class _RequirementsWizardDialogState extends State<RequirementsWizardDialog> {
  final _api = ApiService();
  
  // Departments in order
  final List<String> _departments = [
    'facility',
    'it',
    'marketing',
    'transport'
  ];
  
  int _currentStep = 0;
  String _phase = 'edit'; // 'edit' or 'review'
  
  // Track skipped departments
  final Map<String, bool> _skipped = {
    'facility': false,
    'it': false,
    'marketing': false,
    'transport': false,
  };
  
  // Form data
  final Map<String, dynamic> _facilityForm = {
    'to': '',
    'venue_required': false,
    'refreshments': false,
    'other_notes': '',
  };
  
  final Map<String, dynamic> _itForm = {
    'to': '',
    'event_mode': 'offline',
    'pa_system': false,
    'projection': false,
    'other_notes': '',
  };
  
  final Map<String, dynamic> _marketingForm = {
    'to': '',
    'requirements': {
      'pre_event': {'poster': false, 'social_media': false},
      'during_event': {'photo': false, 'video': false},
      'post_event': {
        'social_media': false,
        'photo_upload': false,
        'video': false,
      }
    },
    'other_notes': '',
  };
  
  final Map<String, dynamic> _transportForm = {
    'to': '',
    'include_guest_cab': false,
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
  bool get _hasAnySelected =>
      _departments.any((d) => !_skipped[d]!);
  
  int get _totalSteps => _departments.length;

  void _goNext() {
    if (_phase == 'edit') {
      if (_currentStep < _totalSteps - 1) {
        setState(() => _currentStep++);
      } else {
        setState(() => _phase = 'review');
      }
    }
  }

  void _goPrev() {
    if (_phase == 'edit' && _currentStep > 0) {
      setState(() => _currentStep--);
    } else if (_phase == 'review') {
      setState(() => _phase = 'edit');
    }
  }

  void _skip() {
    setState(() => _skipped[_currentDept] = true);
    _goNext();
  }

  Future<void> _sendAll() async {
    if (!_hasAnySelected) return;
    
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

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All requirements sent successfully!'),
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
        'requested_to': _facilityForm['to'].isEmpty ? null : _facilityForm['to'],
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
        'requested_to': _marketingForm['to'].isEmpty ? null : _marketingForm['to'],
        'event_id': widget.event.id,
        'event_name': widget.event.title,
        'start_date': widget.event.startTime.toString().split(' ')[0],
        'start_time': _formatTime(widget.event.startTime),
        'end_date': widget.event.endTime.toString().split(' ')[0],
        'end_time': _formatTime(widget.event.endTime),
        'marketing_requirements': _marketingForm['requirements'],
        'other_notes': _marketingForm['other_notes'],
      },
    );
    if (res == null) throw Exception('Failed to send marketing request');
  }

  Future<void> _sendTransportRequest() async {
    // Validate transport
    final wantsGuest = _transportForm['include_guest_cab'] as bool;
    final wantsStudents = _transportForm['include_students'] as bool;
    
    if (!wantsGuest && !wantsStudents) {
      throw Exception('Select at least one transport option');
    }
    
    if (wantsGuest) {
      if (_transportForm['guest_pickup_location'].toString().isEmpty) {
        throw Exception('Guest pickup location is required');
      }
      if (_transportForm['guest_pickup_date'].toString().isEmpty) {
        throw Exception('Guest pickup date is required');
      }
      if (_transportForm['guest_dropoff_location'].toString().isEmpty) {
        throw Exception('Guest dropoff location is required');
      }
    }
    
    if (wantsStudents) {
      if (_transportForm['student_count'].toString().isEmpty) {
        throw Exception('Student count is required');
      }
      if (_transportForm['student_transport_kind'].toString().isEmpty) {
        throw Exception('Transport kind is required');
      }
      if (_transportForm['student_date'].toString().isEmpty) {
        throw Exception('Student date is required');
      }
      if (_transportForm['student_pickup_point'].toString().isEmpty) {
        throw Exception('Pickup point is required');
      }
    }
    
    final transportType = wantsGuest && wantsStudents
        ? 'both'
        : wantsGuest
            ? 'guest_cab'
            : 'students_off_campus';
    
    final studentCountParsed = int.tryParse(_transportForm['student_count'].toString()) ?? 0;
    
    final res = await _api.post(
      '/transport/requests',
      data: {
        'requested_to': _transportForm['to'].isEmpty ? null : _transportForm['to'],
        'event_id': widget.event.id,
        'event_name': widget.event.title,
        'start_date': widget.event.startTime.toString().split(' ')[0],
        'start_time': _formatTime(widget.event.startTime),
        'end_date': widget.event.endTime.toString().split(' ')[0],
        'end_time': _formatTime(widget.event.endTime),
        'transport_type': transportType,
        'guest_pickup_location': wantsGuest ? _transportForm['guest_pickup_location'] : null,
        'guest_pickup_date': wantsGuest ? _transportForm['guest_pickup_date'] : null,
        'guest_pickup_time': wantsGuest ? _transportForm['guest_pickup_time'] : null,
        'guest_dropoff_location': wantsGuest ? _transportForm['guest_dropoff_location'] : null,
        'guest_dropoff_date': wantsGuest ? _transportForm['guest_dropoff_date'] : null,
        'guest_dropoff_time': wantsGuest ? _transportForm['guest_dropoff_time'] : null,
        'student_count': wantsStudents && studentCountParsed > 0 ? studentCountParsed : null,
        'student_transport_kind': wantsStudents ? _transportForm['student_transport_kind'] : null,
        'student_date': wantsStudents ? _transportForm['student_date'] : null,
        'student_time': wantsStudents ? _transportForm['student_time'] : null,
        'student_pickup_point': wantsStudents ? _transportForm['student_pickup_point'] : null,
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

  Widget _buildFacilityStep() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step ${_currentStep + 1} of $_totalSteps',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'FACILITY MANAGER REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'From',
                hintText: 'Your email',
                border: OutlineInputBorder(),
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
            Text('Requirements:', style: const TextStyle(fontWeight: FontWeight.w600)),
            CheckboxListTile(
              value: _facilityForm['venue_required'],
              onChanged: (v) => setState(() => _facilityForm['venue_required'] = v ?? false),
              title: const Text('Venue setup'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _facilityForm['refreshments'],
              onChanged: (v) => setState(() => _facilityForm['refreshments'] = v ?? false),
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
            Text(
              'Step ${_currentStep + 1} of $_totalSteps',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'IT SUPPORT REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'From',
                border: OutlineInputBorder(),
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
            Text('Event mode:', style: const TextStyle(fontWeight: FontWeight.w600)),
            RadioListTile(
              value: 'online',
              groupValue: _itForm['event_mode'],
              onChanged: (v) => setState(() => _itForm['event_mode'] = v),
              title: const Text('Online'),
              contentPadding: EdgeInsets.zero,
            ),
            RadioListTile(
              value: 'offline',
              groupValue: _itForm['event_mode'],
              onChanged: (v) => setState(() => _itForm['event_mode'] = v),
              title: const Text('Offline'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            Text('Requirements:', style: const TextStyle(fontWeight: FontWeight.w600)),
            CheckboxListTile(
              value: _itForm['pa_system'],
              onChanged: (v) => setState(() => _itForm['pa_system'] = v ?? false),
              title: const Text('PA System'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _itForm['projection'],
              onChanged: (v) => setState(() => _itForm['projection'] = v ?? false),
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
    final req = _marketingForm['requirements'] as Map<String, dynamic>;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step ${_currentStep + 1} of $_totalSteps',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'MARKETING REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'From',
                border: OutlineInputBorder(),
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
            Text('Pre-Event:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            CheckboxListTile(
              value: req['pre_event']['poster'],
              onChanged: (v) => setState(() => req['pre_event']['poster'] = v ?? false),
              title: const Text('Poster'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['pre_event']['social_media'],
              onChanged: (v) => setState(() => req['pre_event']['social_media'] = v ?? false),
              title: const Text('Social Media Post'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text('During Event:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            CheckboxListTile(
              value: req['during_event']['photo'],
              onChanged: (v) => setState(() => req['during_event']['photo'] = v ?? false),
              title: const Text('Photography'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['during_event']['video'],
              onChanged: (v) => setState(() => req['during_event']['video'] = v ?? false),
              title: const Text('Videoshoot'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Text('Post-Event:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
            CheckboxListTile(
              value: req['post_event']['social_media'],
              onChanged: (v) => setState(() => req['post_event']['social_media'] = v ?? false),
              title: const Text('Social Media Post'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['post_event']['photo_upload'],
              onChanged: (v) => setState(() => req['post_event']['photo_upload'] = v ?? false),
              title: const Text('Photo Upload'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: req['post_event']['video'],
              onChanged: (v) => setState(() => req['post_event']['video'] = v ?? false),
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
            Text(
              'Step ${_currentStep + 1} of $_totalSteps',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'TRANSPORT REQUEST',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'From',
                border: OutlineInputBorder(),
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
              onChanged: (v) => setState(() => _transportForm['include_guest_cab'] = v ?? false),
              title: const Text('Cab for guest'),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _transportForm['include_students'],
              onChanged: (v) => setState(() => _transportForm['include_students'] = v ?? false),
              title: const Text('Students (off-campus event)'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_transportForm['include_guest_cab']) ...[
              const SizedBox(height: 12),
              Text('Guest cab details:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
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
              Text('Student transport details:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
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
                  child: Text(
                    '${dept.toUpperCase()}: Skipped',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildReviewItem(dept),
              );
            }).toList(),
            if (!_hasAnySelected)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'All departments were skipped.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewItem(String dept) {
    final title = dept == 'facility'
        ? 'Facility'
        : dept == 'it'
            ? 'IT'
            : dept == 'marketing'
                ? 'Marketing'
                : 'Transport';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (dept == 'facility') ...[
          Text('To: ${_facilityForm['to'].isEmpty ? '(default)' : _facilityForm['to']}', style: const TextStyle(fontSize: 12)),
          Text('Venue: ${_facilityForm['venue_required'] ? 'Yes' : 'No'}', style: const TextStyle(fontSize: 12)),
          Text('Refreshments: ${_facilityForm['refreshments'] ? 'Yes' : 'No'}', style: const TextStyle(fontSize: 12)),
        ] else if (dept == 'it') ...[
          Text('To: ${_itForm['to'].isEmpty ? '(default)' : _itForm['to']}', style: const TextStyle(fontSize: 12)),
          Text('Mode: ${_itForm['event_mode']}', style: const TextStyle(fontSize: 12)),
          Text('PA System: ${_itForm['pa_system'] ? 'Yes' : 'No'}', style: const TextStyle(fontSize: 12)),
          Text('Projection: ${_itForm['projection'] ? 'Yes' : 'No'}', style: const TextStyle(fontSize: 12)),
        ] else if (dept == 'marketing') ...[
          Text('To: ${_marketingForm['to'].isEmpty ? '(default)' : _marketingForm['to']}', style: const TextStyle(fontSize: 12)),
          Text('Pre-Event items selected', style: const TextStyle(fontSize: 12)),
        ] else if (dept == 'transport') ...[
          Text('To: ${_transportForm['to'].isEmpty ? '(default)' : _transportForm['to']}', style: const TextStyle(fontSize: 12)),
          Text('Guest cab: ${_transportForm['include_guest_cab'] ? 'Yes' : 'No'}', style: const TextStyle(fontSize: 12)),
          Text('Students: ${_transportForm['include_students'] ? 'Yes' : 'No'}', style: const TextStyle(fontSize: 12)),
        ],
        const Divider(),
      ],
    );
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
          Text('Event: ${widget.event.title}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  _phase == 'review' ? 'Review requirements' : 'Send Requirements',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
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
                  ElevatedButton(
                    onPressed: _skip,
                    child: const Text('Skip'),
                  ),
                if (_phase == 'edit')
                  ElevatedButton(
                    onPressed: _goNext,
                    child: Text(_currentStep >= _totalSteps - 1 ? 'Review' : 'Next'),
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
    );
  }
}
