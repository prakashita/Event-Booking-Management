import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late Future<List<dynamic>> _future;
  String _searchQuery = '';
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final data = await widget.api.get('/events');
    return asList(data);
  }

  List<dynamic> _filter(List<dynamic> events) {
    return events.where((e) {
      final m = asMap(e);
      final name = m['name']?.toString().toLowerCase() ?? '';
      final status = m['status']?.toString() ?? 'pending';
      final matchesSearch =
          _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
      final matchesStatus =
          _statusFilter == 'all' || status == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  Future<void> _createEvent() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CreateEventDialog(),
    );
    if (payload == null) return;
    try {
      await widget.api.post('/events', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event created successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: 'My Events',
      subtitle: 'Create and manage your event lifecycle end-to-end.',
      action: FilledButton.icon(
        onPressed: _createEvent,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('New Event'),
      ),
      child: Column(
        children: [
          // Search + filter row
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search events…',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _statusFilter,
                  borderRadius: BorderRadius.circular(12),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                        value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(
                        value: 'rejected', child: Text('Rejected')),
                    DropdownMenuItem(
                        value: 'completed', child: Text('Completed')),
                  ],
                  onChanged: (v) =>
                      setState(() => _statusFilter = v ?? 'all'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<dynamic>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const ShimmerLoader();
              }
              if (snap.hasError) {
                return ErrorCard(
                  error: snap.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                );
              }

              final filtered = _filter(snap.data ?? []);
              if (filtered.isEmpty) {
                return const EmptyCard(
                  message: 'No events found. Create one to get started.',
                  icon: Icons.event_busy_rounded,
                );
              }

              return Column(
                children: filtered.map((e) {
                  final m = asMap(e);
                  return _EventCard(
                    event: m,
                    onDelete: () => _deleteEvent(m),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final id = event['event_id'] ?? event['id'];
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text(
          'Delete "${event['name'] ?? 'this event'}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.api.delete('/events/$id');
      if (!mounted) return;
      setState(() => _future = _load());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, this.onDelete});

  final Map<String, dynamic> event;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final name = event['name']?.toString() ?? 'Untitled';
    final venue = event['venue_name']?.toString() ?? 'No venue';
    final startDate = event['start_date']?.toString() ?? '-';
    final startTime = event['start_time']?.toString() ?? '';
    final status = event['status']?.toString() ?? 'pending';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.event_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            venue,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  '$startDate  $startTime'.trim(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: AppColors.error,
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(4),
                    ),
                    tooltip: 'Delete event',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Create Event Dialog ──────────────────────────────────────────────────────

class _CreateEventDialog extends StatefulWidget {
  const _CreateEventDialog();

  @override
  State<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends State<_CreateEventDialog> {
  final _name = TextEditingController();
  final _facilitator = TextEditingController();
  final _venue = TextEditingController();
  final _startDate = TextEditingController();
  final _endDate = TextEditingController();
  final _startTime = TextEditingController();
  final _endTime = TextEditingController();
  final _description = TextEditingController();
  final _budget = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in [
      _name, _facilitator, _venue, _startDate, _endDate,
      _startTime, _endTime, _description, _budget,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      ctrl.text =
      '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      ctrl.text =
      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create New Event'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                dialogInput('Event Name *', _name),
                dialogInput('Facilitator', _facilitator),
                dialogInput('Venue Name', _venue),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        label: 'Start Date',
                        ctrl: _startDate,
                        onPick: () => _pickDate(_startDate),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateField(
                        label: 'End Date',
                        ctrl: _endDate,
                        onPick: () => _pickDate(_endDate),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TimeField(
                        label: 'Start Time',
                        ctrl: _startTime,
                        onPick: () => _pickTime(_startTime),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TimeField(
                        label: 'End Time',
                        ctrl: _endTime,
                        onPick: () => _pickTime(_endTime),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                dialogInput(
                  'Description',
                  _description,
                  maxLines: 3,
                ),
                dialogInput(
                  'Budget (optional)',
                  _budget,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Event name is required.')),
              );
              return;
            }
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'facilitator': _facilitator.text.trim(),
              'venue_name': _venue.text.trim(),
              'start_date': _startDate.text.trim(),
              'end_date': _endDate.text.trim(),
              'start_time': _startTime.text.trim(),
              'end_time': _endTime.text.trim(),
              'description': _description.text.trim(),
              if (_budget.text.trim().isNotEmpty)
                'budget': double.tryParse(_budget.text.trim()),
            });
          },
          child: const Text('Create Event'),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.ctrl,
    required this.onPick,
  });

  final String label;
  final TextEditingController ctrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      readOnly: true,
      onTap: onPick,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.ctrl,
    required this.onPick,
  });

  final String label;
  final TextEditingController ctrl;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      readOnly: true,
      onTap: onPick,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.access_time_rounded, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }
}
