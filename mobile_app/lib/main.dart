import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/session.dart';
import 'screens/login/login_screen.dart';
import 'screens/shell/main_shell.dart';

void main() {
  runApp(const EventBookingApp());
}

class EventBookingApp extends StatefulWidget {
  const EventBookingApp({super.key});

  @override
  State<EventBookingApp> createState() => _EventBookingAppState();
}

class _EventBookingAppState extends State<EventBookingApp> {
  AppSession? _session;

  void _onLogin(AppSession session) => setState(() => _session = session);
  void _onLogout() => setState(() => _session = null);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Event Booking Management',
      theme: _buildTheme(),
      home: _session == null
          ? LoginScreen(onContinue: _onLogin)
          : MainShell(session: _session!, onLogout: _onLogout),
    );
  }

  ThemeData _buildTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF007BFF),
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: const Color(0xFFF0F4F7),
      textTheme: GoogleFonts.spaceGroteskTextTheme(ThemeData.light().textTheme),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 10),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}
