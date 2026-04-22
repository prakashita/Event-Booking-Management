import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  static const Duration _autoRefreshInterval = Duration(seconds: 5);

  List<ChatConversation> _conversations = [];
  List<User> _users = [];
  bool _isLoading = true;
  bool _isLoadingUsers = false;
  String? _error;
  WebSocketChannel? _ws;
  bool _isConnectingWs = false;
  String _currentUserId = '';
  Timer? _autoRefreshTimer;
  Timer? _reconnectTimer;

  String _activeTab = 'Chats';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = context.read<AuthProvider>().user?.id ?? '';
    _loadConversations();
    _loadUsers();
    _connectWs();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _reconnectTimer?.cancel();
    _ws?.sink.close();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshConversationList();
      _loadUsers();
      _reconnectWs();
      _startAutoRefresh();
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _autoRefreshTimer?.cancel();
    }
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.get<dynamic>('/chat/conversations/me');
      final items = _extractItems(data);
      setState(() {
        _conversations = items
            .whereType<Map<String, dynamic>>()
            .map(ChatConversation.fromJson)
            .toList();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);
    try {
      final data = await _api.get<dynamic>('/chat/users');
      final items = _extractItems(data);
      setState(() {
        _users = items
            .whereType<Map<String, dynamic>>()
            .map(User.fromJson)
            .toList();
        _isLoadingUsers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }

  /// Connect to WebSocket for real-time conversation updates
  void _connectWs() {
    if (_isConnectingWs) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final token = authProvider.token;
    if (token == null) return;

    final wsBaseUrl = _api.wsBaseUrl;
    if (wsBaseUrl == null) return;

    try {
      _isConnectingWs = true;
      final url = Uri.parse('$wsBaseUrl/api/v1/chat/ws?token=$token');
      _ws = WebSocketChannel.connect(url);
      _isConnectingWs = false;
      _refreshConversationList();

      _ws?.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            _handleWsEvent(data is Map<String, dynamic> ? data : {});
          } catch (e) {
            // Ignore malformed messages
            if (kDebugMode) {
              print('Error processing WebSocket message: $e');
            }
          }
        },
        onError: (error) {
          _isConnectingWs = false;
          if (kDebugMode) {
            print('WebSocket error: $error');
          }
          _scheduleReconnect();
        },
        onDone: () {
          _isConnectingWs = false;
          if (kDebugMode) {
            print('WebSocket closed');
          }
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _isConnectingWs = false;
      if (kDebugMode) {
        print('Failed to connect WebSocket: $e');
      }
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted) return;
      _refreshConversationList();
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _reconnectWs();
      }
    });
  }

  void _reconnectWs() {
    _reconnectTimer?.cancel();
    _ws?.sink.close();
    _ws = null;
    _connectWs();
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
    if (type == null) return;

    if (type == 'presence') {
      _handlePresenceUpdate(event);
      return;
    }

    if (type == 'message' || type == 'new_message') {
      _handleIncomingConversationMessage(event);
      return;
    }

    if (type == 'read' || type == 'read_conversation') {
      _refreshConversationList();
      return;
    }

    if (type == 'message_deleted') {
      _handleConversationMessageDeleted(event);
      return;
    }

    if (type == 'message_edited') {
      _handleConversationMessageEdited(event);
      return;
    }

    if (type == 'conversation_cleared') {
      final conversationId = event['conversation_id']?.toString();
      if (conversationId == null || !mounted) return;
      setState(() {
        _conversations = _conversations
            .map(
              (conversation) => conversation.id == conversationId
                  ? conversation.copyWith(
                      clearLastMessage: true,
                      clearLastMessageAt: true,
                      unreadCount: 0,
                    )
                  : conversation,
            )
            .toList();
      });
      return;
    }

    if (type == 'conversation_deleted') {
      final conversationId = event['conversation_id']?.toString();
      if (conversationId == null || !mounted) return;
      setState(() {
        _conversations = _conversations
            .where((conversation) => conversation.id != conversationId)
            .toList();
      });
    }
  }

  void _handleIncomingConversationMessage(Map<String, dynamic> event) {
    final message = _extractPayload(event);
    final conversationId = message['conversation_id']?.toString();
    if (conversationId == null || !mounted) return;

    final senderId = message['sender_id']?.toString();
    final isIncoming = senderId != null && senderId != _currentUserId;
    final preview = _buildConversationPreview(message);
    final createdAt = _parseDateTime(message['created_at']?.toString());

    final index = _conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index == -1) {
      _refreshConversationList();
      return;
    }

    setState(() {
      final existing = _conversations[index];
      final updated = existing.copyWith(
        lastMessage: preview,
        lastMessageAt: createdAt ?? existing.lastMessageAt ?? DateTime.now(),
        unreadCount: isIncoming ? existing.unreadCount + 1 : existing.unreadCount,
      );

      _conversations = List<ChatConversation>.from(_conversations)
        ..removeAt(index)
        ..insert(0, updated);
    });
  }

  void _handleConversationMessageDeleted(Map<String, dynamic> event) {
    final conversationId = event['conversation_id']?.toString();
    if (conversationId == null || !mounted) return;

    setState(() {
      _conversations = _conversations.map((conversation) {
        if (conversation.id != conversationId) {
          return conversation;
        }

        final replacement = event['message'];
        if (replacement is Map<String, dynamic>) {
          return conversation.copyWith(
            lastMessage: _buildConversationPreview(replacement),
            lastMessageAt:
                _parseDateTime(replacement['created_at']?.toString()) ??
                conversation.lastMessageAt,
          );
        }

        return conversation.copyWith(lastMessage: 'This message was deleted');
      }).toList();
    });
  }

  void _handleConversationMessageEdited(Map<String, dynamic> event) {
    final message = event['message'];
    if (message is! Map<String, dynamic> || !mounted) return;

    final conversationId = message['conversation_id']?.toString();
    if (conversationId == null) return;

    setState(() {
      _conversations = _conversations.map((conversation) {
        if (conversation.id != conversationId) {
          return conversation;
        }

        return conversation.copyWith(
          lastMessage: _buildConversationPreview(message),
          lastMessageAt:
              _parseDateTime(message['created_at']?.toString()) ??
              conversation.lastMessageAt,
        );
      }).toList();
    });
  }

  void _handlePresenceUpdate(Map<String, dynamic> event) {
    final userId = event['user_id']?.toString();
    if (userId == null || !mounted) return;

    final online = event['online'] == true;

    setState(() {
      _conversations = _conversations.map((conversation) {
        if (conversation.kind != 'direct') {
          return conversation;
        }

        final matchesOtherUser = conversation.participants.any(
          (participantId) =>
              participantId == userId && participantId != _currentUserId,
        );

        if (!matchesOtherUser) {
          return conversation;
        }

        return conversation.copyWith(otherUserOnline: online);
      }).toList();
    });
  }

  Map<String, dynamic> _extractPayload(Map<String, dynamic> event) {
    final message = event['message'];
    if (message is Map<String, dynamic>) return message;
    final payload = event['payload'];
    if (payload is Map<String, dynamic>) return payload;
    return event;
  }

  String _buildConversationPreview(Map<String, dynamic> message) {
    final content = (message['content'] ?? message['text'] ?? '').toString().trim();
    if (content.isNotEmpty) {
      return content.length > 120 ? '${content.substring(0, 120)}...' : content;
    }

    final attachments = message['attachments'];
    if (attachments is List && attachments.isNotEmpty) {
      return 'Sent an attachment';
    }

    return 'New message';
  }

  DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// Refresh conversation list from API
  Future<void> _refreshConversationList() async {
    try {
      final data = await _api.get<dynamic>('/chat/conversations/me');
      final items = _extractItems(data);
      if (mounted) {
        setState(() {
          _conversations = items
              .whereType<Map<String, dynamic>>()
              .map(ChatConversation.fromJson)
              .toList();
        });
      }
    } catch (e) {
      // Ignore errors in background refresh
    }
  }

  List<dynamic> _extractItems(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List) return items;
    }
    return <dynamic>[];
  }

  Future<void> _startDirectMessage(User user) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/chat/conversations',
        data: {'user_id': user.id},
      );
      final convId = res['id'] ?? res['_id'];
      if (convId != null && mounted) {
        context.push('/chat/$convId');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create chat: $e')));
    }
  }

  Future<void> _handleConversationAction(
    ChatConversation conversation,
    String action,
  ) async {
    try {
      if (action == 'clear') {
        await _api.post<dynamic>('/chat/conversations/${conversation.id}/clear');
        if (!mounted) return;
        setState(() {
          _conversations = _conversations.map((item) {
            if (item.id != conversation.id) return item;
            return item.copyWith(
              clearLastMessage: true,
              clearLastMessageAt: true,
              unreadCount: 0,
            );
          }).toList();
        });
        return;
      }

      if (action == 'purge') {
        await _api.post<dynamic>('/chat/conversations/${conversation.id}/purge');
      } else if (action == 'hide') {
        await _api.delete<dynamic>('/chat/conversation/${conversation.id}');
      }

      if (!mounted) return;
      setState(() {
        _conversations = _conversations
            .where((item) => item.id != conversation.id)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update chat: $e')),
      );
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Color _getAvatarThemeColor(String name) {
    final colors = [
      Colors.indigo,
      Colors.blue,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.deepOrange,
      Colors.pink,
      Colors.purple,
    ];
    final hash = name.codeUnits.fold(0, (prev, curr) => prev + curr);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // slate-100/50
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Messages',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900, // extabold
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Chats & Conversations',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: _isLoading ? null : _loadConversations,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF7C3AED),
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                                size: 20,
                                color: Color(0xFF94A3B8),
                              ),
                        splashRadius: 24,
                      ),
                      IconButton(
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/dashboard');
                          }
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Color(0xFF94A3B8),
                        ),
                        splashRadius: 24,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Search Bar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search conversations...',
                    hintStyle: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),

            // Tabs
            Container(
              color: Colors.white,
              child: Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: ['Chats', 'Workflow', 'People', 'Unread'].map((
                      tab,
                    ) {
                      final isActive = _activeTab == tab;
                      return GestureDetector(
                        onTap: () => setState(() => _activeTab = tab),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: isActive
                                    ? const Color(0xFF7C3AED)
                                    : Colors.transparent, // violet-600
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            tab,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isActive
                                  ? const Color(0xFF7C3AED)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            // Content
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _conversations.isEmpty) {
      return _buildLoading();
    }
    if (_error != null && _conversations.isEmpty) {
      return ErrorState(message: _error!, onRetry: _loadConversations);
    }

    final query = _searchCtrl.text.trim().toLowerCase();

    if (_activeTab == 'People') {
      List<User> filteredUsers = _users;
      if (query.isNotEmpty) {
        filteredUsers = filteredUsers
            .where((u) => u.name.toLowerCase().contains(query))
            .toList();
      }
      if (_isLoadingUsers && filteredUsers.isEmpty) return _buildLoading();
      if (filteredUsers.isEmpty) {
        return const Center(
          child: Text(
            'No users found',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: filteredUsers.length,
        itemBuilder: (ctx, i) {
          final u = filteredUsers[i];
          final color = _getAvatarThemeColor(u.name);
          return _buildChatItem(
            name: u.name,
            subtitle2: u.department ?? u.role.name,
            initials: _getInitials(u.name),
            avatarBg: color.withValues(alpha: 0.15),
            avatarFg: color,
            isOnline: false,
            onTap: () => _startDirectMessage(u),
          );
        },
      );
    }

    final unreadOnly = _activeTab == 'Unread';

    List<ChatConversation> targetConversations = _conversations;
    if (query.isNotEmpty) {
      targetConversations = targetConversations.where((c) {
        final title =
            (c.eventTitle ?? c.otherUserName ?? c.participantNames.join(', '))
                .toLowerCase();
        return title.contains(query);
      }).toList();
    }
    if (unreadOnly) {
      targetConversations = targetConversations
          .where((c) => c.unreadCount > 0)
          .toList();
    }

    final isWorkflowTab = _activeTab == 'Workflow';

    if (isWorkflowTab) {
      final workflowThreads = targetConversations
          .where((c) => c.kind == 'approval_thread')
          .toList();
      if (workflowThreads.isEmpty) {
        return const Center(
          child: Text(
            'No workflow discussions',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _buildSectionHeader('Active Discussions'),
          ...workflowThreads.map((conv) {
            final title = conv.eventTitle ?? 'Event Discussion';
            final dept = conv.departmentLabel ?? conv.department ?? 'Workflow';
            return _buildChatItem(
              name: title,
              subtitle1: dept,
              subtitle2: conv.lastMessage ?? 'No messages yet',
              initials: dept.isNotEmpty ? dept[0].toUpperCase() : 'W',
              avatarBg: const Color(0xFFFFF7ED), // orange bg
              avatarFg: const Color(0xFFC2410C), // orange fg
              date: conv.lastMessageAt != null
                  ? _formatTime(conv.lastMessageAt!)
                  : null,
              unreadCount: conv.unreadCount,
              onActionSelected: (value) => _handleConversationAction(conv, value),
              onTap: () => context.push('/chat/${conv.id}'),
            );
          }),
        ],
      );
    }

    // Default Chats (Event Group and Direct)
    final eventChats = targetConversations
        .where((c) => c.kind == 'event' || c.kind == 'event_group')
        .toList();
    final directChats = targetConversations
        .where((c) => c.kind == 'direct')
        .toList();

    if (eventChats.isEmpty && directChats.isEmpty) {
      return const Center(
        child: Text(
          'No matching conversations.',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          if (eventChats.isNotEmpty) ...[
            _buildSectionHeader('Event Chats'),
            ...eventChats.map((conv) {
              final title = conv.eventTitle ?? 'Event Group';
              final nMembers = conv.participantCount > 0
                  ? conv.participantCount
                  : conv.participants.length;
              return _buildChatItem(
                name: title,
                subtitle1: '$nMembers members',
                subtitle2: conv.lastMessage ?? 'No messages yet',
                initials: title.isNotEmpty ? title[0].toUpperCase() : 'E',
                avatarBg: const Color(
                  0xFFEDE9FE,
                ), // violet-100 equivalent, keeping consistent
                avatarFg: const Color(0xFF6D28D9), // violet-700
                date: conv.lastMessageAt != null
                    ? _formatTime(conv.lastMessageAt!)
                    : null,
                unreadCount: conv.unreadCount,
                onActionSelected: (value) => _handleConversationAction(conv, value),
                onTap: () => context.push('/chat/${conv.id}'),
              );
            }),
            const SizedBox(height: 16),
          ],
          if (directChats.isNotEmpty) ...[
            _buildSectionHeader('Direct Messages'),
            ...directChats.map((conv) {
              final title =
                  conv.otherUserName ?? conv.participantNames.join(', ');
              final color = _getAvatarThemeColor(title);
              return _buildChatItem(
                name: title.isEmpty ? 'Unknown' : title,
                subtitle2: conv.lastMessage,
                initials: _getInitials(title.isEmpty ? 'U' : title),
                avatarBg: color.withValues(alpha: 0.12),
                avatarFg: color,
                isOnline: conv.otherUserOnline,
                date: conv.lastMessageAt != null
                    ? _formatTime(conv.lastMessageAt!)
                    : null,
                unreadCount: conv.unreadCount,
                onActionSelected: (value) => _handleConversationAction(conv, value),
                onTap: () => context.push('/chat/${conv.id}'),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildChatItem({
    required String name,
    String? subtitle1,
    String? subtitle2,
    String? date,
    required String initials,
    required Color avatarBg,
    required Color avatarFg,
    bool isOnline = false,
    int unreadCount = 0,
    ValueChanged<String>? onActionSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: unreadCount > 0 ? const Color(0xFFF8FAFC) : Colors.transparent,
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: avatarBg,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: avatarFg,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB), // slate-300
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w800
                                : FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (date != null)
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: unreadCount > 0
                                ? const Color(0xFF7C3AED)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (subtitle1 != null) ...[
                    Text(
                      subtitle1,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                  ],
                  if (subtitle2 != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle2,
                            style: TextStyle(
                              fontSize: 12,
                              color: unreadCount > 0
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFF94A3B8),
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (onActionSelected != null)
              PopupMenuButton<String>(
                onSelected: onActionSelected,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'clear', child: Text('Clear messages')),
                  PopupMenuItem(value: 'hide', child: Text('Hide chat')),
                  PopupMenuItem(value: 'purge', child: Text('Delete thread')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      itemCount: 8,
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            ShimmerBox(width: 44, height: 44, radius: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 140, height: 14, radius: 7),
                  const SizedBox(height: 6),
                  ShimmerBox(width: 200, height: 12, radius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (now.day == dt.day && now.month == dt.month && now.year == dt.year) {
      return DateFormat('h:mm a').format(dt);
    }
    if (diff.inDays < 7) return DateFormat('EEE').format(dt);
    return DateFormat('d MMM').format(dt);
  }
}
