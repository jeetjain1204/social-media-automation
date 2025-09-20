import 'dart:convert';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/widgets/my_dropdown.dart';
import 'package:blob/utils/my_snack_bar.dart';

class IdeaGeneratorPage extends StatefulWidget {
  const IdeaGeneratorPage({super.key});

  @override
  State<IdeaGeneratorPage> createState() => IdeaGeneratorPageState();
}

class IdeaGeneratorPageState extends State<IdeaGeneratorPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<Map<String, dynamic>> generatedIdeas = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> unreviewedIdeas = <Map<String, dynamic>>[];

  int selectedCount = 5;
  bool showUnreviewed = false;
  bool isLoading = false;

  String? profilePersona;
  String? profileCategory;
  String? profileSubCategory;
  String? profileGoal;
  List profileVoiceTags = [];

  String selectedMainTab = 'Image';
  String selectedImageSubTab = 'Quote';

  bool showAdvanced = false;

  List<String> selectedVoiceTags = [];
  String? topicSeed;
  String? formatPreference;
  String? hookStyle;
  String? emotionTarget;
  String? authorArchetype;
  String? metricType;
  String? timeHorizon;
  String? sourceSeriousness;
  String? region;
  String? difficultyLevel;
  double implementationTime = 0.2;
  String? desiredKPI;
  String? selectedTone;
  bool includeSource = false;

  static const List<String> formats = ['Question', 'Hot-take', 'Story prompt'];
  static const List<String> hooks = ['Statistic', 'Challenge', 'Myth bust'];
  static const List<String> emotions = ['Inspire', 'Courage', 'Humour'];
  static const List<String> archetypes = ['Visionary', 'Operator', 'Coach'];
  static const List<String> metrics = ['%', r'$', 'X-of-Y'];
  static const List<String> horizons = [
    'Latest Month',
    'Latest Year',
    'Last 5 yrs',
    'Last 10 Years',
    'Next Year',
    'Next 5 Years',
    'All-Time Record',
  ];
  static const List<String> regions = ['Global', 'India', 'APAC', 'USA'];
  static const List<String> seriousnessLevels = [
    "Casual Blog Post",
    "Company Report",
    "Industry White-paper",
    "Government Data",
    "Academic Journal",
    "Peer-reviewed Meta Analysis",
  ];
  static const List<String> difficulties = ['Beginner', 'Pro'];

  late final Future<SharedPreferences> prefsFuture;
  int lastGenMs = 0;

  @override
  void initState() {
    super.initState();
    prefsFuture = SharedPreferences.getInstance();
    getProfileData();
    loadUnreviewedIdeas();
  }

  Future<void> getProfileData() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final brandProfile = await supabase
          .from('brand_profiles')
          .select('persona, category, subcategory, primary_goal, voice_tags')
          .eq('user_id', user.id)
          .maybeSingle();

      if (brandProfile != null) {
        profilePersona = brandProfile['persona'] as String?;
        profileCategory = brandProfile['category'] as String?;
        profileSubCategory = brandProfile['subcategory'] as String?;
        profileGoal = brandProfile['primary_goal'] as String?;
        profileVoiceTags = (brandProfile['voice_tags'] ?? []) as List;
      }
    } catch (_) {}
  }

  Future<void> generateIdeas() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastGenMs < 800) return;
    lastGenMs = now;

    setState(() => isLoading = true);

    try {
      final session = supabase.auth.currentSession;
      final accessToken = session?.accessToken;

      final isImage = selectedMainTab == 'Image';
      final category = isImage ? selectedImageSubTab : 'Text';

      final Map<String, dynamic> payload = <String, dynamic>{
        'count': selectedCount,
        'category': category,
        if (profilePersona != null) 'profile_persona': profilePersona,
        if (profileCategory != null) 'profile_category': profileCategory,
        if (profileSubCategory != null)
          'profile_sub_category': profileSubCategory,
        if (profileGoal != null) 'profile_goal': profileGoal,
        if ((selectedVoiceTags.isNotEmpty
                ? selectedVoiceTags
                : profileVoiceTags)
            .isNotEmpty)
          'voice_tags': selectedVoiceTags.isNotEmpty
              ? selectedVoiceTags
              : profileVoiceTags,
        if ((topicSeed ?? '').isNotEmpty) 'topic_seed': topicSeed,
        if (category == 'Text' && (formatPreference ?? '').isNotEmpty)
          'format': formatPreference,
        if (category == 'Text' && (hookStyle ?? '').isNotEmpty)
          'hook_style': hookStyle,
        if (category == 'Tip' && (desiredKPI ?? '').isNotEmpty)
          'desired_kpi': desiredKPI,
        if (category == 'Quote' && (emotionTarget ?? '').isNotEmpty)
          'emotion_target': emotionTarget,
        if (category == 'Quote' && (authorArchetype ?? '').isNotEmpty)
          'author_archetype': authorArchetype,
        if (category == 'Quote' && includeSource) 'include_source': true,
        if (category == 'Fact' && (metricType ?? '').isNotEmpty)
          'metric_type': metricType,
        if (category == 'Fact' && (timeHorizon ?? '').isNotEmpty)
          'time_horizon': timeHorizon,
        if (category == 'Fact' && (sourceSeriousness ?? '').isNotEmpty)
          'source_seriousness': sourceSeriousness,
        if (category == 'Fact' && (region ?? '').isNotEmpty) 'region': region,
        if ((category == 'Fact' || category == 'Tip') && selectedTone != null)
          'tone': selectedTone!.toLowerCase(),
        if (category == 'Tip' && (difficultyLevel ?? '').isNotEmpty)
          'difficulty_level': difficultyLevel,
        if (category == 'Tip') 'implementation_time': implementationTime,
      };

      final response = await supabase.functions.invoke(
        'generate-ideas',
        body: payload,
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken'
        },
      );

      final raw = response.data;
      if (raw == null) {
        if (mounted) mySnackBar(context, 'Failed to generate ideas');
        return;
      }

      final decoded = jsonDecode(raw as String);
      final List<dynamic> rawIdeas = decoded['ideas'] ?? [];

      final List<Map<String, dynamic>> newIdeas = <Map<String, dynamic>>[];
      for (final e in rawIdeas) {
        if (e is Map<String, dynamic> && e['response'] != '{') {
          final Map<String, dynamic> sanitized = Map<String, dynamic>.from(e);
          sanitized['customization'] =
              sanitized['customization'] ?? <String, dynamic>{};
          sanitized['category'] = category;
          newIdeas.add(sanitized);
        }
      }

      if (newIdeas.isEmpty) {
        if (mounted) mySnackBar(context, 'No new ideas this round');
        return;
      }

      final Set<String> newResp =
          newIdeas.map((e) => e['response']?.toString() ?? '').toSet();
      final List<Map<String, dynamic>> merged = <Map<String, dynamic>>[
        ...newIdeas,
        ...generatedIdeas.where(
          (g) => !newResp.contains(g['response']?.toString() ?? ''),
        ),
      ];

      unreviewedIdeas.addAll(newIdeas);
      await saveUnreviewedIdeas();

      if (!mounted) return;
      setState(() {
        generatedIdeas = merged;
        showUnreviewed = false;
      });
    } catch (e) {
      if (mounted) mySnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> acceptIdea(Map<String, dynamic> idea) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) mySnackBar(context, 'Please login');
      return;
    }

    try {
      await supabase.from('content_ideas').insert({
        'user_id': user.id,
        'idea': idea['response'],
        'source': idea['source'] ?? '',
        'background': idea['background'] ?? '',
        'accepted': true,
        'used_in_generation': false,
        'category': idea['category'],
        'customization': idea['customization'],
      });

      await removeIdeaFromPrefs(idea);
    } catch (_) {
      if (mounted) mySnackBar(context, 'Failed to accept idea');
    }
  }

  // ---------- UI helpers ----------

  Widget buildAdvancedPanel(double width, bool isWide) {
    final bool isText = selectedMainTab == 'Text';
    final bool isQuote =
        selectedMainTab == 'Image' && selectedImageSubTab == 'Quote';
    final bool isFact =
        selectedMainTab == 'Image' && selectedImageSubTab == 'Fact';
    final bool isTip =
        selectedMainTab == 'Image' && selectedImageSubTab == 'Tip';

    final double fieldWidth = isWide ? width * 0.4 : width;

    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: lightColor.withOpacity(0.05),
        border: Border.all(
          color: darkColor.withOpacity(0.15),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "🔧 Advanced Customizations",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 24),
          buildTextField("Topic / Keyword Seed", topicSeed,
              (val) => setState(() => topicSeed = val), fieldWidth),
          if (isText) ...[
            buildRadioRow(
              "Format Preference",
              formats,
              formatPreference,
              (val) => setState(() => formatPreference = val),
            ),
            buildRadioRow(
              "Hook Style",
              hooks,
              hookStyle,
              (val) => setState(() => hookStyle = val),
            ),
          ],
          if (isQuote) ...[
            buildDropdown("Emotion Target", emotionTarget, emotions,
                (val) => setState(() => emotionTarget = val), fieldWidth),
            buildDropdown("Author Archetype", authorArchetype, archetypes,
                (val) => setState(() => authorArchetype = val), fieldWidth),
            const SizedBox(height: 4),
            Row(
              children: [
                Checkbox(
                  value: includeSource,
                  onChanged: (val) => setState(() => includeSource = val!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side:
                      BorderSide(color: darkColor.withOpacity(0.3), width: 1.5),
                  fillColor: MaterialStateProperty.resolveWith((states) {
                    if (states.contains(MaterialState.selected))
                      return lightColor;
                    return Colors.transparent;
                  }),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Include Source",
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ],
          if (isFact) ...[
            buildDropdown("Metric Type", metricType, metrics,
                (val) => setState(() => metricType = val), fieldWidth),
            buildDropdown("Time Horizon", timeHorizon, horizons,
                (val) => setState(() => timeHorizon = val), fieldWidth),
            buildDropdown(
                "Source Seriousness",
                sourceSeriousness,
                seriousnessLevels,
                (val) => setState(() => sourceSeriousness = val),
                fieldWidth),
            buildDropdown("Region / Market", region, regions,
                (val) => setState(() => region = val), fieldWidth),
          ],
          if (isTip) ...[
            buildDropdown("Difficulty Level", difficultyLevel, difficulties,
                (val) => setState(() => difficultyLevel = val), fieldWidth),
            buildSlider(
              "Implementation Time (0 = quick, 1 = long)",
              implementationTime,
              (val) => setState(() => implementationTime = val),
            ),
            buildTextField("Desired Outcome KPI", desiredKPI,
                (val) => setState(() => desiredKPI = val), fieldWidth),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget buildDropdown(
    String label,
    String? selected,
    List<String> items,
    void Function(String?) onChanged,
    double width,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF111827)),
          ),
          const SizedBox(height: 8),
          MyDropDown(
            width: width,
            height: 44,
            value: selected,
            hint: 'Select $label',
            items: items,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget buildTextField(
    String label,
    String? value,
    void Function(String) onChanged,
    double width,
  ) {
    final Color fill = Colors.white;
    final Color baseBorder = lightColor.withOpacity(0.4);
    const double radius = 16;
    const double height = 50;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: baseBorder, width: 1.5),
      ),
      child: TextFormField(
        initialValue: value,
        onChanged: onChanged,
        style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(
              color: darkColor.withOpacity(0.4), fontWeight: FontWeight.w400),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        ),
      ),
    );
  }

  Widget buildRadioRow(
    String label,
    List<String> options,
    String? selected,
    void Function(String?) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF111827)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: options.map((opt) {
              final bool isSelected = selected == opt;
              return AnimatedScale(
                scale: isSelected ? 1.125 : 1.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: ChoiceChip(
                  label: Text(
                    opt,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isSelected ? lightColor : darkColor),
                  ),
                  selected: isSelected,
                  onSelected: (_) => onChanged(opt),
                  backgroundColor: lightColor,
                  selectedColor: darkColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                  pressElevation: 0,
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget buildSlider(
    String label,
    double value,
    void Function(double) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ${(value * 100).round()}%",
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF111827)),
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 10,
            activeColor: lightColor,
            inactiveColor: darkColor.withOpacity(0.1),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // ---------- Local persistence ----------

  Future<void> saveUnreviewedIdeas() async {
    final prefs = await prefsFuture;
    await prefs.setString('unreviewed_ideas', jsonEncode(unreviewedIdeas));
  }

  Future<void> loadUnreviewedIdeas() async {
    final prefs = await prefsFuture;
    final encoded = prefs.getString('unreviewed_ideas');
    if (encoded == null || encoded.isEmpty) return;

    final List<dynamic> decoded = jsonDecode(encoded);
    final List<Map<String, dynamic>> items =
        decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (!mounted || items.isEmpty) return;
    setState(() {
      unreviewedIdeas = items;
    });
  }

  Future<void> removeIdeaFromPrefs(Map<String, dynamic> idea) async {
    unreviewedIdeas.removeWhere((e) => e['response'] == idea['response']);
    await saveUnreviewedIdeas();
  }

  void removeUnreviewedFromGenerated() {
    setState(() {
      final Set<String> unrev =
          unreviewedIdeas.map((u) => u['response']?.toString() ?? '').toSet();
      generatedIdeas
          .removeWhere((g) => unrev.contains(g['response']?.toString() ?? ''));
    });
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool isWide = width >= 900;

    // Wide layout: keep current behavior
    if (isWide) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: SingleChildScrollView(
          padding: EdgeInsets.all(width * 0.0125),
          child: buildContent(width: width, isWide: true),
        ),
      );
    }

    // Mobile layout: compact paddings, full-width controls
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: buildContent(width: width - 32, isWide: false),
      ),
    );
  }

  // Shared content builder with width + isWide toggles
  Widget buildContent({required double width, required bool isWide}) {
    final int indexCountCap =
        isWide ? selectedCount.clamp(1, 50) : selectedCount.clamp(1, 20);
    final double buttonWidth = isWide ? width * 0.25 : width;
    final double ideasListWidth = isWide ? width * 0.9 : width;
    final double countPickerWidth =
        isWide ? width * 0.1 : (width * 0.35).clamp(120, 220);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Main Tab Toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selectedMainTab == 'Image' ? 1.125 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: ChoiceChip(
                label: Text(
                  'Image',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: selectedMainTab == 'Image' ? lightColor : darkColor,
                  ),
                ),
                selected: selectedMainTab == 'Image',
                onSelected: (_) => setState(() => selectedMainTab = 'Image'),
                backgroundColor: lightColor,
                selectedColor: darkColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                pressElevation: 0,
                showCheckmark: false,
              ),
            ),
            const SizedBox(width: 12),
            AnimatedScale(
              scale: selectedMainTab == 'Text' ? 1.125 : 1.0,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: ChoiceChip(
                label: Text(
                  'Text',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: selectedMainTab == 'Text' ? lightColor : darkColor,
                  ),
                ),
                selected: selectedMainTab == 'Text',
                onSelected: (_) => setState(() {
                  selectedMainTab = 'Text';
                  selectedImageSubTab = 'Quote';
                  includeSource = false;
                  selectedTone = null;
                }),
                backgroundColor: lightColor,
                selectedColor: darkColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
                pressElevation: 0,
                showCheckmark: false,
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Sub-tabs under Image
        if (selectedMainTab == 'Image')
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: ['Quote', 'Fact', 'Tip'].map((type) {
              final bool isSelected = selectedImageSubTab == type;
              return AnimatedScale(
                scale: isSelected ? 1.125 : 1.0,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: ChoiceChip(
                  label: Text(
                    type,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isSelected ? lightColor : darkColor),
                  ),
                  selected: isSelected,
                  onSelected: (_) => setState(() {
                    selectedImageSubTab = type;
                    includeSource = false;
                    selectedTone = null;
                  }),
                  backgroundColor: lightColor,
                  selectedColor: darkColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                  pressElevation: 0,
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),

        const SizedBox(height: 28),

        // Toggle Advanced Panel
        MyTextButton(
          onPressed: () => setState(() => showAdvanced = !showAdvanced),
          child: Text(
            showAdvanced
                ? 'Hide Advanced Customization'
                : 'Show Advanced Customization (Style, Tone, Source)',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),

        if (showAdvanced) buildAdvancedPanel(width, isWide),

        const SizedBox(height: 28),

        // Idea Count Picker
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Ideas to generate in one click:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 12),
            MyDropDown(
              width: countPickerWidth,
              value: selectedCount.toString(),
              items: const ['1', '5', '10', '30', '50', '100'],
              onChanged: (value) => setState(
                () => selectedCount = int.parse(value!),
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // Generate Button
        MyButton(
          width: buttonWidth,
          text:
              'Generate $selectedCount${generatedIdeas.isNotEmpty ? ' More' : ''} ${selectedCount > 1 ? 'Ideas' : 'Idea'}',
          isLoading: isLoading,
          onTap: isLoading ? null : () async => generateIdeas(),
        ),

        const SizedBox(height: 12),

        // Unreviewed Toggle
        if (unreviewedIdeas.isNotEmpty)
          Tooltip(
            message: 'Ideas generated earlier but not accepted or rejected',
            child: MyTextButton(
              onPressed: () {
                setState(() {
                  if (showUnreviewed) {
                    showUnreviewed = false;
                    removeUnreviewedFromGenerated();
                  } else {
                    generatedIdeas = [...unreviewedIdeas];
                    showUnreviewed = true;
                  }
                });
              },
              icon: const Icon(Icons.history, size: 18),
              child: Text(
                showUnreviewed
                    ? "Hide Unreviewed Ideas"
                    : "Show Unreviewed Ideas",
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ),

        const SizedBox(height: 32),

        // Generated Ideas
        if (generatedIdeas.isNotEmpty)
          SizedBox(
            width: ideasListWidth,
            child: ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: generatedIdeas.length,
              itemBuilder: (context, index) {
                final idea = generatedIdeas[index];
                final String ideaText = idea['response']?.toString() ?? '';
                final String ideaSource = idea['source']?.toString() ?? '';
                final String ideaBackground =
                    idea['background']?.toString() ?? '';

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: lightColor.withOpacity(0.2),
                    border: Border.all(
                      color: darkColor.withOpacity(0.2),
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    title: Text(
                      ideaText,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (idea['category'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              idea['category'].toString(),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: darkColor),
                            ),
                          ),
                        if (ideaSource.isNotEmpty) const SizedBox(height: 4),
                        if (ideaSource.isNotEmpty)
                          Text(
                            'Source: $ideaSource',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        if (ideaBackground.isNotEmpty)
                          const SizedBox(height: 4),
                        if (ideaBackground.isNotEmpty)
                          Text(
                            'Background: $ideaBackground',
                            maxLines: isWide ? null : 2,
                            overflow: isWide
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Accept',
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () async {
                            setState(() {
                              generatedIdeas.remove(idea);
                            });
                            await acceptIdea(idea);
                          },
                        ),
                        IconButton(
                          tooltip: 'Reject',
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () async {
                            setState(() {
                              generatedIdeas.remove(idea);
                            });
                            await removeIdeaFromPrefs(idea);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

        if (isLoading)
          SizedBox(
            width: ideasListWidth,
            child: ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: indexCountCap,
              itemBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: ShimmerRow(),
              ),
            ),
          ),
      ],
    );
  }
}

// Tiny shimmer row
class ShimmerRow extends StatelessWidget {
  const ShimmerRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: lightColor,
      highlightColor: darkColor.withOpacity(0.5),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            16,
          ),
        ),
      ),
    );
  }
}
