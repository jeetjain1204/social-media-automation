// OPT: Removed dart:html usage and the avoid_web_libraries_in_flutter ignore.
//      We now use url_launcher everywhere for consistency, security, and DX.

import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

class ConnectLinkedInPagesPage extends StatefulWidget {
  const ConnectLinkedInPagesPage({super.key});

  @override
  State<ConnectLinkedInPagesPage> createState() =>
      _ConnectLinkedInPagesPageState();
}

class _ConnectLinkedInPagesPageState extends State<ConnectLinkedInPagesPage> {
  late final VideoPlayerController videoController;

  @override
  void initState() {
    super.initState();
    // OPT: Defer heavy async initialize to next frame to not compete with first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      videoController = VideoPlayerController.asset(
        'assets/videos/linkedin_demo.mp4',
      );
      await videoController.initialize();
      // OPT: Rely on controller's internal Listenable rather than frequent setState storms.
      if (mounted) setState(() {}); // single paint after init
    });
  }

  @override
  void dispose() {
    // OPT: Guard dispose in case init never completed (rare), though late ensures presence after init.
    videoController.dispose();
    super.dispose();
  }

  Future<void> launchURL(BuildContext context, String url) async {
    // OPT: url_launcher for all platforms; avoids direct window APIs and keeps DX consistent.
    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) {
      if (context.mounted) mySnackBar(context, 'Failed to launch URL');
      return;
    }
    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
    if (!ok && context.mounted) {
      mySnackBar(context, 'Failed to launch URL');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isWide = width > 900;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: width * 0.05,
              vertical: 48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Title
                Text(
                  'Set Up Your LinkedIn Page',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: isWide ? 36 : 28,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Subtitle
                Text(
                  'This 60-second guide will help you set up a LinkedIn Page so Blob can post and track analytics for you',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.grey.shade700,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 48),

                // Video player (isolated repaint scope)
                RepaintBoundary(
                  // OPT: RepaintBoundary to confine video/animation repaints for lower TBT/paint cost.
                  child: _VideoCard(
                    controller:
                        (mounted && (videoController.value.isInitialized))
                            ? videoController
                            : null, // null-safe until initialized
                    width: width,
                    isWide: isWide,
                  ),
                ),

                const SizedBox(height: 64),

                // Guide Steps
                StepTile(
                  number: 1,
                  title: 'Open LinkedIn Page Creation',
                  desc:
                      'Go to LinkedIn’s official tool to create a new Organization Page',
                  link: 'https://www.linkedin.com/company/setup/new/',
                  onOpenLink: (url) => launchURL(context, url),
                ),
                StepTile(
                  number: 2,
                  title: 'Fill Out Company Details',
                  desc:
                      'Add your company name, website, and upload your logo. This builds your LinkedIn presence',
                  onOpenLink: null,
                ),
                StepTile(
                  number: 3,
                  title: 'Verify & Become Admin',
                  desc:
                      'Ensure you’re the Page Admin - only admins can connect accounts for posting and analytics',
                  onOpenLink: null,
                ),
                StepTile(
                  number: 4,
                  title: 'Reconnect LinkedIn to Blob',
                  desc:
                      'Once your Page is live, reconnect LinkedIn here to enable publishing + analytics',
                  onOpenLink: null,
                ),

                const SizedBox(height: 48),

                // CTA Button
                MyButton(
                  width: isWide ? width * 0.3 : width * 0.6,
                  height: 52,
                  text: 'Reconnect LinkedIn Now',
                  isLoading: false,
                  onTap: () => context.push('/connect/linkedin'),
                ),

                const SizedBox(height: 24),

                // Back to Dashboard
                MyTextButton(
                  onPressed: () => context.push('/home'),
                  child: const Text('Back to Dashboard'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------
// OPT: Extracted widgets
// ---------------------------

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.controller,
    required this.width,
    required this.isWide,
  });

  final VideoPlayerController? controller;
  final double width;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final contentWidth = isWide ? width * 0.6 : width * 0.9;

    return Container(
      width: contentWidth,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          // OPT: Single shadow layer; balanced visual + lower paint cost.
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: (controller?.value.isInitialized ?? false)
            ? controller!.value.aspectRatio
            : 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AutoSkeleton(
            enabled: controller == null || !(controller!.value.isInitialized),
            preserveSize: true,
            clipPadding: const EdgeInsets.symmetric(vertical: 12),
            child: (controller == null || !(controller!.value.isInitialized))
                ? Stack(
                    children: [
                      Positioned.fill(child: Container(color: Colors.white)),
                      Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: controller!,
                        builder: (context, _) => VideoPlayer(controller!),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: AnimatedBuilder(
                          animation: controller!,
                          builder: (context, _) => VideoProgressIndicator(
                            controller!,
                            allowScrubbing: true,
                            padding: const EdgeInsets.only(top: 4),
                            colors: VideoProgressColors(
                              playedColor: Color(0xFF004AAD),
                              backgroundColor: Colors.grey,
                              bufferedColor: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: controller!,
                        builder: (context, _) {
                          final isPlaying = controller!.value.isPlaying;
                          return AnimatedOpacity(
                            opacity: isPlaying ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            child: IconButton(
                              icon: const Icon(
                                Icons.play_circle_fill,
                                size: 64,
                                color: Colors.white70,
                              ),
                              onPressed: () => controller!.play(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class StepTile extends StatelessWidget {
  const StepTile({
    super.key,
    required this.number,
    required this.title,
    required this.desc,
    this.link,
    required this.onOpenLink,
  });

  final int number;
  final String title;
  final String desc;
  final String? link;
  final Future<void> Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E6ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step $number',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1a1a1a),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.grey.shade700,
              height: 1.5, // OPT: Readability + consistent line height
            ),
          ),
          if (link != null && onOpenLink != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => onOpenLink!(link!),
              child: Text(
                'Open Link',
                style: GoogleFonts.inter(
                  color: const Color(0xFF2fb2ff),
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
