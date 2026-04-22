import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../screens/chat/chat_list_screen.dart';
import '../../screens/chat/chat_screen.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/common/side_nav_bar.dart';
import '../../widgets/dashboard/profile_dropdown.dart';

class HomeScreen extends StatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';
  final ValueNotifier<bool> _chatFabVisible = ValueNotifier<bool>(true);
  Offset? _fabPos;
  bool? _lastChatUiOpen;
  OverlayEntry? _notificationBanner;
  Timer? _notificationBannerTimer;
  NotificationProvider? _notificationProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkGoogleScopes();
      // Initialize real-time notifications
      _initializeNotifications();
    });
  }

  Future<void> _initializeNotifications() async {
    if (!mounted) return;
    final notificationProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    );
    _notificationProvider ??= notificationProvider;
    _notificationProvider?.removePopupListener(_handlePopupNotification);
    _notificationProvider?.addPopupListener(_handlePopupNotification);
    await notificationProvider.initialize();
  }

  void _handlePopupNotification(NotificationPopupEvent event) {
    if (!mounted) return;
    _showInAppNotificationBanner(event);
  }

  void _showInAppNotificationBanner(NotificationPopupEvent event) {
    _notificationBannerTimer?.cancel();
    _notificationBanner?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);

    _notificationBanner = OverlayEntry(
      builder: (context) => _NotificationPopupBanner(
        event: event,
        onTap: () {
          _dismissNotificationBanner();
          GoRouter.of(context).go(event.route);
        },
        onDismiss: _dismissNotificationBanner,
      ),
    );

    overlay.insert(_notificationBanner!);
    _notificationBannerTimer = Timer(const Duration(seconds: 4), () {
      _dismissNotificationBanner();
    });
  }

  void _dismissNotificationBanner() {
    _notificationBannerTimer?.cancel();
    _notificationBannerTimer = null;
    _notificationBanner?.remove();
    _notificationBanner = null;
  }

  Future<void> _openNotificationsPanel() async {
    if (!mounted) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final notificationProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    );

    // Ensure notification service is initialized and refresh unread count
    await notificationProvider.initialize();
    if (!mounted) return;
    await notificationProvider.refreshUnreadCount();
    if (!mounted) return;

    final totalUnread = notificationProvider.totalUnread;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (totalUnread > 0)
                      Text(
                        '$totalUnread unread',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (totalUnread > 0)
                  InkWell(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/chat');
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? theme.colorScheme.surfaceContainerHigh
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? theme.colorScheme.outline.withValues(
                                  alpha: 0.35,
                                )
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.message_outlined, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Unread Messages',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$totalUnread unread in chats and discussions',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              totalUnread > 99 ? '99+' : '$totalUnread',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        "You're all caught up",
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkGoogleScopes() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null || user.id.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final promptedKey = 'google_connect_prompted_${user.id}';

      final api = ApiService();
      final res = await api.get<Map<String, dynamic>>('/auth/google/status');

      final connected = res['connected'] == true;
      final missing = List<String>.from(res['missing_scopes'] ?? []);

      if (connected) {
        await prefs.remove(promptedKey);
        return;
      }

      if (missing.isNotEmpty) {
        final alreadyPrompted = prefs.getBool(promptedKey) ?? false;
        if (!alreadyPrompted) {
          await prefs.setBool(promptedKey, true);
          if (mounted) {
            _showGoogleScopeModal(missing);
          }
        }
      }
    } catch (_) {
      // Background check, silently ignore errors
    }
  }

  void _showGoogleScopeModal(List<String> missing) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final theme = Theme.of(dialogContext);
        final isDark = theme.brightness == Brightness.dark;

        final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
        final textColor = isDark
            ? const Color(0xFFF8FAFC)
            : const Color(0xFF0F172A);
        final subColor = isDark
            ? const Color(0xFF94A3B8)
            : const Color(0xFF64748B);
        final dividerColor = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0);

        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Connect Google',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(dialogContext).pop(),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, color: subColor, size: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: dividerColor),
                const SizedBox(height: 16),
                Text(
                  'Your Google connection is missing permissions needed for calendar, invites, or report uploads. Please connect Google to continue.',
                  style: TextStyle(fontSize: 14, height: 1.5, color: subColor),
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: subColor,
                    ),
                    children: [
                      TextSpan(
                        text: 'Missing scopes: ',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      TextSpan(text: missing.join(', ')),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Divider(height: 1, color: dividerColor),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: textColor,
                        backgroundColor: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFF1F5F9),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text(
                        'Later',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        try {
                          final api = ApiService();
                          final res = await api.get<Map<String, dynamic>>(
                            '/calendar/connect-url',
                          );
                          final url = res['url']?.toString();
                          if (url != null && url.isNotEmpty) {
                            final uri = Uri.parse(url);
                            try {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (_) {
                              // Fallback if external application fails
                              await launchUrl(
                                uri,
                                mode: LaunchMode.platformDefault,
                              );
                            }
                          }
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Failed to obtain Google Connect URL.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text(
                        'Connect Google',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _dismissNotificationBanner();
    _notificationProvider?.removePopupListener(_handlePopupNotification);
    _notificationBannerTimer?.cancel();
    _chatFabVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isChatChild =
        widget.child is ChatListScreen || widget.child is ChatScreen;
    final isChatRoute =
        isChatChild ||
        currentRoute == '/chat' ||
        currentRoute.startsWith('/chat/');
    if (_lastChatUiOpen != isChatRoute) {
      _lastChatUiOpen = isChatRoute;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<NotificationProvider>().setChatUiOpen(isChatRoute);
      });
    }
    final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = theme.scaffoldBackgroundColor;
    final headerBg = theme.colorScheme.surface;
    final searchBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF4F7FE);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.35 : 0.05);

    return Scaffold(
      backgroundColor: pageBg,
      drawer: SideNavBar(currentRoute: currentRoute),
      body: Row(
        children: [
          if (isDesktop) SideNavBar(currentRoute: currentRoute),
          Expanded(
            child: Column(
              children: [
                // Custom Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 8.0,
                      ),
                      decoration: BoxDecoration(
                        color: headerBg,
                        borderRadius: BorderRadius.circular(24.0),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          if (!isDesktop)
                            Builder(
                              builder: (context) => IconButton(
                                icon: const Icon(LucideIcons.menu),
                                onPressed: () {
                                  Scaffold.of(context).openDrawer();
                                },
                              ),
                            ),
                          if (!isDesktop) const SizedBox(width: 8),
                          // Search Bar
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextField(
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search...',
                                  prefixIcon: const Icon(
                                    LucideIcons.search,
                                    size: 18,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(16.0),
                                    ),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: searchBg,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Consumer<NotificationProvider>(
                            builder: (context, notificationProvider, _) {
                              final totalUnread =
                                  notificationProvider.totalUnread;
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  IconButton(
                                    tooltip: 'Notifications',
                                    onPressed: _openNotificationsPanel,
                                    icon: const Icon(
                                      LucideIcons.bell,
                                      size: 18,
                                    ),
                                  ),
                                  if (totalUnread > 0)
                                    Positioned(
                                      right: 6,
                                      top: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDC2626),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          totalUnread > 99
                                              ? '99+'
                                              : '$totalUnread',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          if (user != null)
                            ProfileDropdown(user: user)
                          else
                            const CircleAvatar(
                              backgroundColor: Color(0xFF2563EB),
                              child: Icon(
                                LucideIcons.user,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Main Content
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: ChatFabVisibilityScope(
                              visibleNotifier: _chatFabVisible,
                              child: DashboardSearchScope(
                                searchQuery: _searchQuery,
                                child: widget.child,
                              ),
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: _chatFabVisible,
                            builder: (context, visible, _) {
                              final showFab =
                                  isTopRoute && visible && !isChatRoute;

                              if (!showFab) return const SizedBox.shrink();

                              // Keep logic for dynamically calculating the default position based on page
                              final hasPageLevelActions =
                                  currentRoute == '/requirements' ||
                                  currentRoute == '/admin' ||
                                  currentRoute == '/events/create';

                              final baseBottomOffset = hasPageLevelActions
                                  ? 96.0
                                  : 16.0;
                              final defaultBottom = bottomInset > 0
                                  ? bottomInset + 16.0
                                  : baseBottomOffset;
                              final defaultRight = 16.0;

                              return Positioned(
                                left: _fabPos?.dx,
                                top: _fabPos?.dy,
                                right: _fabPos == null ? defaultRight : null,
                                bottom: _fabPos == null ? defaultBottom : null,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setState(() {
                                      double curX =
                                          _fabPos?.dx ??
                                          (constraints.maxWidth -
                                              56 -
                                              defaultRight);
                                      double curY =
                                          _fabPos?.dy ??
                                          (constraints.maxHeight -
                                              56 -
                                              defaultBottom);

                                      double newX = curX + details.delta.dx;
                                      double newY = curY + details.delta.dy;

                                      newX = newX.clamp(
                                        0.0,
                                        constraints.maxWidth - 56.0,
                                      );
                                      newY = newY.clamp(
                                        0.0,
                                        constraints.maxHeight - 56.0,
                                      );

                                      _fabPos = Offset(newX, newY);
                                    });
                                  },
                                  child: Consumer<NotificationProvider>(
                                    builder: (context, notificationProvider, _) {
                                      final totalUnread =
                                          notificationProvider.totalUnread;
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          FloatingActionButton(
                                            key: const ValueKey<String>(
                                              'chat_fab_visible',
                                            ),
                                            onPressed: () {
                                              context.push('/chat');
                                            },
                                            backgroundColor: const Color(0xFF2563EB),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(16),
                                            ),
                                            child: const Icon(
                                              LucideIcons.messageSquare,
                                              color: Colors.white,
                                            ),
                                          ),
                                          if (totalUnread > 0)
                                            Positioned(
                                              right: -2,
                                              top: -2,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 5,
                                                  vertical: 1,
                                                ),
                                                constraints: const BoxConstraints(
                                                  minWidth: 18,
                                                  minHeight: 16,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFDC2626),
                                                  borderRadius: BorderRadius.circular(
                                                    999,
                                                  ),
                                                  border: Border.all(
                                                    color: Colors.white,
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Text(
                                                  totalUnread > 99
                                                      ? '99+'
                                                      : '$totalUnread',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
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

class ChatFabVisibilityScope extends InheritedWidget {
  const ChatFabVisibilityScope({
    super.key,
    required this.visibleNotifier,
    required super.child,
  });

  final ValueNotifier<bool> visibleNotifier;

  static ValueNotifier<bool>? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<ChatFabVisibilityScope>();
    return scope?.visibleNotifier;
  }

  @override
  bool updateShouldNotify(ChatFabVisibilityScope oldWidget) {
    return oldWidget.visibleNotifier != visibleNotifier;
  }
}

class DashboardSearchScope extends InheritedWidget {
  const DashboardSearchScope({
    super.key,
    required this.searchQuery,
    required super.child,
  });

  final String searchQuery;

  static DashboardSearchScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DashboardSearchScope>();
  }

  @override
  bool updateShouldNotify(DashboardSearchScope oldWidget) {
    return oldWidget.searchQuery != searchQuery;
  }
}

class _NotificationPopupBanner extends StatefulWidget {
  final NotificationPopupEvent event;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationPopupBanner({
    required this.event,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_NotificationPopupBanner> createState() =>
      _NotificationPopupBannerState();
}

class _NotificationPopupBannerState extends State<_NotificationPopupBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 10,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _slide,
          child: SafeArea(
            bottom: false,
            child: Dismissible(
              key: ValueKey('${widget.event.title}-${widget.event.body}'),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismiss(),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.message_rounded,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.event.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: widget.onDismiss,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
