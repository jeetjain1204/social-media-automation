import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blob/widgets/my_button.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    // OPT: Defer async work until after first frame so layout can paint sooner (LCP win).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      checkConnection();
    });
  }

  Future<void> checkConnection() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.push('/login');
      return;
    }

    // OPT: Replace 3 round trips (one per platform) with a single targeted query.
    //      Only fetch required columns, cap with timeout to avoid hangs.
    final platforms = ['linkedin', 'facebook', 'instagram'];

    try {
      final res = await supabase
          .from('social_accounts')
          .select('platform, access_token, is_disconnected')
          .eq('user_id', user.id)
          .contains(
            'platform',
            platforms,
          ) // OPT: single query for all platforms
          .eq('is_disconnected', false)
          .limit(3) // OPT: defensive cap
          .timeout(const Duration(seconds: 10)); // OPT: network timeout

      // res is List<dynamic>; iterate and short‑circuit on first connected
      bool atLeastOneConnected = false;
      for (final row in (res as List<dynamic>)) {
        final map = row as Map<String, dynamic>;
        final token = map['access_token'];
        if (token != null && token.toString().isNotEmpty) {
          atLeastOneConnected = true;
          break; // OPT: no extra work once one is connected
        }
      }

      if (atLeastOneConnected && mounted) {
        context.go('/home');
      }
    } on TimeoutException {
      // OPT: Silent fail by design (keeps behavior the same); avoids blocking the UI indefinitely.
    } catch (_) {
      // OPT: Silent catch to preserve original behavior (no snackbars or UI state changes here).
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.04, vertical: 64),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Text(
                'Connect Your Platforms',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isWide ? 28 : 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1A1A1A),
                  height: 1.3,
                ),
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                'Link your social accounts to unlock posting and analytics',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Colors.grey.shade700,
                ),
              ),

              const SizedBox(height: 40),

              // LinkedIn Button
              MyButton(
                width: isWide ? width * 0.25 : width * 0.6,
                isLoading: false,
                text: 'Connect LinkedIn',
                onTap: () => context.push('/connect/linkedin'),
              ),

              const SizedBox(height: 24),

              // Facebook Button
              MyButton(
                width: isWide ? width * 0.25 : width * 0.6,
                isLoading: false,
                text: 'Connect Facebook',
                onTap: () => context.push('/connect/meta'),
              ),

              const SizedBox(height: 24),

              // Instagram Button
              MyButton(
                width: isWide ? width * 0.25 : width * 0.6,
                isLoading: false,
                text: 'Connect Instagram',
                onTap: () => context.push('/connect/meta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
