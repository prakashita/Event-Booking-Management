import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';

class ApprovalGateScreen extends StatefulWidget {
  const ApprovalGateScreen({super.key});

  @override
  State<ApprovalGateScreen> createState() => _ApprovalGateScreenState();
}

class _ApprovalGateScreenState extends State<ApprovalGateScreen> {
  bool _checking = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.isApprovalPending) {
        _checkStatus(auth);
      }
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || _checking) return;
      final auth = context.read<AuthProvider>();
      if (!auth.isApprovalPending) return;
      _checkStatus(auth);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus(AuthProvider auth) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await auth.refreshApprovalStatus(silent: true);
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shellBg = isDark ? theme.scaffoldBackgroundColor : AppColors.primary;

    return Scaffold(
      backgroundColor: shellBg,
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            final isRejected = auth.isApprovalRejected;
            final title = isRejected ? 'Access Denied' : 'Approval Pending';
            final subtitle = isRejected
                ? 'Your account access request has been declined by an administrator.'
                : 'Your account is awaiting administrator approval. You will be able to access the application once an admin reviews and approves your account.';
            final icon = isRejected
                ? Icons.close_rounded
                : Icons.schedule_rounded;
            final iconColor = isRejected
                ? const Color(0xFFFF5A73)
                : const Color(0xFFFFD400);

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: iconColor.withValues(alpha: 0.16),
                            ),
                            child: Icon(icon, color: iconColor, size: 44),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.8,
                            ),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (isRejected &&
                            auth.user?.rejectionReason != null &&
                            auth.user!.rejectionReason!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Reason: ${auth.user!.rejectionReason!.trim()}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Text(
                          'If you believe this is an error, please contact your system administrator.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Signed in as ${auth.user?.email ?? '-'}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (auth.error != null && auth.error!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              auth.error!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 22),
                        _ApprovalGateActions(
                          isRejected: isRejected,
                          isChecking: _checking,
                          onSignOut: () => auth.signOut(),
                          onCheckStatus: () async {
                            if (_checking) return;
                            setState(() => _checking = true);
                            try {
                              await auth.refreshApprovalStatus();
                            } finally {
                              if (mounted) {
                                setState(() => _checking = false);
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ApprovalGateActions extends StatelessWidget {
  final bool isRejected;
  final bool isChecking;
  final VoidCallback onSignOut;
  final Future<void> Function() onCheckStatus;

  const _ApprovalGateActions({
    required this.isRejected,
    required this.isChecking,
    required this.onSignOut,
    required this.onCheckStatus,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shouldStack = constraints.maxWidth < 320;
        final signOut = _fixedHeightButton(
          OutlinedButton(
            onPressed: onSignOut,
            child: const Text(
              'Sign out',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
        final checkStatus = _fixedHeightButton(
          ElevatedButton(
            onPressed: isChecking ? null : onCheckStatus,
            child: isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text(
                    'Check status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        );

        if (isRejected) {
          return signOut;
        }

        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [checkStatus, const SizedBox(height: 12), signOut],
          );
        }

        return Row(
          children: [
            Expanded(child: signOut),
            const SizedBox(width: 12),
            Expanded(child: checkStatus),
          ],
        );
      },
    );
  }

  Widget _fixedHeightButton(Widget child) {
    return SizedBox(width: double.infinity, height: 52, child: child);
  }
}
