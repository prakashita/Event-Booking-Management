import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import 'api_service.dart';
import 'notification_parity.dart';

class NotificationPopupEvent {
  final String title;
  final String body;
  final String route;

  const NotificationPopupEvent({
    required this.title,
    required this.body,
    required this.route,
  });
}

/// Real-time notification service using WebSocket.
/// Listens for chat message and presence events to update unread counts instantly.
/// Also shows local notifications for new messages when appropriate.
class NotificationService extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService _api;
  final GlobalKey<NavigatorState> _navigatorKey;
  AuthProvider _authProvider;

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);

  int _totalUnread = 0;
  String?
  _activeChatConversationId; // Track which conversation is currently open
  bool _isChatUiOpen = false;
  bool _isAppInForeground = true;
  bool _observerRegistered = false;

  // Local notifications
  FlutterLocalNotificationsPlugin? _localNotifications;
  bool _notificationsInitialized = false;
  String? _pendingLaunchRoute;

  // Callbacks for listeners
  final List<Function(int)> _unreadCountListeners = [];
  final List<Function(NotificationPopupEvent)> _popupListeners = [];

  NotificationService(this._api, this._authProvider, this._navigatorKey);

  bool get isConnected => _isConnected;
  int get totalUnread => _totalUnread;

  void updateAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;

    if (!_authProvider.isAuthenticated) {
      _reconnectTimer?.cancel();
      _channel?.sink.close();
      _channel = null;
      _isConnected = false;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _totalUnread = 0;
      _activeChatConversationId = null;
      notifyListeners();
      return;
    }

    if (_notificationsInitialized && !_isConnected && !_isConnecting) {
      _refreshUnreadCount();
      _connect();
    }
  }

  /// Set the currently active chat conversation (to suppress notifications)
  void setActiveChatConversation(String? conversationId) {
    _activeChatConversationId = conversationId;
  }

  /// Clear the active conversation only if it still matches the provided one.
  /// This avoids older chat screens wiping out a newer active chat state.
  void clearActiveChatConversationIfMatches(String conversationId) {
    if (_activeChatConversationId == conversationId) {
      _activeChatConversationId = null;
    }
  }

  /// Tracks whether the app's chat UI is currently open, mirroring the website
  /// notification suppression when the messenger panel is visible.
  void setChatUiOpen(bool isOpen) {
    _isChatUiOpen = isOpen;
  }

  /// Initialize WebSocket connection if authenticated.
  /// Call this after auth is confirmed (e.g., after login).
  Future<void> initialize() async {
    if (!_authProvider.isAuthenticated || _isConnecting || _isConnected) {
      return;
    }
    _registerLifecycleObserver();
    await _initializeLocalNotifications();
    await _refreshUnreadCount();
    await _connect();
  }

  void _registerLifecycleObserver() {
    if (_observerRegistered) return;
    WidgetsBinding.instance.addObserver(this);
    _observerRegistered = true;
  }

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    if (_notificationsInitialized) return;

    _localNotifications = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications!.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    await _localNotifications!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _localNotifications!
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    final launchDetails = await _localNotifications!
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingLaunchRoute = launchDetails?.notificationResponse?.payload;
      _flushPendingLaunchRoute();
    }
    _notificationsInitialized = true;

    if (kDebugMode) {
      print('Local notifications initialized');
    }
  }

  /// Connect to WebSocket server.
  Future<void> _connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      final token = _authProvider.token;
      if (token == null) {
        _isConnecting = false;
        return;
      }

      final wsUrl = _api.wsBaseUrl;
      if (wsUrl == null) {
        _isConnecting = false;
        return;
      }

      if (kDebugMode) {
        print('NotificationService: Connecting to WebSocket at $wsUrl');
        print(
          'NotificationService: Full URL will be $wsUrl/api/v1/chat/ws?token=...',
        );
      }

      final url = Uri.parse('$wsUrl/api/v1/chat/ws?token=$token');

      if (kDebugMode) {
        print('NotificationService: Parsed URI: $url');
        print('NotificationService: URI scheme: ${url.scheme}');
      }

      _channel = WebSocketChannel.connect(url);

      // Wait for connection to be established
      await _channel?.ready;
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      if (kDebugMode) {
        print('NotificationService: WebSocket connected successfully');
      }

      notifyListeners();

      // Start listening to events
      _listen();
    } catch (e) {
      if (kDebugMode) {
        print('NotificationService: WebSocket connection error: $e');
      }
      _isConnecting = false;
      _isConnected = false;
      _handleConnectionError();
    }
  }

  /// Listen to WebSocket events.
  void _listen() {
    _channel?.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message) as Map<String, dynamic>;
          final type = data['type'] as String?;

          if (NotificationParity.shouldRefreshUnreadCount(type)) {
            _refreshUnreadCount();
          }

          if (type == 'message' || type == 'new_message') {
            _handleNewMessageNotification(data);
          }
        } catch (e) {
          // Log error but don't crash
          if (kDebugMode) {
            print('Error processing WebSocket message: $e');
          }
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('WebSocket error: $error');
        }
        _isConnected = false;
        notifyListeners();
        _handleConnectionError();
      },
      onDone: () {
        if (kDebugMode) {
          print('WebSocket closed');
        }
        _isConnected = false;
        notifyListeners();
        _handleConnectionError();
      },
    );
  }

  /// Handle new message notification (similar to website logic)
  Future<void> _handleNewMessageNotification(Map<String, dynamic> data) async {
    try {
      if (kDebugMode) {
        print('_handleNewMessageNotification called with data: $data');
      }

      final rawMessageData = data['message'];
      final messageData = rawMessageData is Map<String, dynamic>
          ? rawMessageData
          : _extractInlineMessageData(data);
      if (messageData == null) {
        if (kDebugMode) {
          print('No message data found in notification');
        }
        return;
      }

      final presentation = NotificationParity.buildMessagePresentation(
        messageData: messageData,
        visibility: NotificationVisibilityState(
          currentUserId: _authProvider.user?.id.toString(),
          activeConversationId: _activeChatConversationId,
          isAppInForeground: _isAppInForeground,
          isChatUiOpen: _isChatUiOpen,
        ),
      );
      if (presentation == null) return;

      final conversationId = messageData['conversation_id']?.toString();
      final route = conversationId == null ? '/chat' : '/chat/$conversationId';

      if (_isAppInForeground) {
        _notifyPopupListeners(
          NotificationPopupEvent(
            title: presentation.title,
            body: presentation.body,
            route: route,
          ),
        );
      }

      // Show local notification
      await _showLocalNotification(
        title: presentation.title,
        body: presentation.body,
        conversationId: conversationId,
      );

      if (kDebugMode) {
        print(
          'Showing notification: ${presentation.title} - ${presentation.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error showing notification: $e');
      }
    }
  }

  /// Show a local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? conversationId,
  }) async {
    if (_localNotifications == null || !_notificationsInitialized) return;

    const androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Messages',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      styleInformation: BigTextStyleInformation(''),
      category: AndroidNotificationCategory.message,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Generate a unique ID for the notification (use conversation ID hash or timestamp)
    final id =
        conversationId?.hashCode.abs() ??
        DateTime.now().millisecondsSinceEpoch % 100000;

    await _localNotifications!.show(
      id,
      title,
      body,
      notificationDetails,
      payload: conversationId == null ? '/chat' : '/chat/$conversationId',
    );
  }

  void _handleNotificationResponse(NotificationResponse response) {
    _pendingLaunchRoute = response.payload;
    _flushPendingLaunchRoute();
  }

  void _flushPendingLaunchRoute() {
    final route = _pendingLaunchRoute;
    final context = _navigatorKey.currentContext;
    if (route == null || route.isEmpty || context == null) {
      if (route != null && route.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _flushPendingLaunchRoute();
        });
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentContext = _navigatorKey.currentContext;
      if (currentContext == null) return;
      _pendingLaunchRoute = null;
      GoRouter.of(currentContext).go(route);
    });
  }

  Map<String, dynamic>? _extractInlineMessageData(Map<String, dynamic> data) {
    const messageKeys = {
      'id',
      '_id',
      'conversation_id',
      'conversationId',
      'sender_id',
      'senderId',
      'sender_name',
      'senderName',
      'content',
      'attachments',
    };

    final inlineMessage = <String, dynamic>{};
    for (final entry in data.entries) {
      if (messageKeys.contains(entry.key)) {
        inlineMessage[entry.key] = entry.value;
      }
    }

    return inlineMessage.isEmpty ? null : inlineMessage;
  }

  /// Refresh unread count from API.
  Future<void> _refreshUnreadCount() async {
    try {
      final data = await _api.get<dynamic>('/chat/conversations/me');
      final items = data is List
          ? data
          : (data is Map<String, dynamic>
                ? (data['items'] as List? ?? [])
                : []);
      final unread = items
          .whereType<Map<String, dynamic>>()
          .map(ChatConversation.fromJson)
          .fold<int>(0, (sum, c) => sum + c.unreadCount);

      if (_totalUnread != unread) {
        _totalUnread = unread;
        notifyListeners();
        _notifyUnreadCountListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error refreshing unread count: $e');
      }
    }
  }

  /// Handle connection errors and schedule reconnection.
  void _handleConnectionError() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;

    if (_reconnectAttempts <= _maxReconnectAttempts) {
      if (kDebugMode) {
        print(
          'Scheduling WebSocket reconnect (attempt $_reconnectAttempts/$_maxReconnectAttempts)',
        );
      }
      _reconnectTimer = Timer(_reconnectDelay, () => _connect());
    } else {
      if (kDebugMode) {
        print('Max reconnect attempts exceeded');
      }
    }
  }

  /// Register a callback to listen for unread count changes.
  void addUnreadCountListener(Function(int) callback) {
    _unreadCountListeners.add(callback);
  }

  /// Unregister an unread count listener.
  void removeUnreadCountListener(Function(int) callback) {
    _unreadCountListeners.remove(callback);
  }

  void addPopupListener(Function(NotificationPopupEvent) callback) {
    _popupListeners.add(callback);
  }

  void removePopupListener(Function(NotificationPopupEvent) callback) {
    _popupListeners.remove(callback);
  }

  void _notifyUnreadCountListeners() {
    for (final callback in _unreadCountListeners) {
      callback(_totalUnread);
    }
  }

  void _notifyPopupListeners(NotificationPopupEvent event) {
    for (final callback in _popupListeners) {
      callback(event);
    }
  }

  /// Manually refresh unread count (e.g., when returning to foreground).
  Future<void> refreshUnreadCount() async {
    await _refreshUnreadCount();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _isAppInForeground;
    _isAppInForeground = state == AppLifecycleState.resumed;

    if (_isAppInForeground && !wasForeground) {
      refreshUnreadCount();
      if (!_isConnected && !_isConnecting) {
        _connect();
      }
    }
  }

  /// Disconnect and clean up resources.
  @override
  Future<void> dispose() async {
    if (_observerRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _observerRegistered = false;
    }
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _isConnecting = false;
    super.dispose();
  }
}
