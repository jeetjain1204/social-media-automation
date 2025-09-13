import 'dart:convert';
import 'dart:async';
import 'package:blob/utils/html_stub.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';

class ConnectMetaPage extends StatefulWidget {
  const ConnectMetaPage({super.key});

  @override
  State<ConnectMetaPage> createState() => _ConnectMetaPageState();
}

class _ConnectMetaPageState extends State<ConnectMetaPage> {
  final supabase = Supabase.instance.client;

  bool launching = false;
  bool fbConnected = false;
  bool igConnected = false;
  bool redirectGuard = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    // OPT: Defer async work to next frame to not compete with first paint (LCP win).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await loadConnectionStatus();
      final nonce = Uri.base.queryParameters['nonce'];
      if (nonce != null) {
        await handleMetaRedirect(nonce);
      }
    });
  }

  Future<void> loadConnectionStatus() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) context.go('/login');
        return;
      }

      // OPT: Add network timeout to avoid indefinite hangs; typed result for safety.
      final res = await supabase
          .from('social_accounts')
          .select('platform')
          .eq('user_id', uid)
          .eq('is_disconnected', false)
          .timeout(const Duration(seconds: 10)); // OPT: timeout

      final rows = (res as List<dynamic>).cast<Map<String, dynamic>>();
      fbConnected = rows.any((r) => r['platform'] == 'facebook');
      igConnected = rows.any((r) => r['platform'] == 'instagram');

      if (!mounted) return;

      if (fbConnected && igConnected) {
        // OPT: Short‑circuit navigation if already connected.
        context.go('/home');
        return;
      }
    } on TimeoutException {
      if (mounted) {
        mySnackBar(context, 'Checking connection timed out. Try again.');
      }
    } catch (e) {
      if (mounted) {
        mySnackBar(context, 'Failed to check connection: $e');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> handleMetaRedirect(String nonce) async {
    if (redirectGuard)
      return; // OPT: Idempotent guard to prevent duplicate handling.
    redirectGuard = true;

    if (mounted) setState(() => isLoading = true);

    // OPT: Clear nonce from URL to avoid leaking params in history.
    if (kIsWeb && htmlWindow != null) {
      htmlWindow!.history.replaceState(null, '', '/connect/meta');
    }

    try {
      final res = await supabase.functions.invoke('redeem-meta-token', body: {
        'nonce': nonce
      }).timeout(const Duration(seconds: 15)); // OPT: network timeout

      if (res.status == 200) {
        final data = res.data as Map<String, dynamic>;
        final pages =
            (data['pages'] as List<dynamic>).cast<Map<String, dynamic>>();

        final extra = <String, dynamic>{
          'platform': data['platform'] as String?,
          'nonce': nonce,
          'pages': pages,
        };

        if (!mounted) return;
        setState(() => isLoading = false);
        context.push('/select-pages', extra: extra);
      } else {
        final err = (res.data is Map && (res.data as Map).containsKey('error'))
            ? res.data['error'] as String
            : 'unknown';

        if (!mounted) return;
        setState(() => isLoading = false);

        mySnackBar(context, 'Some error occured');
        if (err == 'no_pages') {
          mySnackBar(
            context,
            'We couldn’t find a Facebook Page linked to this account.\n'
            '· Make sure the IG is Business / Creator\n'
            '· It’s linked to a FB Page you manage\n'
            '· You are Page Admin',
            duration: 10,
          );
        }
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => isLoading = false);
        mySnackBar(context, 'Meta handshake timed out. Please try again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        mySnackBar(context, 'Meta handshake failed: $e');
      }
    }
  }

  Future<void> launchMetaOAuth(String target) async {
    if (launching) return; // OPT: Debounce rapid taps.
    if (mounted) setState(() => launching = true);

    try {
      const appId = '649594124148627'; // Public client_id is OK on client.
      const redirect =
          'https://ehgginqelbgrzfrzbmis.supabase.co/functions/v1/meta-token-exchange';

      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) mySnackBar(context, 'Please log in first');
        return;
      }

      // OPT: Compact, URL‑safe state. No PII beyond user id (already present in session).
      final state = base64Url.encode(
        utf8.encode(jsonEncode({'u': uid, 't': target})),
      );

      // OPT: Keep scopes minimal and explicit; same behavior preserved.
      final scope = [
        'public_profile',
        'pages_show_list',
        'pages_read_engagement',
        'business_management',
        'pages_manage_posts',
        'instagram_basic',
        'instagram_content_publish',
        'instagram_manage_comments',
        'instagram_manage_insights',
        'instagram_manage_messages',
      ].join(',');

      final uri = Uri.https('www.facebook.com', '/v23.0/dialog/oauth', {
        'client_id': appId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'state': state,
        'auth_type': 'rerequest',
        'scope': scope,
      });

      // OPT: url_launcher guardrails + external app mode for web/desktop.
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_self',
        );
        if (!ok && mounted) {
          mySnackBar(context, 'Cannot open Meta OAuth window');
        }
      } else {
        if (mounted) mySnackBar(context, 'Cannot open Meta OAuth window');
      }
    } catch (e) {
      if (mounted) mySnackBar(context, 'Failed to start Meta OAuth: $e');
    } finally {
      if (mounted) setState(() => launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Center(
        child: AutoSkeleton(
          enabled: isLoading,
          preserveSize: true,
          clipPadding: const EdgeInsets.symmetric(vertical: 64),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.04,
              vertical: 64,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Connect Your Social Accounts',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isWide ? 28 : 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'To enable automated scheduling and analytics,\nplease connect your Facebook and Instagram accounts',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 40),
                if (!fbConnected)
                  MyButton(
                    width: isWide ? width * 0.25 : width * 0.6,
                    isLoading: launching,
                    text: 'Connect Facebook',
                    onTap: launching ? null : () => launchMetaOAuth('facebook'),
                  ),
                if (!igConnected) ...[
                  const SizedBox(height: 24),
                  MyButton(
                    width: isWide ? width * 0.25 : width * 0.6,
                    isLoading: launching,
                    text: 'Connect Instagram',
                    onTap:
                        launching ? null : () => launchMetaOAuth('instagram'),
                  ),
                ],
                if (fbConnected && igConnected)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: Colors.green,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Both accounts are connected!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
