// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:blob/pages/ai_generator/background_generator_controls.dart';
import 'package:blob/pages/ai_generator/foreground_control_panel.dart';
import 'package:blob/provider/clear_notifier.dart';
import 'package:blob/utils/media_variant.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/utils/future_date_time_picker.dart';
import 'package:blob/widgets/idea_card.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/widgets/my_dropdown.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/my_switch.dart';
import 'package:blob/widgets/my_textfield.dart';
import 'package:blob/utils/show_platform_picker.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:blob/services/ai_cost_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AIGeneratorPage extends StatefulWidget {
  const AIGeneratorPage({super.key});

  @override
  State<AIGeneratorPage> createState() => _AIGeneratorPageState();
}

class _AIGeneratorPageState extends State<AIGeneratorPage> {
  final textPromptController = TextEditingController();
  final imagePromptController = TextEditingController();
  Map<String, List<Map<String, dynamic>>>? availableIdeas;
  String? generated;
  bool isLoading = false;
  bool? isPremium;

  final List<String> platforms = const ['LinkedIn', 'Instagram', 'Facebook'];
  List selectedPlatforms = [];
  String length = 'Short';
  String tone = 'Professional';
  bool isNewsSelected = false;
  String newsDuration = '7 Days';
  bool allowEmojis = true;
  bool allowHashtags = true;
  bool isIdeasLoading = true;
  bool isScheduling = false;

  String? selectedTextIdea;
  String? selectedTextIdeaId;
  String? currentlySelectedTextIdea;
  String? currentlySelectedTextIdeaId;
  List<PlatformFile> selectedTextImages = [];

  List? imageIdeaList;
  String selectedTab = 'Image';
  String selectedImageTab = 'Quote';
  String? selectedImageIdea;
  String? selectedImageIdeaBackground;
  String? selectedImageIdeaSource;
  Map<String, dynamic>? selectedImageIdeaCustomization;
  String? currentlySelectedImageIdea;
  String? currentlySelectedImageIdeaBackground;
  String? currentlySelectedImageIdeaSource;
  Map<String, dynamic>? currentlySelectedImageIdeaCustomization;
  String? selectedImageBackgroundUrl;
  String? currentlySelectedImageBackgroundUrl;
  bool isSelectedAIGeneratedBackground = false;
  bool isCurrentlySelectedAIGeneratedBackground = false;

  Future<List<String>>? customBackgroundFuture;
  Future<List<String>>? prebuiltBackgroundFuture;
  Future<List<String>>? prebuiltCategoryListFuture;
  String? selectedPrebuiltCategory;

  Timer? _savePrefsDebounce;

  final durationOptions = ['1 Day', '7 Days', '1 Month', '6 Months', '1 Year'];

  @override
  void initState() {
    super.initState();
    unawaited(loadPreferences());
    unawaited(loadAvailableIdeas());
    unawaited(checkPlan());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final clearTrigger = context.watch<ClearNotifier>();
    if (clearTrigger.shouldClear) {
      setState(() {
        textPromptController.clear();
        imagePromptController.clear();
        availableIdeas = null;
        generated = null;
        isLoading = false;
        isPremium = null;
        selectedPlatforms = [];
        length = 'Short';
        tone = 'Professional';
        isNewsSelected = false;
        newsDuration = '7 Days';
        allowEmojis = true;
        allowHashtags = true;
        isIdeasLoading = false;
        isScheduling = false;

        selectedTextIdea = null;
        selectedTextIdeaId = null;
        currentlySelectedTextIdea = null;
        currentlySelectedTextIdeaId = null;
        selectedTextImages = [];

        imageIdeaList = null;
        selectedTab = 'Image';
        selectedImageTab = 'Quote';
        selectedImageIdea = null;
        selectedImageIdeaBackground = null;
        selectedImageIdeaSource = null;
        selectedImageIdeaCustomization = null;
        currentlySelectedImageIdea = null;
        currentlySelectedImageIdeaBackground = null;
        currentlySelectedImageIdeaSource = null;
        currentlySelectedImageIdeaCustomization = null;
        selectedImageBackgroundUrl = null;
        currentlySelectedImageBackgroundUrl = null;
        isSelectedAIGeneratedBackground = false;
        isCurrentlySelectedAIGeneratedBackground = false;

        customBackgroundFuture = null;
        prebuiltBackgroundFuture = null;
        prebuiltCategoryListFuture = null;
        selectedPrebuiltCategory = null;
      });
      clearTrigger.acknowledgeClear();
    }
  }

  @override
  void dispose() {
    textPromptController.dispose();
    imagePromptController.dispose();
    _savePrefsDebounce?.cancel();
    super.dispose();
  }

  // ---------------- Infra helpers ----------------

  Future<T> withRetry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 350),
  }) async {
    var attempt = 0;
    var delay = initialDelay;
    while (true) {
      try {
        return await task();
      } catch (_) {
        attempt++;
        if (attempt >= maxAttempts) rethrow;
        final jitter = Duration(milliseconds: 100 + attempt * 50);
        await Future.delayed(delay + jitter);
        delay *= 2;
      }
    }
  }

  void scheduleSavePreferences() {
    _savePrefsDebounce?.cancel();
    _savePrefsDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(savePreferences());
    });
  }

  String contentTypeForExtension(String ext) {
    final e = ext.toLowerCase();
    if (e == 'png') return 'image/png';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'webp') return 'image/webp';
    if (e == 'gif') return 'image/gif';
    return 'application/octet-stream';
  }

  // ---------------- Data loads ----------------

  Future<void> checkPlan() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    final res = await Supabase.instance.client
        .from('users')
        .select('current_plan_id')
        .eq('id', userId)
        .single();
    final currentPlan = res['current_plan_id'];
    if (mounted) {
      setState(() {
        isPremium = currentPlan == 'creator' || currentPlan == 'studio';
      });
    }
  }

  Future<void> loadAvailableIdeas() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final ideas = await supabase
        .from('content_ideas')
        .select(
          'id,user_id,category,idea,source,background,customization,created_at,accepted,used_in_generation',
        )
        .eq('user_id', userId)
        .eq('accepted', true)
        .eq('used_in_generation', false)
        .order('created_at', ascending: false);

    final Map<String, List<Map<String, dynamic>>> categorizedIdeas = {
      'Text': [],
      'Quote': [],
      'Fact': [],
      'Tip': [],
    };

    for (final idea in ideas) {
      final category = idea['category'] as String?;
      if (category != null && categorizedIdeas.containsKey(category)) {
        categorizedIdeas[category]!.add(Map<String, dynamic>.from(idea));
      }
    }

    if (mounted) {
      setState(() {
        availableIdeas = categorizedIdeas;
        isIdeasLoading = false;
      });
    }
  }

  Future<void> loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ai_generator_preferences');
    if (raw == null) return;
    final data = jsonDecode(raw);
    await prefs.setString('ai_generator_preferences', jsonEncode(data));
    if (!mounted) return;
    setState(() {
      selectedPlatforms = data['selectedPlatforms'] ?? [];
      length = data['length'] ?? length;
      tone = data['tone'] ?? tone;
      isNewsSelected = data['isNewsSelected'] ?? isNewsSelected;
      newsDuration = data['newsDuration'] ?? newsDuration;
      allowEmojis = data['allowEmojis'] ?? allowEmojis;
      allowHashtags = data['allowHashtags'] ?? allowHashtags;
    });
  }

  Future<void> savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'selectedPlatforms': selectedPlatforms,
      'length': length,
      'tone': tone,
      'isNewsSelected': isNewsSelected,
      'newsDuration': newsDuration,
      'allowEmojis': allowEmojis,
      'allowHashtags': allowHashtags,
    };
    await prefs.setString('ai_generator_preferences', jsonEncode(data));
  }

  // ---------------- Scheduling & upload ----------------

  Future<void> scheduleSelectedPosts({
    required Map<String, List<String>> selectedPostTypesMap,
    required List<String> mediaUrls,
    required String caption,
    required DateTime scheduledAt,
  }) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;

    const platformOf = {
      'linkedin_post': 'linkedin',
      'linkedin_image': 'linkedin',
      'linkedin_carousel': 'linkedin',
      'facebook_post': 'facebook',
      'facebook_image': 'facebook',
      'facebook_story': 'facebook',
      'facebook_multi': 'facebook',
      'instagram_post': 'instagram',
      'instagram_story': 'instagram',
      'instagram_carousel': 'instagram',
    };

    final rows = <Map<String, dynamic>>[];
    selectedPostTypesMap.forEach((_, types) {
      for (final pt in types) {
        final platform = platformOf[pt] ?? (throw 'Unknown postType $pt');
        rows.add({
          'user_id': userId,
          'platform': platform,
          'post_type': pt,
          'caption': caption,
          'media_urls': mediaUrls,
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
          'status': 'scheduled',
        });
      }
    });

    if (rows.isEmpty) throw 'No post types selected';
    await supabase.from('scheduled_posts').insert(rows);
  }

  Future<List<String>> uploadMedia(List<PlatformFile> files) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;
    final today = DateFormat('yyyyMMdd').format(DateTime.now());

    final urls = <String>[];
    try {
      for (final pf in files) {
        final bytes = pf.bytes ?? await File(pf.path!).readAsBytes();
        final ext = pf.extension ?? 'bin';
        final key = '$userId/$today/${const Uuid().v4()}.$ext';

        await withRetry(() {
          return supabase.storage.from('posts').uploadBinary(
                key,
                bytes,
                fileOptions: FileOptions(
                  contentType: contentTypeForExtension(ext),
                ),
              );
        });

        urls.add(supabase.storage.from('posts').getPublicUrl(key));
      }
      return urls;
    } catch (e) {
      debugPrint('uploadMedia error: $e');
      if (urls.isEmpty) rethrow;
      return urls;
    }
  }

  Future<void> showScheduleBottomSheet(String caption, double width) async {
    final captionController = TextEditingController(text: caption);

    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      builder: (_) {
        bool localScheduling = false;
        final double w = width >= 900 ? width * 0.8 : width - 32;
        final double thumbsW = width >= 900 ? width * 0.4 : w;

        return Padding(
          padding: EdgeInsets.all(width >= 900 ? width * 0.0125 : 16),
          child: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Schedule Your Post',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: w,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: darkColor, width: 1),
                      ),
                      child: TextFormField(
                        controller: captionController,
                        minLines: 6,
                        maxLines: 12,
                        decoration: InputDecoration(
                          hintText: 'Edit your caption',
                          hintStyle: TextStyle(color: darkColor),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    if (selectedTextImages.isNotEmpty)
                      const SizedBox(height: 12),
                    if (selectedTextImages.isNotEmpty)
                      Center(
                        child: SizedBox(
                          width: thumbsW,
                          height: 100,
                          child: RepaintBoundary(
                            child: ListView.builder(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              scrollDirection: Axis.horizontal,
                              itemCount: selectedTextImages.length > 6
                                  ? 6
                                  : selectedTextImages.length,
                              itemBuilder: (context, index) {
                                final showCounter =
                                    selectedTextImages.length > 6 && index == 5;
                                return AspectRatio(
                                  aspectRatio: 1,
                                  child: Container(
                                    margin: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        width: 0.5,
                                        color: darkColor.withOpacity(0.5),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(100),
                                      child: showCounter
                                          ? Container(
                                              color: darkColor,
                                              child: Center(
                                                child: Text(
                                                  '+${selectedTextImages.length - 5}',
                                                  style: const TextStyle(
                                                      color: lightColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16),
                                                ),
                                              ),
                                            )
                                          : Image.memory(
                                              selectedTextImages[index].bytes!,
                                              fit: BoxFit.cover,
                                              width: 100,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  const Center(
                                                child: Icon(Icons.broken_image),
                                              ),
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    MyButton(
                      width: w,
                      text: 'Confirm & Schedule',
                      isLoading: localScheduling,
                      onTap: () async {
                        try {
                          setState(() => localScheduling = true);
                          final selected =
                              await showFutureDateTimePicker(context);
                          if (selected == null) {
                            setState(() => localScheduling = false);
                            return;
                          }

                          final pfs =
                              getEligiblePlatforms(selectedTextImages.length);
                          final selectedPlatforms =
                              await showPlatformPicker(context, platforms: pfs);
                          if (selectedPlatforms == null ||
                              selectedPlatforms.isEmpty) {
                            setState(() => localScheduling = false);
                            return mySnackBar(context, 'Select Platforms');
                          }

                          final postTypeMap = getPostTypesFor(
                              selectedPlatforms, selectedTextImages.length);
                          final selectedPostTypesMap =
                              await showPostTypePicker(context, postTypeMap);
                          if (selectedPostTypesMap == null) {
                            setState(() => localScheduling = false);
                            return mySnackBar(context, 'Select Post Types');
                          }

                          final mediaUrls =
                              await uploadMedia(selectedTextImages);
                          if (selectedTextImages.isNotEmpty &&
                              mediaUrls.isEmpty) {
                            setState(() => localScheduling = false);
                            return;
                          }

                          await scheduleSelectedPosts(
                            selectedPostTypesMap: selectedPostTypesMap,
                            mediaUrls: mediaUrls,
                            caption: captionController.text.trim(),
                            scheduledAt: selected,
                          );

                          await markIdeaUsed(null);
                          context.read<ClearNotifier>().triggerClear();
                          mySnackBar(context, 'Post scheduled successfully!');
                          context.pop();
                          context.go('/home');
                        } catch (_) {
                          mySnackBar(context, 'Some error occured');
                          context.pop();
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> generateCaption(double width) async {
    if (textPromptController.text.trim().isEmpty && !isNewsSelected) {
      return mySnackBar(context, 'Please enter a prompt');
    }
    if (selectedPlatforms.isEmpty) {
      return mySnackBar(context, 'Select Platform to generate captions for');
    }

    setState(() => isLoading = true);

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      context.go('/login');
      return;
    }

    // Check AI cost limits before generation
    final canGenerate =
        await AICostController.canMakeRequest(user.id, 'gpt-3.5-turbo');
    if (!canGenerate) {
      setState(() => isLoading = false);
      return mySnackBar(context,
          'Daily AI generation limit reached. Please upgrade your plan.');
    }

    final profile = await supabase
        .from('brand_profiles')
        .select(
            'persona,category,subcategory,primary_goal,brand_name,brand_logo_path,primary_color,voice_tags,content_types,target_posts_per_week,timezone')
        .eq('user_id', user.id)
        .maybeSingle();

    final profileData = {
      'persona': profile?['persona'],
      'category': profile?['category'],
      'subcategory': profile?['subcategory'],
      'primary_goal': profile?['primary_goal'],
      'brand_name': profile?['brand_name'],
      'brand_logo_path': profile?['brand_logo_path'],
      'primary_color': profile?['primary_color'],
      'voice_tags': profile?['voice_tags'],
      'content_types': profile?['content_types'],
      'target_posts_per_week': profile?['target_posts_per_week'],
      'timezone': profile?['timezone'] ?? '',
    };

    // Check cache first
    final contextData = {
      'platform': selectedPlatforms.join(', '),
      'tone': tone,
      'length': length,
      'generate_from_news': isNewsSelected,
      'profile': profileData,
      'news_age_window': newsDuration,
      'allow_emojis': allowEmojis,
      'allow_hashtags': allowHashtags,
    };

    final cachedResult = await AICostController.getCachedResult(
      textPromptController.text,
      contextData,
      'gpt-3.5-turbo',
    );

    if (cachedResult != null) {
      setState(() {
        generated = cachedResult;
        isLoading = false;
      });
      return;
    }

    try {
      final session = supabase.auth.currentSession;
      final accessToken = session?.accessToken;

      final res = await withRetry(() {
        return http
            .post(
              Uri.parse(
                  'https://ehgginqelbgrzfrzbmis.functions.supabase.co/generate-caption'),
              headers: {
                'Content-Type': 'application/json',
                if (accessToken != null) 'Authorization': 'Bearer $accessToken',
              },
              body: jsonEncode({
                'prompt': textPromptController.text,
                'platform': selectedPlatforms.join(', '),
                'tone': tone,
                'length': length,
                'generate_from_news': isNewsSelected,
                'profile': profileData,
                'news_age_window': newsDuration,
                'allow_emojis': allowEmojis,
                'allow_hashtags': allowHashtags,
              }),
            )
            .timeout(const Duration(seconds: 25));
      });

      final data = jsonDecode(res.body);
      final caption = data['caption'] ?? 'Error generating';

      // Cache the result
      await AICostController.cacheResult(
        textPromptController.text,
        contextData,
        'gpt-3.5-turbo',
        caption,
      );

      // Track token usage (estimate)
      final estimatedTokens =
          (textPromptController.text.length + caption.length) ~/ 4;
      AICostController.trackTokenUsage('gpt-3.5-turbo', estimatedTokens);

      setState(() {
        generated = caption;
        isLoading = false;
      });

      if (generated == 'No Major News in the Selected Time Range') {
        mySnackBar(context, 'No recent news found in selected time range');
        return;
      } else if (generated == 'Error Generating') {
        mySnackBar(context, 'Some error occured!');
        return;
      } else {
        await showScheduleBottomSheet(generated!, width);
      }
    } catch (e) {
      setState(() => isLoading = false);
      return mySnackBar(context, 'Error: $e');
    }
  }

  Future<List<String>> loadCustomBackgroundUrls() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await supabase
          .schema('brand_kit')
          .from('brand_kits')
          .select('backgrounds')
          .eq('user_id', userId)
          .maybeSingle();
      if (response == null || response['backgrounds'] == null) return [];
      final List<dynamic> paths = response['backgrounds'];

      final urls = await Future.wait(paths.map((path) async {
        final res = await supabase.storage
            .from('brand-kits')
            .createSignedUrl(path, 60 * 60);
        return res;
      }));
      return urls;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> loadPrebuiltBackgroundCategories() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    try {
      final response =
          await supabase.from('prebuilt_backgrounds').select('category');
      final categories = (response as List)
          .map((r) => r['category']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();

      final profile = await supabase
          .from('brand_profiles')
          .select('category')
          .eq('user_id', user!.id)
          .maybeSingle();
      final userCat = profile?['category']?.toString();

      final defaultCat = (userCat != null && categories.contains(userCat))
          ? userCat
          : (categories.isNotEmpty ? categories.first : '');

      setState(() {
        selectedPrebuiltCategory = defaultCat;
        prebuiltBackgroundFuture = loadPrebuiltBackgroundUrls(defaultCat);
      });

      return categories;
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> loadPrebuiltBackgroundUrls(String? category) async {
    final supabase = Supabase.instance.client;

    try {
      if (category == null || category.isEmpty) {
        final user = supabase.auth.currentUser;
        if (user == null) {
          context.go('/login');
          return [];
        }
        final profile = await supabase
            .from('brand_profiles')
            .select('category')
            .eq('user_id', user.id)
            .maybeSingle();
        category = profile?['category']?.toString() ?? '';
      }

      if (category.isEmpty) return [];

      final response = await supabase
          .from('prebuilt_backgrounds')
          .select('path')
          .eq('category', category);
      final rows = List<Map<String, dynamic>>.from(response as List);

      final urls = <String>[];
      await Future.wait(rows.map((row) async {
        final path = row['path']?.toString().trim() ?? '';
        if (path.isEmpty) return;
        try {
          final signedUrl = await supabase.storage
              .from('backgrounds')
              .createSignedUrl(path, 3600);
          if (signedUrl.isNotEmpty) urls.add(signedUrl);
        } catch (_) {
          mySnackBar(context, 'Some error occured');
        }
      }));

      return urls;
    } catch (_) {
      mySnackBar(context, 'Some error occured');
      return [];
    }
  }

  Future<void> markIdeaUsed(String? ideaId) async {
    if (ideaId != null || selectedTextIdeaId != null) {
      final supabase = Supabase.instance.client;
      try {
        await supabase
            .from('content_ideas')
            .update({'used_in_generation': true}).eq(
                'id', ideaId ?? selectedTextIdeaId!);
        if (availableIdeas != null &&
            availableIdeas![
                    selectedTab == 'Image' ? selectedImageTab : selectedTab] !=
                null) {
          setState(() {
            availableIdeas![
                    selectedTab == 'Image' ? selectedImageTab : selectedTab]!
                .removeWhere(
              (idea) => idea['id'] == (ideaId ?? selectedTextIdeaId),
            );
          });
        }
      } catch (_) {
        mySnackBar(context, 'Failed to delete idea');
      }
    }
  }

  void resetImageTabState() {
    currentlySelectedImageIdea = null;
    currentlySelectedImageIdeaBackground = null;
    currentlySelectedImageIdeaSource = null;
    currentlySelectedImageBackgroundUrl = null;
    selectedImageIdea = null;
    selectedImageIdeaBackground = null;
    selectedImageIdeaSource = null;
    selectedImageBackgroundUrl = null;
    selectedImageIdeaCustomization = null;
    currentlySelectedImageIdeaCustomization = null;
    isSelectedAIGeneratedBackground = false;
    isCurrentlySelectedAIGeneratedBackground = false;
    imagePromptController.clear();
  }

  Widget buildTabChip(String label, bool selected, VoidCallback onTap) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? lightColor : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? darkColor : lightColor,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    const Icon(
                      Icons.check,
                      size: 18,
                      color: Color(0xFF004aad),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? const Color(0xFF004aad)
                          : const Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget backgroundPickerSection({
    required double width,
    required String title,
    required Future<List<String>>? future,
    required String? selectedUrl,
    required void Function(String) onSelect,
    Widget? categoryDropdown,
  }) {
    return Container(
      width: width,
      padding: EdgeInsets.all(width >= 900 ? width * 0.0125 : 4),
      decoration: BoxDecoration(
        color: lightColor.withOpacity(0.06125),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                    fontSize: 18,
                    color: darkColor,
                    fontWeight: FontWeight.w600),
              ),
              if (categoryDropdown != null) categoryDropdown,
            ],
          ),
          const SizedBox(height: 12),
          if (future == null)
            const SizedBox.shrink()
          else
            FutureBuilder<List<String>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  final itemW = (width >= 900 ? width * 0.1225 : 90.0);
                  final margin = (width >= 900 ? width * 0.006125 : 6.0);
                  return SizedBox(
                    width: width,
                    height: itemW + 8,
                    child: AutoSkeleton(
                      enabled: true,
                      preserveSize: true,
                      baseColor: lightColor,
                      effectColor: darkColor,
                      borderRadius: 18,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 6,
                        itemBuilder: (_, __) => Container(
                          margin: EdgeInsets.all(margin),
                          width: itemW,
                          height: itemW,
                          decoration: BoxDecoration(
                            color: lightColor,
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: TextStyle(color: darkColor, fontSize: 16),
                        ),
                      ),
                      MyTextButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      )
                    ],
                  );
                }

                final urls = snapshot.data ?? const <String>[];
                if (urls.isEmpty) return const Text('No Backgrounds Found');

                final itemW = (width >= 900 ? width * 0.1225 : 90.0);
                final margin = (width >= 900 ? width * 0.006125 : 6.0);
                return BackgroundThumbStrip(
                  urls: urls,
                  width: width,
                  itemWidth: itemW,
                  itemMargin: margin,
                  selectedUrl: selectedUrl,
                  onSelect: onSelect,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget buildSwitch(String label, bool value, void Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        MySwitch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget buildImageUploader(BuildContext context, double width) {
    final isEmpty = selectedTextImages.isEmpty;
    final double addBtnSize = width >= 900 ? width * 0.0153125 : 48;
    final double addIcon = width >= 900 ? width * 0.0125 : 28;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lightColor.withOpacity(0.25),
        border: Border.all(
          width: 2,
          color: lightColor.withOpacity(0.5),
        ),
        borderRadius: BorderRadius.circular(100),
      ),
      padding: EdgeInsets.all(width >= 900 ? width * 0.006125 : 8),
      child: isEmpty
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add Image',
                  style: TextStyle(color: darkColor),
                ),
                addImageButton(context, addBtnSize, addIcon),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: width >= 900 ? width * 0.4 : width * 0.6,
                  height: 100,
                  child: RepaintBoundary(
                    child: ListView.builder(
                      primary: false,
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedTextImages.length,
                      itemBuilder: (context, index) {
                        final image = selectedTextImages[index];
                        return Stack(
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                margin: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    width: 0.5,
                                    color: darkColor.withOpacity(0.5),
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: ClipOval(
                                  child: Image.memory(
                                    image.bytes!,
                                    fit: BoxFit.cover,
                                    width: 100,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Tooltip(
                                message: 'Remove',
                                child: InkWell(
                                  onTap: () => setState(
                                    () => selectedTextImages.removeAt(index),
                                  ),
                                  borderRadius: BorderRadius.circular(100),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                        color: Colors.black,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.close,
                                        size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                addImageButton(context, addBtnSize, addIcon),
              ],
            ),
    );
  }

  Widget addImageButton(BuildContext context, double size, double iconSize) {
    return GestureDetector(
      onTap: () async {
        final result = await FilePicker.platform.pickFiles(
            type: FileType.image, withData: true, allowMultiple: true);
        if (result == null || result.files.isEmpty) {
          mySnackBar(context, 'No image selected');
          return;
        }

        // Deduplicate, enforce max count, filter huge files
        const maxCount = 10;
        const maxBytes = 8 * 1024 * 1024; // 8 MB per image guard
        final existingNames = selectedTextImages.map((e) => e.name).toSet();
        final addable = result.files
            .where((f) =>
                f.bytes != null &&
                f.bytes!.isNotEmpty &&
                f.bytes!.length <= maxBytes &&
                !existingNames.contains(f.name))
            .toList();

        if (addable.isEmpty) {
          mySnackBar(context, 'No valid images to add');
          return;
        }

        final spaceLeft = maxCount - selectedTextImages.length;
        if (spaceLeft <= 0) {
          mySnackBar(context, 'Limit reached ($maxCount images)');
          return;
        }

        setState(() {
          selectedTextImages.addAll(addable.take(spaceLeft));
        });
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: lightColor.withOpacity(0.25),
          border: Border.all(
            width: 2,
            color: darkColor.withOpacity(0.5),
          ),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Icon(Icons.add_rounded, color: darkColor, size: iconSize),
      ),
    );
  }

  List<Map<String, dynamic>> ideasFor(String key) {
    final map = availableIdeas;
    if (map == null) return const [];
    final raw = map[key];
    if (raw is List) return raw!.cast<Map<String, dynamic>>();
    return const [];
  }

  Widget buildMobile(BuildContext context, BoxConstraints c) {
    final w = c.maxWidth;

    return Scaffold(
      backgroundColor: const Color.fromRGBO(247, 249, 252, 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top tabs
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                buildTabChip('Image', selectedTab == 'Image', () {
                  setState(() => selectedTab = 'Image');
                }),
                buildTabChip('Text', selectedTab == 'Text', () {
                  setState(() => selectedTab = 'Text');
                }),
              ],
            ),
            const SizedBox(height: 12),
            if (selectedTab == 'Image')
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  buildTabChip('Quote', selectedImageTab == 'Quote', () {
                    if (selectedImageTab != 'Quote') resetImageTabState();
                    setState(() => selectedImageTab = 'Quote');
                  }),
                  buildTabChip('Fact', selectedImageTab == 'Fact', () {
                    if (selectedImageTab != 'Fact') resetImageTabState();
                    setState(() => selectedImageTab = 'Fact');
                  }),
                  buildTabChip('Tip', selectedImageTab == 'Tip', () {
                    if (selectedImageTab != 'Tip') resetImageTabState();
                    setState(() => selectedImageTab = 'Tip');
                  }),
                ],
              ),

            if (selectedTab == 'Text' && selectedTextIdea == null) ...[
              const SizedBox(height: 24),
              const Text(
                'Step 1: Choose an Idea',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              MyTextField(
                width: double.infinity,
                controller: textPromptController,
                hintText: 'Enter my own Idea',
                onChanged: (_) {
                  setState(() => currentlySelectedTextIdea = null);
                  scheduleSavePreferences();
                },
              ),
              const SizedBox(height: 12),
              if (availableIdeas != null &&
                  ideasFor('Text').isEmpty &&
                  textPromptController.text.isNotEmpty)
                MyButton(
                  text: 'Next',
                  width: double.infinity,
                  onTap: () async {
                    if (textPromptController.text.trim().isEmpty) {
                      return mySnackBar(context, 'Please enter your idea');
                    }
                    setState(
                        () => selectedTextIdea = textPromptController.text);
                  },
                  isLoading: false,
                ),
            ],

            if (selectedTab == 'Image' && selectedImageIdea == null) ...[
              MyTextField(
                width: double.infinity,
                controller: imagePromptController,
                hintText:
                    'Enter my own ${selectedImageTab == 'Quote' ? 'Quote' : selectedImageTab == 'Fact' ? 'Fact' : 'Tip'}',
                onChanged: (_) {
                  setState(() {
                    currentlySelectedImageIdea = null;
                    currentlySelectedImageIdeaBackground = null;
                    currentlySelectedImageIdeaSource = null;
                    currentlySelectedImageIdeaCustomization = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (availableIdeas != null &&
                  ideasFor(selectedImageTab).isEmpty &&
                  imagePromptController.text.isNotEmpty)
                MyButton(
                  text: 'Next',
                  width: double.infinity,
                  onTap: () async {
                    if (imagePromptController.text.trim().isEmpty) {
                      return mySnackBar(context, 'Please enter your idea');
                    }
                    setState(
                        () => selectedImageIdea = imagePromptController.text);
                    customBackgroundFuture = loadCustomBackgroundUrls();
                    prebuiltBackgroundFuture = loadPrebuiltBackgroundUrls(null);
                    prebuiltCategoryListFuture =
                        loadPrebuiltBackgroundCategories();
                  },
                  isLoading: false,
                ),
            ],

            // available ideas list
            if (availableIdeas != null &&
                ((selectedTab == 'Text' && selectedTextIdea == null) ||
                    (selectedTab == 'Image' && selectedImageIdea == null)))
              mobileIdeaList(w),

            if ((selectedTab == 'Image' && selectedImageIdea == null) ||
                (selectedTab == 'Text' && selectedTextIdea == null))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: MyButton(
                  text: 'Next',
                  width: double.infinity,
                  onTap: () {
                    if (selectedTab == 'Image') {
                      final idea = (currentlySelectedImageIdea != null &&
                              currentlySelectedImageIdea!.trim().isNotEmpty)
                          ? currentlySelectedImageIdea!.trim()
                          : imagePromptController.text.trim().isNotEmpty
                              ? imagePromptController.text.trim()
                              : null;
                      if (idea == null) {
                        return mySnackBar(
                            context, 'Select an idea or enter your own');
                      }
                      setState(() {
                        selectedImageIdea = idea;
                        selectedImageIdeaBackground =
                            currentlySelectedImageIdeaBackground;
                        selectedImageIdeaSource =
                            currentlySelectedImageIdeaSource;
                        selectedImageIdeaCustomization =
                            currentlySelectedImageIdeaCustomization;
                      });
                      customBackgroundFuture = loadCustomBackgroundUrls();
                      prebuiltBackgroundFuture =
                          loadPrebuiltBackgroundUrls(null);
                      prebuiltCategoryListFuture =
                          loadPrebuiltBackgroundCategories();
                    } else {
                      final idea = (currentlySelectedTextIdea != null &&
                              currentlySelectedTextIdea!.trim().isNotEmpty)
                          ? currentlySelectedTextIdea!.trim()
                          : textPromptController.text.trim().isNotEmpty
                              ? textPromptController.text.trim()
                              : null;
                      if (idea == null) {
                        return mySnackBar(
                            context, 'Select an idea or enter your own');
                      }
                      setState(() {
                        selectedTextIdea = idea;
                        if (currentlySelectedTextIdeaId != null) {
                          selectedTextIdeaId = currentlySelectedTextIdeaId;
                        }
                      });
                    }
                  },
                  isLoading: false,
                ),
              ),

            // ----- STEP 2: background for image flow -----
            if (selectedTab == 'Image' &&
                selectedImageIdea != null &&
                selectedImageBackgroundUrl == null &&
                !isSelectedAIGeneratedBackground) ...[
              const SizedBox(height: 24),
              const Text(
                'Step 2: Select Background',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              backgroundPickerSection(
                width: w,
                title: 'Custom Backgrounds',
                future: customBackgroundFuture,
                selectedUrl: currentlySelectedImageBackgroundUrl,
                onSelect: (u) => setState(() {
                  currentlySelectedImageBackgroundUrl = u;
                  isCurrentlySelectedAIGeneratedBackground = false;
                }),
              ),

              backgroundPickerSection(
                width: w,
                title: 'Prebuilt Backgrounds',
                future: prebuiltBackgroundFuture,
                selectedUrl: currentlySelectedImageBackgroundUrl,
                categoryDropdown: prebuiltCategoryListFuture == null
                    ? null
                    : FutureBuilder<List<String>>(
                        future: prebuiltCategoryListFuture,
                        builder: (context, snap) {
                          // normalize + dedupe while preserving order
                          final seen = <String>{};
                          final items = <String>[];
                          for (final s in (snap.data ?? const <String>[])) {
                            final t = s.trim();
                            if (t.isNotEmpty && seen.add(t)) items.add(t);
                          }

                          // safe selected value (must be in the deduped list)
                          final String? value =
                              items.contains(selectedPrebuiltCategory)
                                  ? selectedPrebuiltCategory
                                  : null;

                          return ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 150),
                            child: MyDropDown(
                              key: ValueKey(
                                  '${items.join("|")}::$value'), // forces rebuild on data change
                              items: items,
                              value: value, // null if not present
                              onChanged: (v) {
                                setState(() => selectedPrebuiltCategory =
                                    v); // don't write ''
                                prebuiltBackgroundFuture =
                                    loadPrebuiltBackgroundUrls(v);
                              },
                              hint: 'Category',
                            ),
                          );
                        },
                      ),
                onSelect: (u) => setState(() {
                  currentlySelectedImageBackgroundUrl = u;
                  isCurrentlySelectedAIGeneratedBackground = false;
                }),
              ),

              const SizedBox(height: 12),
              Center(
                child: Text('OR', style: TextStyle(color: darkColor)),
              ),
              const SizedBox(height: 12),

              // AI background toggle
              GestureDetector(
                onTap: () {
                  setState(() {
                    isCurrentlySelectedAIGeneratedBackground =
                        !isCurrentlySelectedAIGeneratedBackground;
                    currentlySelectedImageBackgroundUrl = null;
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: lightColor.withOpacity(
                        isCurrentlySelectedAIGeneratedBackground
                            ? 0.125
                            : 0.06125),
                    border: Border.all(
                      color: isCurrentlySelectedAIGeneratedBackground
                          ? darkColor
                          : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: Text(
                      'Generate Background using AI',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              MyButton(
                text: 'Next',
                width: double.infinity,
                onTap: () {
                  if (!isCurrentlySelectedAIGeneratedBackground &&
                      currentlySelectedImageBackgroundUrl == null) {
                    return mySnackBar(
                      context,
                      'Select a background or choose AI',
                    );
                  }
                  setState(() {
                    if (isCurrentlySelectedAIGeneratedBackground) {
                      isSelectedAIGeneratedBackground = true;
                    } else {
                      selectedImageBackgroundUrl =
                          currentlySelectedImageBackgroundUrl;
                    }
                  });
                },
                isLoading: false,
              ),
            ],

            // ----- TEXT FLOW STEP 2 -----
            if (selectedTab == 'Text' && selectedTextIdea != null)
              mobileTextControls(w),

            // AI background controls when chosen
            if (selectedTab == 'Image' &&
                selectedImageIdea != null &&
                selectedImageIdeaCustomization != null &&
                selectedImageBackgroundUrl == null &&
                isSelectedAIGeneratedBackground)
              BackgroundControlsPanel(
                width: w,
                backgroundPrompt: selectedImageIdeaBackground,
                imageTab: selectedImageTab,
                customization: selectedImageIdeaCustomization,
                onImageGenerated: (u) => setState(() {
                  selectedImageBackgroundUrl = u;
                }),
              ),

            // foreground editor
            if (selectedTab == 'Image' &&
                selectedImageIdea != null &&
                selectedImageBackgroundUrl != null)
              ForegroundControlPanel(
                width: w,
                idea: selectedImageIdea!,
                source: selectedImageIdeaSource,
                background: selectedImageBackgroundUrl!,
                imageTab: selectedImageTab,
                onDone: () => context.read<ClearNotifier>().triggerClear(),
              ),
          ],
        ),
      ),
    );
  }

  Widget mobileIdeaList(double w) {
    final isImg = selectedTab == 'Image';
    final key = isImg ? selectedImageTab : 'Text';
    final list = ideasFor(key);
    if (list.isEmpty) {
      return Column(
        children: [
          const SizedBox(height: 8),
          const Text('No ideas available'),
          const SizedBox(height: 8),
          MyButton(
            text: 'Generate Ideas',
            width: double.infinity,
            onTap: () => context.go('/home/idea'),
            isLoading: false,
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final idea = list[i];
          final ideaText =
              (idea['idea'] is String) ? idea['idea'] as String : '';
          final ideaSrc =
              (idea['source'] is String) ? idea['source'] as String : null;
          return IdeaCard(
            text: ideaText,
            source: ideaSrc,
            isSelected: isImg
                ? currentlySelectedImageIdea == ideaText
                : currentlySelectedTextIdea == ideaText,
            onTap: () {
              setState(() {
                if (isImg) {
                  imagePromptController.clear();
                  currentlySelectedImageIdea = ideaText;
                  currentlySelectedImageIdeaBackground = idea['background'];
                  currentlySelectedImageIdeaSource = ideaSrc;
                  currentlySelectedImageIdeaCustomization =
                      idea['customization'];
                } else {
                  textPromptController.clear();
                  currentlySelectedTextIdea = ideaText;
                  if (idea['id'] != null) {
                    currentlySelectedTextIdeaId = idea['id'];
                  }
                }
              });
            },
            onMarkUsed: () async {
              final id = idea['id'];
              if (id != null) await markIdeaUsed(id);
            },
            width: w,
          );
        },
      ),
    );
  }

  Widget mobileTextControls(double w) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 2: Generate Caption',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // prompt vs news stacked
          MyTextField(
            width: double.infinity,
            controller: textPromptController,
            hintText: 'What do you want to post?',
            onChanged: (_) {
              setState(() => isNewsSelected = false);
              scheduleSavePreferences();
            },
          ),
          const SizedBox(height: 8),
          MyButton(
            text: 'Get Trending News',
            width: double.infinity,
            onTap: () {
              setState(() => isNewsSelected = true);
              scheduleSavePreferences();
            },
            isLoading: false,
          ),

          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: (w * 2) / 2 - 6,
                child: MyDropDown(
                  items: const ['Short', 'Medium', 'Long'],
                  value: length,
                  onChanged: (v) {
                    setState(() => length = v!);
                    scheduleSavePreferences();
                  },
                ),
              ),
              SizedBox(
                width: (w * 2) / 2 - 6,
                child: MyDropDown(
                  items: const ['Professional', 'Playful', 'Casual'],
                  value: tone,
                  onChanged: (v) {
                    setState(() => tone = v!);
                    scheduleSavePreferences();
                  },
                ),
              ),
              if (isNewsSelected)
                SizedBox(
                  width: double.infinity,
                  child: MyDropDown(
                    items: durationOptions.map((e) => 'Last $e').toList(),
                    value: 'Last $newsDuration',
                    onChanged: (v) {
                      setState(
                          () => newsDuration = v!.replaceFirst('Last ', ''));
                      scheduleSavePreferences();
                    },
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),
          buildSwitch('Use Emojis', allowEmojis, (v) {
            setState(() => allowEmojis = v);
            scheduleSavePreferences();
          }),
          const SizedBox(height: 8),
          buildSwitch('Use Hashtags', allowHashtags, (v) {
            setState(() => allowHashtags = v);
            scheduleSavePreferences();
          }),

          const SizedBox(height: 12),
          // platforms chips wrap
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: platforms.map((p) {
              final sel = selectedPlatforms.contains(p);
              return buildTabChip(p, sel, () {
                setState(() {
                  sel ? selectedPlatforms.remove(p) : selectedPlatforms.add(p);
                });
                scheduleSavePreferences();
              });
            }).toList(),
          ),

          const SizedBox(height: 12),
          buildImageUploader(context, w),

          const SizedBox(height: 16),
          MyButton(
            text: 'Generate Caption',
            width: double.infinity,
            onTap: () => generateCaption(w),
            isLoading: isLoading,
            borderRadius: 100,
          ),
          const SizedBox(height: 8),
          Center(
            child: MyTextButton(
              onPressed: () async {
                if (textPromptController.text.trim().isEmpty &&
                    !isNewsSelected) {
                  return mySnackBar(context, 'Please enter caption');
                }
                setState(() => generated = textPromptController.text);
                await showScheduleBottomSheet(generated!, w);
              },
              child: const Text('Schedule this'),
            ),
          ),
        ],
      ),
    );
  }

  Widget textControls({required double width}) {
    // Guard dropdown values
    const lengthItems = ['Short', 'Medium', 'Long'];
    const toneItems = ['Professional', 'Playful', 'Casual'];
    final durationItems = durationOptions.map((e) => 'Last $e').toList();

    String? safeLength = lengthItems.contains(length) ? length : null;
    String? safeTone = toneItems.contains(tone) ? tone : null;
    String? safeDuration = durationItems.contains('Last $newsDuration')
        ? 'Last $newsDuration'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 12),
        Text(
          'Step 2: Generate Caption',
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: darkColor),
        ),
        const SizedBox(height: 12),

        // prompt vs news
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: width,
              height: 48,
              child: GestureDetector(
                onTap: () {
                  if (isNewsSelected) {
                    setState(() => isNewsSelected = false);
                    scheduleSavePreferences();
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: darkColor, width: 1),
                  ),
                  child: TextFormField(
                    controller: textPromptController,
                    decoration: InputDecoration(
                      hintText: 'What do you want to post?',
                      hintStyle: TextStyle(color: darkColor),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                    onChanged: (_) {
                      setState(() => isNewsSelected = false);
                      scheduleSavePreferences();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                setState(() => isNewsSelected = true);
                scheduleSavePreferences();
              },
              child: Container(
                width: width,
                height: 44,
                decoration: BoxDecoration(
                  color: isNewsSelected ? darkColor : const Color(0xFF004AAD),
                  borderRadius: BorderRadius.circular(36),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Get Trending News',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // dropdowns
        Column(
          children: [
            MyDropDown(
              items: lengthItems,
              value: safeLength,
              onChanged: (val) {
                setState(() => length = val ?? 'Short');
                scheduleSavePreferences();
              },
            ),
            const SizedBox(height: 12),
            MyDropDown(
              items: toneItems,
              value: safeTone,
              onChanged: (val) {
                setState(() => tone = val ?? 'Professional');
                scheduleSavePreferences();
              },
            ),
            if (isNewsSelected) ...[
              const SizedBox(height: 12),
              MyDropDown(
                items: durationItems,
                value: safeDuration,
                onChanged: (val) {
                  if (val != null) {
                    setState(
                        () => newsDuration = val.replaceFirst('Last ', ''));
                    scheduleSavePreferences();
                  }
                },
              ),
            ],
          ],
        ),

        const SizedBox(height: 16),

        // switches
        Column(
          children: [
            buildSwitch('Use Emojis', allowEmojis, (val) {
              setState(() => allowEmojis = val);
              scheduleSavePreferences();
            }),
            const SizedBox(height: 8),
            buildSwitch('Use Hashtags', allowHashtags, (val) {
              setState(() => allowHashtags = val);
              scheduleSavePreferences();
            }),
          ],
        ),

        const SizedBox(height: 16),

        // platforms
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: platforms.map((platform) {
            final isSel = selectedPlatforms.contains(platform);
            return buildTabChip(platform, isSel, () {
              setState(() {
                if (isSel) {
                  selectedPlatforms.remove(platform);
                } else {
                  selectedPlatforms.add(platform);
                }
              });
              scheduleSavePreferences();
            });
          }).toList(),
        ),

        const SizedBox(height: 16),

        // images
        buildImageUploader(context, width),
        const SizedBox(height: 16),

        // generate
        MyButton(
          text: 'Generate Caption',
          width: width,
          height: 48,
          onTap: () async => await generateCaption(width),
          isLoading: isLoading,
          borderRadius: 100,
        ),

        const SizedBox(height: 12),

        // quick schedule
        Center(
          child: MyTextButton(
            onPressed: () async {
              if (textPromptController.text.trim().isEmpty && !isNewsSelected) {
                return mySnackBar(context, 'Please enter caption');
              }
              setState(() => generated = textPromptController.text);
              await showScheduleBottomSheet(generated!, width);
            },
            child: Text(
              'Schedule this',
              style: TextStyle(color: darkColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget buildDesktop(BuildContext context, BoxConstraints c) {
    Widget _wideContent({required double w, required double h}) {
      final width = w;
      final height = h;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selectedTab == 'Text' && selectedTextIdea == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Step 1: Choose an Idea',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkColor),
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    height: 66,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MyTextField(
                          width: width * 0.5,
                          controller: textPromptController,
                          hintText: 'Enter my own Idea',
                          onChanged: (p0) {
                            setState(() => currentlySelectedTextIdea = null);
                            scheduleSavePreferences();
                          },
                        ),
                        if (availableIdeas != null &&
                            availableIdeas!['Text'] != null &&
                            availableIdeas!['Text']!.isEmpty &&
                            textPromptController.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Next',
                            iconSize: 36,
                            splashRadius: 20,
                            onPressed: () async {
                              if (currentlySelectedTextIdea == null &&
                                  textPromptController.text.trim().isEmpty) {
                                return mySnackBar(context,
                                    'Please generate idea or enter your own');
                              }
                              setState(() =>
                                  selectedTextIdea = textPromptController.text);
                              customBackgroundFuture =
                                  loadCustomBackgroundUrls();
                              prebuiltBackgroundFuture =
                                  loadPrebuiltBackgroundUrls(null);
                              prebuiltCategoryListFuture =
                                  loadPrebuiltBackgroundCategories();
                            },
                            icon: const Icon(
                              Icons.arrow_circle_right_outlined,
                              color: Color(0xFF002f6e),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            )
          else if (selectedTextIdea != null)
            const SizedBox.shrink()
          else if (selectedTab == 'Text')
            const SizedBox(height: 64)
          else
            const SizedBox.shrink(),

          if (selectedTab == 'Image' && selectedImageIdea == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Step 1: Choose an Idea',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkColor),
                ),
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    height: 66,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MyTextField(
                          width: width * 0.5,
                          controller: imagePromptController,
                          hintText:
                              'Enter my own ${selectedImageTab == "Quote" ? "Quote" : selectedImageTab == "Fact" ? "Fact" : "Tip"}',
                          onChanged: (p0) {
                            setState(() {
                              currentlySelectedImageIdea = null;
                              currentlySelectedImageIdeaBackground = null;
                              currentlySelectedImageIdeaSource = null;
                              currentlySelectedImageIdeaCustomization = null;
                            });
                          },
                        ),
                        if (imagePromptController.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Next',
                            iconSize: 36,
                            splashRadius: 20,
                            onPressed: () async {
                              if (currentlySelectedImageIdea == null &&
                                  imagePromptController.text.trim().isEmpty) {
                                return mySnackBar(context,
                                    'Please generate idea or enter your own');
                              }
                              setState(() => selectedImageIdea =
                                  imagePromptController.text);
                              customBackgroundFuture =
                                  loadCustomBackgroundUrls();
                              prebuiltBackgroundFuture =
                                  loadPrebuiltBackgroundUrls(null);
                              prebuiltCategoryListFuture =
                                  loadPrebuiltBackgroundCategories();
                            },
                            icon: const Icon(
                              Icons.arrow_circle_right_outlined,
                              color: Color(0xFF002f6e),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            )
          else if (selectedImageIdea != null)
            const SizedBox.shrink(),

          availableIdeas == null
              ? SizedBox(
                  width: width,
                  child: AutoSkeleton(
                    enabled: true,
                    preserveSize: true,
                    baseColor: lightColor,
                    effectColor: darkColor,
                    borderRadius: 16,
                    child: Column(
                      children: [
                        Container(
                            height: 20, width: width * 0.25, color: lightColor),
                        const SizedBox(height: 16),
                        ...List.generate(
                          4,
                          (i) => Padding(
                            padding: EdgeInsets.only(bottom: i == 3 ? 0 : 12),
                            child: Container(
                                height: 56, width: width, color: lightColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : (selectedTab == 'Image' && selectedImageIdea == null) ||
                      (selectedTab == 'Text' && selectedTextIdea == null)
                  ? (availableIdeas![selectedTab == 'Text'
                              ? 'Text'
                              : selectedImageTab]!
                          .isEmpty
                      ? SizedBox(
                          height: 80,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'No ideas available',
                                  style: TextStyle(
                                      fontSize: 16, color: Color(0xFF002f6e)),
                                ),
                                MyTextButton(
                                  onPressed: () => context.go('/home/idea'),
                                  child: const Text(
                                    'Generate Ideas',
                                    style: TextStyle(
                                        color: Color(0xFF004aad),
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : selectedTab == 'Image'
                          ? SizedBox(
                              width: width,
                              height: height * 0.75,
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    children: [
                                      const Text(
                                        'OR select from ideas',
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Color(0xFF002f6e)),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: width,
                                        height: height * 0.625,
                                        child: RepaintBoundary(
                                          child: ListView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const ClampingScrollPhysics(),
                                            itemCount: availableIdeas![
                                                    selectedImageTab]!
                                                .length,
                                            padding: EdgeInsets.symmetric(
                                                    horizontal: width * 0.0125)
                                                .copyWith(
                                                    bottom: width * 0.0125),
                                            itemBuilder: (context, index) {
                                              final idea = availableIdeas![
                                                  selectedImageTab]![index];
                                              return IdeaCard(
                                                text: idea['idea'],
                                                source: idea['source'],
                                                isSelected:
                                                    currentlySelectedImageIdea ==
                                                        idea['idea'],
                                                onTap: () {
                                                  setState(() {
                                                    imagePromptController
                                                        .clear();
                                                    currentlySelectedImageIdea =
                                                        idea['idea'];
                                                    currentlySelectedImageIdeaBackground =
                                                        idea['background'];
                                                    currentlySelectedImageIdeaSource =
                                                        idea['source'];
                                                    currentlySelectedImageIdeaCustomization =
                                                        idea['customization'];
                                                  });
                                                },
                                                onMarkUsed: () async =>
                                                    await markIdeaUsed(
                                                        idea['id']),
                                                width: width,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  (currentlySelectedImageIdea != null ||
                                          imagePromptController.text.isNotEmpty)
                                      ? MyButton(
                                          width: width * 0.155,
                                          text: 'Next',
                                          onTap: () async {
                                            if (currentlySelectedImageIdea ==
                                                    null &&
                                                imagePromptController.text
                                                    .trim()
                                                    .isEmpty) {
                                              return mySnackBar(context,
                                                  'Please select an idea OR enter your own');
                                            }
                                            setState(() {
                                              selectedImageIdea =
                                                  currentlySelectedImageIdea ??
                                                      imagePromptController
                                                          .text;
                                              selectedImageIdeaBackground =
                                                  currentlySelectedImageIdeaBackground;
                                              selectedImageIdeaSource =
                                                  currentlySelectedImageIdeaSource;
                                              selectedImageIdeaCustomization =
                                                  currentlySelectedImageIdeaCustomization;
                                            });
                                            customBackgroundFuture =
                                                loadCustomBackgroundUrls();
                                            prebuiltBackgroundFuture =
                                                loadPrebuiltBackgroundUrls(
                                                    null);
                                            prebuiltCategoryListFuture =
                                                loadPrebuiltBackgroundCategories();
                                          },
                                          isLoading: false,
                                        )
                                      : const SizedBox.shrink(),
                                ],
                              ),
                            )
                          : SizedBox(
                              width: width,
                              height: height * 0.75,
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    children: [
                                      const Text(
                                        'OR select from ideas',
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Color(0xFF002f6e)),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: width,
                                        height: height * 0.6125,
                                        child: RepaintBoundary(
                                          child: ListView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const ClampingScrollPhysics(),
                                            itemCount:
                                                availableIdeas!['Text']!.length,
                                            padding: EdgeInsets.symmetric(
                                                    horizontal: width * 0.0125)
                                                .copyWith(
                                                    bottom: width * 0.0125),
                                            itemBuilder: (context, index) {
                                              final idea = availableIdeas![
                                                  'Text']![index];
                                              return IdeaCard(
                                                text: idea['idea'],
                                                source: idea['source'],
                                                isSelected:
                                                    currentlySelectedTextIdea ==
                                                        idea['idea'],
                                                onTap: () {
                                                  setState(() {
                                                    textPromptController
                                                        .clear();
                                                    currentlySelectedTextIdea =
                                                        idea['idea'];
                                                    currentlySelectedTextIdeaId =
                                                        idea['id'];
                                                  });
                                                },
                                                onMarkUsed: () async =>
                                                    await markIdeaUsed(
                                                        idea['id']),
                                                width: width,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  (currentlySelectedTextIdea != null ||
                                          textPromptController.text.isNotEmpty)
                                      ? MyButton(
                                          width: width * 0.155,
                                          text: 'Next',
                                          onTap: () async {
                                            if (currentlySelectedTextIdea ==
                                                    null &&
                                                textPromptController.text
                                                    .trim()
                                                    .isEmpty) {
                                              return mySnackBar(context,
                                                  'Please select an idea OR enter your own');
                                            }
                                            setState(() {
                                              if (currentlySelectedTextIdea !=
                                                  null) {
                                                textPromptController.text =
                                                    currentlySelectedTextIdea!;
                                                selectedTextIdea =
                                                    currentlySelectedTextIdea;
                                                selectedTextIdeaId =
                                                    currentlySelectedTextIdeaId;
                                              } else {
                                                selectedTextIdea =
                                                    textPromptController.text;
                                              }
                                            });
                                          },
                                          isLoading: false,
                                        )
                                      : const SizedBox.shrink(),
                                ],
                              ),
                            ))
                  : const SizedBox.shrink(),

          // Step 2 backgrounds (image flow)
          if (selectedTab == 'Image' &&
              selectedImageIdea != null &&
              selectedImageBackgroundUrl == null &&
              !isSelectedAIGeneratedBackground)
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Step 2: Select Background',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: darkColor),
                ),
                const SizedBox(height: 12),
                backgroundPickerSection(
                  width: width,
                  title: 'Custom Backgrounds',
                  future: customBackgroundFuture,
                  selectedUrl: currentlySelectedImageBackgroundUrl,
                  onSelect: (url) {
                    setState(() {
                      currentlySelectedImageBackgroundUrl = url;
                      isCurrentlySelectedAIGeneratedBackground = false;
                    });
                  },
                ),
                backgroundPickerSection(
                  width: width,
                  title: 'Prebuilt Backgrounds',
                  future: prebuiltBackgroundFuture,
                  selectedUrl: currentlySelectedImageBackgroundUrl,
                  categoryDropdown: prebuiltCategoryListFuture != null
                      ? FutureBuilder(
                          future: prebuiltCategoryListFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return AutoSkeleton(
                                enabled: true,
                                preserveSize: true,
                                baseColor: lightColor,
                                effectColor: darkColor,
                                borderRadius: 16,
                                child: Container(
                                  height: 40,
                                  width: width * 0.2,
                                  decoration: BoxDecoration(
                                      color: lightColor,
                                      borderRadius: BorderRadius.circular(16)),
                                ),
                              );
                            }
                            if (snapshot.hasError) {
                              return Text('Error: ${snapshot.error}',
                                  style: TextStyle(color: darkColor));
                            }
                            if (snapshot.hasData) {
                              final items = snapshot.data ?? [];
                              return MyDropDown(
                                width: width * 0.2,
                                height: 40,
                                items: items,
                                value: selectedPrebuiltCategory,
                                onChanged: (value) async {
                                  setState(
                                      () => selectedPrebuiltCategory = value!);
                                  prebuiltBackgroundFuture =
                                      loadPrebuiltBackgroundUrls(value);
                                },
                                hint: 'Select Category',
                              );
                            }
                            return AutoSkeleton(
                              enabled: true,
                              preserveSize: true,
                              baseColor: lightColor,
                              effectColor: darkColor,
                              borderRadius: 16,
                              child: Container(
                                  height: 40,
                                  width: width * 0.2,
                                  color: lightColor),
                            );
                          },
                        )
                      : null,
                  onSelect: (url) {
                    setState(() {
                      currentlySelectedImageBackgroundUrl = url;
                      isCurrentlySelectedAIGeneratedBackground = false;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'OR',
                  style: TextStyle(fontSize: 16, color: darkColor),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      isCurrentlySelectedAIGeneratedBackground =
                          !isCurrentlySelectedAIGeneratedBackground;
                      currentlySelectedImageBackgroundUrl = null;
                    });
                  },
                  child: Container(
                    alignment: Alignment.center,
                    width: width,
                    padding: EdgeInsets.all(width * 0.0125),
                    margin: EdgeInsets.all(width * 0.0125),
                    decoration: BoxDecoration(
                      color: lightColor.withOpacity(
                          isCurrentlySelectedAIGeneratedBackground
                              ? 0.125
                              : 0.06125),
                      border: Border.all(
                          color: isCurrentlySelectedAIGeneratedBackground
                              ? darkColor
                              : Colors.transparent,
                          width: 2),
                      borderRadius: BorderRadius.circular(
                          isCurrentlySelectedAIGeneratedBackground ? 20 : 24),
                    ),
                    child: Text(
                      'Generate Background using AI',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: darkColor, fontSize: 20),
                    ),
                  ),
                ),
                (isCurrentlySelectedAIGeneratedBackground ||
                        currentlySelectedImageBackgroundUrl != null)
                    ? MyButton(
                        width: width * 0.155,
                        text: 'Next',
                        onTap: () async {
                          if (!isCurrentlySelectedAIGeneratedBackground &&
                              currentlySelectedImageBackgroundUrl == null) {
                            return mySnackBar(context,
                                'Please select a background or generate using AI');
                          }
                          setState(() {
                            if (isCurrentlySelectedAIGeneratedBackground) {
                              isSelectedAIGeneratedBackground = true;
                            } else {
                              selectedImageBackgroundUrl =
                                  currentlySelectedImageBackgroundUrl;
                            }
                          });
                        },
                        isLoading: false,
                      )
                    : const SizedBox.shrink(),
              ],
            ),

          // Background AI panel
          if (selectedTab == 'Image' &&
              selectedImageIdea != null &&
              selectedImageIdeaCustomization != null &&
              selectedImageBackgroundUrl == null &&
              isSelectedAIGeneratedBackground)
            BackgroundControlsPanel(
              width: width * 0.5,
              backgroundPrompt: selectedImageIdeaBackground,
              imageTab: selectedImageTab,
              customization: selectedImageIdeaCustomization,
              onImageGenerated: (imageUrl) =>
                  setState(() => selectedImageBackgroundUrl = imageUrl),
            ),

          // Foreground step titles
          if (selectedTab == 'Image' &&
              selectedImageIdea != null &&
              selectedImageBackgroundUrl != null &&
              !isSelectedAIGeneratedBackground)
            Text('Step 3: Edit Foreground',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkColor))
          else if (selectedTab == 'Image' &&
              selectedImageIdea != null &&
              selectedImageBackgroundUrl != null &&
              isSelectedAIGeneratedBackground)
            Text(
              'Step 4: Edit Foreground',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: darkColor),
            ),

          if (selectedTab == 'Image' &&
              selectedImageIdea != null &&
              selectedImageBackgroundUrl != null)
            ForegroundControlPanel(
              width: width,
              idea: selectedImageIdea!,
              source: selectedImageIdeaSource,
              background: selectedImageBackgroundUrl!,
              imageTab: selectedImageTab,
              onDone: () => context.read<ClearNotifier>().triggerClear(),
            ),

          // Text flow step 2
          if (selectedTab == 'Text' && selectedTextIdea != null)
            Center(
              child: Container(
                width: width * 0.5,
                padding: EdgeInsets.all(width * 0.0125),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 16,
                        offset: Offset(0, 6))
                  ],
                ),
                child: textControls(width: width),
              ),
            ),
        ],
      );
    }

    // keep your existing ≥900 px layout here
    return Scaffold(
      backgroundColor: const Color.fromRGBO(247, 249, 252, 1),
      appBar: PreferredSize(
        preferredSize: Size(MediaQuery.of(context).size.width, 136),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  buildTabChip('Image Generation', selectedTab == 'Image', () {
                    setState(() => selectedTab = 'Image');
                  }),
                  const SizedBox(width: 16),
                  buildTabChip('Text Generation', selectedTab == 'Text', () {
                    setState(() => selectedTab = 'Text');
                  }),
                ],
              ),
              const SizedBox(height: 24),
              if (selectedTab == 'Image')
                Row(
                  children: [
                    buildTabChip('Quote', selectedImageTab == 'Quote', () {
                      setState(() {
                        if (selectedImageTab != 'Quote') resetImageTabState();
                        selectedImageTab = 'Quote';
                      });
                    }),
                    const SizedBox(width: 12),
                    buildTabChip('Fact', selectedImageTab == 'Fact', () {
                      setState(() {
                        if (selectedImageTab != 'Fact') resetImageTabState();
                        selectedImageTab = 'Fact';
                      });
                    }),
                    const SizedBox(width: 12),
                    buildTabChip('Tip', selectedImageTab == 'Tip', () {
                      setState(() {
                        if (selectedImageTab != 'Tip') resetImageTabState();
                        selectedImageTab = 'Tip';
                      });
                    }),
                  ],
                )
              else
                const SizedBox(height: 44),
            ],
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: w * 0.0125),
            child: _wideContent(w: w, h: h),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        if (w >= 900) return buildDesktop(context, c); // your current UI
        return buildMobile(context, c); // new compact UI
      },
    );
  }
}

class BackgroundThumbStrip extends StatefulWidget {
  const BackgroundThumbStrip({
    required this.urls,
    required this.width,
    required this.itemWidth,
    required this.itemMargin,
    required this.selectedUrl,
    required this.onSelect,
  });

  final List<String> urls;
  final double width;
  final double itemWidth;
  final double itemMargin;
  final String? selectedUrl;
  final ValueChanged<String> onSelect;

  @override
  State<BackgroundThumbStrip> createState() => _BackgroundThumbStripState();
}

class _BackgroundThumbStripState extends State<BackgroundThumbStrip> {
  late final ScrollController _ctrl;
  double _pixels = 0;
  double _max = 0;

  double get _stride => widget.itemWidth + widget.itemMargin * 2;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController()
      ..addListener(() {
        setState(() {
          _pixels = _ctrl.position.pixels;
          _max = _ctrl.position.maxScrollExtent;
        });
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _step(int dir) {
    final next = (_pixels / _stride).round() + (dir > 0 ? 1 : -1);
    final target = (next * _stride).clamp(0, _max);
    _ctrl.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLeft = _pixels > 1;
    final approxMax = (widget.urls.length * _stride - widget.width);
    final showRight = _max > 0 ? _pixels < _max - 1 : approxMax > 1;

    return SizedBox(
      width: widget.width,
      height: widget.itemWidth + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ListView.builder(
            controller: _ctrl,
            primary: false,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            itemCount: widget.urls.length,
            itemBuilder: (context, index) {
              final url = widget.urls[index];
              final isSel = widget.selectedUrl == url;
              return GestureDetector(
                onTap: () => widget.onSelect(url),
                child: Container(
                  margin: EdgeInsets.all(widget.itemMargin),
                  padding: EdgeInsets.all(isSel ? 2 : 0),
                  decoration: BoxDecoration(
                    color: lightColor,
                    border: Border.all(
                      color: isSel ? darkColor : Colors.transparent,
                      width: isSel ? 2 : 0,
                    ),
                    borderRadius: BorderRadius.circular(isSel ? 20 : 18),
                  ),
                  width: widget.itemWidth,
                  height: widget.itemWidth,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: widget.itemWidth,
                      height: widget.itemWidth,
                      // prevent layout jank
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(color: lightColor);
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (showLeft)
            Positioned(
              left: 4,
              child: Material(
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _step(-1),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.chevron_left,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          if (showRight)
            Positioned(
              right: 4,
              child: Material(
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _step(1),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.chevron_right,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
