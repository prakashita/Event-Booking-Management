import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/common/app_widgets.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isTyping = false;
  WebSocketChannel? _ws;
  String? _conversationTitle;

  late String _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = context.read<AuthProvider>().user?.id ?? '';
    _loadMessages();
    _connectWs();
  }

  @override
  void dispose() {
    _ws?.sink.close();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _api.get<dynamic>(
        '/chat/conversations/${widget.conversationId}/messages',
      );
      final items = _extractItems(data);
      setState(() {
        _messages = items
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
          .toList()
          .reversed
          .toList();
        _isLoading = false;
        _conversationTitle = _extractConversationTitle(data);
      });
      // Mark as read
      _api.post('/chat/read/${widget.conversationId}').catchError((_) {});
    } catch (e) {
      setState(() => _isLoading = false);
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

  String? _extractConversationTitle(dynamic data) {
    if (data is Map<String, dynamic>) {
      final title = data['conversation_title'] ?? data['title'];
      if (title is String && title.trim().isNotEmpty) return title;
    }
    return null;
  }

  void _connectWs() {
    final token = _api.getToken();
    final wsBase = _api.wsBaseUrl;
    if (token == null || wsBase == null) return;

    try {
      final uri = Uri.parse('$wsBase/api/v1/chat/ws?token=$token');
      _ws = WebSocketChannel.connect(uri);
      _ws!.stream.listen(
        (data) {
          try {
            final event = data is String
                ? jsonDecode(data) as Map<String, dynamic>
                : data as Map<String, dynamic>;
            _handleWsEvent(event);
          } catch (_) {}
        },
        onDone: () {},
        onError: (_) {},
      );
      // Join conversation
      _ws!.sink.add(jsonEncode({
        'type': 'join',
        'conversation_id': widget.conversationId,
      }));
    } catch (_) {}
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final payload = _extractPayload(event);

    if (type == 'message' || type == 'new_message') {
      final msg = ChatMessage.fromJson(payload);
      if (msg.conversationId == widget.conversationId) {
        setState(() {
          _messages.insert(0, msg);
          _isTyping = false;
        });
      }
    } else if (type == 'typing') {
      if ((payload['conversation_id'] ?? payload['conversationId']) ==
          widget.conversationId &&
          (payload['user_id'] ?? payload['sender_id']) != _currentUserId) {
        setState(() => _isTyping = true);
        Future.delayed(const Duration(seconds: 3),
            () => mounted ? setState(() => _isTyping = false) : null);
      }
    }
  }

  Map<String, dynamic> _extractPayload(Map<String, dynamic> event) {
    final message = event['message'];
    if (message is Map<String, dynamic>) return message;
    final payload = event['payload'];
    if (payload is Map<String, dynamic>) return payload;
    return event;
  }

  Future<void> _sendMessage() async {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty) return;

    _msgCtrl.clear();
    setState(() => _isSending = true);

    try {
      // Send via WS if connected
      if (_ws != null) {
        _ws!.sink.add(jsonEncode({
          'type': 'message',
          'conversation_id': widget.conversationId,
          'text': content,
        }));
      } else {
        // Fallback to REST
        final data = await _api.post<Map<String, dynamic>>(
          '/chat/messages',
          data: {
            'conversation_id': widget.conversationId,
            'content': content,
          },
        );
        final msg = ChatMessage.fromJson(data);
        setState(() => _messages.insert(0, msg));
      }
    } catch (e) {
      // Restore message on error
      if (!mounted) return;
      _msgCtrl.text = content;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _sendTypingIndicator() {
    _ws?.sink.add(jsonEncode({
      'type': 'typing',
      'conversation_id': widget.conversationId,
      'is_typing': true,
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_conversationTitle ?? 'Chat'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.info_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const EmptyState(
                        icon: Icons.chat_bubble_outline,
                        title: 'No messages yet',
                        message: 'Send the first message!',
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _messages.length + (_isTyping ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == 0 && _isTyping) {
                            return _TypingIndicator();
                          }
                          final idx = _isTyping ? i - 1 : i;
                          final msg = _messages[idx];
                          final isOwn = msg.senderId == _currentUserId;
                          return _ChatBubble(message: msg, isOwn: isOwn);
                        },
                      ),
          ),

          // Input bar
          Container(
            padding: EdgeInsets.fromLTRB(
                12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgCtrl,
                            onChanged: (_) => _sendTypingIndicator(),
                            maxLines: null,
                            decoration: const InputDecoration(
                              hintText: 'Type a message...',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isSending ? null : _sendMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: _isSending
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOwn;

  const _ChatBubble({required this.message, required this.isOwn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Column(
        crossAxisAlignment:
            isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isOwn)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                message.senderName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isOwn ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: isOwn
                    ? const Radius.circular(18)
                    : const Radius.circular(4),
                bottomRight: isOwn
                    ? const Radius.circular(4)
                    : const Radius.circular(18),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 15,
                    color: isOwn ? Colors.white : AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: isOwn
                        ? Colors.white.withValues(alpha: 0.7)
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : dt.hour == 0 ? 12 : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..repeat(
          reverse: true,
          period: Duration(milliseconds: 600 + i * 150),
        ),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => AnimatedBuilder(
                  animation: _controllers[i],
                  builder: (_, _) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted
                          .withValues(alpha: 0.4 + _controllers[i].value * 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
