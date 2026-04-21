import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';

/// Provider for managing real-time notifications via WebSocket.
/// Automatically initializes and manages the notification service lifecycle.
class NotificationProvider extends ChangeNotifier {
  final AuthProvider _authProvider;
  final ApiService _api;

  late NotificationService _notificationService;
  bool _isInitialized = false;

  NotificationProvider(this._authProvider, this._api) {
    _notificationService = NotificationService(_api, _authProvider);
    _notificationService.addListener(_onNotificationServiceChanged);
  }

  bool get isConnected => _notificationService.isConnected;
  int get totalUnread => _notificationService.totalUnread;
  bool get isInitialized => _isInitialized;

  /// Initialize the notification service.
  /// Call this after auth is ready (e.g., after login).
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _notificationService.initialize();
  }

  /// Reconnect if disconnected.
  Future<void> reconnect() async {
    if (_notificationService.isConnected) return;
    await _notificationService.initialize();
  }

  /// Manually refresh unread count.
  Future<void> refreshUnreadCount() async {
    await _notificationService.refreshUnreadCount();
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
