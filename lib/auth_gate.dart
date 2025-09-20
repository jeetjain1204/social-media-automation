// OPT: Reliability pass: cleanup subscriptions/timers, guard setState, safe retry.
//      No behavior changes: same UI/flows, just safer and leak-free.

import 'dart:async'; // OPT: for StreamSubscription and Timer
import 'package:blob/main_page.dart';
import 'package:blob/pages/auth/login_page.dart';
import 'package:blob/widgets/circular_progress_indicator.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool loading = true;
  bool loggedIn = false;
  bool showFallback = false;
  late final DateTime startTime;

  // OPT: Track listener/timer to avoid leaks and late setState
  StreamSubscription<AuthState>? authSub; // OPT: cancel in dispose
  Timer? fallbackTimer; // OPT: cancel in dispose or once resolved

  @override
  void initState() {
    super.initState();
    startTime = DateTime.now();

    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // OPT: Avoid setState; we are in initState and values are defaulted
      loggedIn = true;
      loading = false;
    } else {
      // OPT: Attach listener only when needed; store sub for cleanup
      authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        if (!mounted) return;
        final nextLoggedIn = data.session != null;

        // OPT: Guard against redundant rebuilds
        if (loggedIn == nextLoggedIn && loading == false) return;

        setState(() {
          loggedIn = nextLoggedIn;
          loading = false;
          // OPT: If we resolved auth, ensure fallback will not show
          if (showFallback) showFallback = false;
        });

        // FIXED: Cancel fallback timer once we have a resolution
        fallbackTimer?.cancel();
        fallbackTimer = null;
      });

      // OPT: Trigger fallback only if auth still pending after 10s.
      // Keep a cancellable Timer to avoid late setState.
      fallbackTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        if (loading && !showFallback) {
          setState(() {
            showFallback = true;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    // FIXED: Ensure all subscriptions and timers are properly disposed
    authSub?.cancel();
    authSub = null;
    fallbackTimer?.cancel();
    fallbackTimer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading && !showFallback) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: 'Loading...',
            child:
                MyCircularProgressIndicator(), // OPT: keep non-const to avoid ctor assumptions
          ),
        ),
      );
    }

    if (loading && showFallback) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Taking longer than usual...",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 16),
              MyCircularProgressIndicator(),
              SizedBox(height: 12),
              // OPT: Don't wrap in const because onPressed is dynamic
              RetryButton(),
            ],
          ),
        ),
      );
    }

    return loggedIn
        ? const MainPage(child: SizedBox.shrink()) // OPT: const safe here
        : const LoginPage();
  }
}

// OPT: Extracted stateless widget prevents reallocation; add safe error handling
class RetryButton extends StatelessWidget {
  const RetryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return MyTextButton(
      onPressed: () async {
        try {
          // OPT: Best-effort refresh; ignore returned value to avoid behavior drift
          await Supabase.instance.client.auth.refreshSession();
        } catch (_) {
          // OPT: Swallow errors to avoid surfacing transient issues to users;
          //      actual logging should be centralized in your app logger.
        }
      },
      child: const Text("Retry"),
    );
  }
}
