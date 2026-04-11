import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
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
  List<ChatConversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversations();
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

  List<dynamic> _extractItems(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List) return items;
    }
    return <dynamic>[];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            onPressed: _showNewConversationSheet,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoading()
          : _error != null
              ? ErrorState(message: _error!, onRetry: _loadConversations)
              : _conversations.isEmpty
                  ? const EmptyState(
                      icon: Icons.chat_bubble_outline,
                      title: 'No messages yet',
                      message: 'Start a conversation with a colleague.',
                    )
                  : RefreshIndicator(
                      onRefresh: _loadConversations,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _conversations.length,
                        itemBuilder: (ctx, i) {
                          final conv = _conversations[i];
                          return _ConversationTile(
                            conversation: conv,
                            onTap: () => context.go('/chat/${conv.id}'),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      itemCount: 8,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ShimmerBox(width: 48, height: 48, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 140, height: 14, radius: 7),
                  const SizedBox(height: 6),
                  ShimmerBox(width: double.infinity, height: 12, radius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewConversationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _NewConversationSheet(
        onCreated: (convId) {
          Navigator.pop(ctx);
          context.go('/chat/$convId');
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  String get _title {
    if (conversation.kind == 'event_group') {
      return conversation.eventTitle ?? 'Event Group';
    }
    return conversation.participantNames.isNotEmpty
        ? conversation.participantNames.join(', ')
        : 'Conversation';
  }

  @override
  Widget build(BuildContext context) {
    final isGroup = conversation.kind == 'event_group';
    final hasUnread = conversation.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: hasUnread
              ? AppColors.primary.withOpacity(0.04)
              : AppColors.surface,
          border: const Border(
            bottom: BorderSide(color: AppColors.divider),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isGroup
                    ? AppColors.primaryContainer
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                isGroup ? Icons.groups : Icons.person,
                size: 24,
                color: isGroup ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.lastMessageAt != null)
                        Text(
                          _formatTime(conversation.lastMessageAt!),
                          style: TextStyle(
                            fontSize: 11,
                            color: hasUnread
                                ? AppColors.primary
                                : AppColors.textMuted,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage ?? 'No messages yet',
                          style: TextStyle(
                            fontSize: 13,
                            color: hasUnread
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            '${conversation.unreadCount}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
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

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return DateFormat('h:mm a').format(dt);
    if (diff.inDays < 7) return DateFormat('EEE').format(dt);
    return DateFormat('MMM d').format(dt);
  }
}

class _NewConversationSheet extends StatefulWidget {
  final Function(String convId) onCreated;
  const _NewConversationSheet({required this.onCreated});

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  List<User> _users = [];
  List<User> _filtered = [];
  User? _selected;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final data = await _api.get<dynamic>('/chat/users');
      final users = data is List
          ? data
          : (data is Map<String, dynamic> && data['items'] is List)
              ? data['items'] as List
              : <dynamic>[];
      setState(() {
        _users = users
            .whereType<Map<String, dynamic>>()
            .map(User.fromJson)
            .toList();
        _filtered = _users;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? _users
          : _users
              .where((u) =>
                  u.name.toLowerCase().contains(q.toLowerCase()) ||
                  u.email.toLowerCase().contains(q.toLowerCase()))
              .toList();
    });
  }

  Future<void> _createConversation() async {
    if (_selected == null) return;
    try {
      final data = await _api.post<Map<String, dynamic>>(
        '/chat/conversations',
        data: {'user_id': _selected!.id},
      );
      widget.onCreated(data['id'] ?? data['_id']);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New Message',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _searchCtrl,
            onChanged: _filter,
            decoration: const InputDecoration(
              hintText: 'Search people...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final u = _filtered[i];
                      final isSelected = _selected?.id == u.id;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryContainer,
                          child: Text(
                            u.name[0].toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        title: Text(u.name),
                        subtitle: Text(u.email),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle,
                                color: AppColors.primary)
                            : null,
                        selected: isSelected,
                        onTap: () => setState(() => _selected = u),
                      );
                    },
                  ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected != null ? _createConversation : null,
              child: const Text('Start Conversation'),
            ),
          ),
        ],
      ),
    );
  }
}
