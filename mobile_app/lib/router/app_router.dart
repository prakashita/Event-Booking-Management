import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/approval_gate_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/events/events_screen.dart';
import '../screens/events/create_event_screen.dart';
import '../screens/events/event_details_screen.dart';
import '../screens/approvals/approvals_screen.dart';
import '../screens/requirements/requirements_screen.dart';
import '../screens/calendar/calendar_screen.dart';
import '../screens/calendar/calendar_updates_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/publications/publications_screen.dart';
import '../screens/iqac/iqac_screen.dart';
import '../screens/admin/admin_screen.dart';
import '../screens/admin/user_approvals_screen.dart';
import '../screens/reports/event_reports_screen.dart';
import '../screens/home_screen.dart';

class AppRouter {
  static GoRouter createRouter(AuthProvider authProvider) {
    return GoRouter(
      refreshListenable: authProvider,
      initialLocation: '/dashboard',
      redirect: (context, state) {
        final isAuth = authProvider.isAuthenticated;
        final isLoading = authProvider.isLoading;
        final approvalPending = authProvider.isApprovalPending;
        final approvalRejected = authProvider.isApprovalRejected;
        final goingToLogin = state.matchedLocation == '/login';
        final goingToApprovalGate = state.matchedLocation == '/approval-gate';

        if (isLoading) return null;
        if (!isAuth && !goingToLogin) return '/login';

        if (isAuth && (approvalPending || approvalRejected)) {
          if (!goingToApprovalGate) return '/approval-gate';
          return null;
        }

        if (isAuth && (goingToLogin || goingToApprovalGate))
          return '/dashboard';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(
          path: '/approval-gate',
          builder: (_, _) => const ApprovalGateScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) {
            return HomeScreen(child: child);
          },
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (_, _) => const DashboardScreen(),
            ),
            GoRoute(path: '/events', builder: (_, _) => const EventsScreen()),
            GoRoute(
              path: '/events/create',
              builder: (_, _) => const CreateEventScreen(),
            ),
            GoRoute(
              path: '/events/:id',
              builder: (_, state) =>
                  EventDetailsScreen(eventId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/approvals',
              builder: (_, _) => const ApprovalsScreen(),
            ),
            GoRoute(
              path: '/requirements',
              builder: (_, _) => const RequirementsScreen(),
            ),
            GoRoute(
              path: '/calendar',
              builder: (_, _) => const CalendarScreen(),
            ),
            GoRoute(
              path: '/calendar-updates',
              builder: (_, _) => const CalendarUpdatesScreen(),
            ),
            GoRoute(path: '/chat', builder: (_, _) => const ChatListScreen()),
            GoRoute(
              path: '/chat/:id',
              builder: (_, state) =>
                  ChatScreen(conversationId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/publications',
              builder: (_, _) => const PublicationsScreen(),
            ),
            GoRoute(path: '/iqac', builder: (_, _) => const IQACScreen()),
            GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
            GoRoute(
              path: '/user-approvals',
              builder: (_, _) => const UserApprovalsScreen(),
            ),
            GoRoute(
              path: '/reports',
              builder: (_, _) => const EventReportsScreen(),
            ),
          ],
        ),
      ],
    );
  }
}
