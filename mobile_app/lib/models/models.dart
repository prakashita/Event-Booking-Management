// ─── User & Auth ──────────────────────────────────────────────────────────────

class User {
  final String id;
  final String email;
  final String name;
  final String? picture;
  final String role;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.picture,
    required this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] ?? json['_id'] ?? '',
        email: json['email'] ?? '',
        name: json['name'] ?? json['email'] ?? '',
        picture: json['picture'],
        role: json['role'] ?? 'faculty',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'picture': picture,
        'role': role,
      };
}

// ─── Event ────────────────────────────────────────────────────────────────────

class Event {
  final String id;
  final String title;
  final String? description;
  final String venueName;
  final DateTime startDatetime;
  final DateTime endDatetime;
  final String status;
  final String createdBy;
  final String? reportFileId;
  final int? audienceCount;
  final String? notes;

  const Event({
    required this.id,
    required this.title,
    this.description,
    required this.venueName,
    required this.startDatetime,
    required this.endDatetime,
    required this.status,
    required this.createdBy,
    this.reportFileId,
    this.audienceCount,
    this.notes,
  });

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'] ?? json['_id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'],
        venueName: json['venue_name'] ?? '',
        startDatetime: DateTime.tryParse(json['start_datetime'] ?? '') ??
            DateTime.now(),
        endDatetime:
            DateTime.tryParse(json['end_datetime'] ?? '') ?? DateTime.now(),
        status: json['status'] ?? 'upcoming',
        createdBy: json['created_by'] ?? '',
        reportFileId: json['report_file_id'],
        audienceCount: json['audience_count'],
        notes: json['notes'],
      );
}

// ─── Approval Request ─────────────────────────────────────────────────────────

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
        eventTitle: json['event_title'] ?? '',
        description: json['description'],
        venueName: json['venue_name'] ?? '',
        startDatetime: DateTime.tryParse(json['start_datetime'] ?? '') ??
            DateTime.now(),
        endDatetime:
            DateTime.tryParse(json['end_datetime'] ?? '') ?? DateTime.now(),
        status: json['status'] ?? 'pending',
        requestedBy: json['requested_by'] ?? '',
        requestedTo: json['requested_to'] ?? '',
        overrideConflict: json['override_conflict'] ?? false,
        notes: json['notes'],
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );
}

// ─── Venue ────────────────────────────────────────────────────────────────────

class Venue {
  final String id;
  final String name;

  const Venue({required this.id, required this.name});

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
        id: json['id'] ?? json['_id'] ?? '',
        name: json['name'] ?? '',
      );
}

// ─── Facility Request ─────────────────────────────────────────────────────────

class FacilityRequest {
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
        eventTitle: json['event_title'] ?? '',
        setupDetails: json['setup_details'],
        refreshmentDetails: json['refreshment_details'],
        status: json['status'] ?? 'pending',
        requestedBy: json['requested_by'] ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );
}

// ─── IT Request ───────────────────────────────────────────────────────────────

class ITRequest {
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
        eventTitle: json['event_title'] ?? '',
        mode: json['mode'] ?? 'offline',
        paSystem: json['pa_system'] ?? false,
        projection: json['projection'] ?? false,
        notes: json['notes'],
        status: json['status'] ?? 'pending',
        requestedBy: json['requested_by'] ?? '',
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );
}

// ─── Marketing Request ────────────────────────────────────────────────────────

class MarketingRequest {
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
        eventTitle: json['event_title'] ?? '',
        items: List<String>.from(json['items'] ?? []),
        notes: json['notes'],
        status: json['status'] ?? 'pending',
        requestedBy: json['requested_by'] ?? '',
        deliverables: (json['deliverables'] as List? ?? [])
            .map((d) => MarketingDeliverable.fromJson(d))
            .toList(),
        createdAt:
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );
}

class MarketingDeliverable {
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
        type: json['type'] ?? '',
        driveFileId: json['drive_file_id'],
        link: json['link'],
        isNa: json['is_na'] ?? false,
      );
}

// ─── Chat ─────────────────────────────────────────────────────────────────────

class ChatConversation {
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
    if (lastMessageField is String) return lastMessageField;
    if (lastMessageField is Map<String, dynamic>) {
      final text = lastMessageField['text'];
      if (text is String) return text;
    }
    return null;
  }

  static DateTime? _extractLastMessageAt(Map<String, dynamic> json) {
    final direct = json['last_message_at'];
    if (direct is String) return DateTime.tryParse(direct);

    final lastMessage = json['last_message'];
    if (lastMessage is Map<String, dynamic>) {
      final createdAt = lastMessage['created_at'];
      if (createdAt is String) return DateTime.tryParse(createdAt);
    }

    final updatedAt = json['updated_at'];
    if (updatedAt is String) return DateTime.tryParse(updatedAt);
    return null;
  }

  static List<String> _extractParticipantNames(Map<String, dynamic> json) {
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
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        readBy: List<String>.from(json['read_by'] ?? []),
      );
}

// ─── Publication ──────────────────────────────────────────────────────────────

class Publication {
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
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      );
}

// ─── IQAC ─────────────────────────────────────────────────────────────────────

class IQACFile {
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
            DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
        size: json['size'],
      );
}

// ─── Dashboard Stats ──────────────────────────────────────────────────────────

class DashboardStats {
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
