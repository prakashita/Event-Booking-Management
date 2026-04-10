import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../admin/admin_screen.dart';
import '../approvals/approvals_screen.dart';
import '../calendar/calendar_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../events/events_screen.dart';
import '../iqac/iqac_screen.dart';
import '../publications/publications_screen.dart';
import '../reports/reports_screen.dart';
import '../requirements/requirements_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.session, required this.onLogout});

  final AppSession session;
  final VoidCallback onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final ApiClient _api;

  static const _navItems = [
    (label: 'Dashboard', icon: Icons.dashboard_rounded),
    (label: 'My Events', icon: Icons.event_rounded),
    (label: 'Event Reports', icon: Icons.receipt_long_rounded),
    (label: 'Calendar View', icon: Icons.calendar_month_rounded),
    (label: 'Approvals', icon: Icons.approval_rounded),
    (label: 'Requirements', icon: Icons.assignment_rounded),
    (label: 'Publications', icon: Icons.menu_book_rounded),
    (label: 'IQAC Data', icon: Icons.folder_copy_rounded),
    (label: 'Admin Console', icon: Icons.admin_panel_settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _api = ApiClient(widget.session);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;

    final screens = [
      DashboardScreen(api: _api, session: widget.session),
      EventsScreen(api: _api),
      ReportsScreen(api: _api),
      CalendarScreen(api: _api),
      ApprovalsScreen(api: _api),
      RequirementsScreen(api: _api),
      PublicationsScreen(api: _api),
      IqacScreen(api: _api),
      AdminScreen(api: _api, session: widget.session),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: wide
          ? null
          : AppBar(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_navItems[_index].label),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {},
          ),
        ],
      ),
      drawer: wide
          ? null
          : _Sidebar(
        items: _navItems,
        selectedIndex: _index,
        session: widget.session,
        onSelect: (i) {
          setState(() => _index = i);
          Navigator.maybePop(context);
        },
        onLogout: widget.onLogout,
      ),
      body: Row(
        children: [
          if (wide)
            _Sidebar(
              items: _navItems,
              selectedIndex: _index,
              session: widget.session,
              onSelect: (i) => setState(() => _index = i),
              onLogout: widget.onLogout,
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: screens,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.session,
    required this.onSelect,
    required this.onLogout,
  });

  final List<({String label, IconData icon})> items;
  final int selectedIndex;
  final AppSession session;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 262,
      color: AppColors.sidebarBg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo / brand
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.event_note_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'EventFlow',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // User info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0x14FFFFFF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primary.withAlpha(80),
                      child: Text(
                        session.name.isNotEmpty
                            ? session.name[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            session.displayRole,
                            style: const TextStyle(
                              color: AppColors.sidebarTextMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(left: 10, bottom: 8),
                child: Text(
                  'NAVIGATION',
                  style: TextStyle(
                    color: AppColors.sidebarTextMuted,
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final active = selectedIndex == i;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _SidebarItem(
                        icon: items[i].icon,
                        label: items[i].label,
                        active: active,
                        onTap: () => onSelect(i),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Color(0x22FFFFFF), height: 1),
              const SizedBox(height: 10),
              _SidebarItem(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                active: false,
                onTap: onLogout,
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? AppColors.sidebarItemActive : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: danger
                    ? const Color(0xFFFF8080)
                    : active
                    ? Colors.white
                    : AppColors.sidebarTextMuted,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: danger
                      ? const Color(0xFFFF8080)
                      : active
                      ? Colors.white
                      : AppColors.sidebarTextMuted,
                  fontWeight:
                  active ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              if (active) ...[
                const Spacer(),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
