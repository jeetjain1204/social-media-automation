import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FreeTrialPage extends StatefulWidget {
  const FreeTrialPage({super.key});

  @override
  State<FreeTrialPage> createState() => _FreeTrialPageState();
}

class _FreeTrialPageState extends State<FreeTrialPage> {
  final supabase = Supabase.instance.client;
  bool isStarting = false;
  bool isLoading = true;

  // OPT: Centralize trial length to match product (7-day free trial).
  // Keeps UI text and DB insert consistent with pricing spec.
  static const int trialDays = 7; // OPT: product-consistent

  @override
  void initState() {
    super.initState();
    checkTrialDetails();
  }

  // OPT: Lightweight retry with exponential backoff + jitter for transient Supabase errors (5xx/429).
  // House rule: no underscores; keeping public-style naming.
  Future<T> withRetry<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 200),
  }) async {
    int attempt = 0;
    Object? lastError;
    while (attempt < maxAttempts) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        attempt += 1;
        if (attempt >= maxAttempts) break;
        final jitterMs = (baseDelay.inMilliseconds * 0.5).toInt();
        final delayMs = baseDelay.inMilliseconds * (1 << (attempt - 1));
        final jitter = Duration(
          milliseconds:
              (jitterMs * (0.5 + (DateTime.now().microsecond % 1000) / 1000))
                  .toInt(),
        );
        await Future.delayed(Duration(milliseconds: delayMs) + jitter);
      }
    }
    throw lastError ?? Exception('Unknown error');
  }

  Future<void> checkTrialDetails() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) context.go('/login');
        return;
      }

      final subscription = await withRetry<Map<String, dynamic>?>(
        () => supabase
            .from('user_subscription_status')
            .select()
            .eq('user_id', user.id)
            .maybeSingle(),
      );

      // No row => user can start trial; render page.
      if (subscription == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      // OPT: If already an active subscriber, short-circuit to home.
      final bool isSubscriber = subscription['is_active_subscriber'] == true;
      if (isSubscriber) {
        if (mounted)
          context.go('/home'); // OPT: avoid parsing dates unnecessarily
        return;
      }

      final bool isTrialActive = subscription['is_trial_active'] == true;
      final DateTime now = DateTime.now().toUtc();
      final DateTime? trialEnds = subscription['trial_ends_at'] is String
          ? DateTime.tryParse(subscription['trial_ends_at'])
          : null;

      final bool trialExpired = trialEnds == null || now.isAfter(trialEnds);

      // OPT: If trial is active and not expired => home. Else => payment.
      if (isTrialActive && !trialExpired) {
        if (mounted) context.go('/home');
        return;
      }

      if (mounted) {
        context.go('/payment');
      }
    } catch (e) {
      if (mounted) {
        mySnackBar(context, 'Error: ${e.toString()}');
        // OPT: In case of transient read failure, let user proceed to trial page instead of blank screen.
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> startTrial() async {
    if (isStarting) return; // OPT: guard double-tap
    setState(() => isStarting = true);

    final user = supabase.auth.currentUser;
    final String? userId = user?.id;

    if (userId == null) {
      if (mounted) {
        mySnackBar(context, 'Please log in to start your trial.');
        context.go('/login');
      }
      setState(() => isStarting = false);
      return;
    }

    try {
      final existing = await withRetry<Map<String, dynamic>?>(
        () => supabase
            .from('user_subscription_status')
            .select()
            .eq('user_id', userId)
            .maybeSingle(),
      );

      if (existing != null) {
        // OPT: Respect server truth; do not create duplicates. Fast-path navigation.
        if (mounted) {
          mySnackBar(context, 'Trial already claimed');
          context.go('/home');
        }
        return;
      }

      final DateTime now = DateTime.now().toUtc();
      final DateTime endsAt = now.add(Duration(days: trialDays)); // OPT: 7 days

      await withRetry<void>(
        () => supabase.from('user_subscription_status').insert({
          'user_id': userId,
          'trial_started_at': now.toIso8601String(),
          'trial_ends_at': endsAt.toIso8601String(),
          'is_trial_active': true,
          // OPT: Leave subscriber flags to billing webhook sources of truth.
        }),
      );

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        mySnackBar(context, '❌ Error starting trial: $e');
      }
    } finally {
      if (mounted) setState(() => isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff9fafb), // --bg
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double width = constraints.maxWidth;

          final bool isMobile = width <= 767;
          final double titleSize = isMobile ? 24.0 : 32.0;
          final double subtitleSize = isMobile ? 14.0 : 16.0;
          final double btnWidth = isMobile ? width * 0.8 : width * 0.33;

          return Center(
            child: AutoSkeleton(
              enabled: isLoading,
              child: Semantics(
                label: 'Start Trial Screen',
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Start Your 7-Day Free Trial',
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xff002f6e),
                          fontFamily: 'Inter',
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No payment details required',
                        style: TextStyle(
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                          fontFamily: 'Inter',
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      Semantics(
                        label: 'Start Free Trial button',
                        button: true,
                        child: MyButton(
                          width: btnWidth,
                          text: 'Start Free Trial',
                          onTap: isStarting ? null : startTrial,
                          isLoading: isStarting,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
