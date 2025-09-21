import 'package:blob/brand_profile_draft.dart';
import 'package:blob/data/category_and_subcategory_options.dart';
import 'package:blob/pages/steps/selection_step.dart';
import 'package:blob/pages/steps/brand_name_step.dart';
import 'package:blob/pages/steps/brand_color_step.dart';
import 'package:blob/pages/steps/target_posts_per_week.dart';
import 'package:blob/pages/steps/timezone_step.dart';
import 'package:blob/pages/steps/done_step.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key, this.incompleteOnly = false});
  final bool incompleteOnly;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  // OPT: cache client (micro perf, avoids repeated getters).
  final SupabaseClient supabase = Supabase.instance.client; // OPT

  int currentStep = 0;
  bool ready = false;
  List<Widget Function(BrandProfileDraft)> flowSteps = [];

  // FIXED: Use atomic operations to prevent race conditions
  void next() {
    if (!mounted) return;
    setState(() {
      if (currentStep < flowSteps.length - 1) {
        currentStep++;
      }
    });
  }

  void back() {
    if (!mounted) return;
    setState(() {
      if (currentStep > 0) {
        currentStep--;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    fetchProfileAndBuildSteps(); // OPT
  }

  // OPT: lightweight retry with backoff + jitter for transient network hiccups.
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
    throw lastError ?? Exception('Unknown error'); // OPT
  }

  Future<void> fetchProfileAndBuildSteps() async {
    // OPT: do not block onboarding if session is missing; proceed with empty profile.
    final user = supabase.auth.currentUser; // OPT

    Map<String, dynamic>? profile;
    if (user != null) {
      try {
        // OPT: project only required columns to reduce payload.
        profile = await retryAsync(
          () => supabase
              .from('brand_profiles')
              .select(
                'persona,category,subcategory,primary_goal,brand_name,primary_color,voice_tags,content_types,target_posts_per_week,timezone',
              ) // OPT
              .eq('user_id', user.id)
              .maybeSingle(),
        );
      } catch (_) {
        // OPT: on repeated transient failure, fall back to empty profile to keep flow usable.
        profile = null; // OPT
      }
    } else {
      profile = null; // OPT
    }

    bool empty(dynamic v) =>
        v == null ||
        (v is String && v.trim().isEmpty) ||
        (v is List && v.isEmpty) ||
        (v is int && v == 0);

    final List<Widget Function(BrandProfileDraft)> steps = [];

    void addStepIf(bool shouldAdd, Widget Function(BrandProfileDraft) builder) {
      if (!widget.incompleteOnly || shouldAdd) {
        steps.add(builder);
      }
    }

    addStepIf(
      empty(profile?['persona']),
      (d) => SelectionStep(
        title: 'Which best describes you?',
        options: const ['Solo Creator', 'SMB Founder', 'Agency Freelancer'],
        fatherProperty: 'persona',
        onNext: next,
        onSelection: (d, option) {
          d.persona = option;
          d.category = '';
          d.subcategory = '';
          d.notify();
        },
        getSelectedOptions: (d) => d.persona.isNotEmpty ? [d.persona] : [],
        isEditing: false,
      ),
    );

    addStepIf(empty(profile?['category']), (d) {
      final finalPersona =
          d.persona.isNotEmpty ? d.persona : (profile?['persona'] ?? '');
      final label = finalPersona == 'Solo Creator'
          ? 'Content'
          : finalPersona == 'SMB Founder'
              ? 'Business'
              : 'Agency';
      final title = 'What is your $label about?';
      return SelectionStep(
        title: title,
        options: getCategoryOptions(finalPersona),
        fatherProperty: 'category',
        onNext: next,
        onSelection: (d, option) => d.category = option,
        getSelectedOptions: (d) => d.category.isNotEmpty ? [d.category] : [],
        isEditing: false,
      );
    });

    addStepIf(
      empty(profile?['subcategory']),
      (d) => SelectionStep(
        title: 'Choose a specific type or focus:',
        options: getSubcategoryOptions(
          d.category.isNotEmpty ? d.category : profile?['category'] ?? '',
        ),
        fatherProperty: 'subcategory',
        onNext: next,
        onSelection: (d, option) => d.subcategory = option,
        getSelectedOptions: (d) =>
            d.subcategory.isNotEmpty ? [d.subcategory] : [],
        isEditing: false,
      ),
    );

    addStepIf(
      empty(profile?['primary_goal']),
      (d) => SelectionStep(
        title: 'Biggest outcome you want from Blob?',
        options: const [
          'Grow Audience',
          'Post Consistently',
          'Save Time',
          'Richer Analytics',
          'Manage Clients',
        ],
        fatherProperty: 'primary-goal',
        onNext: next,
        onSelection: (d, option) => d.primary_goal = option,
        getSelectedOptions: (d) =>
            d.primary_goal.isNotEmpty ? [d.primary_goal] : [],
        isEditing: false,
      ),
    );

    addStepIf(
      empty(profile?['brand_name']),
      (_) => BrandNameStep(onNext: next),
    );

    addStepIf(
      empty(profile?['primary_color']),
      (_) => BrandColorStep(onNext: next),
    );

    addStepIf(
      empty(profile?['voice_tags']),
      (d) => SelectionStep(
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
        onNext: next,
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
        isEditing: false,
      ),
    );

    addStepIf(
      empty(profile?['content_types']),
      (d) => SelectionStep(
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
        onNext: next,
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
        isEditing: false,
      ),
    );

    addStepIf(
      empty(profile?['target_posts_per_week']),
      (_) => TargetPostPerWeekPage(onNext: next),
    );

    addStepIf(empty(profile?['timezone']), (_) => TimezoneStep(onNext: next));

    steps.add((_) => const DoneStep()); // always end with Done

    if (!mounted) return;
    setState(() {
      flowSteps = steps;
      ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // OPT: use read so the whole scaffold doesn't rebuild on every draft change.
    final d = context.read<BrandProfileDraft>();

    final total = flowSteps.isEmpty ? 1 : flowSteps.length;
    final progress = (currentStep + 1) / total;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Top Progress Bar
          TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            tween: Tween<double>(begin: 0, end: progress),
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: lightColor,
              valueColor: AlwaysStoppedAnimation<Color>(darkColor),
            ),
          ),

          // Step Content with skeleton
          Expanded(
            child: AutoSkeleton(
              enabled: !ready,
              preserveSize: true,
              clipPadding: const EdgeInsets.symmetric(vertical: 24),
              child: !ready
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Column(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey<int>(currentStep),
                        child: flowSteps.isNotEmpty &&
                                currentStep < flowSteps.length
                            ? flowSteps[currentStep](d)
                            : const SizedBox.shrink(),
                      ),
                    ),
            ),
          ),

          // Footer Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: currentStep > 0
                      ? MyTextButton(
                          key: const ValueKey('back-button'),
                          onPressed: back,
                          child: const Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : const SizedBox(width: 72),
                ),
                const SizedBox(width: 72),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
