import 'dart:convert';
import 'package:blob/utils/insight_card_defaults.dart';
import 'package:blob/utils/pick_color.dart';
import 'package:blob/widgets/circular_progress_indicator.dart';
import 'package:blob/widgets/color_dot.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/control_tool.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/widgets/my_dropdown.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/my_switch.dart';
import 'package:blob/widgets/my_textfield.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class BackgroundControlsPanel extends StatefulWidget {
  const BackgroundControlsPanel({
    super.key,
    required this.width,
    required this.backgroundPrompt,
    required this.imageTab,
    this.customization,
    this.onImageGenerated,
  });

  final double width;
  final String? backgroundPrompt;
  final String imageTab;
  final Map<String, dynamic>? customization;
  final void Function(String)? onImageGenerated;

  @override
  State<BackgroundControlsPanel> createState() =>
      _BackgroundControlsPanelState();
}

class _BackgroundControlsPanelState extends State<BackgroundControlsPanel> {
  // OPT: Cache client, constants, and maps
  final SupabaseClient supabase = Supabase.instance.client;

  late InsightCardDefaults defaults;
  Map<String, dynamic> brandColors = {};
  Map<String, dynamic>? profile;

  bool loadingBrandKit = true;
  bool isGenerating = false;
  String? generatedImageUrl;
  bool isExpanded = false;

  final promptController = TextEditingController();
  final keywordController = TextEditingController();

  // OPT: Debounce guard for generate call
  int _lastGenMs = 0;

  // OPT: Static reverse lookup for slugs → UI labels
  static const Map<String, String> _slugToLabel = {
    'photo': 'Photo',
    'illustration': 'Illustration',
    'soft-gradient': 'Soft Gradient',
    'grainy-film': 'Grainy Film',
    '3-d-render': '3-D Render',
    'memphis-pattern': 'Memphis Pattern',
    'friendly-pastel': 'Friendly Pastel',
    'bold-neon': 'Bold Neon',
    'formal-minimal': 'Formal Minimal',
    'high-energy-comic': 'High-Energy Comic',
    'vintage-warm': 'Vintage Warm',
    'dark-moody': 'Dark Moody',
    'center-focus': 'Center Focus',
    'edge-detail': 'Edge Detail',
    'uniform-blur': 'Uniform Blur',
  };

  @override
  void initState() {
    super.initState();
    if (widget.backgroundPrompt != null) {
      promptController.text = widget.backgroundPrompt!;
    }
    _getData();
  }

  @override
  void dispose() {
    promptController.dispose();
    keywordController.dispose();
    super.dispose();
  }

  int safeZoneFromAspect(String aspect) {
    switch (aspect) {
      case '9:16':
      case '16:9':
        return 1;
      case '4:5':
        return 2;
      default:
        return 3;
    }
  }

  String fromSlug(String? val, {required String fallback}) {
    if (val == null) return fallback;
    final hit = _slugToLabel[val.toLowerCase()];
    return hit ?? fallback;
  }

  int _safeInt(dynamic val, int fallback) {
    if (val is int) return val;
    if (val is String) return int.tryParse(val) ?? fallback;
    return fallback;
  }

  static String _slug(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[’‘´`"]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .replaceAll(RegExp(r'-+'), '-');
  }

  Future<void> _getData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return context.go('/login');

    try {
      // OPT: Run in parallel & narrow column selection
      final results = await Future.wait([
        supabase
            .schema('brand_kit')
            .from('brand_kits')
            .select('colors')
            .eq('user_id', user.id)
            .maybeSingle(),
        supabase
            .schema('public')
            .from('brand_profiles')
            .select('persona, category, subcategory')
            .eq('user_id', user.id)
            .maybeSingle(),
      ]);

      final brandKit = results[0];
      final brandProfile = results[1];

      if (brandProfile == null ||
          brandProfile['category'] == null ||
          brandProfile['subcategory'] == null) {
        if (mounted) mySnackBar(context, 'Complete your Brand Profile first');
        return;
      }

      // OPT: Build once, then single setState
      Map<String, dynamic> colorMap =
          (brandKit?['colors'] as Map?)?.cast<String, dynamic>() ?? {};

      var resolvedDefaults = resolveInsightCardDefaults(
        subcategory: brandProfile['subcategory'],
        cardType: widget.imageTab,
        useBrandPalette: true,
      );

      String? kwAssist;
      if (widget.customization != null) {
        final c = widget.customization!;
        resolvedDefaults = resolvedDefaults.copyWith(
          selectedStylePreset: fromSlug(
            c['visual_style'],
            fallback: resolvedDefaults.selectedStylePreset,
          ),
          selectedTone: fromSlug(
            c['mood_tone'],
            fallback: resolvedDefaults.selectedTone,
          ),
          textureIntensity: _safeInt(
            c['texture_intensity'],
            resolvedDefaults.textureIntensity,
          ),
          selectedDetailPlacement: fromSlug(
            c['detail_placement'],
            fallback: resolvedDefaults.selectedDetailPlacement,
          ),
          noiseLevel: _safeInt(c['noise_grain'], resolvedDefaults.noiseLevel),
          useBrandPaletteColors: colorMap.isNotEmpty,
          negativeElements: c['negative_elements'] is String
              ? (c['negative_elements'] as String)
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList()
              : (c['negative_elements'] is List
                  ? List<String>.from(c['negative_elements'])
                  : resolvedDefaults.negativeElements),
        );

        final kaa = c['keyword_assist']?.toString();
        if (kaa != null && kaa.isNotEmpty) kwAssist = kaa;
      }

      if (!mounted) return;
      setState(() {
        brandColors = colorMap;
        profile = brandProfile;
        loadingBrandKit = false;
        defaults = resolvedDefaults;
        if (kwAssist != null) keywordController.text = kwAssist;
      });
    } catch (_) {
      if (mounted) mySnackBar(context, 'Failed to load brand data');
    }
  }

  Future<void> generateBackground() async {
    if (isGenerating) return; // OPT: guard
    final p = profile;
    if (p == null) {
      if (mounted) mySnackBar(context, 'Complete your Brand Profile first');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch; // OPT: debounce
    if (now - _lastGenMs < 800) return;
    _lastGenMs = now;

    if (promptController.text.trim().isEmpty) {
      if (mounted) mySnackBar(context, 'Please enter a background prompt');
      return;
    }

    setState(() => isGenerating = true);

    try {
      final token = supabase.auth.currentSession?.accessToken;

      final payload = <String, dynamic>{
        "main_prompt": promptController.text.trim(),
        "card_type": widget.imageTab,
        "visual_style": _slug(defaults.selectedStylePreset),
        "mood_tone": _slug(defaults.selectedTone),
        "texture_intensity": defaults.textureIntensity,
        "detail_placement": _slug(defaults.selectedDetailPlacement),
        "noise_grain": defaults.noiseLevel,
        "safe_zone_pct": safeZoneFromAspect(defaults.selectedAspectRatio),
        "persona": _slug(p['persona'] ?? ''),
        "category": _slug(p['category'] ?? ''),
        "subcategory": _slug(p['subcategory'] ?? ''),
        "aspect_ratio": defaults.selectedAspectRatio,
        "brand_palette_override": defaults.useBrandPaletteColors,
        if (defaults.useBrandPaletteColors) ...{
          "brand_primary": brandColors["primary"] ?? "#000000",
          "brand_secondary": brandColors["secondary"] ?? "#000000",
          "brand_accent": brandColors["accent"] ?? "#000000",
          "brand_background": brandColors["background"] ?? "#ffffff",
        },
        if (keywordController.text.trim().isNotEmpty)
          "keyword_assist": keywordController.text.trim(),
        if (defaults.negativeElements.isNotEmpty)
          "negative_elements": defaults.negativeElements,
      };

      final res = await http.post(
        Uri.parse(
          'https://ehgginqelbgrzfrzbmis.supabase.co/functions/v1/generate-insight-cards-background',
        ),
        headers: {
          if (token != null)
            "Authorization": "Bearer $token", // OPT: don’t send null
          "Content-Type": "application/json",
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final imageUrl = (jsonDecode(res.body) as Map)['url']?.toString();
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('Empty URL');
      }

      if (!mounted) return;
      setState(() => generatedImageUrl = imageUrl);
      widget.onImageGenerated?.call(imageUrl);
    } catch (_) {
      if (mounted) mySnackBar(context, 'Generation Failed');
    } finally {
      if (mounted) setState(() => isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return (loadingBrandKit || profile == null)
        ? const MyCircularProgressIndicator()
        : Center(
            child: SizedBox(
              width: widget.width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Step 3: Generate Background',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: darkColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ControlTool(
                    title: 'Background Prompt',
                    description: promptController.text.isNotEmpty
                        ? 'Auto-generated by AI'
                        : 'Manually guide the AI with a specific visual idea',
                    child: MyTextField(
                      width: widget.width,
                      controller: promptController,
                      hintText: 'Optional prompt override',
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: isExpanded ? 1.0 : 0.9,
                    child: ExpansionTile(
                      title: const Text(
                        'AI Customisation',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      collapsedShape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onExpansionChanged: (value) =>
                          setState(() => isExpanded = value),
                      backgroundColor: lightColor.withOpacity(0.1),
                      collapsedBackgroundColor: lightColor.withOpacity(0.2),
                      textColor: darkColor,
                      collapsedTextColor: darkColor,
                      iconColor: darkColor,
                      collapsedIconColor: darkColor,
                      expansionAnimationStyle: const AnimationStyle(
                        curve: Curves.linear,
                        reverseCurve: Curves.linear,
                        duration: Duration(milliseconds: 1000),
                        reverseDuration: Duration(milliseconds: 1000),
                      ),
                      initiallyExpanded: isExpanded,
                      childrenPadding: EdgeInsets.all(widget.width * 0.025),
                      children: [
                        // Aspect Ratio
                        ControlTool(
                          title: 'Aspect Ratio',
                          description:
                              'Choose the shape of the final image: square, vertical, or landscape',
                          child: Wrap(
                            spacing: 12,
                            children: ['1:1', '4:5', '9:16', '16:9'].map((val) {
                              final sel = defaults.selectedAspectRatio == val;
                              return AnimatedScale(
                                scale: sel ? 1.125 : 1.0,
                                duration: const Duration(milliseconds: 120),
                                child: ChoiceChip(
                                  label: Text(
                                    val,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: sel ? lightColor : darkColor,
                                    ),
                                  ),
                                  selected: sel,
                                  onSelected: (_) => setState(() {
                                    defaults = defaults.copyWith(
                                      selectedAspectRatio: val,
                                    );
                                  }),
                                  backgroundColor: lightColor,
                                  selectedColor: darkColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  showCheckmark: false,
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(
                          thickness: 0.5,
                          height: 1,
                          indent: 24,
                          endIndent: 24,
                          color: darkColor,
                        ),
                        const SizedBox(height: 24),

                        // Style + Tone
                        ControlTool(
                          title: 'Visual Style & Tone',
                          description:
                              'Style defines the look (photo/illustration); tone sets the vibe (playful/moody)',
                          child: Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: 'Choose a style preset to apply',
                                  child: MyDropDown(
                                    hint: 'Style Preset',
                                    items: const [
                                      'Photo',
                                      'Illustration',
                                      'Soft Gradient',
                                      'Grainy Film',
                                      '3-D Render',
                                      'Memphis Pattern',
                                    ],
                                    value: defaults.selectedStylePreset,
                                    onChanged: (v) => setState(() {
                                      defaults = defaults.copyWith(
                                        selectedStylePreset: v ?? 'Photo',
                                      );
                                    }),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Tooltip(
                                  message: 'Choose a tone preset to apply',
                                  child: MyDropDown(
                                    hint: 'Tone',
                                    items: const [
                                      'Friendly Pastel',
                                      'Bold Neon',
                                      'Formal Minimal',
                                      'High-Energy Comic',
                                      'Vintage Warm',
                                      'Dark Moody',
                                    ],
                                    value: defaults.selectedTone,
                                    onChanged: (v) => setState(() {
                                      defaults = defaults.copyWith(
                                        selectedTone:
                                            v ?? defaults.selectedTone,
                                      );
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(
                          thickness: 0.5,
                          height: 1,
                          indent: 24,
                          endIndent: 24,
                          color: darkColor,
                        ),
                        const SizedBox(height: 24),

                        // Brand Colors
                        if (brandColors.isEmpty)
                          const ControlTool(
                            title: 'Brand Kit',
                            description:
                                'Brand Kit can apply brand colors to the image',
                            child: Text(
                              'No Brand Kit yet - create one in Profile',
                              style: TextStyle(fontSize: 14),
                            ),
                          )
                        else ...[
                          ControlTool(
                            title: 'Brand Kit',
                            description:
                                'Toggle to apply your brand’s primary colors',
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Use Brand Colors',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                MySwitch(
                                  value: defaults.useBrandPaletteColors,
                                  onChanged: (v) => setState(() {
                                    defaults = defaults.copyWith(
                                      useBrandPaletteColors: v,
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),
                          if (!defaults.useBrandPaletteColors)
                            ControlTool(
                              title: 'Edit Brand Colors',
                              description:
                                  'Fine-tune the palette if not using Brand Kit',
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  'primary',
                                  'secondary',
                                  'accent',
                                  'background',
                                ].map((k) {
                                  return ColorDot(
                                    color: brandColors[k],
                                    label:
                                        '${k[0].toUpperCase()}${k.substring(1)}',
                                    onTap: () => pickColor(
                                      context: context,
                                      initialColor: brandColors[k],
                                      onColorSelected: (selectedColor) {
                                        setState(() {
                                          brandColors[k] =
                                              '#${selectedColor.value.toRadixString(16).substring(2)}';
                                        });
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],

                        const SizedBox(height: 24),
                        Divider(
                          thickness: 0.5,
                          height: 1,
                          indent: 24,
                          endIndent: 24,
                          color: darkColor,
                        ),
                        const SizedBox(height: 24),

                        // Texture Intensity
                        ControlTool(
                          title: 'Texture Intensity',
                          description:
                              'Controls strength of textures (grain/gradients)',
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16,
                              ),
                              valueIndicatorTextStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            child: Slider(
                              value: defaults.textureIntensity.toDouble(),
                              min: 0,
                              max: 5,
                              divisions: 5,
                              label: '${defaults.textureIntensity}',
                              onChanged: (v) => setState(() {
                                defaults = defaults.copyWith(
                                  textureIntensity: v.round(),
                                );
                              }),
                              activeColor: darkColor,
                              inactiveColor: darkColor.withOpacity(0.2),
                              thumbColor: lightColor,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(
                          thickness: 0.5,
                          height: 1,
                          indent: 24,
                          endIndent: 24,
                          color: darkColor,
                        ),
                        const SizedBox(height: 24),

                        // Texture Focus
                        ControlTool(
                          title: 'Texture Focus',
                          description: 'Choose where detail/blur concentrates',
                          child: Wrap(
                            spacing: 12,
                            children: [
                              'Center Focus',
                              'Edge Detail',
                              'Uniform Blur',
                            ].map((val) {
                              final sel =
                                  defaults.selectedDetailPlacement == val;
                              return AnimatedScale(
                                scale: sel ? 1.125 : 1.0,
                                duration: const Duration(milliseconds: 120),
                                child: ChoiceChip(
                                  label: Text(
                                    val,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: sel ? lightColor : darkColor,
                                    ),
                                  ),
                                  selected: sel,
                                  onSelected: (_) => setState(() {
                                    defaults = defaults.copyWith(
                                      selectedDetailPlacement: val,
                                    );
                                  }),
                                  backgroundColor: lightColor,
                                  selectedColor: darkColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  showCheckmark: false,
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(
                          thickness: 0.5,
                          height: 1,
                          indent: 24,
                          endIndent: 24,
                          color: darkColor,
                        ),
                        const SizedBox(height: 24),

                        // Noise Level
                        ControlTool(
                          title: 'Noise Level',
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16,
                              ),
                              valueIndicatorTextStyle: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            child: Slider(
                              value: defaults.noiseLevel.toDouble(),
                              min: 0,
                              max: 5,
                              divisions: 5,
                              label: '${defaults.noiseLevel}',
                              onChanged: (v) => setState(() {
                                defaults = defaults.copyWith(
                                  noiseLevel: v.round(),
                                );
                              }),
                              activeColor: darkColor,
                              inactiveColor: darkColor.withOpacity(0.2),
                              thumbColor: lightColor,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(
                          thickness: 0.5,
                          height: 1,
                          indent: 24,
                          endIndent: 24,
                          color: darkColor,
                        ),
                        const SizedBox(height: 24),

                        // Keyword Assist
                        ControlTool(
                          title: 'Keyword Assist',
                          description:
                              'Suggest a symbolic object (e.g., rocket, chessboard)',
                          child: MyTextField(
                            width: widget.width,
                            controller: keywordController,
                            hintText: 'Optional visual metaphor (e.g., rocket)',
                          ),
                        ),

                        const SizedBox(height: 24),
                        Divider(
                          thickness: 0.5,
                          height: 1,
                          indent: 24,
                          endIndent: 24,
                          color: darkColor,
                        ),
                        const SizedBox(height: 24),

                        // Replace the current Exclude Elements wrap with this:
                        ControlTool(
                          title: 'Exclude Elements',
                          description: 'Tell the AI what not to include',
                          child: Wrap(
                            spacing: 12,
                            children: const [
                              'People',
                              'Buildings',
                              'Devices',
                              'Nature',
                              'Symbols',
                            ].map((item) {
                              return _ExcludeChip(
                                item: item,
                                selectedProvider: (ctx) =>
                                    (ctx.findAncestorStateOfType<
                                            _BackgroundControlsPanelState>()!)
                                        .defaults
                                        .negativeElements
                                        .contains(item),
                                onToggle: (ctx, isSelected) {
                                  final parent = ctx.findAncestorStateOfType<
                                      _BackgroundControlsPanelState>()!;
                                  final list = List<String>.from(
                                    parent.defaults.negativeElements,
                                  );
                                  isSelected
                                      ? list.add(item)
                                      : list.remove(item);
                                  parent.setState(() {
                                    parent.defaults = parent.defaults
                                        .copyWith(negativeElements: list);
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (promptController.text.isNotEmpty)
                    MyButton(
                      width: widget.width,
                      height: 48,
                      text: 'Generate Background',
                      onTap: isGenerating
                          ? null
                          : () async => generateBackground(),
                      isLoading: isGenerating,
                    ),
                ],
              ),
            ),
          );
  }
}

class _ExcludeChip extends StatelessWidget {
  const _ExcludeChip({
    required this.item,
    required this.selectedProvider,
    required this.onToggle,
  });

  final String item;
  final bool Function(BuildContext) selectedProvider;
  final void Function(BuildContext, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final sel = selectedProvider(context);

    return AnimatedScale(
      scale: sel ? 1.125 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: FilterChip(
        label: Text(
          item,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: sel ? lightColor : darkColor,
          ),
        ),
        selected: sel,
        onSelected: (v) => onToggle(context, v),
        backgroundColor: lightColor,
        selectedColor: darkColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        showCheckmark: false,
      ),
    );
  }
}
