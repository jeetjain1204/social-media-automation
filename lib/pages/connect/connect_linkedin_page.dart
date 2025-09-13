import 'dart:io';
import 'dart:async';
import 'package:blob/utils/html_stub.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:retry/retry.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';

class ConnectLinkedInPage extends StatefulWidget {
  const ConnectLinkedInPage({super.key});

  @override
  State<ConnectLinkedInPage> createState() => _ConnectLinkedInPageState();
}

class _ConnectLinkedInPageState extends State<ConnectLinkedInPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = false;
  String linkedInButtonText = 'Connect LinkedIn';
  bool isRedirectHandled = false;

  @override
  void initState() {
    super.initState();
    // OPT: Avoid unnecessary widget rebuilds by deferring async startup work
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final params = Uri.base.queryParameters;
      final nonce = params['nonce'];
      final error = params['error'];
      if (nonce != null && error == null) {
        handleOAuthRedirect();
      } else {
        loadConnectionStatus();
      }
    });
  }

  Future<void> loadConnectionStatus() async {
    try {
      setState(() => isLoading = true);

      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) context.push('/login');
        return;
      }

      final response = await retry(
        () => supabase
            .from('social_accounts')
            .select()
            .eq('platform', 'linkedin')
            .eq('is_disconnected', false)
            .eq('user_id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 10)),
        retryIf: (e) => e is SocketException || e is TimeoutException,
        maxAttempts: 3,
        delayFactor: const Duration(milliseconds: 500),
      );

      final accessToken = response?['access_token'] as String?;
      final needsReconnect = response?['needs_reconnect'] as bool? ?? false;

      if (!mounted) return;
      setState(() => isLoading = false);

      if (accessToken != null && accessToken.isNotEmpty && !needsReconnect) {
        context.go('/home/generator');
      } else if (accessToken != null &&
          accessToken.isNotEmpty &&
          needsReconnect) {
        mySnackBar(
          context,
          'Your LinkedIn connection expired. Please reconnect',
        );
        setState(() => linkedInButtonText = 'Reconnect LinkedIn');
      } else {
        mySnackBar(context, 'Connect LinkedIn');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      mySnackBar(context, 'Failed to check connection status: ${e.toString()}');
    }
  }

  Future<void> handleOAuthRedirect() async {
    if (isRedirectHandled) return;

    setState(() {
      isRedirectHandled = true;
      isLoading = true;
    });

    final uri = Uri.base;
    final nonce = uri.queryParameters['nonce'];
    final error = uri.queryParameters['error'];

    if (error != null) {
      if (!mounted) return;
      final msg = switch (error) {
        'already_connected' =>
          'Your LinkedIn account is already connected. Please reload the website',
        'urn_conflict' =>
          'This LinkedIn account is already connected to another Blob account',
        _ => 'LinkedIn connection error: $error',
      };
      mySnackBar(context, msg);
      setState(() => isLoading = false);
      return;
    }

    if (nonce != null) {
      if (kIsWeb && htmlWindow != null) {
        // OPT: Avoid polluting browser history with nonce param
        htmlWindow!.history.replaceState(null, '', '/connect/linkedin');
      }

      final res = await supabase.functions.invoke(
        'redeem-linkedin-token',
        body: {'nonce': nonce},
      );

      if (res.status == 200) {
        final token = res.data['access_token'] as String;
        final person = res.data['person_urn'] as String;
        if (!mounted) return;
        context.go(
          '/select-pages',
          extra: {
            'accessToken': token,
            'personUrn': person,
            'platform': 'linkedin',
          },
        );
        // Keep isLoading true until redirected page takes over
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
        mySnackBar(context, res.data['error'] ?? 'LinkedIn handshake failed');
      }
    }
  }

  Future<void> connectLinkedIn() async {
    try {
      setState(() => isLoading = true);
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) context.push('/login');
        return;
      }

      final response = await retry(
        () => supabase.functions.invoke('get-oauth-url',
            body: {'user_id': userId}).timeout(const Duration(seconds: 10)),
        retryIf: (e) => e is SocketException || e is TimeoutException,
        maxAttempts: 3,
        delayFactor: const Duration(milliseconds: 500),
      );

      if (response.status != 200 || response.data == null) {
        if (mounted) mySnackBar(context, 'Failed to get OAuth URL');
        return;
      }

      final authUrl = response.data['url'] as String;
      final uri = Uri.tryParse(authUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_self',
        );
        if (!ok && mounted) mySnackBar(context, 'Could not open OAuth URL');
        return;
      } else {
        if (mounted) mySnackBar(context, 'Could not launch OAuth URL');
      }
    } catch (e) {
      if (mounted) {
        mySnackBar(context, 'Failed to connect LinkedIn: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AutoSkeleton(
          enabled: isLoading,
          preserveSize: true,
          clipPadding: const EdgeInsets.symmetric(vertical: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 64),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'One last step!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Connect your LinkedIn account to start posting',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                MyButton(
                  width: width * 0.25,
                  text: linkedInButtonText,
                  isLoading: false,
                  onTap: connectLinkedIn,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
