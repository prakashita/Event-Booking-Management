import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import 'api_service.dart';
import 'notification_parity.dart';
import 'push_notification_bootstrap.dart';
import 'push_notification_config.dart';

class NotificationPopupEvent {
  final String id;
  final String title;
  final String body;
  final String route;
  final DateTime createdAt;

  const NotificationPopupEvent({
    required this.id,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
  });
}

class AppNotificationItem {
  final String id;
  final String title;
  final String body;
  final String route;
  final DateTime createdAt;
  final bool isRead;
  final String category;

  const AppNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
    required this.isRead,
    required this.category,
  });

  AppNotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    String? route,
    DateTime? createdAt,
    bool? isRead,
    String? category,
  }) {
    return AppNotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      route: route ?? this.route,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      category: category ?? this.category,
    );
  }
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
  List<ChatConversation> _unreadConversations = <ChatConversation>[];
  final List<AppNotificationItem> _notifications = <AppNotificationItem>[];
  static const int _maxStoredNotifications = 50;
  String?
  _activeChatConversationId; // Track which conversation is currently open
  bool _isChatUiOpen = false;
  bool _isAppInForeground = true;
  bool _observerRegistered = false;

  // Local notifications
  FlutterLocalNotificationsPlugin? _localNotifications;
  bool _notificationsInitialized = false;
  String? _pendingLaunchRoute;
  FirebaseMessaging? _firebaseMessaging;
  bool _firebaseMessagingInitialized = false;
  StreamSubscription<RemoteMessage>? _firebaseOnMessageSubscription;
  StreamSubscription<RemoteMessage>? _firebaseOnMessageOpenedSubscription;
  StreamSubscription<String>? _firebaseTokenRefreshSubscription;
  String? _registeredPushToken;
  String? _lastKnownAuthToken;

  // Callbacks for listeners
  final List<Function(int)> _unreadCountListeners = [];
  final List<Function(NotificationPopupEvent)> _popupListeners = [];

  NotificationService(this._api, this._authProvider, this._navigatorKey);

  bool get isConnected => _isConnected;
  int get totalUnread => _totalUnread;
  List<ChatConversation> get unreadConversations =>
      List<ChatConversation>.unmodifiable(_unreadConversations);
  List<AppNotificationItem> get notifications =>
      List<AppNotificationItem>.unmodifiable(_notifications);
  int get unreadNotificationCount =>
      _notifications.where((item) => !item.isRead).length;

  void updateAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;

    if (!_authProvider.isAuthenticated) {
      final authTokenForUnregister = _lastKnownAuthToken;
      unawaited(
        _unregisterPushToken(overrideAuthToken: authTokenForUnregister),
      );
      _reconnectTimer?.cancel();
      _channel?.sink.close();
      _channel = null;
      _isConnected = false;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _totalUnread = 0;
      _unreadConversations = <ChatConversation>[];
      _notifications.clear();
      _activeChatConversationId = null;
      _registeredPushToken = null;
      _lastKnownAuthToken = null;
      notifyListeners();
      return;
    }

    _lastKnownAuthToken = _authProvider.token;

    if (_notificationsInitialized && !_isConnected && !_isConnecting) {
      _refreshUnreadCount();
      _connect();
    }
    if (_notificationsInitialized) {
      unawaited(_initializeFirebaseMessaging());
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
    _lastKnownAuthToken = _authProvider.token;
    _registerLifecycleObserver();
    await _initializeLocalNotifications();
    await _initializeFirebaseMessaging();
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
    const chatChannel = AndroidNotificationChannel(
      'chat_channel',
      'Chat Messages',
      description: 'Notifications for new chat messages',
      importance: Importance.high,
    );
    final androidNotifications = _localNotifications!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.createNotificationChannel(chatChannel);
    await androidNotifications?.requestNotificationsPermission();
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

  Future<void> _initializeFirebaseMessaging() async {
    if (_firebaseMessagingInitialized) {
      if (_authProvider.isAuthenticated) {
        await _syncFirebaseTokenRegistration();
      }
      return;
    }

    final initialized = await PushNotificationBootstrap.ensureInitialized();
    if (!initialized) return;

    _firebaseMessaging = FirebaseMessaging.instance;
    await _firebaseMessaging!.setAutoInitEnabled(true);
    await _firebaseMessaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    await _firebaseMessaging!.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: true,
    );

    _firebaseOnMessageSubscription = FirebaseMessaging.onMessage.listen(
      _handleFirebaseForegroundMessage,
    );
    _firebaseOnMessageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp
        .listen(_handleFirebaseMessageOpen);
    _firebaseTokenRefreshSubscription = _firebaseMessaging!.onTokenRefresh
        .listen((token) {
          unawaited(_registerPushToken(token));
        });

    final initialMessage = await _firebaseMessaging!.getInitialMessage();
    if (initialMessage != null) {
      _handleFirebaseMessageOpen(initialMessage);
    }

    _firebaseMessagingInitialized = true;
    await _syncFirebaseTokenRegistration();
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
      final notificationId = _buildNotificationId(messageData, conversationId);
      final createdAt = _extractMessageCreatedAt(messageData);
      final popupEvent = NotificationPopupEvent(
        id: notificationId,
        title: presentation.title,
        body: presentation.body,
        route: route,
        createdAt: createdAt,
      );

      _storeNotification(
        AppNotificationItem(
          id: notificationId,
          title: presentation.title,
          body: presentation.body,
          route: route,
          createdAt: createdAt,
          isRead: false,
          category: 'message',
        ),
      );

      if (_isAppInForeground) {
        _notifyPopupListeners(popupEvent);
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

  Future<void> _handleFirebaseForegroundMessage(RemoteMessage message) async {
    final item = _buildNotificationItemFromRemoteMessage(message);
    if (item == null) return;

    _storeNotification(item);
    if (_isAppInForeground) {
      _notifyPopupListeners(
        NotificationPopupEvent(
          id: item.id,
          title: item.title,
          body: item.body,
          route: item.route,
          createdAt: item.createdAt,
        ),
      );
    }

    await _showLocalNotification(
      title: item.title,
      body: item.body,
      conversationId: _extractConversationIdFromRemoteMessage(message),
    );
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

  void _handleFirebaseMessageOpen(RemoteMessage message) {
    final item = _buildNotificationItemFromRemoteMessage(message);
    if (item != null) {
      _storeNotification(item);
      markNotificationAsRead(item.id);
    }
    final route = _extractRouteFromRemoteMessage(message);
    if (route == null || route.isEmpty) return;
    _pendingLaunchRoute = route;
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

  AppNotificationItem? _buildNotificationItemFromRemoteMessage(
    RemoteMessage message,
  ) {
    final route = _extractRouteFromRemoteMessage(message);
    if (route == null || route.isEmpty) return null;

    final data = message.data;
    final title =
        message.notification?.title ??
        data['title']?.toString() ??
        data['sender_name']?.toString() ??
        'New notification';
    final body =
        message.notification?.body ??
        data['body']?.toString() ??
        'Open the app to view the latest update.';
    final createdAt =
        DateTime.tryParse(data['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now();
    final id =
        data['notification_id']?.toString() ??
        'push-${message.messageId ?? createdAt.millisecondsSinceEpoch}';
    final category = data['type']?.toString().trim().isNotEmpty == true
        ? data['type']!.toString()
        : 'message';

    return AppNotificationItem(
      id: id,
      title: title,
      body: body,
      route: route,
      createdAt: createdAt,
      isRead: false,
      category: category,
    );
  }

  String? _extractRouteFromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    final route = data['route']?.toString();
    if (route != null && route.trim().isNotEmpty) {
      return route.trim();
    }
    final conversationId = _extractConversationIdFromRemoteMessage(message);
    if (conversationId == null || conversationId.isEmpty) {
      return '/chat';
    }
    return '/chat/$conversationId';
  }

  String? _extractConversationIdFromRemoteMessage(RemoteMessage message) {
    final data = message.data;
    return data['conversation_id']?.toString();
  }

  String _buildNotificationId(
    Map<String, dynamic> messageData,
    String? conversationId,
  ) {
    final rawId =
        messageData['id']?.toString() ??
        messageData['_id']?.toString() ??
        messageData['message_id']?.toString();
    if (rawId != null && rawId.trim().isNotEmpty) {
      return 'message-${rawId.trim()}';
    }
    final stamp =
        messageData['created_at']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();
    return 'message-${conversationId ?? 'chat'}-$stamp';
  }

  DateTime _extractMessageCreatedAt(Map<String, dynamic> messageData) {
    final raw = messageData['created_at']?.toString() ?? '';
    return DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
  }

  void _storeNotification(AppNotificationItem item) {
    final existingIndex = _notifications.indexWhere((n) => n.id == item.id);
    if (existingIndex >= 0) {
      _notifications[existingIndex] = item;
    } else {
      _notifications.insert(0, item);
      if (_notifications.length > _maxStoredNotifications) {
        _notifications.removeRange(
          _maxStoredNotifications,
          _notifications.length,
        );
      }
    }
    notifyListeners();
  }

  void markNotificationAsRead(String id) {
    final index = _notifications.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = _notifications[index];
    if (current.isRead) return;
    _notifications[index] = current.copyWith(isRead: true);
    notifyListeners();
  }

  Future<void> markAllNotificationsAsRead() async {
    var changed = false;
    for (var i = 0; i < _notifications.length; i++) {
      final item = _notifications[i];
      if (!item.isRead) {
        _notifications[i] = item.copyWith(isRead: true);
        changed = true;
      }
    }

    final unreadConversationIds = _unreadConversations
        .where((conversation) => conversation.unreadCount > 0)
        .map((conversation) => conversation.id)
        .where((id) => id.trim().isNotEmpty)
        .toList();

    if (unreadConversationIds.isNotEmpty) {
      for (final id in unreadConversationIds) {
        try {
          await _api.post<dynamic>('/chat/read/$id');
        } catch (e) {
          if (kDebugMode) {
            print('Error marking conversation read: $e');
          }
        }
      }
      _totalUnread = 0;
      _unreadConversations = <ChatConversation>[];
      _notifyUnreadCountListeners();
      changed = true;
    }

    if (changed) notifyListeners();
    await _refreshUnreadCount();
  }

  void dismissNotification(String id) {
    final before = _notifications.length;
    _notifications.removeWhere((item) => item.id == id);
    if (_notifications.length != before) {
      notifyListeners();
    }
  }

  Future<void> clearNotifications() async {
    final hadVisibleItems =
        _notifications.isNotEmpty || _unreadConversations.isNotEmpty;
    await markAllNotificationsAsRead();
    _notifications.clear();
    if (hadVisibleItems) notifyListeners();
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
      final conversations = items
          .whereType<Map<String, dynamic>>()
          .map(ChatConversation.fromJson)
          .toList();
      final unreadConversations = conversations
          .where((conversation) => conversation.unreadCount > 0)
          .toList();
      final unread = unreadConversations.fold<int>(
        0,
        (sum, c) => sum + c.unreadCount,
      );

      final unreadChanged = _totalUnread != unread;
      _totalUnread = unread;
      _unreadConversations = unreadConversations;
      notifyListeners();
      if (unreadChanged) {
        _notifyUnreadCountListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error refreshing unread count: $e');
      }
    }
  }

  Future<void> _syncFirebaseTokenRegistration() async {
    if (!_authProvider.isAuthenticated || _firebaseMessaging == null) return;
    try {
      final token = await _firebaseMessaging!.getToken();
      if (token == null || token.trim().isEmpty) return;
      await _registerPushToken(token);
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing Firebase token: $e');
      }
    }
  }

  Future<void> _registerPushToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty || !_authProvider.isAuthenticated) return;
    if (_registeredPushToken == normalized) return;

    try {
      await _api.post<dynamic>(
        '/users/me/push-tokens',
        data: {
          'token': normalized,
          'platform': PushNotificationConfig.currentPlatformLabel,
        },
      );
      _registeredPushToken = normalized;
      _lastKnownAuthToken = _authProvider.token ?? _lastKnownAuthToken;
    } catch (e) {
      if (kDebugMode) {
        print('Error registering push token: $e');
      }
    }
  }

  Future<void> _unregisterPushToken({String? overrideAuthToken}) async {
    final token = _registeredPushToken;
    if (token == null || token.isEmpty) return;

    try {
      await _api.delete<dynamic>(
        '/users/me/push-tokens',
        data: {'token': token},
        headers: _authorizationHeaderFor(overrideAuthToken),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error unregistering push token: $e');
      }
    }
  }

  Map<String, dynamic>? _authorizationHeaderFor(String? token) {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return {'Authorization': 'Bearer $normalized'};
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
    await _firebaseOnMessageSubscription?.cancel();
    await _firebaseOnMessageOpenedSubscription?.cancel();
    await _firebaseTokenRefreshSubscription?.cancel();
    _isConnected = false;
    _isConnecting = false;
    super.dispose();
  }
}
