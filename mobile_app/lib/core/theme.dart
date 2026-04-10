import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF007BFF);
  static const primaryDark = Color(0xFF0056B3);
  static const navyDark = Color(0xFF1A2B5B);
  static const navyMid = Color(0xFF21509D);
  static const background = Color(0xFFF0F4F7);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF111217);
  static const textSecondary = Color(0xFF666666);
  static const success = Color(0xFF1B6B3D);
  static const error = Color(0xFFA9382A);
  static const warning = Color(0xFFAD7A00);
  static const info = Color(0xFF21509D);
  static const amber = Color(0xFFFFC107);
  static const divider = Color(0xFFE2E8F0);
  static const sidebarBg = Color(0xFF1A2B5B);
  static const sidebarItemActive = Color(0x26FFFFFF);
  static const sidebarText = Colors.white;
  static const sidebarTextMuted = Color(0xAAFFFFFF);
  static const cardShadow = Color(0x13000000);
  static const orbOrange = Color(0xFFFFD7B3);
  static const orbOrangeDark = Color(0xFFC98A2F);
  static const orbBlue = Color(0x33007BFF);
  static const orbBlueDark = Color(0x220056B3);
}

abstract final class AppGradients {
  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.navyDark, AppColors.primaryDark],
  );
  static const primaryButton = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDark],
  );
}

abstract final class AppRadius {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(12);
  static const lg = Radius.circular(16);
  static const xl = Radius.circular(20);
  static const xxl = Radius.circular(28);
}

abstract final class AppShadows {
  static const card = [
    BoxShadow(
      color: AppColors.cardShadow,
      blurRadius: 20,
      offset: Offset(0, 10),
    ),
  ];
  static const elevated = [
    BoxShadow(
      color: Color(0x2A000000),
      blurRadius: 46,
      offset: Offset(0, 18),
    ),
  ];
}
