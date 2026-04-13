import 'package:flutter/material.dart';
import '../models/models.dart';

class AppColors {
  // Primary palette — deep institutional navy blue
  static const Color primary = Color(0xFF1565C0);
  static const Color primaryLight = Color(0xFF1976D2);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color primaryContainer = Color(0xFFE3F2FD);
  static const Color onPrimary = Colors.white;
  static const Color onPrimaryContainer = Color(0xFF1565C0);

  // Secondary — gold accent
  static const Color secondary = Color(0xFFFFD54F);
  static const Color secondaryContainer = Color(0xFFFFF8E1);
  static const Color onSecondary = Color(0xFF1A1A2E);

  // Background
  static const Color background = Color(0xFFF5F6FA);
  static const Color surface = Colors.white;
  static const Color surfaceVariant = Color(0xFFF0F4F8);

  // Text
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF546E7A);
  static const Color textMuted = Color(0xFF90A4AE);

  // Status colors
  static const Color success = Color(0xFF2E7D32);
  static const Color successLight = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF57F17);
  static const Color warningLight = Color(0xFFFFF8E1);
  static const Color error = Color(0xFFD32F2F);
  static const Color errorLight = Color(0xFFFFEBEE);
  static const Color info = Color(0xFF0277BD);
  static const Color infoLight = Color(0xFFE1F5FE);

  // Border
  static const Color border = Color(0xFFDEE2E6);
  static const Color divider = Color(0xFFECEFF1);

  // Chat
  static const Color chatBubbleMine = Color(0xFF1565C0);
  static const Color chatBubbleOther = Colors.white;

  // Overlay
  static const Color overlay = Color(0x80000000);

  // Role-based colors
  static Color roleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return const Color(0xFF6A1B9A);
      case UserRole.iqac:
        return const Color(0xFF283593);
      case UserRole.faculty:
        return primary;
      default:
        return textSecondary;
    }
  }

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return primary;
      case 'ongoing':
        return success;
      case 'completed':
        return warning;
      case 'closed':
        return textSecondary;
      case 'approved':
        return success;
      case 'rejected':
        return error;
      case 'pending':
        return warning;
      case 'accepted':
        return success;
      default:
        return textSecondary;
    }
  }

  static Color statusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'upcoming':
        return primaryContainer;
      case 'ongoing':
        return successLight;
      case 'completed':
        return warningLight;
      case 'closed':
        return surfaceVariant;
      case 'approved':
        return successLight;
      case 'rejected':
        return errorLight;
      case 'pending':
        return warningLight;
      case 'accepted':
        return successLight;
      default:
        return surfaceVariant;
    }
  }
}
