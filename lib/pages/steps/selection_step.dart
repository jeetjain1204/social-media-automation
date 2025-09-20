// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:blob/brand_profile_draft.dart';
import 'package:blob/provider/profile_provider.dart';
import 'package:blob/widgets/hoverable_card.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SelectionStep extends StatefulWidget {
  const SelectionStep({
    super.key,
    required this.title,
    required this.options,
    required this.fatherProperty,
    required this.onNext,
    required this.onSelection,
    required this.getSelectedOptions,
    this.allowMultipleSelection = false,
    this.showNextButton = false,
    required this.isEditing,
  });

  final String title;
  final List<String> options;
  final String fatherProperty;
  final VoidCallback onNext;
  final bool allowMultipleSelection;
  final bool showNextButton;
  final Function(BrandProfileDraft, String) onSelection;
  final List<String> Function(BrandProfileDraft) getSelectedOptions;
  final bool isEditing;

  @override
  State<SelectionStep> createState() => _SelectionStepState();
}

class _SelectionStepState extends State<SelectionStep> {
  // OPT: cache Supabase client to avoid repeated getter calls.
  final SupabaseClient supabase = Supabase.instance.client; // OPT
  String? errorMessage;
  bool isUpdating = false;
  bool isNavigating =
      false; // OPT: prevent multi-fire on single-select fast taps

  @override
  void initState() {
    super.initState();
    loadSelectionData(); // OPT
    if (kIsWeb) {
      html.window.onBeforeUnload.listen((event) {
        (event as html.BeforeUnloadEvent).returnValue = '';
      });
    }
  }

  // OPT: minimal retry helper (exponential backoff + jitter) without new files.
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

  Future<void> loadSelectionData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // OPT: project only the needed column(s) for this step (huge payload cut).
    final String column = widget.fatherProperty;
    final String projected = switch (column) {
      'persona' => 'persona',
      'category' => 'category',
      'subcategory' =>
        'subcategory,category,persona', // need deps to keep logic
      'primary-goal' => 'primary_goal',
      'voice_tags' => 'voice_tags',
      'content_types' => 'content_types',
      _ => column, // safe default
    }; // OPT

    final profile = await retryAsync(
      () => supabase
          .from('brand_profiles')
          .select(projected)
          .eq('user_id', userId)
          .maybeSingle(),
    );

    if (!mounted || profile == null) return;

    final d = context.read<BrandProfileDraft>();

    // OPT: single switch replaces multi if-else and guards nulls.
    switch (column) {
      case 'persona':
        d.persona = (profile['persona'] as String?) ?? '';
        break;
      case 'category':
        d.category = (profile['category'] as String?) ?? '';
        break;
      case 'subcategory':
        d.persona = (profile['persona'] as String?) ?? d.persona;
        d.category = (profile['category'] as String?) ?? d.category;
        d.subcategory = (profile['subcategory'] as String?) ?? '';
        break;
      case 'primary-goal':
        d.primary_goal = (profile['primary_goal'] as String?) ?? '';
        break;
      case 'voice_tags':
        d.voice_tags
          ..clear()
          ..addAll(
            ((profile['voice_tags'] as List?) ?? const []).map(
              (e) => e.toString(),
            ),
          );
        break;
      case 'content_types':
        d.content_types
          ..clear()
          ..addAll(
            ((profile['content_types'] as List?) ?? const []).map(
              (e) => e.toString(),
            ),
          );
        break;
      default:
        break;
    }
    d.notify(); // keep behavior (downstream UI dependent)
  }

  Future<void> handleNext() async {
    final d = context.read<BrandProfileDraft>();
    final selectedOptions = widget.getSelectedOptions(d);

    if (selectedOptions.isEmpty) {
      setState(
        () => errorMessage = 'Please select at least one option to continue',
      );
      return;
    }

    setState(() {
      isUpdating = true;
      errorMessage = null;
    });

    if (widget.isEditing) {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final column = widget.fatherProperty;
        final columnName = column.replaceAll('-', '_');

        // OPT: wrap updates in retry to ride out transient failures.
        if (column == 'subcategory') {
          final bool personaAvailable = d.persona.isNotEmpty;
          final bool categoryAvailable = d.category.isNotEmpty;
          final String sub = selectedOptions.first;

          await retryAsync(() {
            if (personaAvailable && categoryAvailable) {
              return supabase.from('brand_profiles').update({
                'persona': d.persona,
                'category': d.category,
                'subcategory': sub,
              }).eq('user_id', userId);
            } else if (!personaAvailable && categoryAvailable) {
              return supabase
                  .from('brand_profiles')
                  .update({'category': d.category, 'subcategory': sub}).eq(
                      'user_id', userId);
            } else {
              return supabase
                  .from('brand_profiles')
                  .update({'subcategory': sub}).eq('user_id', userId);
            }
          });
        } else {
          final dynamic newValue = widget.allowMultipleSelection
              ? selectedOptions
              : selectedOptions.first;

          await retryAsync(
            () => supabase
                .from('brand_profiles')
                .update({columnName: newValue}).eq('user_id', userId),
          );
        }

        if (mounted) {
          context.read<ProfileNotifier>().notifyProfileUpdated();
        }
      }
    }

    if (!mounted) return;
    setState(() => isUpdating = false);

    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<BrandProfileDraft>(); // keep reactive for choices
    final selectedOptions = widget.getSelectedOptions(d);
    final options = widget.options; // OPT: local ref

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide = width > 800;

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.05,
              vertical: 48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 960,
                  minHeight: MediaQuery.of(context).size.height - 120,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Title
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: isWide ? 40 : 32,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Optional Instruction
                    if (widget.allowMultipleSelection)
                      Text(
                        'You can select multiple options',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),

                    const SizedBox(height: 48),

                    // Option Grid
                    RepaintBoundary(
                      // OPT: isolate heavy repaint area
                      child: LayoutBuilder(
                        builder: (context, wrap) {
                          final double maxWidth = wrap.maxWidth;
                          final int perRow =
                              (maxWidth / 240).clamp(1, 4).toInt(); // OPT
                          const spacing = 16.0;
                          final double cardWidth =
                              ((maxWidth - spacing * (perRow - 1)) / perRow)
                                  .clamp(140, 260);
                          final double cardHeight = cardWidth; // 1:1

                          return Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            alignment: WrapAlignment.center,
                            children: List.generate(options.length, (i) {
                              final option = options[i];
                              final isSelected = selectedOptions.contains(
                                option,
                              );

                              return SizedBox(
                                width: cardWidth,
                                height: cardHeight,
                                child: HoverableCard(
                                  width: cardWidth,
                                  height: cardHeight,
                                  property: option,
                                  fatherProperty: widget.fatherProperty,
                                  isSelected: isSelected,
                                  onTap: () {
                                    widget.onSelection(d, option);
                                    d.notify();

                                    if (errorMessage != null) {
                                      setState(() => errorMessage = null);
                                    }

                                    if (!widget.allowMultipleSelection) {
                                      // OPT: prevent multiple queued navigations on rapid taps.
                                      if (isNavigating) return; // OPT
                                      isNavigating = true; // OPT
                                      Future.delayed(
                                        const Duration(milliseconds: 80),
                                        () {
                                          if (!mounted) return;
                                          isNavigating = false; // OPT
                                          widget.onNext();
                                        },
                                      );
                                    }
                                  },
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),

                    // Error Message
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: errorMessage != null
                          ? Container(
                              key: const ValueKey('error'),
                              margin: const EdgeInsets.only(top: 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.shade200,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    color: Colors.red.shade600,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      errorMessage!,
                                      style: GoogleFonts.inter(
                                        color: Colors.red.shade700,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('no-error'),
                            ),
                    ),

                    // Continue Button
                    if (widget.showNextButton) ...[
                      const SizedBox(height: 64),
                      MyButton(
                        width: width * 0.25,
                        text: 'Continue',
                        onTap: isUpdating
                            ? null
                            : handleNext, // OPT: idempotent tap
                        isLoading: isUpdating,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
