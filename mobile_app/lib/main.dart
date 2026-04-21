import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'constants/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/theme_provider.dart';
import 'router/app_router.dart';
import 'services/api_service.dart';

// Configure API base URL here
// For development: use your FastAPI server URL
// For production: use your deployed server URL
const String _apiBaseOverride = String.fromEnvironment('API_BASE_URL');

String get kApiBaseUrl {
  if (_apiBaseOverride.trim().isNotEmpty) {
    return _apiBaseOverride.trim();
  }

  // Android emulator cannot reach host loopback via localhost.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }

  return 'http://localhost:8000';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider()..init(kApiBaseUrl),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ProxyProvider<AuthProvider, NotificationProvider>(
          create: (_) => NotificationProvider(
            AuthProvider(),
            ApiService(),
          ),
          update: (_, authProvider, notificationProvider) =>
              notificationProvider ?? NotificationProvider(authProvider, ApiService()),
        ),
      ],
      child: const EventBookingApp(),
    ),
  );
}

class EventBookingApp extends StatefulWidget {
  const EventBookingApp({super.key});

  @override
  State<EventBookingApp> createState() => _EventBookingAppState();
}

class _EventBookingAppState extends State<EventBookingApp> {
  GoRouter? _router;

  double _responsiveTextScale(double width) {
    if (width <= 320) return 0.84;
    if (width <= 360) return 0.9;
    if (width <= 390) return 0.96;
    return 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _router ??= AppRouter.createRouter(context.read<AuthProvider>());
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp.router(
      title: 'Event Booking Management',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      routerConfig: _router!,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = _responsiveTextScale(media.size.width);
        final brightness = Theme.of(context).brightness;
        final isDark = brightness == Brightness.dark;
        final overlayStyle = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: Container(
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0F172A), Color(0xFF162032), Color(0xFF1E293B)],
                      )
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFF8FAFC), Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                      ),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
