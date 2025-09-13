// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/widgets/my_dropdown.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final supabase = Supabase.instance.client;

  bool isLoading = true;
  bool isPaying = false;
  int currentStep = 0;
  String? selectedCountry;
  int? selectedDuration;
  bool isWaiting = false;

  // OPT: Cache Razorpay script load to avoid multiple DOM injections
  Future<void>? razorpayLoader; // OPT

  int totalPrice() =>
      (selectedCountry == 'india' ? 1499 : 19) * selectedDuration!;

  @override
  void initState() {
    super.initState();
    checkPaymentDetails();

    final user = supabase.auth.currentUser;
    if (user == null) {
      context.go('/home');
      return;
    }

    final params = Uri.base.queryParameters;
    if (params.containsKey('subscription_id')) {
      isWaiting = true;
    }

    if (isWaiting) {
      waitForActivation(user.id);
    }
  }

  // OPT: Small retry helper with backoff + jitter for network resilience
  Future<T> withRetry<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 250),
  }) async {
    int attempt = 0;
    Object? lastError;
    while (attempt < maxAttempts) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        attempt++;
        if (attempt >= maxAttempts) break;
        final factor = 1 << (attempt - 1); // 1,2
        final jitterMs = baseDelay.inMilliseconds ~/ 2;
        final delay =
            Duration(milliseconds: baseDelay.inMilliseconds * factor) +
                Duration(
                  milliseconds: (DateTime.now().microsecond % (jitterMs + 1)),
                );
        await Future.delayed(delay);
      }
    }
    throw lastError ?? Exception('Unknown error');
  }

  Future<void> waitForActivation(String uid) async {
    try {
      for (var i = 0; i < 20; i++) {
        final row = await withRetry<Map<String, dynamic>?>(
          () => supabase
              .from('user_subscription_status')
              .select('is_active_subscriber')
              .eq('user_id', uid)
              .maybeSingle(),
        );
        if (row?['is_active_subscriber'] == true && mounted) {
          context.go('/home');
          return;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      if (mounted) {
        mySnackBar(context, 'Some error occured');
      }
    } finally {
      if (mounted) setState(() => isWaiting = false);
    }
  }

  Future<void> checkPaymentDetails() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        context.go('/login');
        return;
      }

      final sub = await withRetry<Map<String, dynamic>?>(
        () => supabase
            .from('user_subscription_status')
            .select()
            .eq('user_id', user.id)
            .maybeSingle(),
      );

      final now = DateTime.now().toUtc();

      if (sub == null) {
        if (mounted) {
          context.go('/free-trial');
        }
        return;
      }

      final trialEnds = DateTime.tryParse(sub['trial_ends_at'] ?? '');
      final planStartsAt = DateTime.tryParse(sub['plan_started_at'] ?? '');
      final isTrialActive = sub['is_trial_active'] ?? false;
      final isSubscriber = sub['is_active_subscriber'] ?? false;

      final trialExpired = trialEnds == null || now.isAfter(trialEnds);
      final planExpired = planStartsAt == null
          ? true
          : now.isAfter(planStartsAt.add(const Duration(days: 30)));

      if ((trialExpired || !isTrialActive) && (!isSubscriber || planExpired)) {
        // stay on payment page
      } else {
        if (mounted) {
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) mySnackBar(context, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // OPT: One-time loader for Razorpay script to cut layout thrash and double injection
  Future<void> loadRazorpayScriptOnce() {
    razorpayLoader ??= () async {
      var script = html.document.querySelector('#razorpay-script');
      if (script == null) {
        script = html.ScriptElement()
          ..id = 'razorpay-script'
          ..src = 'https://checkout.razorpay.com/v1/checkout.js'
          ..type = 'text/javascript';
        html.document.body!.append(script);
        await (script as html.ScriptElement).onLoad.first;
      }
    }();
    return razorpayLoader!;
  }

  Future<void> payWithRazorpay() async {
    if (isPaying) return; // OPT: prevent double submit
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      mySnackBar(context, 'User not logged in');
      context.go('/login');
      return;
    }
    if (selectedDuration == null) {
      mySnackBar(context, 'Please select a duration');
      return;
    }

    try {
      setState(() => isPaying = true);

      final response = await withRetry(
        () => supabase.functions.invoke(
          'create-subscription',
          body: {'user_id': uid, 'duration': selectedDuration},
        ).timeout(const Duration(seconds: 15)),
      );

      if (response.status != 200) {
        if (mounted) {
          mySnackBar(
            context,
            'Subscription error: ${response.data?['error'] ?? 'failed'}',
          );
        }
        return;
      }

      final data = response.data['data'] as Map<String, dynamic>;
      final subId = data['subscription_id']?.toString();
      final email = data['email'] ?? 'user@example.com';
      final contact = data['contact'] ?? '+919000000000';

      if (subId == null) {
        if (mounted) {
          mySnackBar(context, 'Subscription id missing');
        }
        return;
      }

      // OPT: Load checkout once, then call open()
      await loadRazorpayScriptOnce();

      final callbackUrl = Uri.https('app.blobautomation.com').toString();
      final jsOptions = {
        // NOTE: Public key kept as-is to avoid behavior change.
        // OPT (future): fetch publishable key from Edge Function to avoid hardcoding.
        'key': 'rzp_test_3Uwe4B8CBkpIXd',
        'subscription_id': subId,
        'name': 'Blob Automation',
        'description': 'Blob Plus',
        'callback_url': callbackUrl,
        'redirect': true,
        'recurring': true,
        'prefill': {'email': email, 'contact': contact},
        'theme': {'color': '#004aad'},
      };

      final callScript = html.ScriptElement()
        ..type = 'text/javascript'
        ..innerHtml = '''
          try {
            var options = ${jsonEncode(jsOptions)};
            var rzp = new Razorpay(options);
            rzp.open();
          } catch (e) {
            console.error('Razorpay open error', e);
          }
        ''';

      html.document.body!.append(callScript);
      // OPT: Clean up to avoid DOM bloat on repeated opens
      callScript.remove(); // OPT
    } catch (e) {
      if (mounted) mySnackBar(context, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isPaying = false);
    }
  }

  Future<void> payWithPaypal() async {
    if (isPaying) return; // OPT: prevent double submit
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      mySnackBar(context, 'User not logged in');
      context.go('/login');
      return;
    }
    if (selectedDuration == null) {
      mySnackBar(context, 'Please select a duration');
      return;
    }

    try {
      setState(() => isPaying = true);

      final response = await withRetry(
        () => supabase.functions.invoke(
          'paypal-create-subscription',
          body: {'userId': uid, 'duration': selectedDuration},
        ).timeout(const Duration(seconds: 15)),
      );

      if (response.status != 200) {
        final msg = response.data is String
            ? response.data
            : response.data['error'] ?? 'PayPal error';
        if (mounted) {
          mySnackBar(context, msg.toString());
        }
        return;
      }

      final approveUrl = response.data['approveUrl'] as String?;
      if (approveUrl == null) {
        if (mounted) {
          mySnackBar(context, 'Unable to generate PayPal subscription');
        }
        return;
      }

      html.window.location.href = approveUrl;
    } catch (e) {
      if (mounted) mySnackBar(context, 'Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isPaying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // import 'package:blob/widgets/auto_skeleton.dart'; // ensure this import

    return Scaffold(
      body: LayoutBuilder(
        builder: (_, constraints) {
          final width = constraints.maxWidth;

          final Widget content = AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: currentStep == 0
                ? Semantics(
                    label: 'Country selection screen',
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MyButton(
                            width: width * 0.35,
                            text: 'India',
                            onTap: () {
                              setState(() {
                                selectedCountry = 'india';
                                currentStep = 1;
                              });
                            },
                            isLoading: false,
                          ),
                          const SizedBox(height: 24),
                          MyButton(
                            width: width * 0.35,
                            text: 'International',
                            onTap: () {
                              setState(() {
                                selectedCountry = 'international';
                                currentStep = 1;
                              });
                            },
                            isLoading: false,
                          ),
                        ],
                      ),
                    ),
                  )
                : Semantics(
                    label: 'Plan selection screen',
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Select Duration',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          MyDropDown(
                            width: 250,
                            items: const ['1', '3', '6', '12'],
                            hint: 'Months',
                            value: selectedDuration?.toString(),
                            onChanged: (duration) {
                              setState(() {
                                if (duration != null) {
                                  selectedDuration =
                                      int.tryParse(duration) ?? 1;
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 32),
                          if (selectedDuration != null)
                            Column(
                              children: [
                                Text(
                                  selectedCountry == 'india'
                                      ? 'Total: ₹${totalPrice()}'
                                      : 'Total: \$${totalPrice()}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 32),
                              ],
                            ),
                          MyButton(
                            width: width * 0.33,
                            text: selectedCountry == 'india'
                                ? 'Pay with Razorpay'
                                : 'Pay with PayPal',
                            onTap: () async {
                              if (selectedCountry == 'india') {
                                await payWithRazorpay();
                              } else {
                                await payWithPaypal();
                              }
                            },
                            isLoading: isPaying,
                          ),
                          const SizedBox(height: 24),
                          MyTextButton(
                            onPressed: () => setState(() => currentStep = 0),
                            icon: const Icon(Icons.arrow_back),
                            child: const Text('Change country'),
                          ),
                        ],
                      ),
                    ),
                  ),
          );

          // AutoSkeleton builds the same UI offstage and paints its exact geometry.
          return Center(
            child: AutoSkeleton(
              enabled: isWaiting || isLoading,
              child: content,
            ),
          );
        },
      ),
    );
  }
}
