import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../models/models.dart';
import '../../screens/auth/sign_out_screen.dart';
import '../../screens/settings/settings_screen.dart';

const Color _eventActionBlue = Color(0xFF1A73E8);

class ProfileDropdown extends StatefulWidget {
  final User user;
  const ProfileDropdown({super.key, required this.user});

  @override
  State<ProfileDropdown> createState() => _ProfileDropdownState();
}

class _ProfileDropdownState extends State<ProfileDropdown> {
  final OverlayPortalController _tooltipController = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.colorScheme.surface;
    final cardBorder = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final settingsBg = isDark
        ? const Color(0xFF1E293B)
        : Colors.grey.withValues(alpha: 0.1);
    final settingsFg = isDark ? const Color(0xFFCBD5E1) : Colors.grey[800]!;
    final dividerColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);
    final avatarBg = isDark
        ? const Color(0xFF1E3A5F)
        : theme.colorScheme.primary.withValues(alpha: 0.1);
    final avatarIcon = isDark
        ? const Color(0xFFDBEAFE)
        : theme.colorScheme.primary;
    final triggerBg = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE8F0FE);
    final triggerBorder = isDark
        ? const Color(0xFF334155)
        : _eventActionBlue.withValues(alpha: 0.14);
    final triggerIcon = isDark ? const Color(0xFFBFDBFE) : _eventActionBlue;

    return GestureDetector(
      onTap: _tooltipController.toggle,
      child: OverlayPortal(
        controller: _tooltipController,
        overlayChildBuilder: (BuildContext context) {
          return Stack(
            children: [
              GestureDetector(
                onTap: _tooltipController.hide,
                child: Container(color: Colors.transparent),
              ),
              Positioned(
                top: kToolbarHeight + 8,
                right: 16,
                child: Material(
                  elevation: isDark ? 0 : 8,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.35 : 0.08,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: avatarBg,
                          child: Icon(
                            LucideIcons.user,
                            size: 30,
                            color: avatarIcon,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.user.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Chip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.shieldCheck,
                                size: 14,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.user.role.name.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          backgroundColor: isDark
                              ? const Color(0xFF0F2E1A)
                              : Colors.green.withValues(alpha: 0.1),
                          labelStyle: const TextStyle(color: Colors.green),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: Colors.green.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Divider(height: 1, color: dividerColor),
                        const SizedBox(height: 16),
                        _buildInfoRow(
                          context,
                          LucideIcons.mail,
                          "Email Address",
                          widget.user.email,
                        ),
                        const SizedBox(height: 16),
                        Divider(height: 1, color: dividerColor),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            icon: const Icon(LucideIcons.settings, size: 16),
                            label: const Text('Settings'),
                            onPressed: () async {
                              _tooltipController.hide();
                              await showGeneralDialog<void>(
                                context: context,
                                barrierDismissible: true,
                                barrierLabel: 'Settings',
                                barrierColor: Colors.transparent,
                                transitionDuration: const Duration(
                                  milliseconds: 180,
                                ),
                                pageBuilder: (context, animation, secondary) =>
                                    const SettingsScreen(),
                                transitionBuilder:
                                    (
                                      context,
                                      animation,
                                      secondaryAnimation,
                                      child,
                                    ) {
                                      final curve = CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      );
                                      return FadeTransition(
                                        opacity: curve,
                                        child: ScaleTransition(
                                          scale: Tween<double>(
                                            begin: 0.98,
                                            end: 1.0,
                                          ).animate(curve),
                                          child: child,
                                        ),
                                      );
                                    },
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: settingsFg,
                              backgroundColor: settingsBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Divider(height: 1, color: dividerColor),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            icon: const Icon(LucideIcons.logOut, size: 16),
                            label: const Text('Log Out'),
                            onPressed: () {
                              _tooltipController.hide();
                              showSignOutDialog(context);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              backgroundColor: isDark
                                  ? const Color(0xFF3F1D1D)
                                  : Colors.red.withValues(alpha: 0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: SizedBox(
          width: 48,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: triggerBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: triggerBorder),
                  ),
                  child: Icon(LucideIcons.user, color: triggerIcon, size: 19),
                ),
              ),
              Positioned(
                right: 0,
                bottom: -1,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _eventActionBlue,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cardColor, width: 2),
                  ),
                  child: const Icon(
                    LucideIcons.chevronDown,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedText = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Row(
      children: [
        Icon(icon, size: 16, color: mutedText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mutedText,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
