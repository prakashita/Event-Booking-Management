import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_app/providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _close(BuildContext context) {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final modalSurface = theme.colorScheme.surface;
    final modalLayer = theme.colorScheme.surface;
    final panel = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerLowest;
    final border = isDark
        ? theme.colorScheme.outline
        : theme.colorScheme.outlineVariant;
    final heading = theme.colorScheme.onSurface;
    final subheading = isDark
        ? theme.colorScheme.onSurface.withValues(alpha: 0.7)
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final iconTile = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainer;
    final closeIcon = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final closeHover = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainer;

    return Scaffold(
      backgroundColor: Colors
          .transparent, // Making background transparent for modal look if navigated via showDialog
      // Or if solid background:
      // backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.4), // bg-slate-900/40
      body: Stack(
        children: [
          // Background Backdrop (Simulated)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _close(context),
              child: Container(
                color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.28),
              ),
            ),
          ),
          // Centered Content Modal
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 24.0,
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 448), // max-w-md
                  decoration: BoxDecoration(
                    color: modalSurface,
                    borderRadius: BorderRadius.circular(40), // rounded-[2.5rem]
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.1),
                        blurRadius: 30,
                        offset: const Offset(0, 20),
                      ),
                    ],
                    border: Border.all(color: border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Settings Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 24,
                        ),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: border)),
                          color: modalLayer,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(40),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: iconTile,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      LucideIcons.settings,
                                      size: 20,
                                      color: closeIcon,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Preferences',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: heading,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => _close(context),
                                hoverColor: closeHover,
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Icon(
                                    LucideIcons.x,
                                    size: 20,
                                    color: closeIcon,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Settings Body
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: panel.withValues(alpha: 0.9),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(40),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(left: 4.0, bottom: 16.0),
                              child: Text(
                                'APPEARANCE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: subheading,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                _buildThemeOption(
                                  currentThemeMode:
                                      themeProvider.themeModeValue,
                                  id: 'light',
                                  title: 'Light',
                                  subtitle: 'Clean, bright interface',
                                  icon: LucideIcons.sun,
                                  activeColor: const Color(
                                    0xFF3B82F6,
                                  ), // blue-500
                                  activeBgColor: const Color(
                                    0xFFEFF6FF,
                                  ), // blue-50
                                  iconActiveBg: const Color(
                                    0xFFDBEAFE,
                                  ), // blue-100
                                  iconActiveColor: const Color(
                                    0xFF2563EB,
                                  ), // blue-600
                                  titleActiveColor: const Color(
                                    0xFF1E40AF,
                                  ), // blue-800
                                ),
                                const SizedBox(height: 12),
                                _buildThemeOption(
                                  currentThemeMode:
                                      themeProvider.themeModeValue,
                                  id: 'dark',
                                  title: 'Dark',
                                  subtitle: 'Easy on the eyes',
                                  icon: LucideIcons.moon,
                                  activeColor: const Color(
                                    0xFF6366F1,
                                  ), // indigo-500
                                  activeBgColor: const Color(
                                    0xFFEEF2FF,
                                  ), // indigo-50
                                  iconActiveBg: const Color(
                                    0xFFE0E7FF,
                                  ), // indigo-100
                                  iconActiveColor: const Color(
                                    0xFF4F46E5,
                                  ), // indigo-600
                                  titleActiveColor: const Color(
                                    0xFF3730A3,
                                  ), // indigo-800
                                ),
                                const SizedBox(height: 12),
                                _buildThemeOption(
                                  currentThemeMode:
                                      themeProvider.themeModeValue,
                                  id: 'system',
                                  title: 'System',
                                  subtitle: 'Match your OS setting',
                                  icon: LucideIcons.monitor,
                                  activeColor: const Color(
                                    0xFF1E293B,
                                  ), // slate-800
                                  activeBgColor: const Color(
                                    0xFFF1F5F9,
                                  ), // slate-100
                                  iconActiveBg: const Color(
                                    0xFFCBD5E1,
                                  ), // slate-300
                                  iconActiveColor: const Color(
                                    0xFF1E293B,
                                  ), // slate-800
                                  titleActiveColor: const Color(
                                    0xFF0F172A,
                                  ), // slate-900
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required String currentThemeMode,
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    required Color activeBgColor,
    required Color iconActiveBg,
    required Color iconActiveColor,
    required Color titleActiveColor,
  }) {
    final bool isActive = currentThemeMode == id;
    final themeProvider = context.read<ThemeProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inactiveBg = theme.colorScheme.surface;
    final inactiveBorder = isDark
        ? theme.colorScheme.outline
        : theme.colorScheme.outlineVariant;
    final inactiveTitle = theme.colorScheme.onSurface;
    final inactiveSubtitle = theme.colorScheme.onSurface.withValues(alpha: 0.62);
    final inactiveIconBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainer;
    final inactiveIcon = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return GestureDetector(
      onTap: () async {
        await themeProvider.setThemeModeByValue(id);
        if (!mounted) return;
        _close(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? activeBgColor : inactiveBg,
          borderRadius: BorderRadius.circular(16), // rounded-2xl
          border: Border.all(
            color: isActive ? activeColor : inactiveBorder,
            width: 2,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.1),
                    blurRadius: 0,
                    spreadRadius: 4,
                  ),
                ] // ring-4
              : [], // No shadow by default to simulate basic inactive state
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isActive ? iconActiveBg : inactiveIconBg,
                    borderRadius: BorderRadius.circular(12), // rounded-xl
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 24,
                      color: isActive ? iconActiveColor : inactiveIcon,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isActive ? titleActiveColor : inactiveTitle,
                      ),
                      child: Text(title),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: inactiveSubtitle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: isActive ? 1.0 : 0.0,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 300),
                scale: isActive ? 1.0 : 0.5,
                child: Icon(
                  LucideIcons.checkCircle2,
                  size: 24,
                  color: activeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
