import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  int _step = 0;

  // Step 1 fields
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _audienceCtrl = TextEditingController();

  // Step 2 fields
  Venue? _selectedVenue;
  DateTime? _startDate;
  TimeOfDay? _startTime;
  DateTime? _endDate;
  TimeOfDay? _endTime;

  List<Venue> _venues = [];
  bool _loadingVenues = false;
  bool _checkingConflicts = false;
  bool _hasConflict = false;
  bool _overrideConflict = false;
  List<dynamic> _conflicts = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _audienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVenues() async {
    setState(() => _loadingVenues = true);
    try {
      final data = await _api.get<Map<String, dynamic>>('/venues');
      setState(() {
        _venues = (data['items'] as List? ?? data['venues'] as List? ?? [])
            .map((v) => Venue.fromJson(v))
            .toList();
        _loadingVenues = false;
      });
    } catch (_) {
      setState(() => _loadingVenues = false);
    }
  }

  DateTime? get _startDateTime {
    if (_startDate == null || _startTime == null) return null;
    return DateTime(
      _startDate!.year, _startDate!.month, _startDate!.day,
      _startTime!.hour, _startTime!.minute,
    );
  }

  DateTime? get _endDateTime {
    if (_endDate == null || _endTime == null) return null;
    return DateTime(
      _endDate!.year, _endDate!.month, _endDate!.day,
      _endTime!.hour, _endTime!.minute,
    );
  }

  Future<void> _checkConflicts() async {
    if (_selectedVenue == null || _startDateTime == null || _endDateTime == null) return;
    setState(() {
      _checkingConflicts = true;
      _hasConflict = false;
      _conflicts = [];
    });
    try {
      final iso = (DateTime dt) => dt.toIso8601String();
      final data = await _api.post<Map<String, dynamic>>('/events/conflicts', data: {
        'venue_name': _selectedVenue!.name,
        'start_datetime': iso(_startDateTime!),
        'end_datetime': iso(_endDateTime!),
      });
      final conflicts = data['conflicts'] as List? ?? [];
      setState(() {
        _conflicts = conflicts;
        _hasConflict = conflicts.isNotEmpty;
        _checkingConflicts = false;
      });
    } catch (_) {
      setState(() => _checkingConflicts = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final iso = (DateTime dt) => dt.toIso8601String();
      await _api.post('/events', data: {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'venue_name': _selectedVenue!.name,
        'start_datetime': iso(_startDateTime!),
        'end_datetime': iso(_endDateTime!),
        'notes': _notesCtrl.text.trim(),
        'audience_count': int.tryParse(_audienceCtrl.text.trim()) ?? 0,
        'override_conflict': _overrideConflict,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event submitted for approval!')),
        );
        context.go('/events');
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/events');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create Event'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
      ),
      body: LoadingOverlay(
        isLoading: _submitting,
        message: 'Submitting event...',
        child: Column(
          children: [
            _StepIndicator(currentStep: _step, steps: const ['Details', 'Schedule', 'Review']),
            Expanded(
              child: Form(
                key: _formKey,
                child: IndexedStack(
                  index: _step,
                  children: [
                    _buildStep1(),
                    _buildStep2(),
                    _buildStep3(),
                  ],
                ),
              ),
            ),
            _buildNavButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Event Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Provide basic information about your event.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          _FieldLabel('Event Title *'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _titleCtrl,
            decoration: const InputDecoration(hintText: 'Enter event title'),
            validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          _FieldLabel('Description'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descCtrl,
            decoration: const InputDecoration(hintText: 'Describe the event...'),
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          _FieldLabel('Expected Audience'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _audienceCtrl,
            decoration: const InputDecoration(hintText: 'Number of attendees'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _FieldLabel('Additional Notes'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _notesCtrl,
            decoration: const InputDecoration(hintText: 'Any additional notes...'),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final df = DateFormat('MMM d, yyyy');
    final tf = DateFormat('h:mm a');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Schedule & Venue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Choose venue and set event dates/times.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          _FieldLabel('Venue *'),
          const SizedBox(height: 6),
          _loadingVenues
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<Venue>(
                  value: _selectedVenue,
                  decoration: const InputDecoration(hintText: 'Select a venue'),
                  items: _venues.map((v) => DropdownMenuItem(value: v, child: Text(v.name))).toList(),
                  onChanged: (v) => setState(() {
                    _selectedVenue = v;
                    _hasConflict = false;
                    _conflicts = [];
                  }),
                  validator: (v) => v == null ? 'Please select a venue' : null,
                ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel('Start Date *'),
                    const SizedBox(height: 6),
                    _DateTile(
                      label: _startDate != null ? df.format(_startDate!) : 'Select',
                      icon: Icons.calendar_today,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setState(() => _startDate = d);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel('Start Time *'),
                    const SizedBox(height: 6),
                    _DateTile(
                      label: _startTime != null ? tf.format(DateTime(0, 1, 1, _startTime!.hour, _startTime!.minute)) : 'Select',
                      icon: Icons.access_time,
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (t != null) setState(() => _startTime = t);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel('End Date *'),
                    const SizedBox(height: 6),
                    _DateTile(
                      label: _endDate != null ? df.format(_endDate!) : 'Select',
                      icon: Icons.calendar_today,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: _startDate ?? DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setState(() => _endDate = d);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FieldLabel('End Time *'),
                    const SizedBox(height: 6),
                    _DateTile(
                      label: _endTime != null ? tf.format(DateTime(0, 1, 1, _endTime!.hour, _endTime!.minute)) : 'Select',
                      icon: Icons.access_time,
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _startTime ?? TimeOfDay.now(),
                        );
                        if (t != null) setState(() => _endTime = t);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkingConflicts ? null : _checkConflicts,
              icon: _checkingConflicts
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_checkingConflicts ? 'Checking...' : 'Check for Conflicts'),
            ),
          ),
          if (_hasConflict) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
                      SizedBox(width: 8),
                      Text('Scheduling Conflict Detected', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.warning)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_conflicts.length} event(s) already scheduled at ${_selectedVenue?.name} during this time.',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Checkbox(
                        value: _overrideConflict,
                        onChanged: (v) => setState(() => _overrideConflict = v ?? false),
                        activeColor: AppColors.warning,
                      ),
                      const Expanded(
                        child: Text(
                          'Override conflict and proceed anyway',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (!_hasConflict && _conflicts.isEmpty && _selectedVenue != null && _startDateTime != null) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: AppColors.success),
                SizedBox(width: 6),
                Text('No conflicts detected', style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3() {
    final df = DateFormat('MMM d, yyyy · h:mm a');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review & Submit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text('Review your event details before submitting for approval.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ReviewRow('Title', _titleCtrl.text),
                _ReviewRow('Description', _descCtrl.text.isEmpty ? 'Not provided' : _descCtrl.text),
                _ReviewRow('Venue', _selectedVenue?.name ?? 'Not selected'),
                _ReviewRow('Start', _startDateTime != null ? df.format(_startDateTime!) : 'Not set'),
                _ReviewRow('End', _endDateTime != null ? df.format(_endDateTime!) : 'Not set'),
                if (_audienceCtrl.text.isNotEmpty)
                  _ReviewRow('Audience', _audienceCtrl.text),
                if (_notesCtrl.text.isNotEmpty)
                  _ReviewRow('Notes', _notesCtrl.text),
                if (_overrideConflict)
                  const _ReviewRow('Conflict', 'Override requested', valueColor: AppColors.warning),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your event will be sent to the Registrar for approval. You will be notified once a decision is made.',
                    style: TextStyle(fontSize: 13, color: AppColors.primary, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                child: const Text('Back'),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () {
                if (_step < 2) {
                  if (_formKey.currentState?.validate() ?? false) {
                    if (_step == 1 && _selectedVenue == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please select a venue')),
                      );
                      return;
                    }
                    if (_step == 1 && (_startDateTime == null || _endDateTime == null)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please set start and end times')),
                      );
                      return;
                    }
                    if (_step == 1 && _hasConflict && !_overrideConflict) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please resolve the conflict or enable override'),
                          backgroundColor: AppColors.warning,
                        ),
                      );
                      return;
                    }
                    setState(() => _step++);
                  }
                } else {
                  _submit();
                }
              },
              child: Text(_step < 2 ? 'Continue' : 'Submit for Approval'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> steps;
  const _StepIndicator({required this.currentStep, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final isActive = e.key <= currentStep;
          final isCurrent = e.key == currentStep;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? AppColors.primary : AppColors.surfaceVariant,
                    border: isCurrent
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: isActive && e.key < currentStep
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : Text(
                            '${e.key + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.white : AppColors.textMuted,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: isCurrent ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
                if (e.key < steps.length - 1) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: isActive ? AppColors.primary : AppColors.border,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _DateTile({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _ReviewRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
