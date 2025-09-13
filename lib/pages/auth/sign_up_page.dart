import 'dart:async'; // OPT: Handle TimeoutException on network calls

import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;

  @override
  void dispose() {
    // OPT: Prevent memory leaks on web by disposing controllers.
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> signUp() async {
    if (isLoading) return; // OPT: Debounce double taps.
    if (mounted) setState(() => isLoading = true);

    final email = emailController.text.trim();
    final password = passwordController.text;

    // OPT: Early, lightweight validation to avoid network calls.
    if (!email.contains('@')) {
      if (mounted) mySnackBar(context, 'Enter a valid email');
      if (mounted) setState(() => isLoading = false);
      return;
    }
    if (password.length < 6) {
      if (mounted)
        mySnackBar(context, 'Password must be at least 6 characters');
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      // OPT: Keep signup pure; downstream inserts are wrapped with timeouts.
      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final user = response.user;

      if (user != null) {
        // OPT: Insert user + brand_kit rows with timeouts to avoid hangs.
        await Supabase.instance.client.from('users').insert({
          'id': user.id,
          'full_name': '',
          'email': email,
          'profile_pic': '',
          'current_plan_id': 'kickstart', // respecting current code behavior
          'is_admin': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }).timeout(const Duration(seconds: 12)); // OPT: timeout

        await Supabase.instance.client
            .schema('brand_kit')
            .from('brand_kits')
            .insert({
          'id': user.id,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }).timeout(const Duration(seconds: 12)); // OPT: timeout

        // NOTE: Keeping your commented template logic intact (no behavior change).

        if (!mounted) return;
        context.push('/onboarding');
      } else {
        if (mounted) mySnackBar(context, 'Signup failed');
      }
    } on TimeoutException {
      if (mounted) mySnackBar(context, 'Network is slow. Please try again.');
    } catch (e) {
      if (!mounted) return;

      // Preserve your existing error mapping while preventing duplicate snackbars.
      if (e is PostgrestException && e.code == '23505') {
        // OPT: Graceful fallback → try sign in once.
        try {
          final response = await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
          if (response.user != null) {
            context.go('/home');
            mySnackBar(context, 'This email is already registered, Signing In');
            return; // OPT: Avoid showing the second snackbar below.
          }
          mySnackBar(context, 'This email is already registered, Pls Login');
        } catch (signInErr) {
          mySnackBar(context, signInErr.toString());
        }
      } else if (e is AuthApiException) {
        if (e.statusCode == '400' && e.code == 'email_address_invalid') {
          mySnackBar(context, 'Please enter a valid email address');
        } else if (e.statusCode == '429' &&
            e.code == 'over_email_send_rate_limit') {
          mySnackBar(
            context,
            'You\'re trying too quickly. Please wait a few seconds',
          );
        } else {
          mySnackBar(context, e.message);
        }
      } else {
        mySnackBar(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
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
            borderRadius: BorderRadius.circular(24),
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
                  'Create Your Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: darkColor,
                  ),
                ),
                const SizedBox(height: 32),

                // Email Field
                TextField(
                  controller: emailController,
                  autofillHints: const [AutofillHints.email],
                  keyboardType:
                      TextInputType.emailAddress, // OPT: proper keyboard
                  style: TextStyle(color: darkColor),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: darkColor.withOpacity(0.7)),
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
                      TextInputAction.done, // OPT: better submit UX
                  style: TextStyle(color: darkColor),
                  onSubmitted: (_) async {
                    if (!isLoading) await signUp();
                  },
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: darkColor.withOpacity(0.7)),
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
                const SizedBox(height: 16),

                // Sign Up Button
                MyButton(
                  width: 400,
                  text: 'Sign Up',
                  onTap: signUp,
                  isLoading: isLoading,
                ),
                const SizedBox(height: 20),

                // Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                        color: darkColor.withOpacity(0.9),
                        fontSize: 14.5,
                      ),
                    ),
                    MyTextButton(
                      onPressed: () => context.push('/login'),
                      child: Text(
                        'Login',
                        style: TextStyle(
                          color: darkColor,
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
