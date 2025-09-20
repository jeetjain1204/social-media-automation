import 'dart:async';
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'package:universal_html/html.dart' as html;

import 'package:blob/provider/foreground_provider.dart';
import 'package:blob/utils/card_painter.dart';
import 'package:blob/utils/load_image.dart';
import 'package:blob/utils/media_variant.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/utils/pick_color.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/circular_progress_indicator.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/edit_with_label_container.dart';
import 'package:blob/utils/future_date_time_picker.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/widgets/my_dropdown.dart';
import 'package:blob/widgets/my_slider.dart';
import 'package:blob/widgets/my_switch.dart';
import 'package:blob/widgets/my_textfield.dart';
import 'package:blob/utils/show_platform_picker.dart';
import 'package:blob/utils/template_picker_dialog.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import 'package:supabase_flutter/supabase_flutter.dart';

class ForegroundControlPanel extends StatefulWidget {
  const ForegroundControlPanel({
    super.key,
    required this.width,
    required this.idea,
    required this.source,
    required this.background,
    required this.imageTab,
    required this.onDone,
  });

  final double width;
  final String idea;
  final String? source;
  final String background;
  final String imageTab;
  final VoidCallback onDone;

  @override
  State<ForegroundControlPanel> createState() => _ForegroundControlPanelState();
}

class _ForegroundControlPanelState extends State<ForegroundControlPanel> {
  final GlobalKey paintKey = GlobalKey();

  final scrollController = ScrollController();
  final ideaController = TextEditingController();
  final subLineController = TextEditingController();
  final captionController = TextEditingController();
  final templateNameController = TextEditingController();

  ui.Image? bgImage;
  bool isLoading = true;
  bool isDownloading = false;
  bool isPosting = false;

  // OPT: ValueNotifiers to avoid full widget rebuilds on slider drags
  late final ValueNotifier<double> lineHeightNotifier;
  late final ValueNotifier<double> manualFontNotifier;
  late final ValueNotifier<double> subScaleNotifier;
  late final ValueNotifier<double> logoScaleNotifier;
  late final ValueNotifier<double> headshotScaleNotifier;
  late final ValueNotifier<double> overlayPaddingNotifier;
  late final ValueNotifier<double> shadowBlurNotifier;
  late final ValueNotifier<double> roundingNotifier;
  late final ValueNotifier<double> backgroundBlurNotifier;
  late final ValueNotifier<double> backgroundBrightnessNotifier;
  late final ValueNotifier<double> textBoxFactorNotifier;

  // OPT: const maps/lists to reduce allocations
  static const fontWeightOptions = <int, String>{
    100: 'Thin',
    400: 'Normal',
    800: 'Bold',
  };

  // static const List<String> primaryFonts = [
  //   "Poppins",
  //   "Fredoka",
  //   "Chewy",
  //   "Inter",
  //   "IBM Plex Sans",
  //   "Source Sans Pro",
  //   "Bebas Neue",
  //   "Anton",
  //   "Oswald",
  //   "Raleway",
  //   "Work Sans",
  //   "Muli",
  //   "Space Grotesk",
  //   "Roboto Mono",
  //   "Playfair Display",
  //   "Merriweather",
  //   "DM Serif Display",
  // ];

  // static const List<String> secondaryFonts = [
  //   "Quicksand",
  //   "Nunito",
  //   "Open Sans",
  //   "Lato",
  //   "Montserrat",
  //   "Barlow",
  //   "Hind",
  //   "Nunito Sans",
  //   "Manrope",
  //   "Archivo",
  //   "Crimson Text",
  //   "Libre Baskerville",
  // ];

  // static const List<String> scriptFonts = [
  //   "Patrick Hand",
  //   "Caveat",
  //   "Bangers",
  //   "Italianno",
  //   "EB Garamond",
  //   "Great Vibes",
  //   "JetBrains Mono",
  // ];

  // OPT: small infra helpers
  Future<T> _withRetry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 300),
  }) async {
    var attempt = 0;
    var delay = initialDelay;
    while (true) {
      try {
        return await task();
      } catch (_) {
        attempt++;
        if (attempt >= maxAttempts) rethrow;
        await Future.delayed(delay + Duration(milliseconds: 50 * attempt));
        delay *= 2;
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // OPT: init notifiers once
    final cfg = context.read<ForegroundNotifier>();
    lineHeightNotifier = ValueNotifier(cfg.lineHeight);
    manualFontNotifier = ValueNotifier(cfg.manualFont);
    subScaleNotifier = ValueNotifier(cfg.subScale);
    logoScaleNotifier = ValueNotifier(cfg.logoScale);
    headshotScaleNotifier = ValueNotifier(cfg.headshotScale);
    shadowBlurNotifier = ValueNotifier(cfg.shadowBlur);
    roundingNotifier = ValueNotifier(cfg.rounding);
    overlayPaddingNotifier = ValueNotifier(cfg.overlayPadding);
    backgroundBlurNotifier = ValueNotifier(cfg.backgroundBlur);
    textBoxFactorNotifier = ValueNotifier(cfg.textBoxFactor);
    backgroundBrightnessNotifier = ValueNotifier(cfg.backgroundBrightness);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final config = context.read<ForegroundNotifier>();
      if (widget.imageTab == 'Tip') config.update('showSubLine', false);

      final cleanIdea = widget.idea.contains(" Source: ")
          ? widget.idea.split(" Source: ")[0]
          : widget.idea;

      ideaController.text = cleanIdea;
      config.update('Text', cleanIdea);

      if (widget.source != null && widget.source!.isNotEmpty) {
        subLineController.text = widget.source!;
        config.update('subText', widget.source);
      }

      // Load background + logos in parallel
      await Future.wait([
        loadImageFromUrl(widget.background).then((img) {
          if (!mounted) return;
          setState(() {
            bgImage = img;
            isLoading = false;
            captionController.text = '${widget.imageTab} of the Day';
          });
        }),
        loadLogo(config),
      ]);
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    ideaController.dispose();
    subLineController.dispose();
    captionController.dispose();
    templateNameController.dispose();
    // OPT: dispose notifiers
    lineHeightNotifier.dispose();
    manualFontNotifier.dispose();
    subScaleNotifier.dispose();
    logoScaleNotifier.dispose();
    headshotScaleNotifier.dispose();
    overlayPaddingNotifier.dispose();
    shadowBlurNotifier.dispose();
    roundingNotifier.dispose();
    backgroundBlurNotifier.dispose();
    backgroundBrightnessNotifier.dispose();
    textBoxFactorNotifier.dispose();
    super.dispose();
  }

  Future<void> loadLogo(ForegroundNotifier config) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // OPT: select only needed cols
    final profileF = supabase
        .schema('public')
        .from('brand_profiles')
        .select('brand_logo_path')
        .eq('user_id', userId)
        .maybeSingle();

    final brandF = supabase
        .schema('brand_kit')
        .from('brand_kits')
        .select('transparent_logo_path')
        .eq('user_id', userId)
        .maybeSingle();

    final results = await Future.wait([profileF, brandF]);
    final profile = results[0];
    final brand = results[1];
    if (profile == null || brand == null) return;

    final logoPath = profile['brand_logo_path'] as String?;
    final transparentLogoPath = brand['transparent_logo_path'] as String?;
    if (logoPath == null || transparentLogoPath == null) return;

    // OPT: signed URLs + image decode in parallel
    final storage = Supabase.instance.client.storage.from('brand-kits');
    final signed = await Future.wait([
      storage.createSignedUrl(logoPath, 3600),
      storage.createSignedUrl(transparentLogoPath, 3600),
    ]);

    final images = await Future.wait([
      loadImageFromUrl(signed[0]),
      loadImageFromUrl(signed[1]),
    ]);

    config.update('logoImage', images[0]);
    config.update('headshotImage', images[1]);
  }

  double getAspectRatio(String val) {
    switch (val) {
      case '4:5':
        return 4 / 5;
      case '9:16':
        return 9 / 16;
      default:
        return 1.0;
    }
  }

  Future<void> exportCardImage() async {
    try {
      setState(() => isDownloading = true);

      final ctx = paintKey.currentContext;
      if (ctx == null) {
        mySnackBar(context, 'Canvas not found');
        return;
      }

      // OPT: Give a short frame to settle paints then capture
      await Future.delayed(const Duration(milliseconds: 100));

      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final deviceRatio = MediaQuery.of(context).devicePixelRatio;
      // OPT: cap pixelRatio to avoid huge memory on 4K displays
      final ui.Image image = await boundary.toImage(
        pixelRatio: deviceRatio.clamp(1.5, 2.5),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw 'Failed to encode image';
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final blob = html.Blob([pngBytes], 'image/png'); // OPT: content type
      final url = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: url)
        ..setAttribute("download", "insight_card.png")
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print('error: ${e.toString()}');
      if (mounted) mySnackBar(context, 'Some error occured');
    } finally {
      if (mounted) setState(() => isDownloading = false);
    }
  }

  Future<void> schedulePost(ForegroundNotifier config) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return context.go('/login');

    if (config.subText.isEmpty || config.subText == 'Author Name') {
      config.update('showSubLine', false);
    }

    final ctx = paintKey.currentContext;
    if (ctx == null) {
      mySnackBar(context, 'Canvas not found');
      return;
    }

    final caption = captionController.text.trim();
    if (caption.isEmpty) {
      mySnackBar(context, 'Add a caption before scheduling');
      return;
    }

    setState(() => isPosting = true);

    final scheduledAt = await showFutureDateTimePicker(context);
    if (scheduledAt == null) {
      if (mounted) {
        setState(() => isPosting = false);
        mySnackBar(context, 'Pick a schedule time');
      }
      return;
    }

    try {
      // Render image
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final deviceRatio = MediaQuery.of(context).devicePixelRatio;
      final img = await boundary.toImage(
        pixelRatio: deviceRatio.clamp(1.5, 2.5),
      );
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw 'encode fail';
      final pngBytes = data.buffer.asUint8List();

      // Upload with contentType + retry
      final path =
          'insight-card/${widget.imageTab}/$userId/${DateTime.now().millisecondsSinceEpoch}.png';

      await _withRetry(() {
        return supabase.storage.from('posts').uploadBinary(
              path,
              pngBytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/png',
              ),
            );
      });

      final publicUrl = supabase.storage.from('posts').getPublicUrl(path);

      // Pick platforms
      final selectedPlatforms = await showPlatformPicker(context);
      if (selectedPlatforms == null || selectedPlatforms.isEmpty) {
        if (mounted) mySnackBar(context, 'Please select at least one platform');
        return;
      }

      final imageCount = 1;
      final postTypesMap = await getPostTypesFor(selectedPlatforms, imageCount);

      final Map<String, List<String>>? selectedPostTypes =
          await showPostTypePicker(context, postTypesMap);

      if (selectedPostTypes == null || selectedPostTypes.isEmpty) {
        throw 'No post types selected';
      }

      final rows = <Map<String, dynamic>>[];

      selectedPostTypes.forEach((platform, types) {
        for (final pt in types) {
          rows.add({
            'user_id': userId,
            'platform': platform,
            'image_url': publicUrl,
            'post_type': pt,
            'caption': caption,
            'category': widget.imageTab,
            'scheduled_at': scheduledAt.toUtc().toIso8601String(),
            'status': 'scheduled',
          });
        }
      });
      if (rows.isNotEmpty) {
        await supabase.from('scheduled_insight_card_posts').insert(rows);
      }

      if (mounted) {
        mySnackBar(
          context,
          'Scheduled for ${DateFormat.yMMMd().add_jm().format(scheduledAt)}',
        );
        setState(() => isPosting = false);
      }

      widget.onDone();
    } catch (e) {
      print('error: ${e.toString()}');
      if (mounted) mySnackBar(context, 'Some error occured');
    } finally {
      if (mounted) setState(() => isPosting = false);
    }
  }

  Future<bool> saveToTemplate(
    final BuildContext context,
    final ForegroundNotifier config,
  ) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      context.go('/login');
      return false;
    }

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        bool localLoading = false;

        return StatefulBuilder(
          builder: (context, setState) {
            final maxDialogWidth = 420.0; // keep it compact
            final fieldWidth = MediaQuery.of(context)
                .size
                .width
                .clamp(0, maxDialogWidth) as double;

            return AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxDialogWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min, // 👈 key: don't expand
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save as Template',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    MyTextField(
                      width: fieldWidth, // 👈 not widget.width
                      controller: templateNameController,
                      hintText: 'Template Name',
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
              actions: [
                MyTextButton(
                  onPressed: () => context.pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: localLoading
                      ? null
                      : () async {
                          final name = templateNameController.text.trim();
                          if (name.isEmpty) {
                            return mySnackBar(context, 'Enter Template Name');
                          }
                          setState(() => localLoading = true);

                          try {
                            final fullConfig = {
                              'text': config.text,
                              'fontFamily': config.fontFamily,
                              'fontWeight': config.fontWeight,
                              'manualFont': config.manualFont,
                              'lineHeight': config.lineHeight,
                              'textAlign': config.textAlign,
                              'textColor': config.textColor.value.toRadixString(
                                16,
                              ),
                              'italic': config.italic,
                              'uppercase': config.uppercase,
                              'showSubLine': config.showSubLine,
                              'subText': config.subText,
                              'subScale': config.subScale,
                              'showLogo': config.showLogo,
                              'logoPlacement': config.logoPlacement,
                              'logoScale': config.logoScale,
                              'showHeadshot': config.showHeadshot,
                              'headshotPlacement': config.headshotPlacement,
                              'headshotScale': config.headshotScale,
                              'overlayPadding': config.overlayPadding,
                              'rounding': config.rounding,
                              'shadow': config.shadow,
                              'shadowBlur': config.shadowBlur,
                              'autoBrightness': config.autoBrightness,
                              'selectedAspectRatio': config.selectedAspectRatio,
                              'backgroundBlur': config.backgroundBlur,
                              'backgroundBrightness':
                                  config.backgroundBrightness,
                              'textBoxFactor': config.textBoxFactor,
                            };

                            await supabase
                                .from('templates')
                                .insert({
                                  'user_id': user.id,
                                  'name': name,
                                  'aspect_ratio': config.selectedAspectRatio,
                                  'background_path': resolveBackgroundPath(
                                    widget.background,
                                  ),
                                  'config': fullConfig,
                                  'category': null,
                                })
                                .select()
                                .single();

                            if (context.mounted) {
                              context.pop(true);
                              mySnackBar(context, 'Template Saved');
                            }
                          } catch (_) {
                            if (context.mounted) {
                              context.pop(false);
                              mySnackBar(
                                context,
                                'Error while saving template',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => localLoading = false);
                          }
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    return success ?? false;
  }

  String resolveBackgroundPath(String signedUrl) {
    final uri = Uri.parse(signedUrl);
    final segments = uri.pathSegments;
    final index = segments.indexOf('backgrounds');
    if (index == -1 || index + 1 >= segments.length) return '';
    return segments.sublist(index + 1).join('/');
  }

  Future<Map<String, List<Map<String, dynamic>>>> fetchTemplates() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    // OPT: parallel queries
    final futures = await Future.wait([
      if (user != null)
        supabase
            .from('templates')
            .select('*')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
      else
        Future.value([]),
      supabase
          .from('templates')
          .select('*')
          .isFilter('user_id', null)
          .order('created_at', ascending: false),
    ]);

    return {
      'userTemplates': List<Map<String, dynamic>>.from(futures[0]),
      'prebuiltTemplates': List<Map<String, dynamic>>.from(futures[1]),
    };
  }

  Future<void> loadFromTemplate({
    required BuildContext context,
    required ForegroundNotifier config,
    required Map<String, dynamic> template,
    required void Function(String backgroundUrl) onBackgroundLoaded,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      final configData = Map<String, dynamic>.from(template['config'] ?? {});
      final backgroundPath = template['background_url']?.toString() ??
          template['background_path']?.toString();

      if (backgroundPath != null && backgroundPath.isNotEmpty) {
        final signedUrl = await supabase.storage
            .from('backgrounds')
            .createSignedUrl(backgroundPath, 3600);
        onBackgroundLoaded(signedUrl);
      }

      // OPT: robust color parse
      final rawColor = configData['textColor'];
      Color textColor = Colors.black;
      if (rawColor is String && rawColor.isNotEmpty) {
        final padded =
            rawColor.length == 8 ? rawColor : rawColor.padLeft(8, '0');
        textColor = Color(int.parse('0x$padded'));
      }

      config.updateAll({
        'text': configData['text'],
        'fontFamily': configData['fontFamily'],
        'fontWeight': configData['fontWeight'],
        'manualFont': configData['manualFont'],
        'lineHeight': configData['lineHeight'],
        'textAlign': configData['textAlign'],
        'textColor': textColor,
        'italic': configData['italic'],
        'uppercase': configData['uppercase'],
        'showSubLine': configData['showSubLine'],
        'subText': configData['subText'],
        'subScale': configData['subScale'],
        'showLogo': configData['showLogo'],
        'logoPlacement': configData['logoPlacement'],
        'logoScale': configData['logoScale'],
        'showHeadshot': configData['showHeadshot'],
        'headshotPlacement': configData['headshotPlacement'],
        'headshotScale': configData['headshotScale'],
        'overlayPadding': configData['overlayPadding'],
        'rounding': configData['rounding'],
        'shadow': configData['shadow'],
        'shadowBlur': configData['shadowBlur'],
        'autoBrightness': configData['autoBrightness'],
        'selectedAspectRatio': configData['selectedAspectRatio'],
        'backgroundBlur': configData['backgroundBlur'],
        'backgroundBrightness': configData['backgroundBrightness'],
        'textBoxFactor': configData['textBoxFactor'],
      });

      // OPT: sync notifiers with config w/o setState
      manualFontNotifier.value = config.manualFont;
      lineHeightNotifier.value = config.lineHeight;
      subScaleNotifier.value = config.subScale;
      logoScaleNotifier.value = config.logoScale;
      headshotScaleNotifier.value = config.headshotScale;
      shadowBlurNotifier.value = config.shadowBlur;
      roundingNotifier.value = config.rounding;
      overlayPaddingNotifier.value = config.overlayPadding;
      backgroundBlurNotifier.value = config.backgroundBlur;
      backgroundBrightnessNotifier.value = config.backgroundBrightness;
      textBoxFactorNotifier.value = config.textBoxFactor;

      if (context.mounted) {
        mySnackBar(context, 'Template applied succesfully');
      }
    } catch (_) {
      if (context.mounted) mySnackBar(context, 'Failed to apply template');
    }
  }

  // ===== helpers =====
  Widget placementChips({
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    const opts = ['TL', 'TR', 'BL', 'BR', 'TC', 'BC'];
    return Wrap(
      spacing: 8,
      children: opts
          .map(
            (val) => ChoiceChip(
              label: Text(val),
              selected: val == selected,
              onSelected: (_) => onSelect(val),
            ),
          )
          .toList(),
    );
  }

  String firstAlt(String conflict, String a, String b) {
    const opts = ['TL', 'TR', 'BL', 'BR', 'TC', 'BC'];
    return opts.firstWhere(
      (v) => v != conflict && v != a && v != b,
      orElse: () => 'BR',
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ForegroundNotifier>();
    final ar = getAspectRatio(config.selectedAspectRatio);

    if (isLoading) return const MyCircularProgressIndicator(size: 200);

    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 900;

    // ===== DESKTOP / TABLET (>=900) =====
    if (isWide) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: size.height * 0.95,
            maxHeight: size.height * 0.95,
            maxWidth: double.infinity,
          ),
          child: SizedBox.expand(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT: canvas + actions
                SizedBox(
                  width: widget.width * 0.425,
                  child: SingleChildScrollView(
                    primary: false,
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: ar,
                          child: AutoSkeleton(
                            enabled: bgImage == null,
                            preserveSize: true,
                            clipPadding:
                                const EdgeInsets.symmetric(vertical: 16),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                color: lightColor.withOpacity(0.2),
                                child: bgImage == null
                                    ? Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                      height: 18,
                                                      decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      8))),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Container(
                                                      height: 18,
                                                      decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      8))),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      )
                                    : RepaintBoundary(
                                        key: paintKey,
                                        child: AnimatedBuilder(
                                          animation: config,
                                          builder: (_, __) => CustomPaint(
                                            painter: CardPainter(
                                              cfg: config,
                                              bg: bgImage!,
                                              logo: config.logoImage,
                                              headshot: config.headshotImage,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        MyButton(
                          width: widget.width * 0.5,
                          text: 'Schedule Post',
                          onTap: isPosting ? null : () => schedulePost(config),
                          isLoading: isPosting,
                        ),
                        const SizedBox(height: 16),
                        MyButton(
                          width: widget.width * 0.5,
                          text: 'Download',
                          onTap: isDownloading ? null : exportCardImage,
                          isLoading: isDownloading,
                        ),
                        const SizedBox(height: 12),
                        MyTextButton(
                          onPressed: () async {
                            final ok = await saveToTemplate(context, config);
                            mySnackBar(
                                context,
                                ok
                                    ? 'Template saved!'
                                    : 'Failed to save template');
                          },
                          child: const Text('Save Template'),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(width: MediaQuery.of(context).size.width * 0.025),

                // RIGHT: controls
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    controller: scrollController,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: controlsColumn(config, widget.width),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ===== MOBILE (<900) =====
    final mobilePad = 16.0;
    final panelW = size.width - mobilePad * 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Canvas first
          AspectRatio(
            aspectRatio: ar,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: lightColor.withOpacity(0.2),
                child: bgImage == null
                    ? AutoSkeleton(
                        enabled: true,
                        preserveSize: true,
                        child: Container(color: Colors.white),
                      )
                    : RepaintBoundary(
                        key: paintKey,
                        child: AnimatedBuilder(
                          animation: config,
                          builder: (_, __) => CustomPaint(
                            painter: CardPainter(
                              cfg: config,
                              bg: bgImage!,
                              logo: config.logoImage,
                              headshot: config.headshotImage,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Controls stacked, compact widths
          controlsColumn(config, panelW, mobile: true),
          const SizedBox(height: 16),

          // Primary actions full width
          MyButton(
            width: double.infinity,
            text: 'Schedule Post',
            onTap: isPosting ? null : () => schedulePost(config),
            isLoading: isPosting,
          ),
          const SizedBox(height: 12),
          MyButton(
            width: double.infinity,
            text: 'Download',
            onTap: isDownloading ? null : exportCardImage,
            isLoading: isDownloading,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: MyTextButton(
              onPressed: () async {
                final ok = await saveToTemplate(context, config);
                mySnackBar(context,
                    ok ? 'Template saved!' : 'Failed to save template');
              },
              child: const Text('Save Template'),
            ),
          ),
        ],
      ),
    );
  }

// Shared controls. Uses panelWidth and adapts rows to columns on mobile.
  Widget controlsColumn(ForegroundNotifier config, double panelWidth,
      {bool mobile = false}) {
    final twoUp = panelWidth >= 420 && !mobile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MyButton(
          width: panelWidth,
          isLoading: false,
          text: 'Apply Template',
          onTap: () async {
            final result = await fetchTemplates();
            final userTemplates = result['userTemplates']!;
            final prebuiltTemplates = result['prebuiltTemplates']!;
            if (!context.mounted) return;
            await showDialog(
              context: context,
              builder: (context) => TemplatePickerDialog(
                userTemplates: userTemplates,
                prebuiltTemplates: prebuiltTemplates,
                onSelect: (template) async {
                  await loadFromTemplate(
                    context: context,
                    config: context.read<ForegroundNotifier>(),
                    template: template,
                    onBackgroundLoaded: (url) async {
                      final img = await loadImageFromUrl(url);
                      if (!mounted) return;
                      setState(() => bgImage = img);
                    },
                  );
                },
              ),
            );
          },
        ),
        Divider(
          thickness: 0.5,
          height: 24,
          color: darkColor.withOpacity(0.25),
        ),

        Text(
          'Text Content',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: darkColor),
        ),
        const SizedBox(height: 4),
        MyTextField(
          width: panelWidth,
          controller: ideaController,
          hintText: 'Enter ${widget.imageTab}',
          onChanged: (p0) => config.update('Text', p0),
          type: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
        EditWithLabelContainer(
          width: panelWidth,
          description: 'Controls the font size of the main text on your image',
          label: '${widget.imageTab} Size',
          child: MySlider(
            min: 12,
            max: 72,
            divisions: 36,
            valueNotifier: manualFontNotifier,
            onChanged: (v) => config.update('manualFont', v),
            tooltip: '${widget.imageTab} Size',
          ),
        ),
        if (widget.imageTab == 'Quote' || widget.imageTab == 'Fact')
          EditWithLabelContainer(
            width: panelWidth,
            description: widget.imageTab == 'Quote'
                ? 'Add the person who said the quote'
                : 'Mention the source of this fact',
            label: widget.imageTab == 'Quote' ? 'Author' : 'Source',
            switchBool: config.showSubLine,
            onChanged: (v) => config.update('showSubLine', v),
            child: config.showSubLine
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      MyTextField(
                        width: panelWidth,
                        controller: subLineController,
                        hintText:
                            'Enter ${widget.imageTab == 'Quote' ? 'Author' : 'Source'}',
                        onChanged: (p0) => config.update('subText', p0),
                        type: TextInputType.multiline,
                      ),
                      MySlider(
                        min: 0.4,
                        max: 0.8,
                        divisions: 2,
                        valueNotifier: subScaleNotifier,
                        onChanged: (v) => config.update('subScale', v),
                        tooltip: widget.imageTab == 'Quote'
                            ? 'Author Size'
                            : 'Source Size',
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        const SizedBox(height: 12),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Text Box Size',
          description: 'Adjust the size of the text box',
          child: MySlider(
            min: 0.1,
            max: 0.92,
            divisions: 41,
            valueNotifier: textBoxFactorNotifier,
            onChanged: (v) => config.update('textBoxFactor', v),
            tooltip: 'Text Box Size',
          ),
        ),
        const SizedBox(height: 12),

        // font family + weight -> row on wide, column on mobile
        twoUp
            ? Row(
                children: [
                  Expanded(
                    child: MyDropDown(
                      value: config.fontFamily,
                      hint: 'Select Font Family',
                      items: const ['Roboto', 'Inter', 'Poppins'],
                      onChanged: (v) => config.update('fontFamily', v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      hint: const Text('Select Font Weight'),
                      value: config.fontWeight,
                      items: fontWeightOptions.entries
                          .map((e) => DropdownMenuItem<int>(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => config.update('fontWeight', v),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFBDE2FF),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none),
                      ),
                      dropdownColor: const Color(0xFFBDE2FF),
                      style: TextStyle(fontSize: 15, color: darkColor),
                      iconEnabledColor: darkColor,
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  MyDropDown(
                    value: config.fontFamily,
                    hint: 'Select Font Family',
                    items: const ['Roboto', 'Inter', 'Poppins'],
                    onChanged: (v) => config.update('fontFamily', v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    hint: const Text('Select Font Weight'),
                    value: config.fontWeight,
                    items: fontWeightOptions.entries
                        .map((e) => DropdownMenuItem<int>(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => config.update('fontWeight', v),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFBDE2FF),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                    ),
                    dropdownColor: const Color(0xFFBDE2FF),
                    style: TextStyle(fontSize: 15, color: darkColor),
                    iconEnabledColor: darkColor,
                  ),
                ],
              ),

        const SizedBox(height: 12),
        EditWithLabelContainer(
          label: 'Line Height',
          description: 'Set spacing between lines of text',
          width: panelWidth,
          child: MySlider(
            min: 0.8,
            max: 1.6,
            divisions: 4,
            valueNotifier: lineHeightNotifier,
            onChanged: (v) => config.update('lineHeight', v),
            tooltip: 'Line Height',
          ),
        ),
        EditWithLabelContainer(
          width: panelWidth,
          label: "Alignment",
          description: 'Align the text to left, center, or right',
          child: Wrap(
            spacing: 8,
            children: ['L', 'C', 'R'].map((val) {
              return ChoiceChip(
                label: Text(val),
                selected: val == config.textAlign,
                onSelected: (_) => config.update('textAlign', val),
              );
            }).toList(),
          ),
        ),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Text Color',
          description: 'Choose the main color of the text',
          child: MyTextButton(
            onPressed: () async {
              await pickColor(
                context: context,
                initialColor: config.textColor,
                onColorSelected: (c) => config.update('textColor', c),
              );
            },
            child: const Text('Change Text Color'),
          ),
        ),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Font Style',
          description: 'Toggle italic and uppercase styles',
          child: Row(
            children: [
              const Text("Italic"),
              MySwitch(
                value: config.italic,
                onChanged: (v) => config.update('italic', v),
              ),
              SizedBox(width: MediaQuery.sizeOf(context).width >= 900 ? 12 : 1),
              const Text("Uppercase"),
              MySwitch(
                value: config.uppercase,
                onChanged: (v) => config.update('uppercase', v),
              ),
            ],
          ),
        ),

        Divider(
          thickness: 0.5,
          height: 24,
          color: darkColor.withOpacity(0.25),
        ),
        Text(
          'Adjust Logo and Headshot',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: darkColor),
        ),
        const SizedBox(height: 4),

        EditWithLabelContainer(
          width: panelWidth,
          description: 'Enable or disable the brand logo overlay',
          label: 'Show Logo',
          switchBool: config.showLogo,
          onChanged: (v) => config.update('showLogo', v),
          child: config.showLogo
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    placementChips(
                      selected: config.logoPlacement,
                      onSelect: (val) {
                        if (!config.showLogo) return;
                        if (val == config.headshotPlacement) {
                          final alt = firstAlt(val, config.headshotPlacement,
                              config.logoPlacement);
                          config.update('headshotPlacement', alt);
                        }
                        config.update('logoPlacement', val);
                      },
                    ),
                    MySlider(
                      min: 0.06,
                      max: 0.20,
                      divisions: 7,
                      valueNotifier: logoScaleNotifier,
                      onChanged: (v) => config.update('logoScale', v),
                      tooltip: 'Logo Size',
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Show Headshot',
          description: 'Enable or disable headshot overlay on the image',
          switchBool: config.showHeadshot,
          onChanged: (v) => config.update('showHeadshot', v),
          child: config.showHeadshot
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    placementChips(
                      selected: config.headshotPlacement,
                      onSelect: (val) {
                        if (!config.showHeadshot) return;
                        if (val == config.logoPlacement) {
                          final alt = firstAlt(val, config.logoPlacement,
                              config.headshotPlacement);
                          config.update('logoPlacement', alt);
                        }
                        config.update('headshotPlacement', val);
                      },
                    ),
                    MySlider(
                      min: 0.06,
                      max: 0.20,
                      divisions: 7,
                      valueNotifier: headshotScaleNotifier,
                      onChanged: (v) => config.update('headshotScale', v),
                      tooltip: 'Headshot Size',
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Logo Padding',
          description: 'Control how close the logo is to the image edges',
          child: MySlider(
            min: 0,
            max: 0.15,
            divisions: 14,
            valueNotifier: overlayPaddingNotifier,
            onChanged: (v) => config.update('overlayPadding', v),
            tooltip: 'Logo Padding',
          ),
        ),

        Divider(
          thickness: 0.5,
          height: 24,
          color: darkColor.withOpacity(0.25),
        ),
        Text(
          'Background Effects',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: darkColor),
        ),
        const SizedBox(height: 4),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Drop Shadow',
          description: 'Add a subtle drop shadow behind the text',
          switchBool: config.shadow,
          onChanged: (v) => config.update('shadow', v),
          child: config.shadow
              ? MySlider(
                  min: 1,
                  max: 8,
                  divisions: 7,
                  valueNotifier: shadowBlurNotifier,
                  onChanged: (v) => config.update('shadowBlur', v),
                  tooltip: 'Shadow Blur',
                )
              : const SizedBox.shrink(),
        ),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Background Blur',
          description: 'Apply blur effect to the background image',
          child: MySlider(
            min: 0,
            max: 100,
            divisions: 100,
            valueNotifier: backgroundBlurNotifier,
            onChanged: (v) => config.update('backgroundBlur', v),
            tooltip: 'Background Blur',
          ),
        ),
        EditWithLabelContainer(
          width: panelWidth,
          description: 'Increase or decrease how bright the background looks',
          label:
              config.autoBrightness ? 'Auto Brightness' : 'Adjust Brightness',
          switchBool: config.autoBrightness,
          onChanged: (v) => config.update('autoBrightness', v),
          child: config.autoBrightness
              ? const SizedBox.shrink()
              : MySlider(
                  min: 0,
                  max: 200,
                  divisions: 200,
                  valueNotifier: backgroundBrightnessNotifier,
                  onChanged: (v) => config.update('backgroundBrightness', v),
                  tooltip: 'Background Brightness',
                ),
        ),

        Divider(
          thickness: 0.5,
          height: 24,
          color: darkColor.withOpacity(0.25),
        ),
        Text(
          'Resize',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: darkColor),
        ),
        const SizedBox(height: 4),
        EditWithLabelContainer(
          width: panelWidth,
          label: 'Resize',
          description: 'Change the layout aspect ratio',
          child: Wrap(
            spacing: 8,
            children: ['1:1', '4:5', '9:16'].map((val) {
              return ChoiceChip(
                label: Text(val),
                selected: val == config.selectedAspectRatio,
                onSelected: (_) => config.update('selectedAspectRatio', val),
              );
            }).toList(),
          ),
        ),

        Divider(
          thickness: 0.5,
          height: 24,
          color: darkColor.withOpacity(0.25),
        ),
        Text(
          'Caption',
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: darkColor),
        ),
        const SizedBox(height: 4),
        EditWithLabelContainer(
          width: panelWidth,
          description:
              'This will appear below your post. Add hashtags, CTAs, or a message',
          label: 'Caption',
          child: MyTextField(
            width: panelWidth,
            controller: captionController,
            hintText: 'Enter Caption',
            type: TextInputType.multiline,
          ),
        ),
      ],
    );
  }
}
