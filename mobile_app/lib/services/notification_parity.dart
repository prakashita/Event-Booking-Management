class NotificationVisibilityState {
  final String? currentUserId;
  final String? activeConversationId;
  final bool isAppInForeground;
  final bool isChatUiOpen;

  const NotificationVisibilityState({
    required this.currentUserId,
    required this.activeConversationId,
    required this.isAppInForeground,
    required this.isChatUiOpen,
  });
}

class NotificationPresentation {
  final String title;
  final String body;

  const NotificationPresentation({required this.title, required this.body});
}

class NotificationParity {
  static const Set<String> unreadRefreshEventTypes = {
    'message',
    'read',
    'read_conversation',
    'message_deleted',
    'message_edited',
    'conversation_cleared',
    'conversation_deleted',
  };

  static bool shouldRefreshUnreadCount(String? eventType) {
    return unreadRefreshEventTypes.contains(eventType);
  }

  static NotificationPresentation? buildMessagePresentation({
    required Map<String, dynamic> messageData,
    required NotificationVisibilityState visibility,
  }) {
    final senderId =
        messageData['sender_id']?.toString() ??
        messageData['senderId']?.toString();
    final conversationId =
        messageData['conversation_id']?.toString() ??
        messageData['conversationId']?.toString();

    if (senderId == null ||
        visibility.currentUserId == null ||
        senderId == visibility.currentUserId) {
      return null;
    }

    if (conversationId != null &&
        conversationId == visibility.activeConversationId) {
      return null;
    }

    final shouldSurfaceSystemAlert =
        !visibility.isAppInForeground || !visibility.isChatUiOpen;
    if (!shouldSurfaceSystemAlert) {
      return null;
    }

    final senderName =
        messageData['sender_name']?.toString() ??
        messageData['senderName']?.toString() ??
        messageData['sender']?['name']?.toString() ??
        'New message';
    final content =
        messageData['content']?.toString() ??
        messageData['text']?.toString() ??
        '';
    final hasAttachments =
        (messageData['attachments'] as List?)?.isNotEmpty ?? false;
    final trimmedContent = content.trim();

    final body = trimmedContent.isNotEmpty
        ? (trimmedContent.length > 120
              ? '${trimmedContent.substring(0, 120)}...'
              : trimmedContent)
        : (hasAttachments ? 'Sent an attachment' : 'New message');

    return NotificationPresentation(title: senderName, body: body);
  }
}
