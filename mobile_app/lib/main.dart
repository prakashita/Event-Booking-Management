import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'constants/app_theme.dart';
import 'providers/auth_provider.dart';
import 'router/app_router.dart';

// Configure API base URL here
// For development: use your FastAPI server URL
// For production: use your deployed server URL
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8000',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider()..init(kApiBaseUrl),
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
  late final _router = AppRouter.createRouter(
    context.read<AuthProvider>(),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Event Booking Management',
      theme: AppTheme.lightTheme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Global error boundary
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
