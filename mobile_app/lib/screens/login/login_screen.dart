import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

enum _LoginStatus { idle, loading, success, error }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onContinue});

  final ValueChanged<AppSession> onContinue;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final GoogleSignIn _googleSignIn;

  _LoginStatus _status = _LoginStatus.idle;
  String _message = '';
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    final effectiveServerClientId = kGoogleServerClientId.isNotEmpty
        ? kGoogleServerClientId
        : (kGoogleClientId.isNotEmpty ? kGoogleClientId : null);

    _googleSignIn = GoogleSignIn(
      scopes: const ['email', 'profile', 'openid'],
      // On Android/iOS, do not pass clientId. It can trigger OAuth mismatch.
      clientId: kIsWeb && kGoogleClientId.isNotEmpty ? kGoogleClientId : null,
      // If GOOGLE_SERVER_CLIENT_ID is missing, fall back to GOOGLE_CLIENT_ID.
      serverClientId: effectiveServerClientId,
    );
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned(
            left: -110,
            top: 50,
            child: OrbDecoration(
              size: 280,
              colors: [AppColors.orbOrange, AppColors.orbOrangeDark],
            ),
          ),
          const Positioned(
            right: -90,
            bottom: 30,
            child: OrbDecoration(
              size: 230,
              colors: [AppColors.orbBlue, AppColors.orbBlueDark],
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 24,
                    ),
                    child: wide
                        ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(child: _HeroCard()),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 420,
                          child: _LoginCard(
                            status: _status,
                            message: _message,
                            onSubmit: _handleLogin,
                          ),
                        ),
                      ],
                    )
                        : SingleChildScrollView(
                      child: Column(
                        children: [
                          _LoginCard(
                            status: _status,
                            message: _message,
                            onSubmit: _handleLogin,
                          ),
                          const SizedBox(height: 24),
                          const _HeroCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    setState(() {
      _status = _LoginStatus.loading;
      _message = 'Signing you in…';
    });

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() {
          _status = _LoginStatus.error;
          _message = 'Sign-in was cancelled.';
        });
        return;
      }

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception(
          'Google credential missing. '
              'Ensure GOOGLE_SERVER_CLIENT_ID is configured '
              '(or set GOOGLE_CLIENT_ID so fallback can be used).',
        );
      }

      final uri = Uri.parse('$kApiBaseUrl/api/v1/auth/google');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': idToken}),
      );

      dynamic data;
      if (response.body.isNotEmpty) {
        try {
          data = jsonDecode(response.body);
        } catch (_) {}
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = data is Map<String, dynamic>
            ? data['detail']?.toString()
            : null;
        throw Exception(detail ?? 'Login failed (${response.statusCode}).');
      }

      final payload =
      data is Map<String, dynamic> ? data : <String, dynamic>{};
      final user = asMap(payload['user']);
      final token = payload['access_token']?.toString();

      if (token == null || token.isEmpty) {
        throw Exception('Login failed — no access token returned.');
      }

      if (!mounted) return;
      setState(() {
        _status = _LoginStatus.success;
        _message = 'Welcome back!';
      });

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;
      widget.onContinue(
        AppSession(
          baseUrl: kApiBaseUrl,
          token: token,
          role: (user['role'] ?? 'faculty').toString(),
          name:
          (user['name'] ?? account.displayName ?? 'User').toString(),
          email: (user['email'] ?? account.email).toString(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _LoginStatus.error;
        _message = _formatLoginError(e);
      });
    }
  }

  String _formatLoginError(Object error) {
    if (error is PlatformException) {
      final details = '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
      if (error.code == 'sign_in_failed' && details.contains('apiexception: 10')) {
        return 'Google Sign-In is blocked by Android OAuth config (ApiException 10). '
            'In Google Cloud, verify Android OAuth uses package '
          'com.example.mobile_app and includes this app\'s SHA-1 from '
            '`./gradlew signingReport`.';
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }
}

// ─── Hero Card ────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  static const _stats = [
    ('128+', 'Active Events'),
    ('24k+', 'Attendees'),
    ('98%', 'On-time Reminders'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: AppGradients.hero,
        boxShadow: AppShadows.elevated,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: const Center(
              child: Icon(
                Icons.event_note_rounded,
                color: Color(0xCCFFFFFF),
                size: 80,
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'EVENT BOOKING MANAGEMENT',
            style: GoogleFonts.spaceGrotesk(
              letterSpacing: 2.4,
              color: const Color(0xCCFFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Run smarter events,\nfrom invites to attendance.',
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Organize every stage with a centralized workspace, automated reminders, and real-time visibility that keeps teams aligned.',
            style: TextStyle(
              color: Color(0xCCFFFFFF),
              height: 1.6,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _stats
                .map(
                  (s) => Container(
                width: 155,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x1FFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.$1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      s.$2,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Login Card ───────────────────────────────────────────────────────────────

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.status,
    required this.message,
    required this.onSubmit,
  });

  final _LoginStatus status;
  final String message;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final loading = status == _LoginStatus.loading;
    final msgColor = switch (status) {
      _LoginStatus.success => AppColors.success,
      _LoginStatus.error => AppColors.error,
      _LoginStatus.loading => AppColors.info,
      _LoginStatus.idle => AppColors.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 48,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'WELCOME BACK',
            style: TextStyle(
              letterSpacing: 2.4,
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Login to your account',
            style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.w700,
              fontSize: 40,
              color: AppColors.textPrimary,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sign in to manage, track, and refine every event experience.',
            style: TextStyle(
              color: AppColors.textSecondary,
              height: 1.55,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: _GoogleButton(loading: loading, onTap: loading ? null : onSubmit),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: message.isEmpty
                ? const SizedBox.shrink()
                : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: msgColor),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Use your institutional Google account to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: const Color(0x330A1A2F)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const _GoogleLogo(),
              const SizedBox(width: 10),
              Text(
                loading ? 'Signing in…' : 'Continue with Google',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF333333),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final segments = [
      (Colors.red, 0.0, 0.9),
      (Colors.yellow, 0.9, 1.7),
      (Colors.green, 1.7, 2.6),
      (Colors.blue, 2.6, 3.14 * 2),
    ];

    for (final seg in segments) {
      final paint = Paint()
        ..color = seg.$1
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.16
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.7),
        seg.$2,
        seg.$3 - seg.$2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
