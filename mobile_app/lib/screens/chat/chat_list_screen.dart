import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();

  List<ChatConversation> _conversations = [];
  List<User> _users = [];
  bool _isLoading = true;
  bool _isLoadingUsers = false;
  String? _error;

  String _activeTab = 'Chats';

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadUsers();
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
      if (filteredUsers.isEmpty)
        return const Center(
          child: Text(
            'No users found',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        );

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
            avatarBg: color.withOpacity(0.15),
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
                avatarBg: color.withOpacity(0.12),
                avatarFg: color,
                isOnline: conv.otherUserOnline,
                date: conv.lastMessageAt != null
                    ? _formatTime(conv.lastMessageAt!)
                    : null,
                unreadCount: conv.unreadCount,
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
