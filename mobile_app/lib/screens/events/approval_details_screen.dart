import 'package:flutter/widgets.dart';

import 'event_details_screen.dart';

class ApprovalDetailsScreen extends StatelessWidget {
  final String approvalId;

  const ApprovalDetailsScreen({super.key, required this.approvalId});

  @override
  Widget build(BuildContext context) {
    return EventDetailsScreen(
      eventId: 'approval-$approvalId',
      viewMode: EventDetailsViewMode.approval,
    );
  }
}
