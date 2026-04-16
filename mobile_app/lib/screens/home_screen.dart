import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/common/side_nav_bar.dart';
import '../../widgets/dashboard/profile_dropdown.dart';

class HomeScreen extends StatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final currentRoute = GoRouterState.of(context).matchedLocation;
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
      key: _scaffoldKey,
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
                            IconButton(
                              icon: const Icon(LucideIcons.menu),
                              onPressed: () {
                                _scaffoldKey.currentState?.openDrawer();
                              },
                            ),
                          if (!isDesktop) const SizedBox(width: 8),
                          // Search Bar
                          Expanded(
                            child: SizedBox(
                              height: 40,
                              child: TextField(
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
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.go('/chat');
        },
        backgroundColor: const Color(0xFF2563EB),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(LucideIcons.messageSquare, color: Colors.white),
      ),
    );
  }
}
