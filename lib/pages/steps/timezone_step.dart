import 'package:blob/widgets/my_button.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_timezone/flutter_native_timezone.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:blob/platform/tz.dart' as tz;
import '../../brand_profile_draft.dart';

class TimezoneStep extends StatefulWidget {
  final VoidCallback onNext;
  const TimezoneStep({super.key, required this.onNext});

  @override
  State<TimezoneStep> createState() => _TimezoneStepState();
}

class _TimezoneStepState extends State<TimezoneStep> {
  String? selectedTimezone;
  bool isLoading = true; // OPT: explicit loading state

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      html.window.onBeforeUnload.listen((event) {
        (event as html.BeforeUnloadEvent).returnValue = '';
      });
    }
    loadTimezone(); // OPT
  }

  Future<String?> detectTimezone() async {
    // native first
    try {
      final tzNative = await FlutterNativeTimezone.getLocalTimezone();
      if (tzNative.isNotEmpty) return tzNative;
    } catch (_) {}

    // web via wrapper
    if (kIsWeb) {
      try {
        final tzWeb = await tz.browserTimeZone();
        if (tzWeb != null && tzWeb.isNotEmpty) return tzWeb;
      } catch (_) {}

      // offset fallback
      final offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
      switch (offsetMinutes) {
        case 330:
          return 'Asia/Kolkata';
        case 0:
          return 'Etc/UTC';
        case 60:
          return 'Europe/Berlin';
        case -300:
          return 'America/New_York';
        default:
          final sign =
              offsetMinutes == 0 ? '' : (offsetMinutes > 0 ? '-' : '+');
          final hours = (offsetMinutes.abs() / 60).round();
          return 'Etc/GMT$sign$hours';
      }
    }

    return 'Etc/UTC';
  }

  Future<void> loadTimezone() async {
    final tz = await detectTimezone();
    if (!mounted) return; // OPT: lifecycle safety
    setState(() {
      selectedTimezone = tz;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (_, c) {
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: c.maxWidth * 0.05,
                vertical: 48,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    selectedTimezone != null
                        ? 'Your timezone is set to'
                        : 'Detecting your timezone...',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1A1A1A),
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Timezone value or loading indicator
                  if (!isLoading && selectedTimezone != null)
                    Text(
                      selectedTimezone!,
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade800,
                      ),
                    )
                  else
                    Shimmer.fromColors(
                      baseColor: Colors.grey.shade200,
                      highlightColor: Colors.grey.shade100,
                      child: Container(
                        width: 160,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),

                  const SizedBox(height: 48),

                  // Continue Button
                  MyButton(
                    width: c.maxWidth * 0.25,
                    text: 'Continue',
                    onTap: (!isLoading && selectedTimezone != null)
                        ? () {
                            final d = context.read<BrandProfileDraft>();
                            d.timezone = selectedTimezone!;
                            d.notify();
                            widget.onNext();
                          }
                        : null,
                    isLoading: false,
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
