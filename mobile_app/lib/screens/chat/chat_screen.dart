import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final VoidCallback? onBack;

  const ChatScreen({super.key, required this.conversationId, this.onBack});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _maxChatFileSize = 5 * 1024 * 1024;
  static const String _maxChatFileSizeLabel = '5MB';
  static const Set<String> _allowedChatMimeTypes = {
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
    'application/pdf',
  };
  static const Map<String, String> _mimeTypesByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
  };

  final _api = ApiService();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<ChatMessage> _messages = [];
  List<PlatformFile> _pendingFiles = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isUploading = false;
  bool _isTyping = false;
  WebSocketChannel? _ws;
  ChatConversation? _conversation;
  ChatReplySnapshot? _replyingTo;
  String? _conversationTitle;
  NotificationProvider? _notificationProvider;
  Timer? _typingTimer;
  Timer? _reconnectTimer;
  Timer? _remoteTypingResetTimer;

  late String _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _loadConversationMetadata();
    _connectWs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentUserId = context.read<AuthProvider>().user?.id ?? '';
    _notificationProvider ??= context.read<NotificationProvider>();

    // Cache provider references while the element tree is stable.
    _updateNotificationService(widget.conversationId);
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId == widget.conversationId) {
      return;
    }

    _notificationProvider?.clearActiveChatConversationIfMatches(
      oldWidget.conversationId,
    );
    _updateNotificationService(widget.conversationId);
    _conversation = null;
    _conversationTitle = null;
    _replyingTo = null;
    _pendingFiles = [];
    _loadMessages();
    _loadConversationMetadata();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _remoteTypingResetTimer?.cancel();
    _reconnectTimer?.cancel();
    _ws?.sink.close();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();

    // Notify notification service that this chat is no longer active
    _clearNotificationServiceForThisChat();
    super.dispose();
  }

  /// Update notification service with current chat activity status
  void _updateNotificationService(String? conversationId) {
    try {
      _notificationProvider?.setActiveChatConversation(conversationId);
    } catch (e) {
      // Ignore if notification provider is not available
      if (kDebugMode) {
        print('Error updating notification service: $e');
      }
    }
  }

  void _clearNotificationServiceForThisChat() {
    try {
      _notificationProvider?.clearActiveChatConversationIfMatches(
        widget.conversationId,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing notification service state: $e');
      }
    }
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.get<dynamic>(
        '/chat/conversations/${widget.conversationId}/messages',
      );
      final items = _extractItems(data);
      if (!mounted) return;
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
      await _markConversationRead();
      _syncReadReceipts();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadConversationMetadata() async {
    try {
      final data = await _api.get<dynamic>('/chat/conversations/me');
      final items = _extractItems(data);
      final match = items.whereType<Map<String, dynamic>>().firstWhere(
        (item) =>
            (item['id'] ?? item['_id'])?.toString() == widget.conversationId,
        orElse: () => <String, dynamic>{},
      );
      if (match.isEmpty || !mounted) return;

      final conversation = ChatConversation.fromJson(match);
      setState(() {
        _conversation = conversation;
        _conversationTitle = _buildConversationTitle(conversation);
      });
    } catch (_) {
      // Keep screen usable even if metadata refresh fails.
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

  String _buildConversationTitle(ChatConversation conversation) {
    if ((conversation.eventTitle ?? '').trim().isNotEmpty) {
      return conversation.eventTitle!.trim();
    }
    if ((conversation.otherUserName ?? '').trim().isNotEmpty) {
      return conversation.otherUserName!.trim();
    }
    final joined = conversation.participantNames.join(', ').trim();
    return joined.isNotEmpty ? joined : 'Chat';
  }

  void _connectWs() {
    final token = _api.getToken();
    final wsBase = _api.wsBaseUrl;
    if (token == null || wsBase == null) return;

    try {
      _reconnectTimer?.cancel();
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
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {}
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!mounted) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        _connectWs();
      }
    });
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final payload = _extractPayload(event);

    if (type == 'message' || type == 'new_message') {
      final msg = ChatMessage.fromJson(payload);
      if (msg.conversationId == widget.conversationId) {
        setState(() {
          // Check if this is a response to an optimistic message
          final clientId = payload['client_id']?.toString();
          if (clientId != null && clientId.startsWith('client-')) {
            // Replace optimistic message with real message
            final hasMatch = _messages.any(
              (m) => m.clientId == clientId || m.id == clientId,
            );
            if (hasMatch) {
              _messages = _messages
                  .map(
                    (m) =>
                        (m.clientId == clientId || m.id == clientId) ? msg : m,
                  )
                  .toList();
            } else {
              _messages.insert(0, msg);
            }
          } else {
            // Regular incoming message
            _messages.insert(0, msg);
          }
          _isTyping = false;
        });
        if (msg.senderId != _currentUserId) {
          _syncReadReceipts();
        }
      }
    } else if (type == 'typing') {
      if ((payload['conversation_id'] ?? payload['conversationId']) ==
              widget.conversationId &&
          (payload['user_id'] ?? payload['sender_id']) != _currentUserId) {
        final isTyping = payload['is_typing'] == true;
        _remoteTypingResetTimer?.cancel();
        setState(() => _isTyping = isTyping);
        if (isTyping) {
          _remoteTypingResetTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _isTyping = false);
            }
          });
        }
      }
    } else if (type == 'presence') {
      final userId = event['user_id']?.toString();
      if (userId != null &&
          _conversation?.kind == 'direct' &&
          _conversation!.participants.contains(userId) &&
          userId != _currentUserId) {
        setState(() {
          _conversation = _conversation?.copyWith(
            otherUserOnline: event['online'] == true,
            otherUserLastSeen: _parseWsDateTime(event['last_seen']?.toString()),
          );
        });
      }
    } else if (type == 'read' && event['message_ids'] != null) {
      // Handle read receipts for specific messages
      final List<dynamic> messageIds = event['message_ids'] is List
          ? event['message_ids']
          : [];
      final String userId = event['user_id']?.toString() ?? '';

      if (messageIds.isNotEmpty && userId.isNotEmpty) {
        setState(() {
          _messages = _messages.map((msg) {
            if (messageIds.contains(msg.id) && !msg.readBy.contains(userId)) {
              return msg.copyWith(readBy: [...msg.readBy, userId]);
            }
            return msg;
          }).toList();
        });
      }
    } else if (type == 'read_conversation') {
      // Handle when another user reads the entire conversation
      final String userId = event['user_id']?.toString() ?? '';
      final String conversationId = event['conversation_id']?.toString() ?? '';

      if (userId.isNotEmpty && conversationId == widget.conversationId) {
        setState(() {
          _messages = _messages.map((msg) {
            if (!msg.readBy.contains(userId)) {
              return msg.copyWith(readBy: [...msg.readBy, userId]);
            }
            return msg;
          }).toList();
        });
      }
    } else if (type == 'message_deleted') {
      // Handle message deletion
      final String messageId = event['message_id']?.toString() ?? '';
      final String conversationId = event['conversation_id']?.toString() ?? '';

      if (messageId.isNotEmpty && conversationId == widget.conversationId) {
        setState(() {
          _messages = _messages.map((msg) {
            if (msg.id == messageId) {
              final replacement = event['message'];
              if (replacement is Map<String, dynamic>) {
                return msg.copyWith(
                  content:
                      replacement['content']?.toString() ??
                      'This message was deleted',
                  attachments: List<dynamic>.from(
                    replacement['attachments'] ?? const [],
                  ),
                  isDeleted: replacement['is_deleted'] == true,
                  deletedForEveryone:
                      replacement['deleted_for_everyone'] == true,
                  edited: replacement['edited'] == true,
                  editedAt: replacement['edited_at'] != null
                      ? DateTime.tryParse(
                          replacement['edited_at'].toString(),
                        )?.toLocal()
                      : null,
                );
              }

              return msg.copyWith(
                content: 'This message was deleted',
                attachments: const [],
                isDeleted: true,
                deletedForEveryone: true,
                edited: false,
                editedAt: null,
              );
            }
            return msg;
          }).toList();
        });
      }
    } else if (type == 'message_edited' && event['message'] != null) {
      // Handle message edit
      final Map<String, dynamic> editedMessage =
          event['message'] is Map<String, dynamic>
          ? event['message'] as Map<String, dynamic>
          : {};
      final String messageId = editedMessage['id']?.toString() ?? '';
      final String conversationId =
          editedMessage['conversation_id']?.toString() ?? '';

      if (messageId.isNotEmpty && conversationId == widget.conversationId) {
        setState(() {
          _messages = _messages.map((msg) {
            if (msg.id == messageId) {
              return msg.copyWith(
                content: editedMessage['content']?.toString() ?? msg.content,
                attachments: List<dynamic>.from(
                  editedMessage['attachments'] ?? msg.attachments,
                ),
                edited: editedMessage['edited'] == true,
                editedAt: editedMessage['edited_at'] != null
                    ? DateTime.tryParse(
                        editedMessage['edited_at'].toString(),
                      )?.toLocal()
                    : msg.editedAt,
              );
            }
            return msg;
          }).toList();
        });
      }
    } else if (type == 'message_hidden') {
      // Handle message hidden (soft delete for current user)
      final String messageId = event['message_id']?.toString() ?? '';
      final String conversationId = event['conversation_id']?.toString() ?? '';

      if (messageId.isNotEmpty && conversationId == widget.conversationId) {
        setState(() {
          // Remove the message from view
          _messages = _messages.where((msg) => msg.id != messageId).toList();
        });
      }
    } else if (type == 'conversation_cleared') {
      final String conversationId = event['conversation_id']?.toString() ?? '';
      if (conversationId == widget.conversationId) {
        setState(() {
          _messages = [];
          _isTyping = false;
        });
      }
    } else if (type == 'conversation_deleted') {
      final String conversationId = event['conversation_id']?.toString() ?? '';
      if (conversationId == widget.conversationId && mounted) {
        Navigator.of(context).maybePop();
      }
    }
  }

  Future<void> _markConversationRead() async {
    try {
      await _notificationProvider?.markConversationAsRead(
        widget.conversationId,
      );
    } catch (_) {
      // Keep chat usable even if unread counter sync fails.
    }
  }

  Map<String, dynamic> _extractPayload(Map<String, dynamic> event) {
    final message = event['message'];
    if (message is Map<String, dynamic>) return message;
    final payload = event['payload'];
    if (payload is Map<String, dynamic>) return payload;
    return event;
  }

  Future<void> _syncReadReceipts() async {
    final unreadMessageIds = _messages
        .where(
          (message) =>
              message.senderId != _currentUserId &&
              !message.readBy.contains(_currentUserId),
        )
        .map((message) => message.id)
        .toList();

    if (unreadMessageIds.isEmpty) return;

    try {
      if (_ws != null) {
        _ws!.sink.add(
          jsonEncode({'type': 'read', 'message_ids': unreadMessageIds}),
        );
      } else {
        await _api.post<dynamic>(
          '/chat/read',
          data: {'message_ids': unreadMessageIds},
        );
      }

      if (!mounted) return;
      final unreadIds = unreadMessageIds.toSet();
      setState(() {
        _messages = _messages.map((message) {
          if (!unreadIds.contains(message.id) ||
              message.readBy.contains(_currentUserId)) {
            return message;
          }

          return message.copyWith(readBy: [...message.readBy, _currentUserId]);
        }).toList();
      });
    } catch (_) {
      _api.post('/chat/read/${widget.conversationId}').catchError((_) {});
    }
  }

  Future<void> _sendMessage() async {
    final content = _msgCtrl.text.trim();
    if (content.isEmpty && _pendingFiles.isEmpty) return;
    if (_isUploading) return;

    _typingTimer?.cancel();
    _typingTimer = null;
    _sendTypingStatus(false);

    final shortUserId = _currentUserId.length >= 4
        ? _currentUserId.substring(0, 4)
        : _currentUserId;
    final clientId =
        'client-${DateTime.now().millisecondsSinceEpoch}-${shortUserId.isEmpty ? 'anon' : shortUserId}';

    final auth = context.read<AuthProvider>();
    final capturedReply = _replyingTo;
    final capturedFiles = List<PlatformFile>.from(_pendingFiles);

    setState(() {
      _isSending = true;
      if (capturedFiles.isNotEmpty) {
        _isUploading = true;
      }
    });

    try {
      final attachments = capturedFiles.isNotEmpty
          ? await _uploadAttachments(capturedFiles)
          : <Map<String, dynamic>>[];

      final optimisticMessage = ChatMessage(
        id: clientId,
        clientId: clientId,
        conversationId: widget.conversationId,
        senderId: _currentUserId,
        senderName: auth.user?.name ?? 'You',
        senderEmail: auth.user?.email,
        content: content,
        createdAt: DateTime.now(),
        readBy: [_currentUserId],
        attachments: attachments,
        replyToMessageId: capturedReply?.messageId,
        replyToSnapshot: capturedReply,
      );

      setState(() {
        _messages.insert(0, optimisticMessage);
        _msgCtrl.clear();
        _pendingFiles = [];
        _replyingTo = null;
      });

      final payload = {
        'type': 'message',
        'conversation_id': widget.conversationId,
        'text': content,
        'attachments': attachments,
        'client_id': clientId,
        if (capturedReply?.messageId != null)
          'reply_to_message_id': capturedReply!.messageId,
      };

      if (_ws != null) {
        _ws!.sink.add(jsonEncode(payload));
      } else {
        final data = await _api.post<Map<String, dynamic>>(
          '/chat/messages',
          data: {
            'conversation_id': widget.conversationId,
            'content': content,
            'attachments': attachments,
            if (capturedReply?.messageId != null)
              'reply_to_message_id': capturedReply!.messageId,
          },
        );
        final msg = ChatMessage.fromJson(data);
        if (!mounted) return;
        setState(() {
          _messages = _messages.map((m) => m.id == clientId ? msg : m).toList();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = _messages.where((m) => m.id != clientId).toList();
        _replyingTo = capturedReply;
        _pendingFiles = capturedFiles;
      });
      _msgCtrl.text = content;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isUploading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _uploadAttachments(
    List<PlatformFile> files,
  ) async {
    final uploaded = <Map<String, dynamic>>[];
    for (final file in files) {
      final multipartFile = await _createMultipartFile(file);
      final formData = FormData.fromMap({'file': multipartFile});
      final response = await _api.postMultipart<Map<String, dynamic>>(
        '/chat/upload',
        formData,
      );
      final attachment = response['attachment'];
      if (attachment is Map<String, dynamic>) {
        uploaded.add(attachment);
      }
    }
    return uploaded;
  }

  Future<MultipartFile> _createMultipartFile(PlatformFile file) async {
    final contentType = _inferMimeType(file);
    final mediaType = MediaType.parse(contentType);

    if (file.bytes != null) {
      return MultipartFile.fromBytes(
        file.bytes!,
        filename: file.name,
        contentType: mediaType,
      );
    }
    if (file.path != null) {
      return MultipartFile.fromFile(
        file.path!,
        filename: file.name,
        contentType: mediaType,
      );
    }
    throw Exception('Unsupported attachment source for ${file.name}.');
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      );
      if (result == null || !mounted) return;

      for (final file in result.files) {
        final mimeType = _inferMimeType(file);
        if (!_allowedChatMimeTypes.contains(mimeType)) {
          _showErrorSnackBar(
            'Unsupported file type. Please upload an image (JPEG, PNG, WebP) or PDF only.',
          );
          return;
        }
        if (file.size > _maxChatFileSize) {
          _showErrorSnackBar(
            'File size exceeds $_maxChatFileSizeLabel. Please upload a smaller file or share a Drive link.',
          );
          return;
        }
      }

      setState(() {
        _pendingFiles = [..._pendingFiles, ...result.files];
      });
    } catch (e) {
      _showErrorSnackBar('Could not pick attachments: $e');
    }
  }

  String _inferMimeType(PlatformFile file) {
    final ext = file.extension?.toLowerCase();
    return _mimeTypesByExtension[ext] ?? 'application/octet-stream';
  }

  void _removePendingFile(int index) {
    setState(() {
      _pendingFiles = List<PlatformFile>.from(_pendingFiles)..removeAt(index);
    });
  }

  bool get _isThreadLocked {
    final status = (_conversation?.threadStatus ?? '').trim().toLowerCase();
    return status == 'resolved' || status == 'closed';
  }

  Future<void> _showMessageActions(ChatMessage message) async {
    final isOwn = message.senderId == _currentUserId;
    final canEdit =
        isOwn &&
        !message.deletedForEveryone &&
        message.content.trim().isNotEmpty;
    final canReply = !_isThreadLocked && !message.deletedForEveryone;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canReply)
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() {
                      _replyingTo = ChatReplySnapshot(
                        messageId: message.id,
                        senderName: message.senderName,
                        contentPreview: _messagePreview(message),
                        isDeleted: message.deletedForEveryone,
                      );
                    });
                  },
                ),
              if (canEdit)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit message'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showEditMessageDialog(message);
                  },
                ),
              if (isOwn && !message.deletedForEveryone)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete for everyone'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _confirmDeleteForEveryone(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Delete for me'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _deleteMessageForMe(message.id);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditMessageDialog(ChatMessage message) async {
    final controller = TextEditingController(text: message.content);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit message'),
          content: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Update your message',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final nextText = controller.text.trim();
    if (saved != true || nextText.isEmpty || !mounted) {
      return;
    }

    try {
      final updated = await _api.patch<Map<String, dynamic>>(
        '/chat/message/${message.id}',
        data: {'content': nextText},
      );
      final parsed = ChatMessage.fromJson(updated);
      setState(() {
        _messages = _messages
            .map((item) => item.id == message.id ? parsed : item)
            .toList();
      });
    } catch (e) {
      _showErrorSnackBar('Could not save changes: $e');
    }
  }

  Future<void> _confirmDeleteForEveryone(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete for everyone?'),
          content: const Text(
            'This message will be removed for all participants in the chat.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.delete<dynamic>('/chat/message/${message.id}');
      setState(() {
        _messages = _messages.map((item) {
          if (item.id != message.id) return item;
          return item.copyWith(
            content: 'This message was deleted',
            attachments: const [],
            isDeleted: true,
            deletedForEveryone: true,
            edited: false,
            editedAt: null,
          );
        }).toList();
      });
    } catch (e) {
      _showErrorSnackBar('Could not delete message: $e');
    }
  }

  Future<void> _deleteMessageForMe(String messageId) async {
    try {
      await _api.post<dynamic>('/chat/message/$messageId/delete-for-me');
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .where((message) => message.id != messageId)
            .toList();
      });
    } catch (e) {
      _showErrorSnackBar('Could not delete message: $e');
    }
  }

  Future<void> _handleConversationAction(String value) async {
    if (value == 'clear') {
      final confirmed = await _confirmConversationAction(
        title: 'Clear messages?',
        message: 'This will remove all messages from this conversation.',
        actionLabel: 'Clear',
      );
      if (confirmed != true) return;
      try {
        await _api.post<dynamic>(
          '/chat/conversations/${widget.conversationId}/clear',
        );
        if (!mounted) return;
        setState(() {
          _messages = [];
        });
      } catch (e) {
        _showErrorSnackBar('Could not clear conversation: $e');
      }
      return;
    }

    if (value == 'purge') {
      final confirmed = await _confirmConversationAction(
        title: 'Delete thread?',
        message: 'This will remove the conversation for everyone.',
        actionLabel: 'Delete',
      );
      if (confirmed != true) return;
      try {
        await _api.post<dynamic>(
          '/chat/conversations/${widget.conversationId}/purge',
        );
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      } catch (e) {
        _showErrorSnackBar('Could not delete thread: $e');
      }
      return;
    }

    if (value == 'hide') {
      try {
        await _api.delete<dynamic>(
          '/chat/conversation/${widget.conversationId}',
        );
        if (mounted) {
          Navigator.of(context).maybePop();
        }
      } catch (e) {
        _showErrorSnackBar('Could not hide conversation: $e');
      }
    }
  }

  Future<bool?> _confirmConversationAction({
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAttachment(Map<String, dynamic> attachment) async {
    final rawUrl = attachment['url']?.toString();
    if (rawUrl == null || rawUrl.isEmpty) return;

    final uri = Uri.parse(_resolveAttachmentUrl(rawUrl));
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showErrorSnackBar('Could not open attachment.');
    }
  }

  String _resolveAttachmentUrl(String rawUrl) {
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    final base = _api.baseUrl ?? '';
    if (base.isEmpty) return rawUrl;
    return '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}$rawUrl';
  }

  String _messagePreview(ChatMessage message) {
    final text = message.content.trim();
    if (text.isNotEmpty) {
      return text.length > 200 ? '${text.substring(0, 200)}...' : text;
    }
    if (message.attachments.isNotEmpty) {
      return 'Sent an attachment';
    }
    return 'New message';
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  DateTime? _parseWsDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _buildDirectStatus() {
    if (_conversation?.otherUserOnline == true) {
      return 'Online';
    }
    final lastSeen = _conversation?.otherUserLastSeen;
    if (lastSeen != null) {
      return 'Last seen ${_formatPresenceTime(lastSeen)}';
    }
    return 'Direct chat';
  }

  String _formatPresenceTime(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    }
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
        ? 12
        : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day}/${dt.month} $h:$m $ap';
  }

  void _sendTypingStatus(bool isTyping) {
    _ws?.sink.add(
      jsonEncode({
        'type': 'typing',
        'conversation_id': widget.conversationId,
        'is_typing': isTyping,
      }),
    );
  }

  void _sendTypingIndicator() {
    // Cancel previous timer
    _typingTimer?.cancel();

    // Send typing: true immediately
    _sendTypingStatus(true);

    // Schedule typing: false after 1.5 seconds (matching web behavior)
    _typingTimer = Timer(const Duration(milliseconds: 1500), () {
      _sendTypingStatus(false);
    });
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
    final composerBg = isDark ? const Color(0xFF0F172A) : AppColors.surface;
    final inputBg = isDark ? const Color(0xFF111827) : AppColors.background;
    final workflowDeptLabel =
        _conversation?.departmentLabel ?? _conversation?.department;
    final threadStatus = (_conversation?.threadStatus ?? '')
        .trim()
        .toLowerCase();
    final workflowStatusHint = threadStatus == 'waiting_for_faculty'
        ? 'Waiting for faculty'
        : threadStatus == 'waiting_for_department'
        ? 'Waiting for department'
        : null;
    final participantLabel =
        _conversation != null &&
            _conversation!.participantCount > 0 &&
            (_conversation!.kind == 'event' ||
                _conversation!.kind == 'event_group' ||
                _conversation!.kind == 'approval_thread')
        ? '${_conversation!.participantCount} member${_conversation!.participantCount == 1 ? '' : 's'}'
        : null;
    final subtitle = workflowDeptLabel != null || workflowStatusHint != null
        ? [workflowDeptLabel, workflowStatusHint]
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .join(' · ')
        : (_conversation?.kind == 'direct') &&
              _conversation?.otherUserName != null
        ? _buildDirectStatus()
        : participantLabel;
    final title = _conversationTitle ?? 'Chat';

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: surface,
        foregroundColor: heading,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 6),
          child: IconButton(
            tooltip: 'Back',
            onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Text(
                _conversationInitial(title),
                style: TextStyle(
                  color: isDark ? const Color(0xFF93C5FD) : AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: heading,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: PopupMenuButton<String>(
              tooltip: 'Chat options',
              onSelected: _handleConversationAction,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'clear', child: Text('Clear messages')),
                PopupMenuItem(value: 'hide', child: Text('Hide chat')),
                PopupMenuItem(value: 'purge', child: Text('Delete thread')),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: border),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: pageBg,
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : _messages.isEmpty
                  ? _ChatEmptyState(isDark: isDark)
                  : ListView.builder(
                      controller: _scrollCtrl,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 18),
                      itemCount: _messages.length + (_isTyping ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i == 0 && _isTyping) {
                          return _TypingIndicator();
                        }
                        final idx = _isTyping ? i - 1 : i;
                        final msg = _messages[idx];
                        final isOwn = msg.senderId == _currentUserId;
                        final isRead = _conversation?.kind == 'direct'
                            ? _messages[idx].readBy.any(
                                (readerId) =>
                                    readerId != _currentUserId &&
                                    readerId.isNotEmpty,
                              )
                            : _messages[idx].readBy.any(
                                (readerId) =>
                                    readerId != _currentUserId &&
                                    (_conversation?.participants.contains(
                                          readerId,
                                        ) ??
                                        false),
                              );
                        return _ChatBubble(
                          message: msg,
                          isOwn: isOwn,
                          isRead: isRead,
                          resolveAttachmentUrl: _resolveAttachmentUrl,
                          onAttachmentTap: _openAttachment,
                          onLongPress: () => _showMessageActions(msg),
                        );
                      },
                    ),
            ),
          ),
          if (_isThreadLocked)
            _ThreadLockedBanner(closedAt: _conversation?.closedAt)
          else ...[
            if (_replyingTo != null)
              _ReplyBar(
                reply: _replyingTo!,
                onDismiss: () => setState(() => _replyingTo = null),
              ),
            if (_pendingFiles.isNotEmpty)
              _PendingFilesBar(
                files: _pendingFiles,
                onRemove: _removePendingFile,
              ),
            Container(
              padding: EdgeInsets.fromLTRB(
                12,
                10,
                12,
                MediaQuery.of(context).padding.bottom + 10,
              ),
              decoration: BoxDecoration(
                color: composerBg,
                border: Border(top: BorderSide(color: border)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Attach file',
                    child: IconButton.filledTonal(
                      onPressed: (_isSending || _isUploading)
                          ? null
                          : _pickAttachments,
                      style: IconButton.styleFrom(
                        backgroundColor: panel,
                        foregroundColor: muted,
                        disabledForegroundColor: muted.withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.attach_file_rounded),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: TextField(
                        controller: _msgCtrl,
                        onChanged: (_) => _sendTypingIndicator(),
                        maxLines: 5,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: _isUploading
                              ? 'Uploading...'
                              : 'Type a message...',
                          hintStyle: TextStyle(color: muted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                        ),
                        style: TextStyle(color: heading, fontSize: 14),
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Send',
                    child: InkWell(
                      onTap: (_isSending || _isUploading) ? null : _sendMessage,
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: (_isSending || _isUploading)
                              ? AppColors.primary.withValues(alpha: 0.72)
                              : AppColors.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.24),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: (_isSending || _isUploading)
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
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _conversationInitial(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFD8E8FF),
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 34,
                color: isDark ? const Color(0xFF93C5FD) : AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No messages yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Send the first message!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: muted,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isOwn;
  final bool isRead;
  final String Function(String rawUrl) resolveAttachmentUrl;
  final Future<void> Function(Map<String, dynamic> attachment) onAttachmentTap;
  final VoidCallback onLongPress;

  const _ChatBubble({
    required this.message,
    required this.isOwn,
    required this.isRead,
    required this.resolveAttachmentUrl,
    required this.onAttachmentTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bubbleOther = isDark ? const Color(0xFF1E293B) : AppColors.surface;
    final bubbleDeleted = isDark
        ? const Color(0xFF111827)
        : AppColors.surface.withValues(alpha: 0.9);
    final bubbleBorder = isDark ? const Color(0xFF334155) : AppColors.border;
    final textPrimary = theme.colorScheme.onSurface;
    final textSecondary = theme.colorScheme.onSurfaceVariant;
    final replyBg = isOwn
        ? Colors.white.withValues(alpha: 0.14)
        : (isDark ? const Color(0xFF0F172A) : AppColors.background);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Column(
        crossAxisAlignment: isOwn
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
          GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isOwn
                    ? AppColors.primary
                    : (message.deletedForEveryone
                          ? bubbleDeleted
                          : bubbleOther),
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
                  if (message.replyToSnapshot != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: replyBg,
                        borderRadius: BorderRadius.circular(12),
                        border: isOwn ? null : Border.all(color: bubbleBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.replyToSnapshot!.senderName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isOwn ? Colors.white : AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            message.replyToSnapshot!.contentPreview,
                            style: TextStyle(
                              fontSize: 12,
                              color: isOwn
                                  ? Colors.white.withValues(alpha: 0.9)
                                  : textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 15,
                        color: isOwn ? Colors.white : textPrimary,
                        height: 1.4,
                        fontStyle: message.deletedForEveryone
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  if (message.attachments.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...message.attachments
                        .whereType<Map<String, dynamic>>()
                        .map((attachment) {
                          final contentType =
                              attachment['content_type']?.toString() ?? '';
                          final isImage = contentType.startsWith('image/');
                          return GestureDetector(
                            onTap: () => onAttachmentTap(attachment),
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isOwn
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : (isDark
                                          ? const Color(0xFF0F172A)
                                          : AppColors.background),
                                borderRadius: BorderRadius.circular(14),
                                border: isOwn
                                    ? null
                                    : Border.all(color: bubbleBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isImage)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        resolveAttachmentUrl(
                                          attachment['url']?.toString() ?? '',
                                        ),
                                        height: 180,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            const SizedBox.shrink(),
                                      ),
                                    ),
                                  if (isImage) const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        isImage
                                            ? Icons.image_outlined
                                            : Icons.picture_as_pdf_outlined,
                                        size: 18,
                                        color: isOwn
                                            ? Colors.white
                                            : AppColors.primary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          attachment['name']?.toString() ??
                                              'Attachment',
                                          style: TextStyle(
                                            color: isOwn
                                                ? Colors.white
                                                : textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: isOwn
                              ? Colors.white.withValues(alpha: 0.7)
                              : textSecondary,
                        ),
                      ),
                      if (message.edited) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(edited)',
                          style: TextStyle(
                            fontSize: 10,
                            color: isOwn
                                ? Colors.white.withValues(alpha: 0.7)
                                : textSecondary,
                          ),
                        ),
                      ],
                      if (isOwn) ...[
                        const SizedBox(width: 6),
                        Text(
                          isRead ? '✓✓' : '✓',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isRead
                                ? const Color(0xFF93C5FD)
                                : Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
        ? 12
        : dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }
}

class _ReplyBar extends StatelessWidget {
  final ChatReplySnapshot reply;
  final VoidCallback onDismiss;

  const _ReplyBar({required this.reply, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF111827) : AppColors.surface;
    final border = isDark ? const Color(0xFF334155) : AppColors.border;
    final textSecondary = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reply.senderName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.contentPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _PendingFilesBar extends StatelessWidget {
  final List<PlatformFile> files;
  final void Function(int index) onRemove;

  const _PendingFilesBar({required this.files, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF111827) : AppColors.surface;
    final border = isDark ? const Color(0xFF334155) : AppColors.border;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(files.length, (index) {
          final file = files[index];
          return Chip(
            label: Text(file.name, overflow: TextOverflow.ellipsis),
            deleteIcon: const Icon(Icons.close_rounded, size: 18),
            onDeleted: () => onRemove(index),
          );
        }),
      ),
    );
  }
}

class _ThreadLockedBanner extends StatelessWidget {
  final DateTime? closedAt;

  const _ThreadLockedBanner({this.closedAt});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final closedLabel = closedAt == null
        ? ''
        : ' since ${TimeOfDay.fromDateTime(closedAt!).format(context)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: isDark ? const Color(0xFF2A1C0C) : const Color(0xFFFFF7ED),
      child: Text(
        'This discussion is closed$closedLabel.',
        style: TextStyle(
          color: isDark ? const Color(0xFFFCD34D) : const Color(0xFF9A3412),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
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
      )..repeat(reverse: true, period: Duration(milliseconds: 600 + i * 150)),
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
                      color: AppColors.textMuted.withValues(
                        alpha: 0.4 + _controllers[i].value * 0.6,
                      ),
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
