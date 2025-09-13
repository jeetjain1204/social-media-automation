import 'package:blob/utils/pick_color.dart';
import 'package:blob/utils/colors.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:blob/widgets/my_button.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../brand_profile_draft.dart';

class BrandColorStep extends StatefulWidget {
  const BrandColorStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<BrandColorStep> createState() => _BrandColorStepState();
}

class _BrandColorStepState extends State<BrandColorStep> {
  // OPT: cache the client reference (micro improvement, avoids repeated getters).
  final SupabaseClient supabase = Supabase.instance.client; // OPT

  Color color = darkColor;
  bool isHovering = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      // Keeps existing behavior: warn before unload.
      html.window.onBeforeUnload.listen((event) {
        (event as html.BeforeUnloadEvent).returnValue = '';
      });
    }
    loadColor();
  }

  // OPT: robust hex helpers to prevent dropped leading zeros and keep consistent casing.
  static String colorToHex6(Color c) {
    return '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'; // OPT
  }

  static Color hexToColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    final withAlpha =
        cleaned.length == 6 ? 'FF$cleaned' : cleaned.padLeft(8, 'F');
    final parsed = int.tryParse(withAlpha, radix: 16);
    return parsed == null ? darkColor : Color(parsed); // OPT
  }

  Future<void> loadColor() async {
    final user = supabase.auth.currentUser; // OPT
    if (user == null) return; // OPT: safe-guard

    final profileData = await supabase
        .from('brand_profiles')
        .select('primary_color')
        .eq('user_id', user.id)
        .maybeSingle();

    if (!mounted) return; // OPT: avoid setState after dispose

    if (profileData != null) {
      final String? hexColor = profileData['primary_color'] as String?;
      if (hexColor != null && hexColor.isNotEmpty) {
        setState(() {
          color = hexToColor(hexColor); // OPT
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hex6 = colorToHex6(color); // OPT: compute once per build

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: LayoutBuilder(
          builder: (_, con) => Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(con.maxWidth * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Pick a primary brand colour',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Color Preview
                  GestureDetector(
                    onTap: () async {
                      await pickColor(
                        context: context,
                        initialColor: color,
                        onColorSelected: (picked) {
                          setState(() {
                            color = picked;
                          });
                        },
                      );
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      onEnter: (_) => setState(() => isHovering = true),
                      onExit: (_) => setState(() => isHovering = false),
                      child: Semantics(
                        label: 'Selected brand color: $hex6', // OPT
                        child: AnimatedScale(
                          scale: isHovering ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: isHovering
                                ? const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                    size: 26,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text(
                    hex6, // OPT
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[800],
                    ),
                  ),

                  const SizedBox(height: 32),

                  MyButton(
                    width: con.maxWidth * 0.25,
                    text: 'Continue',
                    onTap: () {
                      context.read<BrandProfileDraft>().primary_color =
                          hex6; // OPT
                      context.read<BrandProfileDraft>().notify();
                      widget.onNext();
                    },
                    isLoading: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
