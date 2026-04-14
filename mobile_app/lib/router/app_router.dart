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
import '../screens/reports/event_reports_screen.dart';
import '../screens/home_screen.dart';
import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../screens/settings/settings_screen.dart';

class AppRouter {
  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      refreshListenable: authProvider,
      initialLocation: '/dashboard',
      redirect: (context, state) {
        final isAuth = authProvider.isAuthenticated;
        final isLoading = authProvider.isLoading;
        final goingToLogin = state.matchedLocation == '/login';

        if (isLoading) return null;
        if (!isAuth && !goingToLogin) return '/login';
        if (isAuth && goingToLogin) return '/dashboard';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        ShellRoute(
          builder: (context, state, child) {
            return HomeScreen(child: child);
          },
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, __) => const DashboardScreen(),
            ),
            GoRoute(path: '/events', builder: (_, __) => const EventsScreen()),
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
            GoRoute(path: '/chat', builder: (_, __) => const ChatListScreen()),
            GoRoute(
              path: '/chat/:id',
              builder: (_, state) =>
                  ChatScreen(conversationId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/publications',
              builder: (_, __) => const PublicationsScreen(),
            ),
            GoRoute(path: '/iqac', builder: (_, __) => const IQACScreen()),
            GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
            GoRoute(
              path: '/reports',
              builder: (_, __) => const EventReportsScreen(),
            ),
            GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    );
  }
}

class _EventDetailPlaceholder extends StatelessWidget {
  final String id;
  const _EventDetailPlaceholder({required this.id});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Event $id')),
      body: Center(child: Text('Details for event $id')),
    );
  }
}
