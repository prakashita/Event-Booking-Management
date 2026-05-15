import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/common/side_nav_bar.dart';
import '../../widgets/dashboard/profile_dropdown.dart';

const Color _eventActionBlue = Color(0xFF1A73E8);
const Color _eventActionBlueSoft = Color(0xFFE8F0FE);

class HomeScreen extends StatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Increase this to make the in-app notification banner larger everywhere.
  // Example: 1.15 gives the popup bar more height, padding, and larger text.
  static const double _notificationPopupScale = 1.0;

  String _searchQuery = '';
  final ValueNotifier<bool> _chatFabVisible = ValueNotifier<bool>(true);
  Offset? _fabPos;
  bool? _lastChatUiOpen;
  OverlayEntry? _notificationBanner;
  final List<NotificationPopupEvent> _activePopupEvents =
      <NotificationPopupEvent>[];
  final Map<String, Timer> _popupTimers = <String, Timer>{};
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
    _popupTimers[event.id]?.cancel();
    _activePopupEvents.removeWhere((item) => item.id == event.id);
    _activePopupEvents.insert(0, event);
    if (_activePopupEvents.length > 3) {
      final removed = _activePopupEvents.removeLast();
      _popupTimers.remove(removed.id)?.cancel();
    }

    _popupTimers[event.id] = Timer(const Duration(seconds: 5), () {
      _dismissPopupById(event.id);
    });

    final overlay = Overlay.of(context, rootOverlay: true);
    _notificationBanner?.remove();

    _notificationBanner = OverlayEntry(
      builder: (context) => _NotificationPopupStack(
        events: List<NotificationPopupEvent>.unmodifiable(_activePopupEvents),
        bannerScale: _notificationPopupScale,
        onOpen: (popup) {
          _notificationProvider?.markNotificationAsRead(popup.id);
          _dismissPopupById(popup.id);
          _openRoute(popup.route);
        },
        onDismiss: (popup) {
          _notificationProvider?.markNotificationAsRead(popup.id);
          _dismissPopupById(popup.id);
        },
      ),
    );

    overlay.insert(_notificationBanner!);
  }

  void _dismissNotificationBanner() {
    for (final timer in _popupTimers.values) {
      timer.cancel();
    }
    _popupTimers.clear();
    _activePopupEvents.clear();
    _notificationBanner?.remove();
    _notificationBanner = null;
  }

  void _dismissPopupById(String id) {
    _popupTimers.remove(id)?.cancel();
    _activePopupEvents.removeWhere((item) => item.id == id);
    _notificationBanner?.markNeedsBuild();
    if (_activePopupEvents.isEmpty) {
      _notificationBanner?.remove();
      _notificationBanner = null;
    }
  }

  void _openChat() {
    context.read<NotificationProvider>().setChatUiOpen(true);
    context.push('/chat');
  }

  void _openRoute(String route) {
    if (route == '/chat' || route.startsWith('/chat/')) {
      context.push(route);
      return;
    }
    context.go(route);
  }

  Future<void> _openNotificationsPanel() async {
    if (!mounted) return;

    final notificationProvider = Provider.of<NotificationProvider>(
      context,
      listen: false,
    );

    // Ensure notification service is initialized and refresh unread count
    await notificationProvider.initialize();
    if (!mounted) return;
    await notificationProvider.refreshUnreadCount();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) {
        var showUnreadOnly = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Consumer<NotificationProvider>(
              builder: (context, provider, _) {
                final allNotifications = provider.notifications;
                final notifications = showUnreadOnly
                    ? allNotifications.where((item) => !item.isRead).toList()
                    : allNotifications;
                final unreadConversations = provider.unreadConversations;
                final visibleConversations = unreadConversations;
                final unreadNotifications = provider.unreadNotificationCount;
                final currentTotalUnread = provider.totalUnread;
                final visibleConversationRoutes = visibleConversations
                    .map((conversation) => '/chat/${conversation.id}')
                    .toSet();
                final hasUnreadItems =
                    unreadNotifications > 0 || unreadConversations.isNotEmpty;
                final hasVisibleItems =
                    visibleConversations.isNotEmpty || notifications.isNotEmpty;
                final hasAnyItems =
                    unreadConversations.isNotEmpty ||
                    allNotifications.isNotEmpty;
                final badgeCount = unreadNotifications > currentTotalUnread
                    ? unreadNotifications
                    : currentTotalUnread;
                final today = DateTime.now();
                final yesterday = today.subtract(const Duration(days: 1));
                final groupedTiles = <String, List<Widget>>{
                  'Today': <Widget>[],
                  'Yesterday': <Widget>[],
                  'Older': <Widget>[],
                };

                String dateGroup(DateTime timestamp) {
                  final local = timestamp.toLocal();
                  if (DateUtils.isSameDay(local, today)) return 'Today';
                  if (DateUtils.isSameDay(local, yesterday)) return 'Yesterday';
                  return 'Older';
                }

                void addTile(DateTime timestamp, Widget tile) {
                  groupedTiles[dateGroup(timestamp)]!.add(tile);
                }

                for (final conversation in visibleConversations) {
                  addTile(
                    conversation.lastMessageAt ?? today,
                    _UnreadConversationTile(
                      conversation: conversation,
                      onOpen: () {
                        Navigator.of(sheetContext).pop();
                        if (mounted) {
                          this.context.push('/chat/${conversation.id}');
                        }
                      },
                      onDismiss: () {
                        provider.markConversationAsRead(conversation.id);
                        ScaffoldMessenger.maybeOf(sheetContext)?.showSnackBar(
                          const SnackBar(
                            content: Text('Chat notification removed'),
                          ),
                        );
                      },
                    ),
                  );
                }

                for (final item in notifications) {
                  if (visibleConversationRoutes.contains(item.route)) {
                    continue;
                  }
                  addTile(
                    item.createdAt,
                    _NotificationListTile(
                      item: item,
                      onOpen: () {
                        provider.markNotificationAsRead(item.id);
                        Navigator.of(sheetContext).pop();
                        if (mounted) {
                          _openRoute(item.route);
                        }
                      },
                      onDismiss: () {
                        provider.dismissNotification(item.id);
                        ScaffoldMessenger.maybeOf(sheetContext)?.showSnackBar(
                          const SnackBar(content: Text('Notification removed')),
                        );
                      },
                      onMarkRead: () {
                        provider.markNotificationAsRead(item.id);
                      },
                    ),
                  );
                }

                return DraggableScrollableSheet(
                  initialChildSize: 0.74,
                  minChildSize: 0.36,
                  maxChildSize: 0.88,
                  expand: false,
                  snap: true,
                  snapSizes: const [0.36, 0.74, 0.88],
                  builder: (context, scrollController) {
                    final theme = Theme.of(context);
                    final isDark = theme.brightness == Brightness.dark;
                    final sheetColor = isDark
                        ? theme.scaffoldBackgroundColor
                        : const Color(0xFFF4F7FE);
                    final sheetBorder = isDark
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0);
                    final elevatedSurface = isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white;

                    return SafeArea(
                      top: false,
                      child: Container(
                        decoration: BoxDecoration(
                          color: sheetColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          border: Border(top: BorderSide(color: sheetBorder)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.32 : 0.14,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, -8),
                            ),
                          ],
                        ),
                        child: CustomScrollView(
                          controller: scrollController,
                          physics: const ClampingScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  10,
                                  18,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 44,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF334155)
                                              : _eventActionBlue.withValues(
                                                  alpha: 0.24,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'Notifications',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 24,
                                                    height: 1,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0,
                                                    color: isDark
                                                        ? Colors.white
                                                        : AppColors.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              if (badgeCount > 0) ...[
                                                const SizedBox(width: 10),
                                                Container(
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    color: _eventActionBlue,
                                                    shape: BoxShape.circle,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: _eventActionBlue
                                                            .withValues(
                                                              alpha: 0.22,
                                                            ),
                                                        blurRadius: 8,
                                                        offset: const Offset(
                                                          0,
                                                          3,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Text(
                                                    badgeCount > 99
                                                        ? '99+'
                                                        : '$badgeCount',
                                                    style: const TextStyle(
                                                      color:
                                                          AppColors.onPrimary,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Tooltip(
                                          message: 'Close',
                                          child: IconButton(
                                            onPressed: () => Navigator.of(
                                              sheetContext,
                                            ).pop(),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                            style: IconButton.styleFrom(
                                              backgroundColor: elevatedSurface,
                                              foregroundColor: isDark
                                                  ? const Color(0xFFCBD5E1)
                                                  : const Color(0xFF64748B),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: BorderSide(
                                                  color: sheetBorder,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        _NotificationFilterButton(
                                          label: 'All',
                                          selected: !showUnreadOnly,
                                          onTap: () {
                                            setSheetState(() {
                                              showUnreadOnly = false;
                                            });
                                          },
                                        ),
                                        const SizedBox(width: 10),
                                        _NotificationFilterButton(
                                          label: 'Unread',
                                          selected: showUnreadOnly,
                                          onTap: () {
                                            setSheetState(() {
                                              showUnreadOnly = true;
                                            });
                                          },
                                        ),
                                        const Spacer(),
                                        SizedBox(
                                          width: 38,
                                          height: 38,
                                          child: Tooltip(
                                            message: 'Mark all read',
                                            child: IconButton(
                                              onPressed: hasUnreadItems
                                                  ? () async {
                                                      await provider
                                                          .markAllNotificationsAsRead();
                                                    }
                                                  : null,
                                              icon: const Icon(
                                                LucideIcons.checkCheck,
                                                size: 18,
                                              ),
                                              style: IconButton.styleFrom(
                                                backgroundColor: hasUnreadItems
                                                    ? _eventActionBlue
                                                    : elevatedSurface,
                                                foregroundColor: hasUnreadItems
                                                    ? Colors.white
                                                    : _eventActionBlue,
                                                disabledForegroundColor:
                                                    AppColors.textMuted,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  side: BorderSide(
                                                    color: hasUnreadItems
                                                        ? _eventActionBlue
                                                        : sheetBorder,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 38,
                                          height: 38,
                                          child: Tooltip(
                                            message: 'Clear notifications',
                                            child: IconButton(
                                              onPressed: hasAnyItems
                                                  ? () async {
                                                      await provider
                                                          .clearNotifications();
                                                    }
                                                  : null,
                                              icon: const Icon(
                                                LucideIcons.trash2,
                                                size: 17,
                                              ),
                                              style: IconButton.styleFrom(
                                                backgroundColor:
                                                    elevatedSurface,
                                                foregroundColor:
                                                    AppColors.textMuted,
                                                disabledForegroundColor:
                                                    AppColors.textMuted
                                                        .withValues(alpha: 0.5),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  side: BorderSide(
                                                    color: sheetBorder,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            ),
                            if (!hasVisibleItems)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _NotificationsEmptyState(
                                  showUnreadOnly: showUnreadOnly,
                                ),
                              )
                            else
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    0,
                                    18,
                                    28,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final group in groupedTiles.entries)
                                        if (group.value.isNotEmpty) ...[
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              8,
                                              8,
                                              8,
                                            ),
                                            child: Text(
                                              group.key.toUpperCase(),
                                              style: const TextStyle(
                                                color: _eventActionBlue,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.9,
                                              ),
                                            ),
                                          ),
                                          ...group.value.expand(
                                            (tile) => <Widget>[
                                              tile,
                                              const SizedBox(height: 6),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
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
    for (final timer in _popupTimers.values) {
      timer.cancel();
    }
    _popupTimers.clear();
    _chatFabVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final routerState = GoRouterState.of(context);
    final currentRoute = routerState.matchedLocation;
    final currentPath = routerState.uri.path;
    final isChatRoute =
        currentRoute == '/chat' ||
        currentRoute.startsWith('/chat/') ||
        currentPath == '/chat' ||
        currentPath.startsWith('/chat/');
    final shouldShowChatFab = !isChatRoute;
    if (_lastChatUiOpen != isChatRoute) {
      _lastChatUiOpen = isChatRoute;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<NotificationProvider>().setChatUiOpen(isChatRoute);
        _chatFabVisible.value = shouldShowChatFab;
      });
    }
    final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = theme.scaffoldBackgroundColor;

    if (isChatRoute) {
      return ChatFabVisibilityScope(
        visibleNotifier: _chatFabVisible,
        child: DashboardSearchScope(
          searchQuery: _searchQuery,
          child: widget.child,
        ),
      );
    }

    final headerBg = theme.colorScheme.surface;
    final searchBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF4F7FE);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.35 : 0.05);

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 16.0 : 10.0,
                    vertical: isDesktop ? 8.0 : 6.0,
                  ),
                  child: SafeArea(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 8.0 : 6.0,
                        vertical: isDesktop ? 8.0 : 6.0,
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
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(LucideIcons.menu),
                                onPressed: () {
                                  Scaffold.of(context).openDrawer();
                                },
                              ),
                            ),
                          if (!isDesktop) const SizedBox(width: 4),
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
                          SizedBox(width: isDesktop ? 12 : 8),
                          Consumer<NotificationProvider>(
                            builder: (context, notificationProvider, _) {
                              final totalUnread =
                                  notificationProvider.unreadNotificationCount >
                                      notificationProvider.totalUnread
                                  ? notificationProvider.unreadNotificationCount
                                  : notificationProvider.totalUnread;
                              final bellBg = isDark
                                  ? const Color(0xFF1E293B)
                                  : totalUnread > 0
                                  ? _eventActionBlueSoft
                                  : _eventActionBlueSoft.withValues(
                                      alpha: 0.58,
                                    );
                              final bellBorder = isDark
                                  ? const Color(0xFF334155)
                                  : totalUnread > 0
                                  ? _eventActionBlue.withValues(alpha: 0.24)
                                  : _eventActionBlue.withValues(alpha: 0.12);
                              final bellIconColor = isDark
                                  ? const Color(0xFF93C5FD)
                                  : _eventActionBlue;
                              return SizedBox(
                                width: isDesktop ? 48 : 44,
                                height: 42,
                                child: Tooltip(
                                  message: 'Notifications',
                                  child: InkWell(
                                    onTap: _openNotificationsPanel,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            width: isDesktop ? 42 : 40,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: bellBg,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: bellBorder,
                                              ),
                                            ),
                                            child: Icon(
                                              totalUnread > 0
                                                  ? LucideIcons.bellRing
                                                  : LucideIcons.bell,
                                              color: bellIconColor,
                                              size: 19,
                                            ),
                                          ),
                                        ),
                                        if (totalUnread > 0)
                                          Positioned(
                                            right: 0,
                                            top: -3,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              constraints: const BoxConstraints(
                                                minWidth: 18,
                                                minHeight: 18,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFDC2626),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: headerBg,
                                                  width: 2,
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
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          SizedBox(width: isDesktop ? 8 : 4),
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
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
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
                            if (!isChatRoute)
                              ValueListenableBuilder<bool>(
                                valueListenable: _chatFabVisible,
                                builder: (context, visible, _) {
                                  final showFab = isTopRoute && visible;

                                  if (!showFab) return const SizedBox.shrink();

                                  // Keep logic for dynamically calculating the default position based on page
                                  final hasPageLevelActions =
                                      currentRoute == '/requirements' ||
                                      currentRoute == '/admin' ||
                                      currentRoute == '/events/create' ||
                                      currentRoute == '/publications' ||
                                      currentRoute == '/student-achievements' ||
                                      currentRoute.startsWith('/events/') ||
                                      currentRoute.startsWith(
                                        '/approval-details/',
                                      );
                                  final hasTallBottomActionBar =
                                      currentRoute == '/events/create';
                                  final hasExtendedPageFab =
                                      currentRoute == '/publications' ||
                                      currentRoute == '/student-achievements';
                                  final bottomInset = MediaQuery.viewPaddingOf(
                                    context,
                                  ).bottom;

                                  final baseBottomOffset =
                                      hasTallBottomActionBar
                                      ? 150.0 + bottomInset
                                      : hasExtendedPageFab
                                      ? 32.0 + bottomInset
                                      : hasPageLevelActions
                                      ? 72.0 + bottomInset
                                      : 16.0;
                                  final defaultBottom = baseBottomOffset;
                                  final defaultRight = 16.0;

                                  return Positioned(
                                    left: _fabPos?.dx,
                                    top: _fabPos?.dy,
                                    right: _fabPos == null
                                        ? defaultRight
                                        : null,
                                    bottom: _fabPos == null
                                        ? defaultBottom
                                        : null,
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
                                                  _openChat();
                                                },
                                                backgroundColor: const Color(
                                                  0xFF2563EB,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
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
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 5,
                                                          vertical: 1,
                                                        ),
                                                    constraints:
                                                        const BoxConstraints(
                                                          minWidth: 18,
                                                          minHeight: 16,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFDC2626,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
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
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w700,
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

class _NotificationPopupStack extends StatelessWidget {
  final List<NotificationPopupEvent> events;
  final double bannerScale;
  final void Function(NotificationPopupEvent event) onOpen;
  final void Function(NotificationPopupEvent event) onDismiss;

  const _NotificationPopupStack({
    required this.events,
    this.bannerScale = 1.0,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final scale = bannerScale.clamp(0.9, 1.35);

    return Positioned(
      top: topPadding + (10 * scale),
      left: 12,
      right: 12,
      child: IgnorePointer(
        ignoring: events.isEmpty,
        child: Material(
          color: Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                for (var i = 0; i < events.length; i++) ...[
                  if (i > 0) SizedBox(height: 8 * scale),
                  _NotificationPopupBanner(
                    event: events[i],
                    stackIndex: i,
                    sizeScale: scale,
                    onOpen: () => onOpen(events[i]),
                    onDismiss: () => onDismiss(events[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationPopupBanner extends StatefulWidget {
  final NotificationPopupEvent event;
  final int stackIndex;
  final double sizeScale;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _NotificationPopupBanner({
    required this.event,
    required this.stackIndex,
    this.sizeScale = 1.0,
    required this.onOpen,
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
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _relativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = widget.sizeScale.clamp(0.9, 1.35);
    final isDark = theme.brightness == Brightness.dark;

    return Transform.translate(
      offset: Offset(0, widget.stackIndex * 2 * scale),
      child: SlideTransition(
        position: _slide,
        child: Dismissible(
          key: ValueKey(widget.event.id),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onDismiss(),
          child: InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(24 * scale),
            child: Container(
              constraints: BoxConstraints(minHeight: 86 * scale),
              padding: EdgeInsets.fromLTRB(
                14 * scale,
                14 * scale,
                10 * scale,
                14 * scale,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24 * scale),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.14),
                    blurRadius: 26 * scale,
                    offset: Offset(0, 12 * scale),
                  ),
                ],
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.14),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44 * scale,
                    height: 44 * scale,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(15 * scale),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Icon(
                      LucideIcons.bellRing,
                      color: const Color(0xFF2563EB),
                      size: 22 * scale,
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 14.5 * scale,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            SizedBox(width: 8 * scale),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8 * scale,
                                vertical: 4 * scale,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: isDark ? 0.35 : 0.75),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _relativeTime(widget.event.createdAt),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10.5 * scale,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 5 * scale),
                        Text(
                          widget.event.body,
                          maxLines: scale > 1.12 ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13 * scale,
                            height: 1.35,
                          ),
                        ),
                        SizedBox(height: 10 * scale),
                        Row(
                          children: [
                            FilledButton(
                              onPressed: widget.onOpen,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                minimumSize: Size(0, 34 * scale),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14 * scale,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    12 * scale,
                                  ),
                                ),
                                textStyle: TextStyle(
                                  fontSize: 12.5 * scale,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: const Text('Open'),
                            ),
                            SizedBox(width: 8 * scale),
                            TextButton(
                              onPressed: widget.onDismiss,
                              style: TextButton.styleFrom(
                                minimumSize: Size(0, 34 * scale),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12 * scale,
                                ),
                                textStyle: TextStyle(
                                  fontSize: 12.5 * scale,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('Dismiss'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 6 * scale),
                  IconButton(
                    onPressed: widget.onDismiss,
                    icon: Icon(Icons.close_rounded, size: 18 * scale),
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: isDark ? 0.2 : 0.55),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12 * scale),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationFilterButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NotificationFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final inactiveBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final inactiveText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          height: 38,
          constraints: const BoxConstraints(minWidth: 74),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2563EB) : inactiveBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? const Color(0xFF2563EB) : inactiveBorder,
              width: 1.5,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x332563EB),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : inactiveText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationListTile extends StatelessWidget {
  final AppNotificationItem item;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final VoidCallback onMarkRead;

  const _NotificationListTile({
    required this.item,
    required this.onOpen,
    required this.onDismiss,
    required this.onMarkRead,
  });

  String _displayTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    if (DateUtils.isSameDay(local, DateTime.now())) {
      return DateFormat('hh:mm a').format(local);
    }
    return DateFormat('MMM d').format(local);
  }

  String get _headline {
    final title = item.title.trim();
    if (title.isNotEmpty) return title;
    return 'Notification';
  }

  String get _contextLabel {
    final category = item.category.trim();
    final normalized = category.toLowerCase();
    if (normalized == 'message' || normalized == 'chat') return 'Chat';
    if (normalized == 'approval_thread' || normalized == 'workflow') {
      return 'Workflow discussion';
    }
    if (normalized == 'event') return 'Event chat';
    if (category.isNotEmpty) return category;
    return 'System update';
  }

  Color get _accentColor {
    final source = '${_headline.toLowerCase()} ${_contextLabel.toLowerCase()}';
    if (source.contains('marketing')) return AppColors.warning;
    if (source.contains('finance')) return const Color(0xFF0E7490);
    if (source.contains('facility')) return const Color(0xFF00897B);
    if (source.contains('workflow') || source.contains('approval')) {
      return AppColors.info;
    }
    if (source.contains('event')) return AppColors.primaryDark;
    return AppColors.primary;
  }

  IconData get _contextIcon {
    final label = _contextLabel.toLowerCase();
    if (label.contains('workflow') || label.contains('approval')) {
      return LucideIcons.gitBranch;
    }
    if (label.contains('event')) return LucideIcons.calendarDays;
    if (label.contains('chat')) return LucideIcons.messageCircle;
    return LucideIcons.bell;
  }

  Widget _dismissBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: alignment,
      child: const Icon(LucideIcons.trash2, color: Colors.white, size: 22),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = _accentColor;
    final cardBg = item.isRead
        ? isDark
              ? const Color(0xFF172033)
              : Colors.white
        : isDark
        ? _eventActionBlue.withValues(alpha: 0.12)
        : _eventActionBlueSoft.withValues(alpha: 0.82);
    final borderColor = item.isRead
        ? isDark
              ? const Color(0xFF334155)
              : const Color(0xFFE8EEF7)
        : _eventActionBlue.withValues(alpha: isDark ? 0.32 : 0.22);
    final primaryText = isDark ? Colors.white : const Color(0xFF172033);
    final secondaryText = isDark
        ? const Color(0xFFCBD5E1)
        : AppColors.textSecondary;

    return Dismissible(
      key: ValueKey('notification-${item.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.18,
        DismissDirection.endToStart: 0.18,
      },
      background: _dismissBackground(Alignment.centerLeft),
      secondaryBackground: _dismissBackground(Alignment.centerRight),
      confirmDismiss: (_) async {
        onDismiss();
        return false;
      },
      child: InkWell(
        onTap: onOpen,
        onDoubleTap: item.isRead ? null : onMarkRead,
        onLongPress: onDismiss,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!item.isRead) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _eventActionBlue,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accentColor.withValues(alpha: 0.1)),
                ),
                child: Icon(_contextIcon, color: accentColor, size: 20),
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
                            _headline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: item.isRead
                                  ? FontWeight.w700
                                  : FontWeight.w900,
                              color: item.isRead ? secondaryText : primaryText,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _displayTime(item.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _contextLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: item.isRead
                            ? secondaryText
                            : const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: item.isRead ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: secondaryText,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message: item.isRead ? 'Dismiss' : 'Mark read',
                child: IconButton(
                  onPressed: item.isRead ? onDismiss : onMarkRead,
                  icon: Icon(
                    item.isRead ? LucideIcons.x : LucideIcons.check,
                    size: 16,
                  ),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    foregroundColor: item.isRead
                        ? AppColors.textMuted
                        : const Color(0xFF16A34A),
                    backgroundColor: item.isRead
                        ? Colors.transparent
                        : const Color(0xFF16A34A).withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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

class _NotificationsEmptyState extends StatelessWidget {
  final bool showUnreadOnly;

  const _NotificationsEmptyState({required this.showUnreadOnly});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final boxBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFF1F5F9);
    final iconColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFFCBD5E1);
    final titleColor = isDark ? Colors.white : const Color(0xFF334155);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF94A3B8);

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 20, 32, 52),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: boxBg,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: boxBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                showUnreadOnly ? LucideIcons.checkCheck : LucideIcons.bell,
                color: iconColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              showUnreadOnly
                  ? 'No unread notifications'
                  : "You're all caught up",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                color: titleColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showUnreadOnly
                  ? 'Everything visible here has already been handled.'
                  : 'New updates will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: subtitleColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadConversationTile extends StatelessWidget {
  final ChatConversation conversation;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _UnreadConversationTile({
    required this.conversation,
    required this.onOpen,
    required this.onDismiss,
  });

  String _displayTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    if (DateUtils.isSameDay(local, DateTime.now())) {
      return DateFormat('hh:mm a').format(local);
    }
    return DateFormat('MMM d').format(local);
  }

  String get _title {
    final eventTitle = conversation.eventTitle?.trim() ?? '';
    if (eventTitle.isNotEmpty) return eventTitle;

    final otherUser = conversation.otherUserName?.trim() ?? '';
    if (otherUser.isNotEmpty) return otherUser;

    final participants = conversation.participantNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    if (participants.isNotEmpty) return participants.join(', ');

    return 'Chat conversation';
  }

  String get _contextLabel {
    final department = conversation.departmentLabel?.trim() ?? '';
    if (department.isNotEmpty) return department;

    switch (conversation.kind) {
      case 'approval_thread':
        return 'Workflow discussion';
      case 'event':
        return 'Event chat';
      default:
        return 'Chat';
    }
  }

  String get _initials {
    final source = _title.trim().isNotEmpty ? _title : _contextLabel;
    final parts = source.split(RegExp(r'\s+|_|-|–')).where((part) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) return false;
      return RegExp(r'[A-Za-z0-9]').hasMatch(trimmed);
    }).toList();
    if (parts.isEmpty) return 'CH';
    if (parts.length == 1) {
      final text = parts.first.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      if (text.isEmpty) return 'CH';
      return text.substring(0, text.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  Color get _avatarColor {
    final source = '${_title.toLowerCase()} ${_contextLabel.toLowerCase()}';
    if (source.contains('marketing')) return AppColors.warning;
    if (source.contains('finance')) return const Color(0xFF0E7490);
    if (source.contains('facility')) return const Color(0xFF00897B);
    if (source.contains('it ') || source.contains('system')) {
      return AppColors.primary;
    }
    if (source.contains('approval') || source.contains('workflow')) {
      return AppColors.info;
    }
    if (source.contains('event')) return AppColors.primaryDark;
    return AppColors.primary;
  }

  String get _messagePreview {
    final message = conversation.lastMessage?.trim() ?? '';
    if (message.isNotEmpty) return message;
    return 'Open this conversation to view unread messages.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final unreadCount = conversation.unreadCount;
    final isWorkflow = conversation.kind == 'approval_thread';
    final isEvent = conversation.kind == 'event';
    final tileColor = isDark ? const Color(0xFF172033) : Colors.white;
    final borderColor = _eventActionBlue.withValues(
      alpha: isDark ? 0.32 : 0.22,
    );
    final primaryText = isDark
        ? const Color(0xFFF8FAFC)
        : AppColors.textPrimary;
    final secondaryText = isDark
        ? const Color(0xFFCBD5E1)
        : AppColors.textSecondary;

    return Dismissible(
      key: ValueKey('conversation-notification-${conversation.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.18,
        DismissDirection.endToStart: 0.18,
      },
      background: _conversationDismissBackground(Alignment.centerLeft),
      secondaryBackground: _conversationDismissBackground(
        Alignment.centerRight,
      ),
      confirmDismiss: (_) async {
        onDismiss();
        return false;
      },
      child: InkWell(
        onTap: onOpen,
        onLongPress: onDismiss,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                left: -8,
                top: 18,
                child: SizedBox(
                  width: 7,
                  height: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _eventActionBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _avatarColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _avatarColor.withValues(alpha: 0.10),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: Text(
                              _initials,
                              style: TextStyle(
                                color: _avatarColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0F172A)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _avatarColor.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Icon(
                                isWorkflow
                                    ? LucideIcons.gitBranch
                                    : isEvent
                                    ? LucideIcons.calendarDays
                                    : LucideIcons.messageCircle,
                                size: 10,
                                color: _avatarColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.18,
                              fontWeight: FontWeight.w800,
                              color: primaryText,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _contextLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: primaryText,
                                  ),
                                ),
                              ),
                              if (isWorkflow) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.infoLight,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _workflowStatusLabel,
                                    style: const TextStyle(
                                      color: AppColors.info,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _messagePreview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.25,
                              color: secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 60,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (conversation.lastMessageAt != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF273449)
                                      : const Color(0xFFE6EDF5),
                                ),
                              ),
                              child: Text(
                                _displayTime(conversation.lastMessageAt!),
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          if (unreadCount > 0)
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: _eventActionBlue,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _workflowStatusLabel {
    switch ((conversation.threadStatus ?? '').toLowerCase()) {
      case 'waiting_for_faculty':
        return 'Faculty';
      case 'waiting_for_department':
        return 'Dept';
      case 'resolved':
        return 'Resolved';
      case 'closed':
        return 'Closed';
      default:
        return 'Thread';
    }
  }

  Widget _conversationDismissBackground(Alignment alignment) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: alignment,
      child: const Icon(LucideIcons.trash2, color: Colors.white, size: 22),
    );
  }
}
