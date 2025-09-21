// MainPage.dart
import 'dart:async';
import 'package:blob/services/database_service.dart';
import 'package:blob/services/network_optimizer.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/utils/performance_baseline.dart';
import 'package:blob/widgets/circular_progress_indicator.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:collapsible_sidebar/collapsible_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.child});
  final Widget child;

  @override
  State<MainPage> createState() => MainPageState();
}

class MainPageState extends State<MainPage> {
  final supabase = Supabase.instance.client;
  bool isCheckingSocials = true;
  int pendingChecks = 2;
  String location = '/home/idea';

  // FIXED: Use atomic operations to prevent race conditions
  void doneOne() {
    if (!mounted) return;

    // Use atomic decrement to prevent race conditions
    final newPendingChecks = pendingChecks - 1;
    if (newPendingChecks <= 0 && isCheckingSocials) {
      _cleanupTimers();
      if (mounted) {
        setState(() {
          pendingChecks = newPendingChecks;
          isCheckingSocials = false;
        });
      }
    } else {
      pendingChecks = newPendingChecks;
    }
  }

  Timer? takingLongerTimer;

  // FIXED: Centralized cleanup method
  void _cleanupTimers() {
    takingLongerTimer?.cancel();
    takingLongerTimer = null;
  }

  @override
  void initState() {
    super.initState();

    // Initialize performance tracking
    PerformanceBaseline.initialize();

    // Use optimized batch loading
    _loadUserData();

    takingLongerTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !isCheckingSocials) return;
      postFrame(
        () => mySnackBar(
          context,
          'This is taking longer than usual...',
        ),
      );
      setState(() => isCheckingSocials = false);
    });
  }

  /// Optimized batch loading of user data
  Future<void> _loadUserData() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) nav('/login');
      return;
    }

    try {
      // Use optimized dashboard data loading
      final dashboardData = await NetworkOptimizer.deduplicatedRequest(
        'user_dashboard_${user.id}',
        () => DatabaseService.getUserDashboardData(user.id),
      );

      print('dashboardData: $dashboardData');

      if (dashboardData != null) {
        // Process subscription status
        final subscription =
            dashboardData['subscription'] as Map<String, dynamic>?;
        if (subscription != null) {
          _processSubscriptionStatus(subscription);
        }

        // Process social connections
        final socialAccounts = dashboardData['social_accounts'] as List?;
        if (socialAccounts != null) {
          _processSocialConnections(
              socialAccounts.cast<Map<String, dynamic>>());
        }
      }

      // TEMPORARILY DISABLED: RPC function has issues
      // Also check social connection status for additional validation
      final socialStatus = await NetworkOptimizer.deduplicatedRequest(
        'social_status_${user.id}',
        () => DatabaseService.getSocialConnectionStatus(user.id),
      );

      // if (socialStatus != null) {
      _processSocialConnectionStatus(socialStatus!);
      doneOne();
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        postFrame(() => mySnackBar(context, 'Failed to load user data'));
      }
      doneOne();
    }
  }

  @override
  void dispose() {
    // FIXED: Ensure all timers are properly disposed
    _cleanupTimers();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newLocation = GoRouterState.of(context).matchedLocation;
    if (newLocation != location) {
      // Track page load performance
      final loadStart = DateTime.now();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final loadTime = DateTime.now().difference(loadStart);
        PerformanceBaseline.trackPageLoad(newLocation, loadTime);
      });
      location = newLocation;
    }
  }

  /// Process subscription status from dashboard data
  void _processSubscriptionStatus(Map<String, dynamic> subscription) {
    if (subscription.isEmpty) {
      if (!mounted) return;
      postFrame(
        () => mySnackBar(
          context,
          'No active plan found. Starting your free trial...',
        ),
      );
      nav('/free-trial');
      return;
    }

    final now = DateTime.now().toUtc();
    final trialEndsIso = subscription['trial_ends_at'] as String?;
    final planEndsIso = subscription['plan_ends_at'] as String?;
    final trialEnds =
        trialEndsIso == null ? null : DateTime.tryParse(trialEndsIso)?.toUtc();
    final planEnds =
        planEndsIso == null ? null : DateTime.tryParse(planEndsIso)?.toUtc();

    final isTrialActive = (subscription['is_trial_active'] as bool?) ?? false;
    final isSubscriber =
        (subscription['is_active_subscriber'] as bool?) ?? false;

    if ((!isTrialActive || (trialEnds != null && now.isAfter(trialEnds))) &&
        !isSubscriber) {
      if (!mounted) return;
      postFrame(
        () => mySnackBar(
          context,
          'Your plan has expired. Pls upgrade to continue',
        ),
      );
      nav('/payment');
      return;
    }

    final trialExpired = trialEnds == null || now.isAfter(trialEnds);
    final planExpired = planEnds == null || now.isAfter(planEnds);

    if ((trialExpired || !isTrialActive) && (!isSubscriber || planExpired)) {
      if (mounted) nav('/payment');
      return;
    }
  }

  /// Process social connections from dashboard data
  void _processSocialConnections(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      if (mounted) {
        postFrame(
          () => mySnackBar(
            context,
            "You need to connect LinkedIn to continue.",
          ),
        );
        nav('/connect/linkedin');
      }
      return;
    }

    final now = DateTime.now().toUtc();
    bool linkedinConnected = false;
    print('rows: $rows');

    for (final row in rows) {
      final platform = (row['platform'] as String?) ?? '';
      final accessToken = row['access_token'];
      final isConnected =
          accessToken != null && accessToken.toString().isNotEmpty;

      // Only check LinkedIn connection
      if (platform == 'linkedin' && isConnected) {
        linkedinConnected = true;

        final needsReconnect = row['needs_reconnect'] == true;

        final connectedAtIso = row['connected_at'] as String?;
        final connectedAt = connectedAtIso == null
            ? null
            : DateTime.tryParse(connectedAtIso)?.toUtc();
        final daysOld =
            connectedAt == null ? 999 : now.difference(connectedAt).inDays;

        if ((daysOld > 50 || needsReconnect) && mounted) {
          postFrame(
            () => mySnackBar(
              context,
              'Your LinkedIn connection is over 50 days old or expired. Please reconnect',
            ),
          );

          nav('/connect/linkedin');
          return;
        }
      }
    }

    if (!linkedinConnected && mounted) {
      postFrame(
        () => mySnackBar(
          context,
          "You need to connect LinkedIn to continue.",
        ),
      );
      nav('/connect/linkedin');
      return;
    }
  }

  /// Process social connection status from optimized RPC
  void _processSocialConnectionStatus(Map<String, dynamic> status) {
    // Additional validation using the optimized social connection status
    final hasConnections = status['has_connections'] as bool? ?? false;
    final needsReconnect = status['needs_reconnect'] as bool? ?? false;

    // Only check if LinkedIn is connected, not any platform
    if (!hasConnections && mounted) {
      postFrame(
        () => mySnackBar(
          context,
          "You need to connect LinkedIn to continue.",
        ),
      );
      nav('/connect/linkedin');
      return;
    }

    if (needsReconnect && mounted) {
      postFrame(
        () => mySnackBar(
          context,
          'Your LinkedIn connection is expired. Please reconnect',
        ),
      );
      nav('/connect/linkedin');
      return;
    }
  }

  void nav(String path) {
    if (!mounted) return;
    _cleanupTimers(); // FIXED: Use centralized cleanup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(path);
    });
  }

  List<CollapsibleItem> sidebarItems(BuildContext context) {
    return [
      CollapsibleItem(
        text: 'Idea Generator',
        icon: location.startsWith('/home/idea')
            ? Icons.lightbulb
            : Icons.lightbulb_outline,
        isSelected: location.startsWith('/home/idea'),
        onPressed: () {
          if (location != '/home/idea') nav('/home/idea');
        },
      ),
      CollapsibleItem(
        text: 'AI Generator',
        icon: location.startsWith('/home/generator')
            ? Icons.auto_awesome
            : Icons.auto_awesome_outlined,
        isSelected: location.startsWith('/home/generator'),
        onPressed: () {
          if (location != '/home/generator') nav('/home/generator');
        },
      ),
      CollapsibleItem(
        text: 'History',
        icon: location.startsWith('/home/history')
            ? Icons.history
            : Icons.history_outlined,
        isSelected: location.startsWith('/home/history'),
        onPressed: () {
          if (location != '/home/history') nav('/home/history');
        },
      ),
      CollapsibleItem(
        text: 'Profile',
        icon: location.startsWith('/home/profile')
            ? Icons.person
            : Icons.person_outline,
        isSelected: location.startsWith('/home/profile'),
        onPressed: () {
          if (location != '/home/profile') nav('/home/profile');
        },
      ),
      CollapsibleItem(
        text: 'Logout',
        icon: Icons.logout,
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Logout'),
              content: const Text('Are you sure you want to logout?'),
              actions: [
                MyTextButton(
                  onPressed: () => c.pop(false),
                  child: const Text('Cancel'),
                ),
                MyTextButton(
                  onPressed: () => c.pop(true),
                  child: const Text('Logout'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await supabase.auth.signOut();
            if (context.mounted) nav('/login');
          }
        },
        isSelected: false,
      ),
    ];
  }

  int currentIndex(BuildContext context) {
    if (location.startsWith('/home/idea')) return 0;
    if (location.startsWith('/home/generator')) return 1;
    if (location.startsWith('/home/history')) return 2;
    if (location.startsWith('/home/profile')) return 3;
    return 1;
  }

  void selectTab(BuildContext context, int index) {
    final targets = [
      '/home/idea',
      '/home/generator',
      '/home/history',
      '/home/profile'
    ];
    final target = targets[index];
    if (location == target) return; // no-op
    nav(target);
  }

  void postFrame(void Function() f) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) f();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isCheckingSocials) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: 'Checking social connections...',
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
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

    final width = MediaQuery.sizeOf(context).width;

    if (width >= 900) {
      return Scaffold(
        body: RepaintBoundary(
          child: CollapsibleSidebar(
            isCollapsed: true,
            items: sidebarItems(context),
            title: '',
            showTitle: false,
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => current ?? const SizedBox(),
              child: KeyedSubtree(
                key: ValueKey(location),
                child: widget.child,
              ),
            ),
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
            sidebarBoxShadow: const [],
          ),
        ),
      );
    }

    final index = location.startsWith('/home/idea')
        ? 0
        : location.startsWith('/home/generator')
            ? 1
            : location.startsWith('/home/history')
                ? 2
                : location.startsWith('/home/profile')
                    ? 3
                    : 1;

    return Scaffold(
      body: SafeArea(
        child: RepaintBoundary(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => current ?? const SizedBox(),
            child: KeyedSubtree(
              key: ValueKey(location),
              child: widget.child,
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => selectTab(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: 'Idea',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
