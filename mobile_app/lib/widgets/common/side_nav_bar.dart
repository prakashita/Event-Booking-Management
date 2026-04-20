import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../constants/app_constants.dart';

class SideNavBar extends StatelessWidget {
  final String currentRoute;

  const SideNavBar({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final roleKey = user?.roleKey ?? 'faculty';
    final roleLabel = user?.roleLabel ?? 'FACULTY';

    final isAdmin = roleKey == 'admin';
    final isRegistrar = roleKey == 'registrar';
    final isViceChancellor = roleKey == 'vice_chancellor';
    final isDeputyRegistrar = roleKey == 'deputy_registrar';
    final isFinanceTeam = roleKey == 'finance_team';
    final isRegistrarDashboard =
        isRegistrar || isViceChancellor || isDeputyRegistrar || isFinanceTeam;
    final isFacilityManager = roleKey == 'facility_manager';
    final isMarketing = roleKey == 'marketing';
    final isIt = roleKey == 'it';
    final isTransport = roleKey == 'transport';

    final canAccessApprovals = isRegistrarDashboard;
    final canAccessRequirements =
        isFacilityManager || isMarketing || isIt || isTransport;
    final canAccessEventReports = isAdmin || isRegistrarDashboard;
    final canAccessCalendarUpdates = isAdmin || isRegistrarDashboard;
    final canAccessAdminConsole = isAdmin;
    final canAccessIqac = AppConstants.iqacAllowedRoles.contains(roleKey);

    return Container(
      width: 256,
      color: const Color(0xFF1B254B),
      child: Column(
        children: [
          // Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(
                        LucideIcons.shieldCheck,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    roleLabel,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Menu Items
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MENU',
                      style: TextStyle(
                        color: Color(0xFF718096),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildNavItem(
                      context,
                      icon: LucideIcons.layoutDashboard,
                      title: 'Dashboard',
                      route: '/dashboard',
                    ),
                    _buildNavItem(
                      context,
                      icon: LucideIcons.calendar,
                      title: 'My Events',
                      route: '/events',
                    ),
                    if (canAccessEventReports)
                      _buildNavItem(
                        context,
                        icon: LucideIcons.barChart3,
                        title: 'Event Reports',
                        route: '/reports',
                      ),
                    _buildNavItem(
                      context,
                      icon: LucideIcons.calendarCheck,
                      title: 'Calendar View',
                      route: '/calendar',
                    ),
                    if (canAccessCalendarUpdates)
                      _buildNavItem(
                        context,
                        icon: LucideIcons.calendarDays,
                        title: 'Calendar Updates',
                        route: '/calendar-updates',
                      ),
                    if (canAccessApprovals)
                      _buildNavItem(
                        context,
                        icon: LucideIcons.shieldCheck,
                        title: 'Approvals',
                        route: '/approvals',
                      ),
                    if (canAccessRequirements)
                      _buildNavItem(
                        context,
                        icon: LucideIcons.clipboardCheck,
                        title: 'Requirements',
                        route: '/requirements',
                      ),
                    _buildNavItem(
                      context,
                      icon: LucideIcons.bookOpen,
                      title: 'Publications',
                      route: '/publications',
                    ),
                    if (canAccessIqac)
                      _buildNavItem(
                        context,
                        icon: LucideIcons.database,
                        title: 'IQAC Data Collection',
                        route: '/iqac',
                      ),
                    if (canAccessAdminConsole) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'ADMINISTRATION',
                        style: TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildNavItem(
                        context,
                        icon: LucideIcons.users,
                        title: 'User Approvals',
                        route: '/user-approvals',
                      ),
                      _buildNavItem(
                        context,
                        icon: LucideIcons.userCog,
                        title: 'Admin Console',
                        route: '/admin',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Footer (Logout)
          const Divider(color: Color(0xFF2D3748)),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildLogoutItem(context),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
  }) {
    final bool isSelected =
        currentRoute == route || currentRoute.startsWith('$route/');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.go(route);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.blue.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border(
                    left: BorderSide(color: Colors.blue.shade400, width: 4),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? Colors.blue.shade300
                    : const Color(0xFFA0AEC0),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFFA0AEC0),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutItem(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Provider.of<AuthProvider>(context, listen: false).signOut();
          context.go('/login');
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: const Row(
            children: [
              Icon(LucideIcons.logOut, size: 20, color: Color(0xFFA0AEC0)),
              SizedBox(width: 16),
              Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFA0AEC0),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
