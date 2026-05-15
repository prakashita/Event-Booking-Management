// ignore_for_file: constant_identifier_names

// ─── User & Auth ──────────────────────────────────────────────────────────────

class User {
  final String id;
  final String email;
  final String name;
  final String? picture;
  final UserRole role;
  final String? rawRole;
  final String approvalStatus;
  final String? rejectionReason;
  final String? department;
  final bool online;
  final DateTime? lastSeen;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.picture,
    required this.role,
    this.rawRole,
    this.approvalStatus = 'approved',
    this.rejectionReason,
    this.department,
    this.online = false,
    this.lastSeen,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? json['_id'] ?? '',
    email: json['email'] ?? '',
    name: json['name'] ?? json['email'] ?? '',
    picture: json['picture'],
    role: _parseRole((json['role'] ?? '').toString()),
    rawRole: (json['role'] ?? '').toString(),
    approvalStatus: (json['approval_status'] ?? 'approved').toString(),
    rejectionReason: json['rejection_reason']?.toString(),
    department: json['department'],
    online: json['online'] == true,
    lastSeen: json['last_seen'] is String
        ? DateTime.tryParse(json['last_seen'] as String)?.toLocal()
        : null,
  );

  User copyWith({bool? online, DateTime? lastSeen}) {
    return User(
      id: id,
      email: email,
      name: name,
      picture: picture,
      role: role,
      rawRole: rawRole,
      approvalStatus: approvalStatus,
      rejectionReason: rejectionReason,
      department: department,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  String get roleKey {
    final fromServer = (rawRole ?? '').trim().toLowerCase();
    if (fromServer.isNotEmpty) return fromServer;
    return role.name;
  }

  String get roleLabel => roleKey.replaceAll('_', ' ').toUpperCase();

  static UserRole _parseRole(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'registrar':
        return UserRole.registrar;
      case 'vice_chancellor':
        return UserRole.vice_chancellor;
      case 'deputy_registrar':
        return UserRole.deputy_registrar;
      case 'finance_team':
        return UserRole.finance_team;
      case 'facility_manager':
        return UserRole.facility_manager;
      case 'marketing':
        return UserRole.marketing;
      case 'it':
        return UserRole.it;
      case 'iqac':
        return UserRole.iqac;
      case 'transport':
        return UserRole.transport;
      case 'faculty':
      default:
        return UserRole.faculty;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'picture': picture,
    'role': roleKey,
    'raw_role': rawRole,
    'approval_status': approvalStatus,
    'rejection_reason': rejectionReason,
    'department': department,
  };
}

enum UserRole {
  admin,
  registrar,
  vice_chancellor,
  deputy_registrar,
  finance_team,
  faculty,
  facility_manager,
  marketing,
  it,
  iqac,
  transport,
}

DateTime _parseDateTime(
  Map<String, dynamic> json, {
  required String dateKey,
  required String timeKey,
  required String datetimeKey,
}) {
  final dtRaw = (json[datetimeKey] ?? '').toString().trim();
  final parsedDt = DateTime.tryParse(dtRaw);
  if (parsedDt != null) {
    return parsedDt.toLocal();
  }

  final dateRaw = (json[dateKey] ?? '').toString().trim();
  final timeRaw = (json[timeKey] ?? '').toString().trim();
  if (dateRaw.isNotEmpty && timeRaw.isNotEmpty) {
    final combined = DateTime.tryParse('${dateRaw}T$timeRaw');
    if (combined != null) {
      return combined.toLocal();
    }
  }

  return DateTime.now();
}

List<String> _deriveMarketingItems(Map<String, dynamic> json) {
  final direct = json['items'];
  if (direct is List) {
    return direct.map((e) => e.toString()).toList();
  }

  final out = <String>[];
  final req = json['marketing_requirements'];
  if (req is Map<String, dynamic>) {
    final pre = req['pre_event'];
    if (pre is Map<String, dynamic>) {
      if (pre['poster'] == true) out.add('Poster');
      if (pre['social_media'] == true) out.add('Social Media');
    }
    final during = req['during_event'];
    if (during is Map<String, dynamic>) {
      if (during['photo'] == true) out.add('Photography');
      if (during['video'] == true) out.add('Video');
    }
    final post = req['post_event'];
    if (post is Map<String, dynamic>) {
      if (post['social_media'] == true) out.add('Post Event Social Media');
      if (post['photo_upload'] == true) out.add('Photo Upload');
      if (post['video'] == true) out.add('Post Event Video');
    }
  }

  if (json['poster_required'] == true && !out.contains('Poster')) {
    out.add('Poster');
  }
  if (json['video_required'] == true && !out.contains('Video')) {
    out.add('Video');
  }
  if (json['linkedin_post'] == true && !out.contains('LinkedIn Post')) {
    out.add('LinkedIn Post');
  }
  if (json['photography'] == true && !out.contains('Photography')) {
    out.add('Photography');
  }
  if (json['recording'] == true && !out.contains('Recording')) {
    out.add('Recording');
  }

  return out;
}

Map<String, dynamic> _toStringDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) {
    return Map<String, dynamic>.fromEntries(
      value.entries.map((e) => MapEntry(e.key.toString(), e.value)),
    );
  }
  return <String, dynamic>{};
}

// ─── Event ────────────────────────────────────────────────────────────────────

class Event {
  final String id;
  final String title;
  final String? facilitator;
  final String? description;
  final String? imageUrl;
  final String venueName;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String createdBy;
  final DateTime? createdAt;
  final String? reportFileId;
  final String? reportFileName;
  final String? reportWebViewLink;
  final String? attendanceFileId;
  final String? attendanceFileName;
  final String? attendanceWebViewLink;
  final int? audienceCount;
  final String? notes;
  final String? pipelineStage;
  final String? approvalRequestId;
  final String? approvalStatus;
  final String? facilityStatus;
  final String? marketingStatus;
  final String? itStatus;
  final String? transportStatus;
  final String? inviteStatus;
  final String? googleEventLink;

  const Event({
    required this.id,
    required this.title,
    this.facilitator,
    this.description,
    this.imageUrl,
    required this.venueName,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdBy,
    this.createdAt,
    this.reportFileId,
    this.reportFileName,
    this.reportWebViewLink,
    this.attendanceFileId,
    this.attendanceFileName,
    this.attendanceWebViewLink,
    this.audienceCount,
    this.notes,
    this.pipelineStage,
    this.approvalRequestId,
    this.approvalStatus,
    this.facilityStatus,
    this.marketingStatus,
    this.itStatus,
    this.transportStatus,
    this.inviteStatus,
    this.googleEventLink,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] ?? json['_id'] ?? '',
    title:
        (json['name'] ?? json['title'] ?? json['summary'] ?? 'Untitled event')
            .toString(),
    facilitator: json['facilitator']?.toString(),
    description: json['description'],
    imageUrl:
        (json['image_url'] ??
                json['event_image'] ??
                json['poster_url'] ??
                json['thumbnail_url'] ??
                json['banner_url'])
            ?.toString(),
    venueName: json['venue_name'] ?? json['location'] ?? '',
    startTime: _parseDateTime(
      json,
      dateKey: 'start_date',
      timeKey: 'start_time',
      datetimeKey: 'start_datetime',
    ),
    endTime: _parseDateTime(
      json,
      dateKey: 'end_date',
      timeKey: 'end_time',
      datetimeKey: 'end_datetime',
    ),
    status: json['status'] ?? 'approved',
    createdBy: json['created_by'] ?? '',
    createdAt: DateTime.tryParse(
      (json['created_at'] ?? '').toString(),
    )?.toLocal(),
    reportFileId: json['report_file_id'],
    reportFileName: json['report_file_name']?.toString(),
    reportWebViewLink: json['report_web_view_link']?.toString(),
    attendanceFileId: json['attendance_file_id']?.toString(),
    attendanceFileName: json['attendance_file_name']?.toString(),
    attendanceWebViewLink: json['attendance_web_view_link']?.toString(),
    audienceCount: json['audience_count'],
    notes: json['notes'] ?? json['htmlLink'],
    pipelineStage: json['pipeline_stage']?.toString(),
    approvalRequestId:
        (json['approval_request_id'] ?? json['id'] ?? json['_id'])?.toString(),
    approvalStatus: json['approval_status']?.toString(),
    facilityStatus: json['facility_status']?.toString(),
    marketingStatus: json['marketing_status']?.toString(),
    itStatus: json['it_status']?.toString(),
    transportStatus: json['transport_status']?.toString(),
    inviteStatus: json['invite_status']?.toString(),
    googleEventLink: json['google_event_link']?.toString(),
  );
}

// ─── Approval Request ─────────────────────────────────────────────────────────
// ... existing code ...
class ApprovalRequest {
  final String id;
  final String eventTitle;
  final String? description;
  final String venueName;
  final DateTime startDatetime;
  final DateTime endDatetime;
  final String status;
  final String requestedBy;
  final String requestedTo;
  final bool overrideConflict;
  final String? notes;
  final String? budgetBreakdownFileId;
  final DateTime createdAt;
  final String? pipelineStage;
  final String? currentStageLabel;
  final String? approvedByRole;
  final bool completed;
  final String? deputyDecidedBy;
  final DateTime? deputyDecidedAt;
  final String? financeDecidedBy;
  final DateTime? financeDecidedAt;
  final bool isActionable;

  const ApprovalRequest({
    required this.id,
    required this.eventTitle,
    this.description,
    required this.venueName,
    required this.startDatetime,
    required this.endDatetime,
    required this.status,
    required this.requestedBy,
    required this.requestedTo,
    this.overrideConflict = false,
    this.notes,
    this.budgetBreakdownFileId,
    required this.createdAt,
    this.pipelineStage,
    this.currentStageLabel,
    this.approvedByRole,
    this.completed = false,
    this.deputyDecidedBy,
    this.deputyDecidedAt,
    this.financeDecidedBy,
    this.financeDecidedAt,
    this.isActionable = true,
  });

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) =>
      ApprovalRequest(
        id: json['id'] ?? json['_id'] ?? '',
        eventTitle: (json['event_name'] ?? json['event_title'] ?? '')
            .toString(),
        description: json['description'],
        venueName: json['venue_name'] ?? '',
        startDatetime: _parseDateTime(
          json,
          dateKey: 'start_date',
          timeKey: 'start_time',
          datetimeKey: 'start_datetime',
        ),
        endDatetime: _parseDateTime(
          json,
          dateKey: 'end_date',
          timeKey: 'end_time',
          datetimeKey: 'end_datetime',
        ),
        status: json['status'] ?? 'pending',
        requestedBy: (json['requester_email'] ?? json['requested_by'] ?? '')
            .toString(),
        requestedTo: json['requested_to'] ?? '',
        overrideConflict: json['override_conflict'] ?? false,
        notes: json['other_notes'] ?? json['notes'],
        budgetBreakdownFileId: json['budget_breakdown_file_id']?.toString(),
        pipelineStage: json['pipeline_stage']?.toString(),
        currentStageLabel: json['current_stage_label']?.toString(),
        approvedByRole: json['approved_by_role']?.toString(),
        completed: json['completed'] == true,
        deputyDecidedBy: json['deputy_decided_by']?.toString(),
        deputyDecidedAt: DateTime.tryParse(
          (json['deputy_decided_at'] ?? '').toString(),
        )?.toLocal(),
        financeDecidedBy: json['finance_decided_by']?.toString(),
        financeDecidedAt: DateTime.tryParse(
          (json['finance_decided_at'] ?? '').toString(),
        )?.toLocal(),
        isActionable: json['is_actionable'] != false,
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class ApprovalThreadReplySnapshot {
  final String? messageId;
  final String senderName;
  final String contentPreview;
  final bool isDeleted;

  const ApprovalThreadReplySnapshot({
    this.messageId,
    required this.senderName,
    required this.contentPreview,
    this.isDeleted = false,
  });

  factory ApprovalThreadReplySnapshot.fromJson(Map<String, dynamic> json) =>
      ApprovalThreadReplySnapshot(
        messageId: json['message_id']?.toString(),
        senderName: (json['sender_name'] ?? '').toString(),
        contentPreview: (json['content_preview'] ?? '').toString(),
        isDeleted: json['is_deleted'] == true,
      );
}

class ApprovalThreadParticipant {
  final String id;
  final String name;
  final String email;
  final String role;

  const ApprovalThreadParticipant({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  factory ApprovalThreadParticipant.fromJson(Map<String, dynamic> json) =>
      ApprovalThreadParticipant(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
      );
}

class ApprovalThreadMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime createdAt;
  final bool isLegacy;
  final String? replyToMessageId;
  final ApprovalThreadReplySnapshot? replyToSnapshot;

  const ApprovalThreadMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    this.isLegacy = false,
    this.replyToMessageId,
    this.replyToSnapshot,
  });

  factory ApprovalThreadMessage.fromJson(Map<String, dynamic> json) =>
      ApprovalThreadMessage(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        senderId: (json['sender_id'] ?? '').toString(),
        senderName: (json['sender_name'] ?? '').toString(),
        content: (json['content'] ?? '').toString(),
        createdAt:
            DateTime.tryParse(
              (json['created_at'] ?? '').toString(),
            )?.toLocal() ??
            DateTime.now(),
        isLegacy: json['is_legacy'] == true,
        replyToMessageId: json['reply_to_message_id']?.toString(),
        replyToSnapshot: json['reply_to_snapshot'] is Map<String, dynamic>
            ? ApprovalThreadReplySnapshot.fromJson(
                json['reply_to_snapshot'] as Map<String, dynamic>,
              )
            : null,
      );
}

class ApprovalThreadInfo {
  final String id;
  final String department;
  final String departmentLabel;
  final String? relatedRequestId;
  final String? relatedKind;
  final String threadStatus;
  final String? deptRequestStatus;
  final List<ApprovalThreadParticipant> participants;
  final DateTime createdAt;
  final List<ApprovalThreadMessage> messages;
  final DateTime? closedAt;
  final String? closedReason;

  const ApprovalThreadInfo({
    required this.id,
    required this.department,
    required this.departmentLabel,
    this.relatedRequestId,
    this.relatedKind,
    required this.threadStatus,
    this.deptRequestStatus,
    required this.participants,
    required this.createdAt,
    required this.messages,
    this.closedAt,
    this.closedReason,
  });

  factory ApprovalThreadInfo.fromJson(Map<String, dynamic> json) =>
      ApprovalThreadInfo(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        department: (json['department'] ?? '').toString(),
        departmentLabel: (json['department_label'] ?? json['department'] ?? '')
            .toString(),
        relatedRequestId: json['related_request_id']?.toString(),
        relatedKind: json['related_kind']?.toString(),
        threadStatus: (json['thread_status'] ?? 'active').toString(),
        deptRequestStatus: json['dept_request_status']?.toString(),
        participants: (json['participants'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ApprovalThreadParticipant.fromJson)
            .toList(),
        createdAt:
            DateTime.tryParse(
              (json['created_at'] ?? '').toString(),
            )?.toLocal() ??
            DateTime.now(),
        messages: (json['messages'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ApprovalThreadMessage.fromJson)
            .toList(),
        closedAt: DateTime.tryParse(
          (json['closed_at'] ?? '').toString(),
        )?.toLocal(),
        closedReason: json['closed_reason']?.toString(),
      );
}

// ─── Venue ────────────────────────────────────────────────────────────────────

class Venue {
  // ... existing code ...
  final String id;
  final String name;

  const Venue({required this.id, required this.name});

  factory Venue.fromJson(Map<String, dynamic> json) =>
      Venue(id: json['id'] ?? json['_id'] ?? '', name: json['name'] ?? '');
}

// ─── Facility Request ─────────────────────────────────────────────────────────

class FacilityRequest {
  // ... existing code ...
  final String id;
  final String? eventId;
  final String eventTitle;
  final String? startDate;
  final String? startTime;
  final String? endDate;
  final String? endTime;
  final String? setupDetails;
  final String? refreshmentDetails;
  final String status;
  final String requestedBy;
  final DateTime createdAt;
  final bool isActionable;

  const FacilityRequest({
    required this.id,
    this.eventId,
    required this.eventTitle,
    this.startDate,
    this.startTime,
    this.endDate,
    this.endTime,
    this.setupDetails,
    this.refreshmentDetails,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
    this.isActionable = true,
  });

  factory FacilityRequest.fromJson(Map<String, dynamic> json) =>
      FacilityRequest(
        id: json['id'] ?? json['_id'] ?? '',
        eventId: json['event_id'],
        eventTitle: (json['event_name'] ?? json['event_title'] ?? '')
            .toString(),
        startDate: json['start_date']?.toString(),
        startTime: json['start_time']?.toString(),
        endDate: json['end_date']?.toString(),
        endTime: json['end_time']?.toString(),
        setupDetails:
            json['setup_details'] ??
            (json['venue_required'] is bool
                ? ((json['venue_required'] as bool)
                      ? 'Venue required'
                      : 'Venue not required')
                : null),
        refreshmentDetails:
            json['refreshment_details'] ??
            (json['refreshments'] is bool
                ? ((json['refreshments'] as bool)
                      ? 'Refreshments required'
                      : 'No refreshments')
                : null),
        status: json['status'] ?? 'pending',
        requestedBy: (json['requester_email'] ?? json['requested_by'] ?? '')
            .toString(),
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
            DateTime.now(),
        isActionable: json['is_actionable'] != false,
      );
}

// ─── IT Request ───────────────────────────────────────────────────────────────

class ITRequest {
  // ... existing code ...
  final String id;
  final String? eventId;
  final String eventTitle;
  final String? startDate;
  final String? startTime;
  final String? endDate;
  final String? endTime;
  final String mode;
  final bool paSystem;
  final bool projection;
  final String? notes;
  final String status;
  final String requestedBy;
  final DateTime createdAt;
  final bool isActionable;

  const ITRequest({
    required this.id,
    this.eventId,
    required this.eventTitle,
    this.startDate,
    this.startTime,
    this.endDate,
    this.endTime,
    required this.mode,
    required this.paSystem,
    required this.projection,
    this.notes,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
    this.isActionable = true,
  });

  factory ITRequest.fromJson(Map<String, dynamic> json) => ITRequest(
    id: json['id'] ?? json['_id'] ?? '',
    eventId: json['event_id'],
    eventTitle: (json['event_name'] ?? json['event_title'] ?? '').toString(),
    startDate: json['start_date']?.toString(),
    startTime: json['start_time']?.toString(),
    endDate: json['end_date']?.toString(),
    endTime: json['end_time']?.toString(),
    mode: json['event_mode'] ?? json['mode'] ?? 'offline',
    paSystem: json['pa_system'] ?? false,
    projection: json['projection'] ?? false,
    notes: json['other_notes'] ?? json['notes'],
    status: json['status'] ?? 'pending',
    requestedBy: (json['requester_email'] ?? json['requested_by'] ?? '')
        .toString(),
    createdAt:
        DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
        DateTime.now(),
    isActionable: json['is_actionable'] != false,
  );
}

// ─── Marketing Request ────────────────────────────────────────────────────────

class MarketingRequest {
  // ... existing code ...
  final String id;
  final String? eventId;
  final String eventTitle;
  final String? startDate;
  final String? startTime;
  final String? endDate;
  final String? endTime;
  final List<String> items;
  final String? notes;
  final String status;
  final String requestedBy;
  final bool posterRequired;
  final bool videoRequired;
  final bool linkedinPost;
  final bool photography;
  final bool recording;
  final Map<String, dynamic> marketingRequirements;
  final List<MarketingDeliverable> deliverables;
  final DateTime createdAt;
  final bool isActionable;

  const MarketingRequest({
    required this.id,
    this.eventId,
    required this.eventTitle,
    this.startDate,
    this.startTime,
    this.endDate,
    this.endTime,
    required this.items,
    this.notes,
    required this.status,
    required this.requestedBy,
    this.posterRequired = false,
    this.videoRequired = false,
    this.linkedinPost = false,
    this.photography = false,
    this.recording = false,
    this.marketingRequirements = const <String, dynamic>{},
    required this.deliverables,
    required this.createdAt,
    this.isActionable = true,
  });

  factory MarketingRequest.fromJson(Map<String, dynamic> json) {
    final req = _toStringDynamicMap(json['marketing_requirements']);
    return MarketingRequest(
      id: json['id'] ?? json['_id'] ?? '',
      eventId: json['event_id'],
      eventTitle: (json['event_name'] ?? json['event_title'] ?? '').toString(),
      startDate: json['start_date']?.toString(),
      startTime: json['start_time']?.toString(),
      endDate: json['end_date']?.toString(),
      endTime: json['end_time']?.toString(),
      items: _deriveMarketingItems(json),
      notes: json['other_notes'] ?? json['notes'],
      status: json['status'] ?? 'pending',
      requestedBy: (json['requester_email'] ?? json['requested_by'] ?? '')
          .toString(),
      posterRequired: json['poster_required'] == true,
      videoRequired: json['video_required'] == true,
      linkedinPost: json['linkedin_post'] == true,
      photography: json['photography'] == true,
      recording: json['recording'] == true,
      marketingRequirements: req,
      deliverables: (json['deliverables'] as List? ?? [])
          .map((d) => MarketingDeliverable.fromJson(d))
          .toList(),
      createdAt:
          DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
          DateTime.now(),
      isActionable: json['is_actionable'] != false,
    );
  }
}

class MarketingDeliverable {
  // ... existing code ...
  final String type;
  final String? driveFileId;
  final String? link;
  final bool isNa;

  const MarketingDeliverable({
    required this.type,
    this.driveFileId,
    this.link,
    this.isNa = false,
  });

  factory MarketingDeliverable.fromJson(Map<String, dynamic> json) =>
      MarketingDeliverable(
        type: (json['deliverable_type'] ?? json['type'] ?? '').toString(),
        driveFileId: json['file_id'] ?? json['drive_file_id'],
        link: json['web_view_link'] ?? json['link'],
        isNa: json['is_na'] ?? false,
      );
}

// ─── Transport Request ────────────────────────────────────────────────────────

class TransportRequest {
  final String id;
  final String? eventId;
  final String eventTitle;
  final String? startDate;
  final String? startTime;
  final String? endDate;
  final String? endTime;
  final String transportType;
  final String? guestPickupLocation;
  final String? guestPickupDate;
  final String? guestPickupTime;
  final String? guestDropoffLocation;
  final String? guestDropoffDate;
  final String? guestDropoffTime;
  final int? studentCount;
  final String? studentTransportKind;
  final String? studentDate;
  final String? studentTime;
  final String? studentPickupPoint;
  final String? notes;
  final String status;
  final String requestedBy;
  final DateTime createdAt;
  final bool isActionable;

  const TransportRequest({
    required this.id,
    this.eventId,
    required this.eventTitle,
    this.startDate,
    this.startTime,
    this.endDate,
    this.endTime,
    required this.transportType,
    this.guestPickupLocation,
    this.guestPickupDate,
    this.guestPickupTime,
    this.guestDropoffLocation,
    this.guestDropoffDate,
    this.guestDropoffTime,
    this.studentCount,
    this.studentTransportKind,
    this.studentDate,
    this.studentTime,
    this.studentPickupPoint,
    this.notes,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
    this.isActionable = true,
  });

  factory TransportRequest.fromJson(Map<String, dynamic> json) =>
      TransportRequest(
        id: json['id'] ?? json['_id'] ?? '',
        eventId: json['event_id'],
        eventTitle: (json['event_name'] ?? json['event_title'] ?? '')
            .toString(),
        startDate: json['start_date']?.toString(),
        startTime: json['start_time']?.toString(),
        endDate: json['end_date']?.toString(),
        endTime: json['end_time']?.toString(),
        transportType: json['transport_type'] ?? 'guest_cab',
        guestPickupLocation: json['guest_pickup_location'],
        guestPickupDate: json['guest_pickup_date'],
        guestPickupTime: json['guest_pickup_time'],
        guestDropoffLocation: json['guest_dropoff_location'],
        guestDropoffDate: json['guest_dropoff_date'],
        guestDropoffTime: json['guest_dropoff_time'],
        studentCount: json['student_count'],
        studentTransportKind: json['student_transport_kind'],
        studentDate: json['student_date'],
        studentTime: json['student_time'],
        studentPickupPoint: json['student_pickup_point'],
        notes: json['other_notes'] ?? json['notes'],
        status: json['status'] ?? 'pending',
        requestedBy: (json['requester_email'] ?? json['requested_by'] ?? '')
            .toString(),
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
            DateTime.now(),
        isActionable: json['is_actionable'] != false,
      );
}

// ─── Chat ─────────────────────────────────────────────────────────────────────

class ChatConversation {
  // ... existing code ...
  final String id;
  final String kind;
  final List<String> participants;
  final String? eventId;
  final String? eventTitle;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final List<String> participantNames;
  final int participantCount;
  final String? otherUserName;
  final bool otherUserOnline;
  final DateTime? otherUserLastSeen;
  final String? department;
  final String? departmentLabel;
  final String? threadStatus;
  final DateTime? closedAt;
  final String? closedReason;

  const ChatConversation({
    required this.id,
    required this.kind,
    required this.participants,
    this.eventId,
    this.eventTitle,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.participantNames,
    this.participantCount = 0,
    this.otherUserName,
    this.otherUserOnline = false,
    this.otherUserLastSeen,
    this.department,
    this.departmentLabel,
    this.threadStatus,
    this.closedAt,
    this.closedReason,
  });

  ChatConversation copyWith({
    String? id,
    String? kind,
    List<String>? participants,
    String? eventId,
    String? eventTitle,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    List<String>? participantNames,
    int? participantCount,
    String? otherUserName,
    bool? otherUserOnline,
    DateTime? otherUserLastSeen,
    String? department,
    String? departmentLabel,
    String? threadStatus,
    DateTime? closedAt,
    String? closedReason,
    bool clearLastMessage = false,
    bool clearLastMessageAt = false,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      participants: participants ?? this.participants,
      eventId: eventId ?? this.eventId,
      eventTitle: eventTitle ?? this.eventTitle,
      lastMessage: clearLastMessage ? null : (lastMessage ?? this.lastMessage),
      lastMessageAt: clearLastMessageAt
          ? null
          : (lastMessageAt ?? this.lastMessageAt),
      unreadCount: unreadCount ?? this.unreadCount,
      participantNames: participantNames ?? this.participantNames,
      participantCount: participantCount ?? this.participantCount,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserOnline: otherUserOnline ?? this.otherUserOnline,
      otherUserLastSeen: otherUserLastSeen ?? this.otherUserLastSeen,
      department: department ?? this.department,
      departmentLabel: departmentLabel ?? this.departmentLabel,
      threadStatus: threadStatus ?? this.threadStatus,
      closedAt: closedAt ?? this.closedAt,
      closedReason: closedReason ?? this.closedReason,
    );
  }

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    int parsedParticipantCount = json['participant_count'] ?? 0;
    if (parsedParticipantCount == 0) {
      final parts = json['participants'];
      if (parts is List) parsedParticipantCount = parts.length;
    }

    String? otherName;
    bool online = false;
    DateTime? lastSeen;
    final otherUser = json['other_user'];
    if (otherUser is Map<String, dynamic>) {
      otherName = otherUser['name'];
      online = otherUser['online'] == true;
      lastSeen = _parseOptionalDate(otherUser['last_seen']);
    }

    return ChatConversation(
      id: json['id'] ?? json['_id'] ?? '',
      kind: json['kind'] ?? json['thread_kind'] ?? 'direct',
      participants: List<String>.from(json['participants'] ?? []),
      eventId: json['event_id'],
      eventTitle: json['event_title'] ?? json['title'],
      lastMessage: _extractLastMessage(json['last_message']),
      lastMessageAt: _extractLastMessageAt(json),
      unreadCount: json['unread_count'] ?? 0,
      participantNames: _extractParticipantNames(json),
      participantCount: parsedParticipantCount,
      otherUserName: otherName,
      otherUserOnline: online,
      otherUserLastSeen: lastSeen,
      department: json['department'],
      departmentLabel: json['department_label'],
      threadStatus: json['thread_status']?.toString(),
      closedAt: _parseOptionalDate(json['closed_at']),
      closedReason: json['closed_reason']?.toString(),
    );
  }

  static String? _extractLastMessage(dynamic lastMessageField) {
    // ... existing code ...
    if (lastMessageField is String) {
      final trimmed = lastMessageField.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (lastMessageField is Map<String, dynamic>) {
      final text = lastMessageField['text']?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
      if (lastMessageField['message_id'] != null) {
        return 'Sent an attachment';
      }
    }
    return null;
  }

  static DateTime? _extractLastMessageAt(Map<String, dynamic> json) {
    // ... existing code ...
    final direct = json['last_message_at'];
    if (direct is String) return DateTime.tryParse(direct)?.toLocal();

    final lastMessage = json['last_message'];
    if (lastMessage is Map<String, dynamic>) {
      final createdAt = lastMessage['created_at'];
      if (createdAt is String) return DateTime.tryParse(createdAt)?.toLocal();
    }

    final updatedAt = json['updated_at'];
    if (updatedAt is String) return DateTime.tryParse(updatedAt)?.toLocal();
    return null;
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  static List<String> _extractParticipantNames(Map<String, dynamic> json) {
    // ... existing code ...
    final directNames = json['participant_names'];
    if (directNames is List) {
      return directNames.map((e) => e.toString()).toList();
    }

    final preview = json['participants_preview'];
    if (preview is List) {
      return preview
          .whereType<Map<String, dynamic>>()
          .map((p) => (p['name'] ?? '').toString())
          .where((name) => name.isNotEmpty)
          .toList();
    }

    final otherUser = json['other_user'];
    if (otherUser is Map<String, dynamic>) {
      final name = (otherUser['name'] ?? '').toString();
      if (name.isNotEmpty) return [name];
    }
    return <String>[];
  }
}

class ChatReplySnapshot {
  final String? messageId;
  final String senderName;
  final String contentPreview;
  final bool isDeleted;

  const ChatReplySnapshot({
    this.messageId,
    required this.senderName,
    required this.contentPreview,
    this.isDeleted = false,
  });

  factory ChatReplySnapshot.fromJson(Map<String, dynamic> json) {
    return ChatReplySnapshot(
      messageId: json['message_id']?.toString(),
      senderName: (json['sender_name'] ?? '').toString(),
      contentPreview: (json['content_preview'] ?? '').toString(),
      isDeleted: json['is_deleted'] == true,
    );
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime createdAt;
  final List<String> readBy;
  final List<dynamic> attachments;
  final String? senderEmail;
  final String? replyToMessageId;
  final ChatReplySnapshot? replyToSnapshot;
  final bool isDeleted;
  final bool deletedForEveryone;
  final bool edited;
  final DateTime? editedAt;
  final String? clientId;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    required this.readBy,
    this.attachments = const [],
    this.senderEmail,
    this.replyToMessageId,
    this.replyToSnapshot,
    this.isDeleted = false,
    this.deletedForEveryone = false,
    this.edited = false,
    this.editedAt,
    this.clientId,
  });

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? senderName,
    String? content,
    DateTime? createdAt,
    List<String>? readBy,
    List<dynamic>? attachments,
    String? senderEmail,
    String? replyToMessageId,
    ChatReplySnapshot? replyToSnapshot,
    bool? isDeleted,
    bool? deletedForEveryone,
    bool? edited,
    DateTime? editedAt,
    String? clientId,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      readBy: readBy ?? this.readBy,
      attachments: attachments ?? this.attachments,
      senderEmail: senderEmail ?? this.senderEmail,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToSnapshot: replyToSnapshot ?? this.replyToSnapshot,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      edited: edited ?? this.edited,
      editedAt: editedAt ?? this.editedAt,
      clientId: clientId ?? this.clientId,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] ?? json['_id'] ?? '',
    conversationId: json['conversation_id'] ?? '',
    senderId: json['sender_id'] ?? '',
    senderName: json['sender_name'] ?? '',
    content: json['content'] ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
        DateTime.now(),
    readBy: List<String>.from(json['read_by'] ?? []),
    attachments: List<dynamic>.from(json['attachments'] ?? []),
    senderEmail: json['sender_email']?.toString(),
    replyToMessageId: json['reply_to_message_id']?.toString(),
    replyToSnapshot: json['reply_to_snapshot'] is Map<String, dynamic>
        ? ChatReplySnapshot.fromJson(
            json['reply_to_snapshot'] as Map<String, dynamic>,
          )
        : null,
    isDeleted: json['is_deleted'] == true,
    deletedForEveryone: json['deleted_for_everyone'] == true,
    edited: json['edited'] == true,
    editedAt: json['edited_at'] != null
        ? DateTime.tryParse(json['edited_at'])?.toLocal()
        : null,
    clientId: json['client_id']?.toString(),
  );
}

// ─── Publication ──────────────────────────────────────────────────────────────

class Publication {
  // ... existing code ...
  final String id;
  final String type;
  final String title;
  final List<String> authors;
  final int? year;
  final String? url;
  final String? journal;
  final String createdBy;
  final DateTime createdAt;

  const Publication({
    required this.id,
    required this.type,
    required this.title,
    required this.authors,
    this.year,
    this.url,
    this.journal,
    required this.createdBy,
    required this.createdAt,
  });

  factory Publication.fromJson(Map<String, dynamic> json) => Publication(
    id: json['id'] ?? json['_id'] ?? '',
    type: json['type'] ?? 'journal_article',
    title: json['title'] ?? '',
    authors: List<String>.from(json['authors'] ?? []),
    year: json['year'],
    url: json['url'],
    journal: json['journal'],
    createdBy: json['created_by'] ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

// ─── IQAC ─────────────────────────────────────────────────────────────────────

class IQACFile {
  // ... existing code ...
  final String id;
  final String criterion;
  final String subfolder;
  final String item;
  final String filename;
  final String uploadedBy;
  final DateTime createdAt;
  final int? size;

  const IQACFile({
    required this.id,
    required this.criterion,
    required this.subfolder,
    required this.item,
    required this.filename,
    required this.uploadedBy,
    required this.createdAt,
    this.size,
  });

  factory IQACFile.fromJson(Map<String, dynamic> json) => IQACFile(
    id: json['id'] ?? json['_id'] ?? '',
    criterion: json['criterion'] ?? '',
    subfolder: json['subfolder'] ?? '',
    item: json['item'] ?? '',
    filename: json['filename'] ?? '',
    uploadedBy: json['uploaded_by'] ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
        DateTime.now(),
    size: json['size'],
  );
}

// ─── Dashboard Stats ──────────────────────────────────────────────────────────

class DashboardStats {
  // ... existing code ...
  final int totalEvents;
  final int upcomingEvents;
  final int ongoingEvents;
  final int completedEvents;
  final int pendingApprovals;

  const DashboardStats({
    this.totalEvents = 0,
    this.upcomingEvents = 0,
    this.ongoingEvents = 0,
    this.completedEvents = 0,
    this.pendingApprovals = 0,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
    totalEvents: json['total_events'] ?? 0,
    upcomingEvents: json['upcoming_events'] ?? 0,
    ongoingEvents: json['ongoing_events'] ?? 0,
    completedEvents: json['completed_events'] ?? 0,
    pendingApprovals: json['pending_approvals'] ?? 0,
  );
}
