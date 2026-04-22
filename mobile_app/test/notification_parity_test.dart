import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/notification_parity.dart';

void main() {
  group('NotificationParity.shouldRefreshUnreadCount', () {
    test('matches website-driven unread refresh event types', () {
      expect(NotificationParity.shouldRefreshUnreadCount('message'), isTrue);
      expect(NotificationParity.shouldRefreshUnreadCount('read'), isTrue);
      expect(
        NotificationParity.shouldRefreshUnreadCount('read_conversation'),
        isTrue,
      );
      expect(
        NotificationParity.shouldRefreshUnreadCount('message_deleted'),
        isTrue,
      );
      expect(
        NotificationParity.shouldRefreshUnreadCount('message_edited'),
        isTrue,
      );
      expect(
        NotificationParity.shouldRefreshUnreadCount('conversation_cleared'),
        isTrue,
      );
      expect(
        NotificationParity.shouldRefreshUnreadCount('conversation_deleted'),
        isTrue,
      );
      expect(NotificationParity.shouldRefreshUnreadCount('typing'), isFalse);
      expect(
        NotificationParity.shouldRefreshUnreadCount('message_hidden'),
        isFalse,
      );
      expect(NotificationParity.shouldRefreshUnreadCount('presence'), isFalse);
    });
  });

  group('NotificationParity.buildMessagePresentation', () {
    const foregroundClosed = NotificationVisibilityState(
      currentUserId: 'me',
      activeConversationId: null,
      isAppInForeground: true,
      isChatUiOpen: false,
    );

    test('suppresses alerts for messages from the current user', () {
      final presentation = NotificationParity.buildMessagePresentation(
        messageData: const {
          'sender_id': 'me',
          'conversation_id': 'conv-1',
          'sender_name': 'Me',
          'content': 'hello',
        },
        visibility: foregroundClosed,
      );

      expect(presentation, isNull);
    });

    test('suppresses alerts for the active conversation', () {
      final presentation = NotificationParity.buildMessagePresentation(
        messageData: const {
          'sender_id': 'other',
          'conversation_id': 'conv-1',
          'sender_name': 'Other',
          'content': 'hello',
        },
        visibility: const NotificationVisibilityState(
          currentUserId: 'me',
          activeConversationId: 'conv-1',
          isAppInForeground: true,
          isChatUiOpen: false,
        ),
      );

      expect(presentation, isNull);
    });

    test('suppresses alerts while app is foregrounded and chat UI is open', () {
      final presentation = NotificationParity.buildMessagePresentation(
        messageData: const {
          'sender_id': 'other',
          'conversation_id': 'conv-1',
          'sender_name': 'Other',
          'content': 'hello',
        },
        visibility: const NotificationVisibilityState(
          currentUserId: 'me',
          activeConversationId: null,
          isAppInForeground: true,
          isChatUiOpen: true,
        ),
      );

      expect(presentation, isNull);
    });

    test('shows alerts with truncated content when chat UI is closed', () {
      final longMessage = 'a' * 121;
      final presentation = NotificationParity.buildMessagePresentation(
        messageData: {
          'sender_id': 'other',
          'conversation_id': 'conv-1',
          'sender_name': 'Other',
          'content': longMessage,
        },
        visibility: foregroundClosed,
      );

      expect(presentation, isNotNull);
      expect(presentation!.title, 'Other');
      expect(presentation.body, '${'a' * 120}...');
    });

    test('uses attachment fallback when there is no text content', () {
      final presentation = NotificationParity.buildMessagePresentation(
        messageData: const {
          'sender_id': 'other',
          'conversation_id': 'conv-1',
          'sender_name': 'Other',
          'content': '   ',
          'attachments': [
            {'name': 'file.pdf'},
          ],
        },
        visibility: foregroundClosed,
      );

      expect(presentation, isNotNull);
      expect(presentation!.body, 'Sent an attachment');
    });

    test('still shows alerts in the background even when chat UI was open', () {
      final presentation = NotificationParity.buildMessagePresentation(
        messageData: const {
          'sender_id': 'other',
          'conversation_id': 'conv-1',
          'sender_name': 'Other',
          'content': 'Background ping',
        },
        visibility: const NotificationVisibilityState(
          currentUserId: 'me',
          activeConversationId: null,
          isAppInForeground: false,
          isChatUiOpen: true,
        ),
      );

      expect(presentation, isNotNull);
      expect(presentation!.body, 'Background ping');
    });
  });
}
