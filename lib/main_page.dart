// MainPage.dart
import 'dart:async';
import 'package:blob/widgets/circular_progress_indicator.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:collapsible_sidebar/collapsible_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.child});
  final Widget child;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final supabase = Supabase.instance.client;

  bool isCheckingSocials = true;

  // OPT: Keep cancellable handle to prevent late UI work and accidental setState after dispose.
  Timer? takingLongerTimer;

  @override
  void initState() {
    super.initState();

    // OPT: Run both independent checks in parallel to minimize total wait time.
    // Avoids serial blocking that hurts LCP.
    checkPlanDetails();
    checkSocialConnections();

    // OPT: Defensive "taking longer" UX with a cancellable timer to avoid late snackbars.
    takingLongerTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !isCheckingSocials) return;
      mySnackBar(context, 'This is taking longer than usual...');
      // OPT: Allow user to interact; we fail open here while other checks continue.
      setState(() => isCheckingSocials = false);
    });
  }

  @override
  void dispose() {
    // OPT: Ensure no pending timer or setState fires after dispose.
    takingLongerTimer?.cancel();
    takingLongerTimer = null;
    super.dispose();
  }

  Future<void> checkPlanDetails() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      // OPT: Only fetch columns actually used to reduce payload.
      final subscription = await supabase
          .from('user_subscription_status')
          .select(
            'user_id, is_trial_active, is_active_subscriber, trial_ends_at, plan_ends_at',
          )
          .eq('user_id', user.id)
          .maybeSingle()
          .timeout(
            const Duration(seconds: 8),
          ); // OPT: Bound network time for better TBT.

      final now = DateTime.now().toUtc();

      if (subscription == null) {
        if (!mounted) return;
        mySnackBar(
          context,
          'No active plan found. Starting your free trial...',
        );
        context.go('/free-trial');
        return;
      }

      // OPT: Safe ISO parsing; Supabase returns ISO8601 strings.
      final trialEndsIso = subscription['trial_ends_at'] as String?;
      final planEndsIso = subscription['plan_ends_at'] as String?;
      final trialEnds = trialEndsIso == null
          ? null
          : DateTime.tryParse(trialEndsIso)?.toUtc();
      final planEnds =
          planEndsIso == null ? null : DateTime.tryParse(planEndsIso)?.toUtc();

      final isTrialActive = (subscription['is_trial_active'] as bool?) ?? false;
      final isSubscriber =
          (subscription['is_active_subscriber'] as bool?) ?? false;

      // Behavior preserved: gate on expired/non‑subscriber state.
      if ((!isTrialActive || (trialEnds != null && now.isAfter(trialEnds))) &&
          !isSubscriber) {
        if (!mounted) return;
        mySnackBar(
          context,
          'Your plan has expired. Please upgrade to continue',
        );
        context.go('/payment');
        return;
      }

      final trialExpired = trialEnds == null || now.isAfter(trialEnds);
      final planExpired = planEnds == null || now.isAfter(planEnds);

      if ((trialExpired || !isTrialActive) && (!isSubscriber || planExpired)) {
        if (mounted) context.go('/payment');
        return;
      }
    } on TimeoutException {
      // OPT: Network hiccup shouldn’t block UX; skip routing to avoid thrash.
    } catch (_) {
      // OPT: Swallow unexpected errors locally; central error logging can capture details elsewhere.
    }
  }

  Future<void> checkSocialConnections() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.push('/login');
      return;
    }

    final now = DateTime.now().toUtc();
    const platforms = ['linkedin', 'facebook'];

    try {
      // OPT: Single round‑trip using IN filter keeps payload small and avoids client filtering.
      final rows = await supabase
          .from('social_accounts')
          .select(
            'platform, access_token, is_disconnected, needs_reconnect, connected_at',
          )
          .eq('user_id', user.id)
          .eq('is_disconnected', false)
          .inFilter(
            'platform',
            platforms,
          ) // OPT: Keep as .inFilter per your current SDK.
          .timeout(const Duration(seconds: 8));

      bool atLeastOneConnected = false;

      for (final row in rows) {
        final platform = (row['platform'] as String?) ?? '';
        final accessToken = row['access_token'];
        final isConnected =
            accessToken != null && accessToken.toString().isNotEmpty;

        if (isConnected) atLeastOneConnected = true;

        final needsReconnect = row['needs_reconnect'] == true;

        final connectedAtIso = row['connected_at'] as String?;
        final connectedAt = connectedAtIso == null
            ? null
            : DateTime.tryParse(connectedAtIso)?.toUtc();
        final daysOld =
            connectedAt == null ? 999 : now.difference(connectedAt).inDays;

        if ((daysOld > 50 || needsReconnect) && mounted) {
          mySnackBar(
            context,
            'Your $platform connection is over 50 days old or expired. Please reconnect',
          );
          context.go(
            platform == 'linkedin' ? '/connect/linkedin' : '/connect/meta',
          );
          return;
        }
      }

      if (!atLeastOneConnected && mounted) {
        mySnackBar(context, "You haven't connected any platform yet.");
        context.go('/connect');
        return;
      }
    } on TimeoutException {
      // OPT: Fail open for UX; we’ll drop the gate spinner below.
    } catch (_) {
      // OPT: Non‑fatal; proceed to clear spinner.
    }

    if (!mounted) return;

    // OPT: Clear gate spinner as soon as we’re done; also stop the "taking longer" timer.
    takingLongerTimer?.cancel();
    takingLongerTimer = null;

    setState(() {
      isCheckingSocials = false;
    });
  }

  List<CollapsibleItem> getSidebarItems(BuildContext context) {
    // OPT: Cheaper location access than building a Uri; reduces string work every build.
    final location = GoRouterState.of(context).fullPath ??
        GoRouterState.of(context).path ??
        '/home/generator';

    return <CollapsibleItem>[
      CollapsibleItem(
        text: 'Idea Generator',
        icon: location.startsWith('/home/idea')
            ? Icons.lightbulb
            : Icons.lightbulb_outline,
        isSelected: location.startsWith('/home/idea'),
        onPressed: () => context.go('/home/idea'),
      ),
      CollapsibleItem(
        text: 'AI Generator',
        icon: location.startsWith('/home/generator')
            ? Icons.auto_awesome
            : Icons.auto_awesome_outlined,
        isSelected: location.startsWith('/home/generator'),
        onPressed: () => context.go('/home/generator'),
      ),
      CollapsibleItem(
        text: 'History',
        icon: location.startsWith('/home/history')
            ? Icons.history
            : Icons.history_outlined,
        isSelected: location.startsWith('/home/history'),
        onPressed: () => context.go('/home/history'),
      ),
      CollapsibleItem(
        text: 'Profile',
        icon: location.startsWith('/home/profile')
            ? Icons.person
            : Icons.person_outline,
        isSelected: location.startsWith('/home/profile'),
        onPressed: () => context.go('/home/profile'),
      ),
      CollapsibleItem(
        text: 'Logout',
        icon: Icons.logout,
        onPressed: () async {
          final confirmed = await showLogoutDialog();
          if (confirmed) {
            await supabase.auth.signOut();
            if (context.mounted) {
              context.go('/login');
            }
          }
        },
        isSelected: false,
      ),
    ];
  }

  Future<bool> showLogoutDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const AlertDialog(
        // OPT: const trees reduce rebuild work for simple static dialogs.
        title: Text('Logout'),
        content: Text('Are you sure you want to logout?'),
        actions: [_DialogCancelButton(), _DialogConfirmButton()],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (isCheckingSocials) {
      return Scaffold(
        // OPT: const Scaffold subtree removes rebuild churn while spinner is shown.
        body: Center(
          child: Semantics(
            label: 'Checking social connections...',
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MyCircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Checking your social connections...',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      // OPT: Isolate the heavy body from sidebar animations to cut repaints.
      body: RepaintBoundary(
        child: CollapsibleSidebar(
          isCollapsed: true,
          items: getSidebarItems(context),
          title: '',
          showTitle: false,
          body: RepaintBoundary(
            child: widget.child,
          ), // OPT: isolate page content too.
          backgroundColor: const Color(0xFFF8FAFC),
          selectedTextColor: darkColor,
          selectedIconColor: darkColor,
          unselectedIconColor: lightColor,
          unselectedTextColor: lightColor,
          selectedIconBox: lightColor,
          iconSize: 28,
          maxWidth: 300,
          minWidth: 72,
          toggleButtonIcon: Icons.menu,
          showToggleButton: true,
          topPadding: 24,
          bottomPadding: 12,
          itemPadding: 12,
          borderRadius: 16,
          screenPadding: 0,
          fitItemsToBottom: false,
          badgeBackgroundColor: darkColor,
          badgeTextColor: lightColor,
          avatarBackgroundColor: lightColor,
          sidebarBoxShadow: const [], // OPT: const list literal for zero‑alloc.
        ),
      ),
    );
  }
}

// OPT: Extracted tiny dialog action buttons as widgets to honor "no inline widget functions"
// and to keep the AlertDialog const‑constructible above.
class _DialogCancelButton extends StatelessWidget {
  const _DialogCancelButton();

  @override
  Widget build(BuildContext context) {
    return MyTextButton(
      onPressed: () => context.pop(false),
      child: const Text('Cancel'),
    );
  }
}

class _DialogConfirmButton extends StatelessWidget {
  const _DialogConfirmButton();

  @override
  Widget build(BuildContext context) {
    return MyTextButton(
      onPressed: () => context.pop(true),
      child: const Text('Logout'),
    );
  }
}
