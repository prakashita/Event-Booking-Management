import 'package:flutter/widgets.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';

/// Provider for managing real-time notifications via WebSocket.
/// Automatically initializes and manages the notification service lifecycle.
class NotificationProvider extends ChangeNotifier {
  AuthProvider _authProvider;
  final ApiService _api;
  final GlobalKey<NavigatorState> _navigatorKey;

  late NotificationService _notificationService;
  bool _isInitialized = false;

  NotificationProvider(this._authProvider, this._api, this._navigatorKey) {
    _notificationService = NotificationService(
      _api,
      _authProvider,
      _navigatorKey,
    );
    _notificationService.addListener(_onNotificationServiceChanged);
  }

  bool get isConnected => _notificationService.isConnected;
  int get totalUnread => _notificationService.totalUnread;
  bool get isInitialized => _isInitialized;

  /// Initialize the notification service.
  /// Call this after auth is ready (e.g., after login).
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (!_authProvider.isAuthenticated) return;
    _isInitialized = true;
    await _notificationService.initialize();
  }

  /// Reconnect if disconnected.
  Future<void> reconnect() async {
    if (_notificationService.isConnected) return;
    await _notificationService.initialize();
  }

  void updateAuthProvider(AuthProvider authProvider) {
    final wasAuthenticated = _authProvider.isAuthenticated;
    _authProvider = authProvider;
    _notificationService.updateAuthProvider(authProvider);

    if (!wasAuthenticated && authProvider.isAuthenticated && !_isInitialized) {
      initialize();
    }

    if (!authProvider.isAuthenticated) {
      _isInitialized = false;
    }
  }

  /// Manually refresh unread count.
  Future<void> refreshUnreadCount() async {
    await _notificationService.refreshUnreadCount();
  }

  void addPopupListener(Function(NotificationPopupEvent) callback) {
    _notificationService.addPopupListener(callback);
  }

  void removePopupListener(Function(NotificationPopupEvent) callback) {
    _notificationService.removePopupListener(callback);
  }

  /// Set the currently active chat conversation (to suppress notifications)
  void setActiveChatConversation(String? conversationId) {
    _notificationService.setActiveChatConversation(conversationId);
  }

  void clearActiveChatConversationIfMatches(String conversationId) {
    _notificationService.clearActiveChatConversationIfMatches(conversationId);
  }

  /// Track whether the chat UI is visible, mirroring the website messenger
  /// panel state used for notification suppression.
  void setChatUiOpen(bool isOpen) {
    _notificationService.setChatUiOpen(isOpen);
  }

  void _onNotificationServiceChanged() {
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    _notificationService.removeListener(_onNotificationServiceChanged);
    await _notificationService.dispose();
    super.dispose();
  }
}
