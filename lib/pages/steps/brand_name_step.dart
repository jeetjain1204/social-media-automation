import 'dart:typed_data';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:file_picker/file_picker.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../brand_profile_draft.dart';
import '../../widgets/my_textfield.dart';

class BrandNameStep extends StatefulWidget {
  const BrandNameStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  State<BrandNameStep> createState() => _BrandNameStepState();
}

class _BrandNameStepState extends State<BrandNameStep> {
  // OPT: Cache Supabase client reference (micro perf; avoids repeated getters).
  final SupabaseClient supabase = Supabase.instance.client; // OPT
  final TextEditingController brandNameController = TextEditingController();

  Uint8List? logo;
  bool isLoading = false;
  bool isHovering = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      html.window.onBeforeUnload.listen((event) {
        (event as html.BeforeUnloadEvent).returnValue = '';
      });
    }
    loadBrandName(); // OPT
  }

  @override
  void dispose() {
    // OPT: Prevent controller leak.
    brandNameController.dispose(); // OPT
    super.dispose();
  }

  Future<void> loadBrandName() async {
    // OPT: Guard against null session to avoid crash.
    final user = supabase.auth.currentUser; // OPT
    if (user == null) return; // OPT

    final profileData = await supabase
        .from('brand_profiles')
        .select('brand_name')
        .eq('user_id', user.id)
        .maybeSingle();

    if (!mounted) return; // OPT: avoid setState after dispose

    if (profileData != null) {
      setState(() {
        brandNameController.text = (profileData['brand_name'] as String?) ?? '';
      });
    }
  }

  Future<void> pickLogo(BrandProfileDraft profileDraft) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true, // ensures bytes on web
      );

      final file = result?.files.single;

      // OPT: Web bugfix — rely on bytes (path is often null on web).
      if (result != null && file != null && file.bytes != null) {
        // OPT
        final bytes = file.bytes!;
        if (!mounted) return; // OPT: lifecycle safety
        setState(() {
          logo = bytes;
        });

        // OPT: Keep behavior but make it robust on web (path may be null).
        profileDraft.brand_logo_bytes = bytes; // OPT
        profileDraft.brand_logo_path =
            file.path; // may be null on web; leave as-is
        profileDraft.notify();
      }
    } catch (e) {
      if (!mounted) return;
      mySnackBar(context, 'Failed to pick logo'); // silent, preserves UX
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileDraft = context.read<BrandProfileDraft>();
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: LayoutBuilder(
          builder: (_, c) => Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(c.maxWidth * 0.04),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo Picker
                  GestureDetector(
                    onTap: () async {
                      await pickLogo(profileDraft);
                    },
                    child: Tooltip(
                      message: 'Select Logo',
                      decoration: BoxDecoration(
                        color: darkColor,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => isHovering = true),
                        onExit: (_) => setState(() => isHovering = false),
                        // OPT: Remove onHover setState storm to avoid jank.
                        child: Semantics(
                          label: logo != null
                              ? 'Selected logo'
                              : 'Tap to upload brand logo',
                          child: AnimatedScale(
                            scale: isHovering ? 1.05 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: logo != null
                                    ? [
                                        BoxShadow(
                                          color: darkColor.withOpacity(0.2),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : const [],
                              ),
                              child: CircleAvatar(
                                radius: 48,
                                backgroundColor: lightColor,
                                backgroundImage:
                                    logo != null ? MemoryImage(logo!) : null,
                                child: logo == null
                                    ? Icon(
                                        Icons.camera_alt_outlined,
                                        size: 32,
                                        color: darkColor,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Title
                  Text(
                    'What\'s your brand called?',
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Text Field
                  MyTextField(
                    controller: brandNameController,
                    hintText: 'Brand name',
                    width: c.maxWidth * 0.5,
                    autoFocus: logo != null, // smart focus
                  ),

                  const SizedBox(height: 48),

                  // Continue Button
                  MyButton(
                    width: c.maxWidth * 0.25,
                    text: 'Continue',
                    onTap: isLoading
                        ? null
                        : () async {
                            final name = brandNameController.text.trim();
                            if (name.isEmpty) {
                              mySnackBar(context, 'Enter your Brand Name');
                              return;
                            }

                            setState(() => isLoading = true);

                            // OPT: Minimal work before navigation; preserves behavior.
                            profileDraft.brand_name = name;
                            profileDraft.brand_logo_bytes = logo;
                            profileDraft.notify();

                            widget.onNext();

                            if (!mounted) return;
                            setState(() => isLoading = false);
                          },
                    isLoading: isLoading,
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
