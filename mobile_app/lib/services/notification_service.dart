import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import 'api_service.dart';

/// Real-time notification service using WebSocket.
/// Listens for chat message and presence events to update unread counts instantly.
class NotificationService extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _authProvider;

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);

  int _totalUnread = 0;

  // Callbacks for listeners
  final List<Function(int)> _unreadCountListeners = [];

  NotificationService(
    this._api,
    this._authProvider,
  );

  bool get isConnected => _isConnected;
  int get totalUnread => _totalUnread;

  /// Initialize WebSocket connection if authenticated.
  /// Call this after auth is confirmed (e.g., after login).
  Future<void> initialize() async {
    if (!_authProvider.isAuthenticated || _isConnecting || _isConnected) {
      return;
    }
    await _connect();
  }

  /// Connect to WebSocket server.
  Future<void> _connect() async {
    if (_isConnecting) return;
    _isConnecting = true;

    try {
      final token = _authProvider.user?.token;
      if (token == null) {
        _isConnecting = false;
        return;
      }

      final wsUrl = _api.wsBaseUrl;
      if (wsUrl == null) {
        _isConnecting = false;
        return;
      }

      final url = Uri.parse('$wsUrl/chat/ws?token=$token');
      _channel = WebSocketChannel.connect(url);

      // Wait for connection to be established
      await _channel?.ready;
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      notifyListeners();

      // Start listening to events
      _listen();
    } catch (e) {
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
          final data = jsonDecode(message);
          final type = data['type'] as String?;

          if (type == 'message') {
            // A new message was created; refresh unread count
            _refreshUnreadCount();
          } else if (type == 'presence') {
            // Someone came online/offline; no unread update needed
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
      _reconnectTimer =
          Timer(_reconnectDelay, () => _connect());
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

  void _notifyUnreadCountListeners() {
    for (final callback in _unreadCountListeners) {
      callback(_totalUnread);
    }
  }

  /// Manually refresh unread count (e.g., when returning to foreground).
  Future<void> refreshUnreadCount() async {
    await _refreshUnreadCount();
  }

  /// Disconnect and clean up resources.
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    _isConnecting = false;
    super.dispose();
  }
}
