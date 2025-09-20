import 'dart:async';

import 'package:blob/utils/colors.dart';
import 'package:blob/utils/error_handler.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();

    // OPT: Let first frame paint; then navigate if already logged in (LCP win).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = supabase.auth.currentUser;
      if (user != null && mounted) {
        context.push('/home');
      }
    });
  }

  @override
  void dispose() {
    // OPT: Prevent leaks on web; dispose controllers.
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (isLoading) return;
    if (mounted) setState(() => isLoading = true);

    final email = emailController.text.trim();
    final password = passwordController.text;

    // FIXED: Use centralized error handling for validation
    if (!email.contains('@')) {
      await ErrorHandler.handleError(
        AppError(
          message: 'Enter a valid email',
          type: ErrorType.validation,
        ),
        null,
        context: 'login validation',
        buildContext: context,
      );
      if (mounted) setState(() => isLoading = false);
      return;
    }

    if (password.length < 6) {
      await ErrorHandler.handleError(
        AppError(
          message: 'Password must be at least 6 characters',
          type: ErrorType.validation,
        ),
        null,
        context: 'login validation',
        buildContext: context,
      );
      if (mounted) setState(() => isLoading = false);
      return;
    }

    // FIXED: Use centralized error handling
    await ErrorHandler.handleAsync(
      () async {
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        final user = response.user;
        if (user == null) {
          throw AppError(
            message: 'Login failed',
            type: ErrorType.authentication,
          );
        }

        if (user.emailConfirmedAt == null) {
          throw AppError(
            message: 'Please verify your email before logging in',
            type: ErrorType.authentication,
          );
        }

        if (!mounted) return null;

        // FIXED: Optimized database query with proper error handling
        final res = await supabase
            .from('social_accounts')
            .select('platform, access_token, is_disconnected')
            .eq('user_id', user.id)
            .inFilter('platform', ['linkedin', 'facebook'])
            .eq('is_disconnected', false)
            .limit(2)
            .timeout(const Duration(seconds: 10));

        bool isConnected = false;
        for (final row in (res as List<dynamic>)) {
          final map = row as Map<String, dynamic>;
          final token = map['access_token'];
          if (token != null && token.toString().isNotEmpty) {
            isConnected = true;
            break;
          }
        }

        if (isConnected) {
          if (mounted) context.go('/home');
        } else {
          if (mounted) context.go('/connect/linkedin');
        }

        return true;
      },
      context: 'login',
      buildContext: context,
    );

    if (mounted) setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightColor,
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24), // --radius-card
            boxShadow: [
              BoxShadow(
                color: darkColor.withOpacity(0.08),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Login to Blob',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: darkColor,
                  ),
                ),
                const SizedBox(height: 32),

                // Email Field
                TextFormField(
                  controller: emailController,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: darkColor),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(
                      color: darkColor.withOpacity(0.7),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF1F7FF),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Password Field
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction:
                      TextInputAction.done, // OPT: better UX on submit
                  style: TextStyle(color: darkColor),
                  onSubmitted: (_) => login(), // OPT: no extra await needed
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(
                      color: darkColor.withOpacity(0.7),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF1F7FF),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Forgot Password
                Align(
                  alignment: Alignment.centerRight,
                  child: MyTextButton(
                    onPressed: () async {
                      final email = emailController.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        mySnackBar(
                          context,
                          'Enter your email to reset password',
                        );
                        return;
                      }
                      try {
                        await supabase.auth.resetPasswordForEmail(email);
                        if (context.mounted) {
                          mySnackBar(context, 'Reset link sent to $email');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          mySnackBar(context, e.toString());
                        }
                      }
                    },
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Login Button
                MyButton(
                  width: 400,
                  text: 'Login',
                  onTap: login, // OPT: pass reference, keeps it tidy
                  isLoading: isLoading,
                ),
                const SizedBox(height: 20),

                // Sign Up CTA
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Don’t have an account? ',
                      style: TextStyle(
                        color: darkColor.withOpacity(0.9),
                        fontSize: 14.5,
                      ),
                    ),
                    MyTextButton(
                      onPressed: () => context.go('/signup'),
                      child: Text(
                        'Sign Up',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
