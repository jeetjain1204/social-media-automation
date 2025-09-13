import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/utils/my_snack_bar.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:blob/widgets/my_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../brand_profile_draft.dart';
import '../../profile_service.dart';

class DoneStep extends StatefulWidget {
  const DoneStep({super.key});

  @override
  State<DoneStep> createState() => _DoneStepState();
}

class _DoneStepState extends State<DoneStep> {
  // OPT: cache client reference (micro perf, avoids repeated getters).
  final SupabaseClient supabase = Supabase.instance.client; // OPT
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Keep existing behavior: warn on page unload.
      html.window.onBeforeUnload.listen((event) {
        (event as html.BeforeUnloadEvent).returnValue = '';
      });
    }
  }

  Future<bool> isProfileIncomplete() async {
    // OPT: short‑circuit if no user (keeps behavior).
    final user = supabase.auth.currentUser;
    if (user == null) return true;

    // OPT: select only needed columns to reduce payload.
    final profile = await supabase
        .from('brand_profiles')
        .select(
          'persona,category,subcategory,primary_goal,brand_name,primary_color,voice_tags,content_types,target_posts_per_week,timezone',
        ) // OPT
        .eq('user_id', user.id)
        .maybeSingle();

    bool empty(dynamic v) =>
        v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty) ||
        (v is int && v == 0);

    return profile == null ||
        empty(profile['persona']) ||
        empty(profile['category']) ||
        empty(profile['subcategory']) ||
        empty(profile['primary_goal']) ||
        // empty(profile['first_platform']) ||
        empty(profile['brand_name']) ||
        // empty(profile['brand_logo_path']) ||
        empty(profile['primary_color']) ||
        empty(profile['voice_tags']) ||
        empty(profile['content_types']) ||
        empty(profile['target_posts_per_week']) ||
        empty(profile['timezone']);
  }

  // OPT: small, local retry helper with exponential backoff + jitter (no new files/classes).
  Future<T> retryAsync<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 200),
  }) async {
    int attempt = 0;
    Object? lastError;
    while (attempt < maxAttempts) {
      try {
        return await task();
      } catch (e) {
        lastError = e;
        attempt++;
        if (attempt >= maxAttempts) break;
        final delayMs = baseDelay.inMilliseconds * (1 << (attempt - 1));
        final jitter = (delayMs * 0.25).toInt();
        final wait = Duration(
          milliseconds: delayMs +
              (jitter == 0
                  ? 0
                  : (DateTime.now().microsecondsSinceEpoch % jitter)),
        );
        await Future.delayed(wait);
      }
    }
    // Re-throw last error to preserve behavior for caller.
    throw lastError ??
        Exception('Unknown error'); // OPT: preserve failure semantics
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<BrandProfileDraft>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Center(
          child: AutoSkeleton(
            enabled: isSaving,
            preserveSize: true,
            clipPadding: const EdgeInsets.symmetric(vertical: 12),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 300),
              tween: Tween(begin: 0.95, end: 1.0),
              curve: Curves.easeOutBack,
              builder: (context, scale, _) {
                return Transform.scale(
                  scale: scale,
                  child: MyButton(
                    width: width * 0.33,
                    text: 'Done & Connect LinkedIn',
                    isLoading: false,
                    onTap: () async {
                      if (isSaving) return;
                      setState(() => isSaving = true);
                      try {
                        await retryAsync(
                          () => ProfileService().upsert(
                            draft,
                            incompleteOnly: false,
                          ),
                        );
                        if (!mounted) return;
                        context.push('/connect/linkedin');
                      } catch (e) {
                        if (!mounted) return;
                        mySnackBar(
                          context,
                          'Couldn’t save your profile. Please try again',
                        );
                      } finally {
                        if (mounted) setState(() => isSaving = false);
                      }
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
