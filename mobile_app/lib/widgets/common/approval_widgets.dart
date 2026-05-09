import 'package:flutter/material.dart';

import '../../constants/approval_ui.dart';

class ApprovalCardShell extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;

  const ApprovalCardShell({
    super.key,
    required this.padding,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            (isDark ? const Color(0xFF172033) : ApprovalUi.surface),
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        border: Border.all(
          color:
              borderColor ??
              (isDark ? const Color(0xFF334155) : ApprovalUi.border),
        ),
        boxShadow:
            boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.04),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
      ),
      child: child,
    );
  }
}

class ApprovalPanelBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  const ApprovalPanelBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            (isDark ? const Color(0xFF0F172A) : ApprovalUi.panel),
        borderRadius: borderRadius ?? BorderRadius.circular(18),
        border: Border.all(
          color:
              borderColor ??
              (isDark ? const Color(0xFF334155) : ApprovalUi.border),
        ),
      ),
      child: child,
    );
  }
}

class ApprovalIconTile extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final BorderRadius? borderRadius;

  const ApprovalIconTile({
    super.key,
    required this.icon,
    this.size = 46,
    this.iconSize = 20,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            (isDark
                ? ApprovalUi.accent.withValues(alpha: 0.16)
                : ApprovalUi.accentSoft),
        borderRadius: borderRadius ?? BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        color:
            foregroundColor ??
            (isDark ? const Color(0xFFA5B4FC) : ApprovalUi.accent),
        size: iconSize,
      ),
    );
  }
}

class ApprovalActionButton extends StatelessWidget {
  final String label;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  const ApprovalActionButton({
    super.key,
    required this.label,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: ApprovalUi.accent,
        borderRadius: borderRadius ?? BorderRadius.circular(14),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
