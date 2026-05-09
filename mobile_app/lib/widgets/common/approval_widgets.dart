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
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? ApprovalUi.surface,
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        border: Border.all(color: borderColor ?? ApprovalUi.border),
        boxShadow:
            boxShadow ??
            const [
              BoxShadow(
                color: Color(0x0A0F172A),
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
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? ApprovalUi.panel,
        borderRadius: borderRadius ?? BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? ApprovalUi.border),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? ApprovalUi.accentSoft,
        borderRadius: borderRadius ?? BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        color: foregroundColor ?? ApprovalUi.accent,
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
