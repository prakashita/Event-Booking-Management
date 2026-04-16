// ─── User & Auth ──────────────────────────────────────────────────────────────

class User {
  final String id;
  final String email;
  final String name;
  final String? picture;
  final UserRole role;
  final String? rawRole;
  final String? department;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.picture,
    required this.role,
    this.rawRole,
    this.department,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] ?? json['_id'] ?? '',
    email: json['email'] ?? '',
    name: json['name'] ?? json['email'] ?? '',
    picture: json['picture'],
    role: _parseRole((json['role'] ?? '').toString()),
    rawRole: (json['role'] ?? '').toString(),
    department: json['department'],
  );

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
    'department': department,
  };
}

enum UserRole {
  admin,
  registrar,
  vice_chancellor,
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

// ─── Event ────────────────────────────────────────────────────────────────────

class Event {
  final String id;
  final String title;
  final String? description;
  final String venueName;
  final DateTime startTime;
  final DateTime endTime;
  final String status;
  final String createdBy;
  final DateTime? createdAt;
  final String? reportFileId;
  final int? audienceCount;
  final String? notes;

  const Event({
    required this.id,
    required this.title,
    this.description,
    required this.venueName,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdBy,
    this.createdAt,
    this.reportFileId,
    this.audienceCount,
    this.notes,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    id: json['id'] ?? json['_id'] ?? '',
    title:
        (json['name'] ?? json['title'] ?? json['summary'] ?? 'Untitled event')
            .toString(),
    description: json['description'],
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
    audienceCount: json['audience_count'],
    notes: json['notes'] ?? json['htmlLink'],
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
  final DateTime createdAt;

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
    required this.createdAt,
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
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
            DateTime.now(),
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
  final String? setupDetails;
  final String? refreshmentDetails;
  final String status;
  final String requestedBy;
  final DateTime createdAt;

  const FacilityRequest({
    required this.id,
    this.eventId,
    required this.eventTitle,
    this.setupDetails,
    this.refreshmentDetails,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
  });

  factory FacilityRequest.fromJson(Map<String, dynamic> json) =>
      FacilityRequest(
        id: json['id'] ?? json['_id'] ?? '',
        eventId: json['event_id'],
        eventTitle: (json['event_name'] ?? json['event_title'] ?? '')
            .toString(),
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
      );
}

// ─── IT Request ───────────────────────────────────────────────────────────────

class ITRequest {
  // ... existing code ...
  final String id;
  final String? eventId;
  final String eventTitle;
  final String mode;
  final bool paSystem;
  final bool projection;
  final String? notes;
  final String status;
  final String requestedBy;
  final DateTime createdAt;

  const ITRequest({
    required this.id,
    this.eventId,
    required this.eventTitle,
    required this.mode,
    required this.paSystem,
    required this.projection,
    this.notes,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
  });

  factory ITRequest.fromJson(Map<String, dynamic> json) => ITRequest(
    id: json['id'] ?? json['_id'] ?? '',
    eventId: json['event_id'],
    eventTitle: (json['event_name'] ?? json['event_title'] ?? '').toString(),
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
  );
}

// ─── Marketing Request ────────────────────────────────────────────────────────

class MarketingRequest {
  // ... existing code ...
  final String id;
  final String? eventId;
  final String eventTitle;
  final List<String> items;
  final String? notes;
  final String status;
  final String requestedBy;
  final List<MarketingDeliverable> deliverables;
  final DateTime createdAt;

  const MarketingRequest({
    required this.id,
    this.eventId,
    required this.eventTitle,
    required this.items,
    this.notes,
    required this.status,
    required this.requestedBy,
    required this.deliverables,
    required this.createdAt,
  });

  factory MarketingRequest.fromJson(Map<String, dynamic> json) =>
      MarketingRequest(
        id: json['id'] ?? json['_id'] ?? '',
        eventId: json['event_id'],
        eventTitle: (json['event_name'] ?? json['event_title'] ?? '')
            .toString(),
        items: _deriveMarketingItems(json),
        notes: json['other_notes'] ?? json['notes'],
        status: json['status'] ?? 'pending',
        requestedBy: (json['requester_email'] ?? json['requested_by'] ?? '')
            .toString(),
        deliverables: (json['deliverables'] as List? ?? [])
            .map((d) => MarketingDeliverable.fromJson(d))
            .toList(),
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '')?.toLocal() ??
            DateTime.now(),
      );
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
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: json['id'] ?? json['_id'] ?? '',
        kind: json['kind'] ?? json['thread_kind'] ?? 'direct',
        participants: List<String>.from(json['participants'] ?? []),
        eventId: json['event_id'],
        eventTitle: json['event_title'] ?? json['title'],
        lastMessage: _extractLastMessage(json['last_message']),
        lastMessageAt: _extractLastMessageAt(json),
        unreadCount: json['unread_count'] ?? 0,
        participantNames: _extractParticipantNames(json),
      );

  static String? _extractLastMessage(dynamic lastMessageField) {
    // ... existing code ...
    if (lastMessageField is String) return lastMessageField;
    if (lastMessageField is Map<String, dynamic>) {
      final text = lastMessageField['text'];
      if (text is String) return text;
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

class ChatMessage {
  // ... existing code ...
  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime createdAt;
  final List<String> readBy;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    required this.readBy,
  });

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
