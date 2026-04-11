import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/events/events_screen.dart';
import '../screens/events/create_event_screen.dart';
import '../screens/approvals/approvals_screen.dart';
import '../screens/requirements/requirements_screen.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/publications/publications_screen.dart';
import '../screens/iqac/iqac_screen.dart';
import '../screens/admin/admin_screen.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';

class AppRouter {
  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      refreshListenable: authProvider,
      redirect: (context, state) {
        final isAuth = authProvider.isAuthenticated;
        final isLoading = authProvider.isLoading;
        final goingToLogin = state.matchedLocation == '/login';

        if (isLoading) return null;
        if (!isAuth && !goingToLogin) return '/login';
        if (isAuth && goingToLogin) return '/';
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) {
            return _AppShell(child: child);
          },
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/events',
              builder: (_, __) => const EventsScreen(),
            ),
            GoRoute(
              path: '/events/create',
              builder: (_, __) => const CreateEventScreen(),
            ),
            GoRoute(
              path: '/events/:id',
              builder: (_, state) =>
                  _EventDetailPlaceholder(id: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/approvals',
              builder: (_, __) => const ApprovalsScreen(),
            ),
            GoRoute(
              path: '/requirements',
              builder: (_, __) => const RequirementsScreen(),
            ),
            GoRoute(
              path: '/calendar',
              builder: (_, __) => const CalendarScreen(),
            ),
            GoRoute(
              path: '/chat',
              builder: (_, __) => const ChatListScreen(),
            ),
            GoRoute(
              path: '/chat/:id',
              builder: (_, state) =>
                  ChatScreen(conversationId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/publications',
              builder: (_, __) => const PublicationsScreen(),
            ),
            GoRoute(
              path: '/iqac',
              builder: (_, __) => const IQACScreen(),
            ),
            GoRoute(
              path: '/admin',
              builder: (_, __) => const AdminScreen(),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.user?.role ?? 'faculty';
    final location = GoRouterState.of(context).matchedLocation;

    // Don't show nav bar on sub-screens
    final hideNavBar = location.startsWith('/events/') ||
        location.startsWith('/chat/') ||
        location == '/events/create';

    if (hideNavBar) return child;

    final navItems = _getNavItems(role);
    final currentIndex = _getCurrentIndex(location, navItems);

    return Scaffold(
      body: child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: AppColors.surface,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: TextButton.icon(
              onPressed: () {
                context.read<AuthProvider>().signOut();
              },
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Logout'),
            ),
          ),
          NavigationBar(
            selectedIndex: currentIndex < 0 ? 0 : currentIndex,
            onDestinationSelected: (i) {
              context.go(navItems[i]['route'] as String);
            },
            destinations: navItems.map((item) {
              return NavigationDestination(
                icon: Icon(item['icon'] as IconData),
                selectedIcon: Icon(item['selectedIcon'] as IconData),
                label: item['label'] as String,
              );
            }).toList(),
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.primaryContainer,
            height: 70,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getNavItems(String role) {
    final items = <Map<String, dynamic>>[
      {
        'route': '/',
        'label': 'Home',
        'icon': Icons.home_outlined,
        'selectedIcon': Icons.home,
        'roles': null,
      },
      {
        'route': '/events',
        'label': 'Events',
        'icon': Icons.event_outlined,
        'selectedIcon': Icons.event,
        'roles': null,
      },
      {
        'route': '/approvals',
        'label': 'Approvals',
        'icon': Icons.approval_outlined,
        'selectedIcon': Icons.approval,
        'roles': AppConstants.adminRoles,
      },
      {
        'route': '/requirements',
        'label': 'Requirements',
        'icon': Icons.assignment_outlined,
        'selectedIcon': Icons.assignment,
        'roles': ['facility_manager', 'marketing', 'it', 'faculty', 'registrar', 'admin'],
      },
      {
        'route': '/calendar',
        'label': 'Calendar',
        'icon': Icons.calendar_month_outlined,
        'selectedIcon': Icons.calendar_month,
        'roles': null,
      },
      {
        'route': '/chat',
        'label': 'Chat',
        'icon': Icons.chat_bubble_outline,
        'selectedIcon': Icons.chat_bubble,
        'roles': null,
      },
      {
        'route': '/publications',
        'label': 'Publications',
        'icon': Icons.menu_book_outlined,
        'selectedIcon': Icons.menu_book,
        'roles': null,
      },
      {
        'route': '/iqac',
        'label': 'IQAC',
        'icon': Icons.folder_outlined,
        'selectedIcon': Icons.folder,
        'roles': AppConstants.iqacAllowedRoles,
      },
      {
        'route': '/admin',
        'label': 'Admin',
        'icon': Icons.admin_panel_settings_outlined,
        'selectedIcon': Icons.admin_panel_settings,
        'roles': AppConstants.adminRoles,
      },
    ];

    return items.where((item) {
      final roles = item['roles'] as List<String>?;
      if (roles == null) return true;
      return roles.contains(role);
    }).take(5).toList(); // Max 5 nav items
  }

  int _getCurrentIndex(String location, List<Map<String, dynamic>> items) {
    for (int i = 0; i < items.length; i++) {
      final route = items[i]['route'] as String;
      if (route == '/' ? location == '/' : location.startsWith(route)) {
        return i;
      }
    }
    return 0;
  }
}

// Placeholder for event detail screen
class _EventDetailPlaceholder extends StatelessWidget {
  final String id;
  const _EventDetailPlaceholder({required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Event Details')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event, size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Event ID: $id'),
          ],
        ),
      ),
    );
  }
}
