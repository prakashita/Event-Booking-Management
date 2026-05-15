import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/common/app_widgets.dart';

class ChatListScreen extends StatefulWidget {
  final VoidCallback? onClose;
  final ValueChanged<String>? onOpenConversation;

  const ChatListScreen({super.key, this.onClose, this.onOpenConversation});

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
  bool _isDisposed = false;
  String _currentUserId = '';
  Timer? _autoRefreshTimer;
  Timer? _reconnectTimer;

  String _activeTab = 'Chats';

  int get _messagesUnreadCount => _conversations
      .where(
        (conversation) =>
            conversation.kind == 'event' ||
            conversation.kind == 'event_group' ||
            conversation.kind == 'direct',
      )
      .fold<int>(0, (sum, conversation) => sum + conversation.unreadCount);

  int get _workflowUnreadCount => _conversations
      .where(
        (conversation) =>
            conversation.kind == 'approval_thread' &&
            _isActiveWorkflowThread(conversation),
      )
      .fold<int>(0, (sum, conversation) => sum + conversation.unreadCount);

  int get _totalUnreadCount => _conversations.fold<int>(
    0,
    (sum, conversation) => sum + conversation.unreadCount,
  );

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
    _isDisposed = true;
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _api.get<dynamic>('/chat/conversations/me');
      final items = _extractItems(data);
      if (!mounted) return;
      setState(() {
        _conversations = items
            .whereType<Map<String, dynamic>>()
            .map(ChatConversation.fromJson)
            .toList();
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(
          e,
          fallback: 'Could not load chats. Please try again.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoadingUsers = true);
    try {
      final data = await _api.get<dynamic>('/chat/users');
      final items = _extractItems(data);
      if (!mounted) return;
      setState(() {
        _users = items
            .whereType<Map<String, dynamic>>()
            .map(User.fromJson)
            .toList();
        _isLoadingUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingUsers = false;
      });
    }
  }

  /// Connect to WebSocket for real-time conversation updates
  void _connectWs() {
    if (_isDisposed || _isConnectingWs) return;

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
          if (_isDisposed) return;
          _isConnectingWs = false;
          if (kDebugMode) {
            print('WebSocket error: $error');
          }
          _scheduleReconnect();
        },
        onDone: () {
          if (_isDisposed) return;
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
    if (_isDisposed || !mounted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _reconnectWs();
      }
    });
  }

  void _reconnectWs() {
    if (_isDisposed) return;
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
        unreadCount: isIncoming
            ? existing.unreadCount + 1
            : existing.unreadCount,
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
    final lastSeen = _parseDateTime(event['last_seen']?.toString());

    setState(() {
      _users = _users
          .map(
            (user) => user.id == userId
                ? user.copyWith(online: online, lastSeen: lastSeen)
                : user,
          )
          .toList();
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

        return conversation.copyWith(
          otherUserOnline: online,
          otherUserLastSeen: lastSeen,
        );
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
    final content = (message['content'] ?? message['text'] ?? '')
        .toString()
        .trim();
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
        _openChatScreen(convId.toString());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Could not create chat. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _handleConversationAction(
    ChatConversation conversation,
    String action,
  ) async {
    try {
      if (action == 'clear') {
        await _api.post<dynamic>(
          '/chat/conversations/${conversation.id}/clear',
        );
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
        await _api.post<dynamic>(
          '/chat/conversations/${conversation.id}/purge',
        );
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
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              e,
              fallback: 'Could not update chat. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  String _conversationTitle(ChatConversation conversation) {
    final title =
        conversation.eventTitle ??
        conversation.otherUserName ??
        conversation.participantNames.join(', ');
    return title.trim().isEmpty ? 'Unknown conversation' : title.trim();
  }

  bool _isActiveWorkflowThread(ChatConversation conversation) {
    final status = (conversation.threadStatus ?? '').trim().toLowerCase();
    return status.isEmpty ||
        status == 'active' ||
        status == 'waiting_for_faculty' ||
        status == 'waiting_for_department';
  }

  bool _isArchivedWorkflowThread(ChatConversation conversation) {
    final status = (conversation.threadStatus ?? '').trim().toLowerCase();
    return status == 'resolved' || status == 'closed';
  }

  bool _matchesConversation(ChatConversation conversation, String query) {
    if (query.isEmpty) return true;
    final haystack = [
      _conversationTitle(conversation),
      conversation.departmentLabel ?? '',
      conversation.department ?? '',
      conversation.lastMessage ?? '',
      conversation.participantNames.join(' '),
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }

  void _openConversation(ChatConversation conversation) {
    if (conversation.unreadCount > 0) {
      setState(() {
        _conversations = _conversations
            .map(
              (item) => item.id == conversation.id
                  ? item.copyWith(unreadCount: 0)
                  : item,
            )
            .toList();
      });
    }
    _openChatScreen(conversation.id);
  }

  Future<void> _openChatScreen(String conversationId) async {
    final onOpenConversation = widget.onOpenConversation;
    if (onOpenConversation != null) {
      onOpenConversation(conversationId);
      return;
    }
    context.push('/chat/$conversationId');
  }

  Future<void> _closeChatSection() async {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }

    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      context.go('/dashboard');
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = isDark
        ? theme.scaffoldBackgroundColor
        : AppColors.background;
    final surface = isDark ? const Color(0xFF111827) : AppColors.surface;
    final panel = isDark ? const Color(0xFF1E293B) : AppColors.surfaceVariant;
    final border = isDark ? const Color(0xFF334155) : AppColors.border;
    final heading = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MESSAGES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: muted,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'Chat',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: heading,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                if (_totalUnreadCount > 0) ...[
                                  const SizedBox(width: 10),
                                  _HeaderUnreadPill(count: _totalUnreadCount),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        children: [
                          const _ThemeModeToggle(),
                          const SizedBox(width: 8),
                          _HeaderActionButton(
                            tooltip: 'Refresh conversations',
                            onPressed: _isLoading ? null : _loadConversations,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                    color: muted,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          _HeaderActionButton(
                            tooltip: 'Close chat',
                            onPressed: _closeChatSection,
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      'Conversations, workflow discussions, and people',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: panel,
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: _activeTab == 'People'
                        ? 'Search people...'
                        : 'Search conversations...',
                    hintStyle: TextStyle(
                      color: muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: Icon(Icons.search, size: 16, color: muted),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),

            Container(
              color: surface,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: ['Chats', 'Workflow', 'People', 'Unread'].map((
                      tab,
                    ) {
                      final isActive = _activeTab == tab;
                      final count = tab == 'Chats'
                          ? _messagesUnreadCount
                          : tab == 'Workflow'
                          ? _workflowUnreadCount
                          : tab == 'Unread'
                          ? _totalUnreadCount
                          : 0;
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
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                tab,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isActive ? AppColors.primary : muted,
                                ),
                              ),
                              if (count > 0) ...[
                                const SizedBox(width: 6),
                                _UnreadBadge(count: count, compact: true),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

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
        filteredUsers = filteredUsers.where((user) {
          final haystack = [
            user.name,
            user.email,
            user.department ?? '',
            user.roleLabel,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        }).toList();
      }
      if (_isLoadingUsers && filteredUsers.isEmpty) return _buildLoading();
      if (filteredUsers.isEmpty) {
        return const EmptyState(
          icon: Icons.person_search_outlined,
          title: 'No people found',
          message: 'Try another name, email, department, or role.',
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
            isOnline: u.online,
            onTap: () => _startDirectMessage(u),
          );
        },
      );
    }

    final unreadOnly = _activeTab == 'Unread';

    List<ChatConversation> targetConversations = _conversations;
    if (query.isNotEmpty) {
      targetConversations = targetConversations
          .where((conversation) => _matchesConversation(conversation, query))
          .toList();
    }
    if (unreadOnly) {
      targetConversations = targetConversations
          .where((c) => c.unreadCount > 0)
          .toList();
    }

    final isWorkflowTab = _activeTab == 'Workflow';

    if (unreadOnly) {
      final unreadWorkflowThreads = targetConversations
          .where((c) => c.kind == 'approval_thread')
          .toList();
      final unreadEventChats = targetConversations
          .where((c) => c.kind == 'event' || c.kind == 'event_group')
          .toList();
      final unreadDirectChats = targetConversations
          .where((c) => c.kind == 'direct')
          .toList();

      if (targetConversations.isEmpty) {
        return EmptyState(
          icon: Icons.mark_chat_read_outlined,
          title: query.isEmpty ? 'All caught up' : 'No unread matches',
          message: query.isEmpty
              ? 'Unread messages from chats and workflow threads will appear here.'
              : 'Try a different search to find unread conversations.',
        );
      }

      return RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (unreadWorkflowThreads.isNotEmpty) ...[
              _buildSectionHeader('Unread Workflow'),
              ...unreadWorkflowThreads.map((conv) {
                final title = conv.eventTitle ?? 'Event Discussion';
                final dept =
                    conv.departmentLabel ?? conv.department ?? 'Workflow';
                return _buildChatItem(
                  name: title,
                  subtitle1: dept,
                  subtitle2: conv.lastMessage ?? 'No messages yet',
                  initials: dept.isNotEmpty ? dept[0].toUpperCase() : 'W',
                  avatarBg: const Color(0xFFFFF7ED),
                  avatarFg: const Color(0xFFC2410C),
                  date: conv.lastMessageAt != null
                      ? _formatTime(conv.lastMessageAt!)
                      : null,
                  unreadCount: conv.unreadCount,
                  onActionSelected: (value) =>
                      _handleConversationAction(conv, value),
                  onTap: () => _openConversation(conv),
                );
              }),
              const SizedBox(height: 16),
            ],
            if (unreadEventChats.isNotEmpty) ...[
              _buildSectionHeader('Unread Event Chats'),
              ...unreadEventChats.map((conv) {
                final title = conv.eventTitle ?? 'Event Group';
                final nMembers = conv.participantCount > 0
                    ? conv.participantCount
                    : conv.participants.length;
                return _buildChatItem(
                  name: title,
                  subtitle1: '$nMembers members',
                  subtitle2: conv.lastMessage ?? 'No messages yet',
                  initials: title.isNotEmpty ? title[0].toUpperCase() : 'E',
                  avatarBg: AppColors.primaryContainer,
                  avatarFg: AppColors.primary,
                  date: conv.lastMessageAt != null
                      ? _formatTime(conv.lastMessageAt!)
                      : null,
                  unreadCount: conv.unreadCount,
                  onActionSelected: (value) =>
                      _handleConversationAction(conv, value),
                  onTap: () => _openConversation(conv),
                );
              }),
              const SizedBox(height: 16),
            ],
            if (unreadDirectChats.isNotEmpty) ...[
              _buildSectionHeader('Unread Direct Messages'),
              ...unreadDirectChats.map((conv) {
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
                  onActionSelected: (value) =>
                      _handleConversationAction(conv, value),
                  onTap: () => _openConversation(conv),
                );
              }),
            ],
          ],
        ),
      );
    }

    if (isWorkflowTab) {
      final workflowThreads = targetConversations
          .where((c) => c.kind == 'approval_thread')
          .toList();
      final activeWorkflowThreads = workflowThreads
          .where(_isActiveWorkflowThread)
          .toList();
      final archivedWorkflowThreads = workflowThreads
          .where(_isArchivedWorkflowThread)
          .toList();
      if (workflowThreads.isEmpty) {
        return const EmptyState(
          icon: Icons.account_tree_outlined,
          title: 'No workflow discussions',
          message: 'Approval threads will appear here when they are active.',
        );
      }
      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          if (activeWorkflowThreads.isNotEmpty) ...[
            _buildSectionHeader('Active Discussions'),
            ...activeWorkflowThreads.map((conv) {
              final title = conv.eventTitle ?? 'Event Discussion';
              final dept =
                  conv.departmentLabel ?? conv.department ?? 'Workflow';
              return _buildChatItem(
                name: title,
                subtitle1: dept,
                subtitle2: conv.lastMessage ?? 'No messages yet',
                initials: dept.isNotEmpty ? dept[0].toUpperCase() : 'W',
                avatarBg: const Color(0xFFFFF7ED),
                avatarFg: const Color(0xFFC2410C),
                date: conv.lastMessageAt != null
                    ? _formatTime(conv.lastMessageAt!)
                    : null,
                unreadCount: conv.unreadCount,
                onActionSelected: (value) =>
                    _handleConversationAction(conv, value),
                onTap: () => _openConversation(conv),
              );
            }),
          ],
          if (archivedWorkflowThreads.isNotEmpty) ...[
            if (activeWorkflowThreads.isNotEmpty) const SizedBox(height: 16),
            _buildSectionHeader('Archived Discussions'),
            ...archivedWorkflowThreads.map((conv) {
              final title = conv.eventTitle ?? 'Event Discussion';
              final dept =
                  conv.departmentLabel ?? conv.department ?? 'Workflow';
              return _buildChatItem(
                name: title,
                subtitle1: dept,
                subtitle2: conv.lastMessage ?? 'No messages yet',
                initials: dept.isNotEmpty ? dept[0].toUpperCase() : 'W',
                avatarBg: const Color(0xFFFFF7ED),
                avatarFg: const Color(0xFFC2410C),
                date: conv.lastMessageAt != null
                    ? _formatTime(conv.lastMessageAt!)
                    : null,
                unreadCount: 0,
                onActionSelected: (value) =>
                    _handleConversationAction(conv, value),
                onTap: () => _openConversation(conv),
              );
            }),
          ],
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
      return EmptyState(
        icon: Icons.chat_bubble_outline,
        title: query.isEmpty && !unreadOnly
            ? 'No conversations yet'
            : 'No matching conversations',
        message: unreadOnly
            ? 'You are all caught up.'
            : 'Start a direct chat from People or open an event discussion.',
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
                avatarBg: AppColors.primaryContainer,
                avatarFg: AppColors.primary,
                date: conv.lastMessageAt != null
                    ? _formatTime(conv.lastMessageAt!)
                    : null,
                unreadCount: conv.unreadCount,
                onActionSelected: (value) =>
                    _handleConversationAction(conv, value),
                onTap: () => _openConversation(conv),
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
                onActionSelected: (value) =>
                    _handleConversationAction(conv, value),
                onTap: () => _openConversation(conv),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF94A3B8);
    final unreadBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.72)
        : const Color(0xFFF8FAFC);
    final unreadText = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF1E293B);
    final avatarBackground = isDark
        ? avatarFg.withValues(alpha: 0.18)
        : avatarBg;
    final onlineBorder = isDark ? const Color(0xFF0F172A) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: unreadCount > 0 ? unreadBg : Colors.transparent,
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
                    color: avatarBackground,
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
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: onlineBorder, width: 2),
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
                            color: titleColor,
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
                                ? AppColors.primary
                                : mutedColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (subtitle1 != null) ...[
                    Text(
                      subtitle1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: subtitleColor,
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
                              color: unreadCount > 0 ? unreadText : mutedColor,
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
                              color: AppColors.primary,
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
                iconColor: isDark ? const Color(0xFFE2E8F0) : null,
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

class _ThemeModeToggle extends StatelessWidget {
  const _ThemeModeToggle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = context.watch<ThemeProvider>();
    final activeColor = isDark
        ? const Color(0xFFFBBF24)
        : const Color(0xFF2563EB);
    final trackColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final inactiveIcon = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    return Tooltip(
      message: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: InkWell(
        onTap: () {
          themeProvider.setThemeModeByValue(isDark ? 'light' : 'dark');
        },
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 64,
          height: 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.wb_sunny_rounded,
                      size: 15,
                      color: isDark ? inactiveIcon : activeColor,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.dark_mode_rounded,
                      size: 15,
                      color: isDark ? activeColor : inactiveIcon,
                    ),
                  ),
                ],
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: isDark
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.32 : 0.12,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
                    size: 15,
                    color: activeColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  const _HeaderActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark ? const Color(0xFF1E293B) : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 38, height: 38, child: Center(child: child)),
        ),
      ),
    );
  }
}

class _HeaderUnreadPill extends StatelessWidget {
  final int count;

  const _HeaderUnreadPill({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$label unread',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  final bool compact;

  const _UnreadBadge({required this.count, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: BoxConstraints(
        minWidth: compact ? 18 : 22,
        minHeight: compact ? 18 : 22,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1 : 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}
