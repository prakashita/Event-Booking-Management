import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkGoogleScopes();
    });
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
        final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
        final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
        final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        
        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: subColor,
                  ),
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
                        style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
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
                        backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Later', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        try {
                          final api = ApiService();
                          final res = await api.get<Map<String, dynamic>>('/calendar/connect-url');
                          final url = res['url']?.toString();
                          if (url != null && url.isNotEmpty) {
                            final uri = Uri.parse(url);
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (_) {
                              // Fallback if external application fails
                              await launchUrl(uri, mode: LaunchMode.platformDefault);
                            }
                          }
                        } catch (_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to obtain Google Connect URL.')),
                            );
                          }
                        }
                      },
                      child: const Text('Connect Google', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
    _chatFabVisible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final currentRoute = GoRouterState.of(context).matchedLocation;
    final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBg = theme.scaffoldBackgroundColor;
    final headerBg = theme.colorScheme.surface;
    final searchBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFF4F7FE);
    final shadowColor = Colors.black.withOpacity(isDark ? 0.35 : 0.05);

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
                  child: ChatFabVisibilityScope(
                    visibleNotifier: _chatFabVisible,
                    child: DashboardSearchScope(
                      searchQuery: _searchQuery,
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _chatFabVisible,
        builder: (context, visible, _) {
          final showFab = isTopRoute && visible;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.92,
                    end: 1.0,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: showFab
                ? FloatingActionButton(
                    key: const ValueKey<String>('chat_fab_visible'),
                    onPressed: () {
                      context.go('/chat');
                    },
                    backgroundColor: const Color(0xFF2563EB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      LucideIcons.messageSquare,
                      color: Colors.white,
                    ),
                  )
                : const SizedBox.shrink(
                    key: ValueKey<String>('chat_fab_hidden'),
                  ),
          );
        },
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
