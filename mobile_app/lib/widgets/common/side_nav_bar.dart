import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../screens/auth/sign_out_screen.dart';

class SideNavBar extends StatelessWidget {
  final String currentRoute;

  const SideNavBar({super.key, required this.currentRoute});

  String _headerRoleLabel(String roleKey, String fallbackRoleLabel) {
    switch ((roleKey).trim().toLowerCase()) {
      case 'deputy_registrar':
        return 'DEPUTY\nREGISTRAR';
      case 'vice_chancellor':
        return 'VICE\nCHANCELLOR';
      case 'facility_manager':
        return 'FACILITY\nMANAGER';
      case 'finance_team':
        return 'FINANCE\nTEAM';
      default:
        return fallbackRoleLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final roleKey = AppConstants.normalizeRole(user?.roleKey ?? 'faculty');
    final roleLabel = user?.roleLabel ?? 'FACULTY';
    final headerRoleLabel = _headerRoleLabel(roleKey, roleLabel);

    final canAccessApprovals = AppConstants.canAccessApprovals(roleKey);
    final canAccessRequirements = AppConstants.canAccessRequirements(roleKey);
    final canAccessEventReports = AppConstants.canAccessEventReports(roleKey);
    final canAccessCalendarUpdates = AppConstants.canAccessCalendarUpdates(
      roleKey,
    );
    final canAccessAdminConsole = AppConstants.canAccessAdminConsole(roleKey);
    final canAccessUserApprovals = AppConstants.canAccessUserApprovals(roleKey);
    final canAccessIqac = AppConstants.canAccessIqac(roleKey);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBg = isDark ? const Color(0xFF111827) : theme.colorScheme.surface;
    final dividerColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final sectionTextColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final headerTextColor = isDark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF0F172A);

    return Container(
      width: 288,
      color: navBg,
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
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Icon(
                        LucideIcons.shieldCheck,
                        color: theme.colorScheme.onPrimary,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      headerRoleLabel,
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: headerTextColor,
                        fontSize: 15,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
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
                    _buildSectionLabel('MENU', color: sectionTextColor),
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
                    _buildNavItem(
                      context,
                      icon: LucideIcons.star,
                      title: 'Other Achievements',
                      route: '/student-achievements',
                    ),
                    if (canAccessIqac)
                      _buildNavItem(
                        context,
                        icon: LucideIcons.database,
                        title: 'IQAC Data Collection',
                        route: '/iqac',
                      ),
                    if (canAccessUserApprovals || canAccessAdminConsole) ...[
                      const SizedBox(height: 24),
                      _buildSectionLabel(
                        'ADMINISTRATION',
                        color: sectionTextColor,
                      ),
                      const SizedBox(height: 12),
                      if (canAccessUserApprovals)
                        _buildNavItem(
                          context,
                          icon: LucideIcons.users,
                          title: 'User Approvals',
                          route: '/user-approvals',
                        ),
                      if (canAccessAdminConsole)
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
          Divider(color: dividerColor),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildLogoutItem(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text, {required Color color}) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
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
        currentRoute == route ||
        (route != '/dashboard' && currentRoute.startsWith('$route/'));
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = isDark
        ? theme.colorScheme.primary.withValues(alpha: 0.18)
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.72);
    final selectedColor = isDark
        ? const Color(0xFFBFDBFE)
        : theme.colorScheme.primary;
    final itemColor = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);
    final hoverColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : theme.colorScheme.primary.withValues(alpha: 0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.go(route);
        },
        borderRadius: BorderRadius.circular(8),
        hoverColor: hoverColor,
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        child: Container(
          padding: EdgeInsetsDirectional.fromSTEB(
            isSelected ? 12 : 16,
            12,
            12,
            12,
          ),
          decoration: BoxDecoration(
            color: isSelected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 4,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? selectedColor : itemColor,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    color: isSelected ? selectedColor : itemColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutItem(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final itemColor = isDark
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF475569);
    final hoverColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : theme.colorScheme.error.withValues(alpha: 0.06);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          showSignOutDialog(context);
        },
        borderRadius: BorderRadius.circular(8),
        hoverColor: hoverColor,
        splashColor: theme.colorScheme.error.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.logOut, size: 20, color: itemColor),
              const SizedBox(width: 16),
              Text(
                'Sign out',
                style: TextStyle(
                  color: itemColor,
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
