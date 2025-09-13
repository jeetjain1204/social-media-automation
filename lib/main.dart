// main.dart
import 'dart:async';
import 'dart:convert';
import 'package:blob/platform/url_strategy_stub.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:blob/utils/colors.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/circular_progress_indicator.dart';

import 'package:blob/data/category_and_subcategory_options.dart';
import 'package:blob/pages/steps/onboarding_flow.dart';
import 'package:blob/pages/steps/selection_step.dart';
import 'package:blob/pages/steps/brand_color_step.dart';
import 'package:blob/pages/steps/brand_name_step.dart';
import 'package:blob/pages/steps/target_posts_per_week.dart';
import 'package:blob/pages/steps/timezone_step.dart';

import 'package:blob/pages/free_trial_page.dart';
import 'package:blob/pages/payment_page.dart';
import 'package:blob/pages/platform_page.dart';

import 'package:blob/pages/auth/login_page.dart';
import 'package:blob/pages/auth/sign_up_page.dart';

import 'package:blob/pages/connect/connect_page.dart';
import 'package:blob/pages/connect/connect_linkedin_page.dart';
import 'package:blob/pages/connect/connect_meta_page.dart';
import 'package:blob/pages/connect/select_pages.dart';
import 'package:blob/pages/connect/connect_linkedin_pages_page.dart';

import 'package:blob/main_page.dart';

import 'brand_profile_draft.dart';
import 'package:blob/provider/clear_notifier.dart';
import 'package:blob/provider/foreground_provider.dart';
import 'package:blob/provider/idea_provider.dart';
import 'package:blob/provider/profile_provider.dart';

// ---------- Deferred (big) pages ----------
import 'package:blob/pages/ai_generator/ai_generator_page.dart' deferred as gen;
import 'package:blob/pages/ai_generator/idea_generator_page.dart'
    deferred as ideas;
import 'package:blob/pages/profile_page.dart' deferred as prof;
import 'package:blob/pages/history_page.dart' deferred as hist;
import 'package:blob/pages/post_page.dart' deferred as post;

// TODO: CONVERT THIS TO APP AND PUBLISH ON PLAY STORE
// TODO: MAKE PAYMENTS AND OTHER FUNCTIONS UNHACKABLE AND COMPLETELY SECURE
// TODO: POST REAL HISTORY FETCH (NOT CONFIRMED)
// TODO: PERSONA ADAPTATION BASED ON EXISTING PROFILE (IF AVAILABLE)
// TODO: ENGINE

// TODO: ADD TEMPLATES (STRUCTURE OF ANSWER TO OPTIMISE FOR SPECIFIC THINGS (REACH/HOOK/ENGAGEMENT)) IN TEXT GENERATION (FIRST)

// ---------- App bootstrap ----------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ehgginqelbgrzfrzbmis.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVoZ2dpbnFlbGJncnpmcnpibWlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY3MDM4ODEsImV4cCI6MjA2MjI3OTg4MX0.SpR6qfl345Ra2RyMQ2SsqfZJ-gnA66_vwDz347tuWlI',
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  GoRouter.optionURLReflectsImperativeAPIs = true;

  configureUrlStrategy();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProfileNotifier()),
        ChangeNotifierProvider(create: (_) => ForegroundNotifier()),
        ChangeNotifierProvider(create: (_) => IdeaNotifier()),
        ChangeNotifierProvider(create: (_) => ClearNotifier()),
        ChangeNotifierProvider(create: (_) => BrandProfileDraft()),
      ],
      child: const MyApp(),
    ),
  );
}

// ---------- Small helpers ----------
Future<Widget> _deferredPage(Future<void> lib, Widget Function() build) async {
  await lib;
  return build();
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// In‑memory + SharedPreferences profile cache used by redirect()
class _ProfileCache {
  Map<String, dynamic>? _mem;
  bool _prefsLoaded = false;

  Future<Map<String, dynamic>?> getOrLoad(
    String userId, {
    required Future<Map<String, dynamic>?> Function() networkFetchOnce,
  }) async {
    if (_mem != null) return _mem;

    if (!_prefsLoaded) {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('cached_profile_$userId');
      if (raw != null) {
        try {
          _mem = Map<String, dynamic>.from(jsonDecode(raw));
        } catch (_) {}
      }
      _prefsLoaded = true;
      if (_mem != null) return _mem;
    }

    _mem = await networkFetchOnce();
    if (_mem != null) {
      final p = await SharedPreferences.getInstance();
      try {
        p.setString('cached_profile_$userId', jsonEncode(_mem));
      } catch (_) {}
    }
    return _mem;
  }

  void set(Map<String, dynamic> profile, String userId) async {
    _mem = profile;
    final p = await SharedPreferences.getInstance();
    try {
      p.setString('cached_profile_$userId', jsonEncode(profile));
    } catch (_) {}
  }

  void clear(String userId) async {
    _mem = null;
    final p = await SharedPreferences.getInstance();
    p.remove('cached_profile_$userId');
  }
}

final _profileCache = _ProfileCache();

// ---------- Router ----------
final router = GoRouter(
  initialLocation: '/home/generator',
  refreshListenable: GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  ),
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainPage(child: child),
      routes: [
        GoRoute(path: '/', redirect: (_, __) => '/home/generator'),
        GoRoute(path: '/home', redirect: (_, __) => '/home/generator'),

        // Idea Generator (deferred)
        GoRoute(
          path: '/home/idea',
          pageBuilder: (_, __) => NoTransitionPage(
            child: FutureBuilder(
              future: _deferredPage(
                ideas.loadLibrary(),
                () => ideas.IdeaGeneratorPage(),
              ),
              builder: (c, s) => s.connectionState == ConnectionState.done
                  ? s.data as Widget
                  : const MyCircularProgressIndicator(size: 60),
            ),
          ),
        ),

        // AI Generator (deferred)
        GoRoute(
          path: '/home/generator',
          pageBuilder: (_, __) => NoTransitionPage(
            child: FutureBuilder(
              future: _deferredPage(
                gen.loadLibrary(),
                () => gen.AIGeneratorPage(),
              ),
              builder: (c, s) => s.connectionState == ConnectionState.done
                  ? s.data as Widget
                  : const MyCircularProgressIndicator(size: 60),
            ),
          ),
        ),

        // History (deferred)
        GoRoute(
          path: '/home/history',
          pageBuilder: (_, __) => NoTransitionPage(
            child: FutureBuilder(
              future: _deferredPage(
                hist.loadLibrary(),
                () => hist.HistoryPage(),
              ),
              builder: (c, s) => s.connectionState == ConnectionState.done
                  ? s.data as Widget
                  : const MyCircularProgressIndicator(size: 60),
            ),
          ),
        ),

        // Profile (deferred)
        GoRoute(
          path: '/home/profile',
          pageBuilder: (_, __) => NoTransitionPage(
            child: FutureBuilder(
              future: _deferredPage(
                prof.loadLibrary(),
                () => prof.ProfilePage(),
              ),
              builder: (c, s) => s.connectionState == ConnectionState.done
                  ? s.data as Widget
                  : const MyCircularProgressIndicator(size: 60),
            ),
          ),
        ),

        // Post details (deferred)
        GoRoute(
          path: '/home/history/post/:type/:id',
          pageBuilder: (context, st) => NoTransitionPage(
            child: FutureBuilder(
              future: _deferredPage(
                post.loadLibrary(),
                () => post.PostPage(
                  postId: st.pathParameters['id']!,
                  type: st.pathParameters['type']!,
                ),
              ),
              builder: (c, s) => s.connectionState == ConnectionState.done
                  ? s.data as Widget
                  : const MyCircularProgressIndicator(size: 60),
            ),
          ),
        ),
      ],
    ),

    // Auth
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(path: '/signup', builder: (_, __) => const SignUpPage()),

    // Onboarding
    GoRoute(
      path: '/onboarding',
      builder: (context, state) {
        final isIncomplete = state.uri.queryParameters['mode'] == 'incomplete';
        return OnboardingFlow(incompleteOnly: isIncomplete);
      },
    ),
    GoRoute(
      path: '/onboarding/persona',
      builder: (context, state) {
        final isEditing = state.uri.queryParameters['isEditing'] == 'true';
        return SelectionStep(
          title: 'Which best describes you?',
          options: const ['Solo Creator', 'SMB Founder', 'Agency Freelancer'],
          fatherProperty: 'persona',
          onNext: () =>
              context.push('/onboarding/category/?isEditing=$isEditing'),
          onSelection: (d, option) => d.updateMany(() {
            d.persona = option;
            d.category = '';
            d.subcategory = '';
            d.updatedPersona = true;
            d.updatedCategory = false;
            d.updatedSubcategory = false;
          }),
          getSelectedOptions: (d) => d.persona.isNotEmpty ? [d.persona] : [],
          isEditing: isEditing,
        );
      },
    ),
    GoRoute(
      path: '/onboarding/category',
      builder: (context, state) {
        final isEditing = state.uri.queryParameters['isEditing'] == 'true';
        final draft = context.read<BrandProfileDraft>();

        Future<Widget> buildStep() async {
          if (draft.persona.isEmpty) {
            await loadPersonaIfEmpty(draft);
          }
          return SelectionStep(
            title:
                'What is your ${draft.persona == 'Solo Creator' ? 'Content' : draft.persona == 'SMB Founder' ? 'Business' : 'Agency'} about?',
            options: getCategoryOptions(draft.persona),
            fatherProperty: 'category',
            onNext: () => context.push(
              '/onboarding/subcategory${isEditing ? '?isEditing=true' : ''}',
            ),
            onSelection: (d, option) => d.updateMany(() {
              d.category = option;
              d.subcategory = '';
              d.updatedCategory = true;
              d.updatedSubcategory = false;
            }),
            getSelectedOptions: (d) =>
                d.category.isNotEmpty ? [d.category] : [],
            isEditing: false,
          );
        }

        return FutureBuilder(
          future: buildStep(),
          builder: (c, s) => s.connectionState == ConnectionState.done
              ? s.data as Widget
              : const MyCircularProgressIndicator(size: 50),
        );
      },
    ),
    GoRoute(
      path: '/onboarding/subcategory',
      builder: (context, state) {
        final isEditing = state.uri.queryParameters['isEditing'] == 'true';
        final draft = context.read<BrandProfileDraft>();

        Future<Widget> buildStep() async {
          if (draft.category.isEmpty) {
            await loadCategoryIfEmpty(draft);
          }
          return SelectionStep(
            title: 'Choose a specific type or focus:',
            options: getSubcategoryOptions(draft.category),
            fatherProperty: 'subcategory',
            onNext: () async {
              if (isEditing) {
                final supa = Supabase.instance.client;
                final userId = supa.auth.currentUser?.id;
                if (userId != null) {
                  final updateData = <String, dynamic>{};
                  if (draft.updatedPersona)
                    updateData['persona'] = draft.persona;
                  if (draft.updatedCategory)
                    updateData['category'] = draft.category;
                  if (draft.updatedSubcategory)
                    updateData['subcategory'] = draft.subcategory;
                  if (updateData.isNotEmpty) {
                    await supa
                        .from('brand_profiles')
                        .update(updateData)
                        .eq('user_id', userId);
                    if (context.mounted)
                      context.read<ProfileNotifier>().notifyProfileUpdated();
                  }
                }
                draft.updateMany(() {
                  draft.updatedPersona = false;
                  draft.updatedCategory = false;
                  draft.updatedSubcategory = false;
                });
              }
              if (context.mounted)
                context.go(isEditing ? '/home/profile' : '/onboarding/goal');
            },
            onSelection: (d, option) => d.updateMany(() {
              d.subcategory = option;
              d.updatedSubcategory = true;
            }),
            getSelectedOptions: (d) =>
                d.subcategory.isNotEmpty ? [d.subcategory] : [],
            isEditing: false,
          );
        }

        return FutureBuilder(
          future: buildStep(),
          builder: (c, s) => s.connectionState == ConnectionState.done
              ? s.data as Widget
              : const MyCircularProgressIndicator(size: 50),
        );
      },
    ),
    GoRoute(
      path: '/onboarding/primary-goal',
      builder: (context, __) => SelectionStep(
        title: 'Biggest outcome you want from Blob?',
        options: const [
          'Grow Audience',
          'Post Consistently',
          'Save Time',
          'Richer Analytics',
          'Manage Clients',
        ],
        fatherProperty: 'primary-goal',
        onNext: () async {
          final draft = context.read<BrandProfileDraft>();
          final supa = Supabase.instance.client;
          final userId = supa.auth.currentUser!.id;
          await supa.from('brand_profiles').update(
              {'primary_goal': draft.primary_goal}).eq('user_id', userId);
          if (context.mounted) context.go('/home/profile');
        },
        onSelection: (d, option) => d.primary_goal = option,
        getSelectedOptions: (d) =>
            d.primary_goal.isNotEmpty ? [d.primary_goal] : [],
        isEditing: true,
      ),
    ),
    GoRoute(
      path: '/onboarding/brand-name',
      builder: (context, __) => BrandNameStep(
        onNext: () async {
          final supabase = Supabase.instance.client;
          final storage = supabase.storage;
          final userId = supabase.auth.currentUser?.id;
          if (userId == null) {
            mySnackBar(context, 'User not logged in');
            return;
          }

          String uploadKey = '';
          String brandKitId = '';
          final draft = context.read<BrandProfileDraft>();

          try {
            final brandKitRes = await supabase
                .schema('brand_kit')
                .from('brand_kits')
                .select('id')
                .eq('user_id', userId)
                .maybeSingle()
                .timeout(const Duration(seconds: 10));

            if (brandKitRes == null) {
              final newKitRes = await supabase
                  .schema('brand_kit')
                  .from('brand_kits')
                  .insert({'user_id': userId, 'brand_name': draft.brand_name})
                  .select('id')
                  .maybeSingle()
                  .timeout(const Duration(seconds: 10));

              if (newKitRes == null || newKitRes['id'] == null) {
                if (context.mounted) {
                  mySnackBar(
                    context,
                    'Failed to create Brand Kit. Please contact support!',
                  );
                }
                return;
              }
              brandKitId = newKitRes['id'];
            } else {
              brandKitId = brandKitRes['id'];
            }

            if (draft.brand_logo_bytes != null &&
                draft.brand_logo_path != null) {
              uploadKey =
                  'users/$userId/kits/$brandKitId/logo/${path.basename(draft.brand_logo_path!)}';

              await storage.from('brand-kits').uploadBinary(
                    uploadKey,
                    draft.brand_logo_bytes!,
                    fileOptions: const FileOptions(upsert: true),
                  );

              draft.brand_logo_path = uploadKey;
              draft.notify();
            }

            final updatePayload = {
              'brand_name': draft.brand_name,
              'brand_logo_path': draft.brand_logo_path,
            };

            await supabase
                .from('brand_profiles')
                .update(updatePayload)
                .eq('user_id', userId)
                .timeout(const Duration(seconds: 10));

            await supabase
                .schema('brand_kit')
                .from('brand_kits')
                .update(updatePayload)
                .eq('user_id', userId)
                .timeout(const Duration(seconds: 10));

            if (context.mounted) {
              context.read<ProfileNotifier>().notifyProfileUpdated();
              context.go('/home/profile');
            }
          } catch (e) {
            if (uploadKey.isNotEmpty) {
              await storage.from('brand-kits').remove([uploadKey]);
            }
            if (context.mounted) {
              mySnackBar(context, 'Something went wrong: ${e.toString()}');
            }
          }
        },
      ),
    ),
    GoRoute(
      path: '/onboarding/primary-color',
      builder: (context, __) => BrandColorStep(
        onNext: () async {
          final draft = context.read<BrandProfileDraft>();
          final supa = Supabase.instance.client;
          final userId = supa.auth.currentUser!.id;
          await supa.from('brand_profiles').update(
              {'primary_color': draft.primary_color}).eq('user_id', userId);
          if (context.mounted) {
            context.read<ProfileNotifier>().notifyProfileUpdated();
            context.go('/home/profile');
          }
        },
      ),
    ),
    GoRoute(
      path: '/onboarding/voice-tags',
      builder: (context, __) => SelectionStep(
        title: 'Choose words that fit your brand voice',
        options: const [
          'Friendly',
          'Professional',
          'Playful',
          'Inspiring',
          'Authoritative',
          'Casual',
        ],
        fatherProperty: 'voice_tags',
        onNext: () async {
          final draft = context.read<BrandProfileDraft>();
          final supa = Supabase.instance.client;
          final userId = supa.auth.currentUser!.id;
          await supa
              .from('brand_profiles')
              .update({'voice_tags': draft.voice_tags}).eq('user_id', userId);
          if (context.mounted) context.go('/home/profile');
        },
        allowMultipleSelection: true,
        showNextButton: true,
        onSelection: (d, option) {
          if (d.voice_tags.contains(option)) {
            d.voice_tags.remove(option);
          } else {
            d.voice_tags.add(option);
          }
        },
        getSelectedOptions: (d) => d.voice_tags,
        isEditing: true,
      ),
    ),
    GoRoute(
      path: '/onboarding/content-types',
      builder: (context, __) => SelectionStep(
        title: 'What content formats do you care about?',
        options: const [
          'Text',
          'Images',
          'Short Video',
          'Long Video',
          'Stories',
          'Carousels',
        ],
        fatherProperty: 'content_types',
        onNext: () async {
          final draft = context.read<BrandProfileDraft>();
          final supa = Supabase.instance.client;
          final userId = supa.auth.currentUser!.id;
          await supa.from('brand_profiles').update(
              {'content_types': draft.content_types}).eq('user_id', userId);
          if (context.mounted) context.go('/home/profile');
        },
        allowMultipleSelection: true,
        showNextButton: true,
        onSelection: (d, option) {
          if (d.content_types.contains(option)) {
            d.content_types.remove(option);
          } else {
            d.content_types.add(option);
          }
        },
        getSelectedOptions: (d) => d.content_types,
        isEditing: true,
      ),
    ),
    GoRoute(
      path: '/onboarding/target-posts-per-week',
      builder: (context, __) => TargetPostPerWeekPage(
        onNext: () async {
          final draft = context.read<BrandProfileDraft>();
          final supa = Supabase.instance.client;
          final userId = supa.auth.currentUser!.id;
          await supa.from('brand_profiles').update({
            'target_posts_per_week': draft.target_posts_per_week
          }).eq('user_id', userId);
          if (context.mounted) {
            context.read<ProfileNotifier>().notifyProfileUpdated();
            context.go('/home/profile');
          }
        },
      ),
    ),
    GoRoute(
      path: '/onboarding/timezone',
      builder: (context, __) => TimezoneStep(
        onNext: () async {
          final draft = context.read<BrandProfileDraft>();
          final supa = Supabase.instance.client;
          final userId = supa.auth.currentUser!.id;
          await supa
              .from('brand_profiles')
              .update({'timezone': draft.timezone}).eq('user_id', userId);
          if (context.mounted) {
            context.read<ProfileNotifier>().notifyProfileUpdated();
            context.go('/home/profile');
          }
        },
      ),
    ),

    // Connect flows
    GoRoute(path: '/connect', builder: (_, __) => const ConnectPage()),
    GoRoute(
      path: '/connect/linkedin',
      builder: (_, __) => const ConnectLinkedInPage(),
    ),
    GoRoute(path: '/connect/meta', builder: (_, __) => const ConnectMetaPage()),
    GoRoute(
      path: '/connect-linkedin-pages',
      builder: (_, __) => const ConnectLinkedInPagesPage(),
    ),

    GoRoute(
      path: '/select-pages',
      builder: (_, state) {
        final m = state.extra as Map<String, dynamic>?;
        if (m == null) {
          return const SelectPages(platform: '', pages: null);
        }
        return SelectPages(
          platform: m['platform'] as String? ?? '',
          nonce: m['nonce'] as String?,
          pages: (m['pages'] as List?)?.cast<Map<String, dynamic>>(),
          accessToken: m['accessToken'] as String?,
          personUrn: m['personUrn'] as String?,
        );
      },
    ),

    // Misc
    GoRoute(path: '/free-trial', builder: (_, __) => const FreeTrialPage()),
    GoRoute(path: '/payment', builder: (_, __) => const PaymentPage()),
    GoRoute(
      path: '/platform/:platformName',
      builder: (_, state) =>
          PlatformPage(name: state.pathParameters['platformName']!),
    ),
  ],
  redirect: (context, state) async {
    // Pass through LinkedIn callback params
    if (state.uri.queryParameters.containsKey('access_token') ||
        state.uri.queryParameters.containsKey('person_urn')) {
      final access = state.uri.queryParameters['access_token'] ?? '';
      final urn = state.uri.queryParameters['person_urn'] ?? '';
      return '/connect/linkedin?access_token=$access&person_urn=$urn';
    }

    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;

    final isAuthRoute = state.matchedLocation.startsWith('/login') ||
        state.matchedLocation.startsWith('/signup');

    if (user == null) {
      return isAuthRoute ? null : '/login';
    }

    // Allow-listed routes (avoid useless fetches)
    final allowedPrefix = ['/home', '/onboarding'];
    if (allowedPrefix.any((r) => state.matchedLocation.startsWith(r))) {
      // If a “home/*” page, we still need to check onboarding completeness. Use cache first.
      final allowedRoutesNoCheck = <String>[
        '/home/generator',
        '/home/idea',
        '/home/history',
        '/home/profile',
      ];
      if (allowedRoutesNoCheck.any(
        (r) => state.matchedLocation.startsWith(r),
      )) {
        // Do not block navigation—let the page mount while we validate in background.
      }
    }

    // Pull profile from cache → prefs → network (once) with timeout
    final profile = await _profileCache.getOrLoad(
      user.id,
      networkFetchOnce: () async {
        try {
          return await supa
              .from('brand_profiles')
              .select(
                'persona, primary_goal, brand_name, primary_color, voice_tags, content_types, target_posts_per_week, category, subcategory, timezone',
              )
              .eq('user_id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 6), onTimeout: () => null);
        } catch (_) {
          return null;
        }
      },
    );

    bool empty(dynamic v) =>
        v == null ||
        (v is String && v.isEmpty) ||
        (v is List && v.isEmpty) ||
        (v is int && v == 0);

    final isIncomplete = profile == null ||
        empty(profile['persona']) ||
        empty(profile['primary_goal']) ||
        empty(profile['brand_name']) ||
        empty(profile['primary_color']) ||
        empty(profile['voice_tags']) ||
        empty(profile['content_types']) ||
        empty(profile['target_posts_per_week']) ||
        empty(profile['category']) ||
        empty(profile['subcategory']) ||
        empty(profile['timezone']);

    if (isIncomplete) {
      return '/onboarding?mode=incomplete';
    }

    // Already logged in & complete; don’t let them sit on auth pages
    if (isAuthRoute) return '/home/generator';

    return null;
  },
);

// ---------- async helpers (unchanged logic) ----------
Future<String?> loadPersonaIfEmpty(BrandProfileDraft draft) async {
  if (draft.persona.isNotEmpty) return draft.persona;
  final profileData = await Supabase.instance.client
      .from('brand_profiles')
      .select('persona')
      .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
      .maybeSingle()
      .timeout(const Duration(seconds: 6), onTimeout: () => null);
  if (profileData != null) {
    draft.persona = profileData['persona'] as String? ?? '';
    draft.notify();
    return draft.persona;
  }
  return null;
}

Future<String?> loadCategoryIfEmpty(BrandProfileDraft draft) async {
  if (draft.category.isNotEmpty) return draft.category;
  final profileData = await Supabase.instance.client
      .from('brand_profiles')
      .select('category')
      .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
      .maybeSingle()
      .timeout(const Duration(seconds: 6), onTimeout: () => null);
  if (profileData != null) {
    draft.category = profileData['category'] as String? ?? '';
    draft.notify();
    return draft.category;
  }
  return null;
}

// ---------- App widget ----------
final _appTheme = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: darkColor,
  scrollbarTheme: ScrollbarThemeData(
    thickness: WidgetStateProperty.all(3),
    radius: const Radius.circular(100),
    trackColor: WidgetStateProperty.all(lightColor),
    trackBorderColor: WidgetStateProperty.all(darkColor),
    thumbColor: WidgetStateProperty.all(darkColor),
  ),
  chipTheme: ChipThemeData(
    backgroundColor: lightColor.withOpacity(0.15),
    selectedColor: lightColor.withOpacity(0.5),
    disabledColor: Colors.grey.withOpacity(0.1),
    labelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: darkColor,
    ),
    secondaryLabelStyle: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: darkColor,
    ),
    showCheckmark: false,
    checkmarkColor: Colors.transparent,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    side: BorderSide(color: darkColor.withOpacity(0.15), width: 1),
    selectedShadowColor: Colors.transparent,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    elevation: 0,
    pressElevation: 0,
    iconTheme: const IconThemeData(size: 16),
    avatarBoxConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    deleteIconBoxConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
  ),
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(
      color: darkColor,
      borderRadius: BorderRadius.circular(100),
      border: Border.all(width: 0.25, color: lightColor),
    ),
    textStyle: TextStyle(color: lightColor, fontSize: 12),
  ),
  checkboxTheme: CheckboxThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    side: BorderSide(color: darkColor.withOpacity(0.3), width: 1.5),
    checkColor: MaterialStatePropertyAll<Color>(Colors.white),
    fillColor: MaterialStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.selected)) return darkColor;
      if (states.contains(WidgetState.hovered))
        return darkColor.withOpacity(0.1);
      return lightColor;
    }),
    overlayColor: MaterialStatePropertyAll<Color>(darkColor.withOpacity(0.1)),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  static final PageStorageBucket bucket = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Blob',
      debugShowCheckedModeBanner: false,
      theme: _appTheme,
      routerConfig: router,
      builder: (context, child) {
        return PageStorage(bucket: bucket, child: child!);
      },
    );
  }
}
