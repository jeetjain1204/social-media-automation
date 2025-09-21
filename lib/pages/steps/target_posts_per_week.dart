import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:blob/widgets/my_textfield.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../brand_profile_draft.dart';

class TargetPostPerWeekPage extends StatefulWidget {
  const TargetPostPerWeekPage({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<TargetPostPerWeekPage> createState() => _TargetPostPerWeekPageState();
}

class _TargetPostPerWeekPageState extends State<TargetPostPerWeekPage> {
  // OPT: cache client (avoids repeated getters)
  final SupabaseClient supabase = Supabase.instance.client; // OPT
  final TextEditingController targetPostsPerWeekController =
      TextEditingController(); // OPT

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      html.window.onBeforeUnload.listen((event) {
        (event as html.BeforeUnloadEvent).returnValue = '';
      });
    }
    loadTargetPostsPerWeek(); // OPT
  }

  @override
  void dispose() {
    // OPT: prevent controller leak
    targetPostsPerWeekController.dispose(); // OPT
    super.dispose();
  }

  // OPT: lightweight retry for transient errors
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

  Future<void> loadTargetPostsPerWeek() async {
    final user = supabase.auth.currentUser; // OPT
    if (user == null) return; // OPT: guard missing session

    final profileData = await retryAsync(
      () => supabase
          .from('brand_profiles')
          .select('target_posts_per_week') // OPT: project only needed column
          .eq('user_id', user.id)
          .maybeSingle(),
    );

    if (!mounted || profileData == null) return; // OPT: lifecycle + null guard

    final dynamic val = profileData['target_posts_per_week'];
    if (val != null) {
      targetPostsPerWeekController.text = val.toString();
      // no setState needed; controller updates input directly  // OPT
    }
  }

  @override
  Widget build(BuildContext context) {
    // OPT: read instead of watch so the whole page doesn't rebuild on unrelated draft changes
    final draft = context.read<BrandProfileDraft>(); // OPT

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (_, constraints) {
          final width = constraints.maxWidth; // OPT

          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.0125,
                vertical: 48, // --space-6
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    'How often do you aim to post per week?',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                      height: 1.25,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Input Field
                  MyTextField(
                    width: 200, // keep your existing logic
                    controller: targetPostsPerWeekController,
                    hintText: 'Target Posts Per Week',
                    type: TextInputType.number,
                  ),

                  const SizedBox(height: 48),

                  // Continue Button
                  MyButton(
                    width: width * 0.25,
                    text: 'Continue',
                    isLoading: false,
                    onTap: () {
                      final raw = targetPostsPerWeekController.text.trim();
                      final parsed = int.tryParse(raw);

                      if (parsed == null || parsed <= 0) {
                        return mySnackBar(
                          context,
                          'Enter a valid whole number greater than 0',
                        );
                      }

                      draft.target_posts_per_week = parsed;
                      draft.notify();
                      widget.onNext();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
