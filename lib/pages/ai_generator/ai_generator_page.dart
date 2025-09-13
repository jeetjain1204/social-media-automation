// ignore_for_file: use_build_context_synchronously

import 'dart:async'; // OPT: debouncing + retry backoff helpers
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
  // OPT: platforms list is immutable; mark const to reduce rebuild allocs
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

  // OPT: memoize futures to avoid refetch on rebuilds
  Future<List<String>>? customBackgroundFuture;
  Future<List<String>>? prebuiltBackgroundFuture;
  Future<List<String>>? prebuiltCategoryListFuture;
  String? selectedPrebuiltCategory;

  // OPT: debounce pref writes
  Timer? _savePrefsDebounce;

  // String? generatedImageUrl;
  // bool isImageLoading = false;

  final durationOptions = ['1 Day', '7 Days', '1 Month', '6 Months', '1 Year'];

  @override
  void initState() {
    super.initState();
    // OPT: load in parallel; no need to await
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
    // OPT: clean up controllers/timers to prevent leaks/jank (esp. web)
    textPromptController.dispose();
    imagePromptController.dispose();
    _savePrefsDebounce?.cancel();
    super.dispose();
  }

  // =================== Infra Helpers: Retry / Debounce / Mime ===================

  Future<T> _withRetry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 350),
  }) async {
    // OPT: exponential backoff + jitter for flaky networks/APIs
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

  void _scheduleSavePreferences() {
    // OPT: debounce SharedPreferences writes to cut I/O
    _savePrefsDebounce?.cancel();
    _savePrefsDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(savePreferences());
    });
  }

  String _contentTypeForExtension(String ext) {
    // OPT: correct contentType -> better caching + preview
    final e = ext.toLowerCase();
    if (e == 'png') return 'image/png';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'webp') return 'image/webp';
    if (e == 'gif') return 'image/gif';
    return 'application/octet-stream';
  }

  // =================== Data Loads ===================

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

    // OPT: select only needed columns, not '*'
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

    // OPT: keep same key; ensure consistent JSON
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

  // =================== Scheduling & Upload ===================

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

        // OPT: set contentType; retry with backoff for reliability
        await _withRetry(() {
          return supabase.storage.from('posts').uploadBinary(
                key,
                bytes,
                fileOptions: FileOptions(
                  contentType: _contentTypeForExtension(ext),
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
    // OPT: init once outside builder; avoid resetting text each rebuild
    final captionController = TextEditingController(text: caption);

    await showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (_) {
        bool localScheduling =
            false; // OPT: local state; avoid page-wide rebuilds
        return Padding(
          padding: EdgeInsets.all(width * 0.0125),
          child: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Schedule Your Post',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: width,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: darkColor, width: 1),
                      ),
                      child: TextFormField(
                        controller: captionController,
                        minLines: 10,
                        maxLines: 20,
                        decoration: InputDecoration(
                          hintText: 'Edit your caption',
                          hintStyle: TextStyle(color: darkColor),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 15,
                          ),
                        ),
                      ),
                    ),
                    if (selectedTextImages.isNotEmpty)
                      const SizedBox(height: 12),
                    if (selectedTextImages.isNotEmpty)
                      Center(
                        child: SizedBox(
                          width: width * 0.4,
                          height: 100,
                          child: RepaintBoundary(
                            // OPT: isolate repaints for scrolling thumbs
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
                                    margin: EdgeInsets.all(width * 0.00125),
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
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            )
                                          : Image.memory(
                                              selectedTextImages[index].bytes!,
                                              fit: BoxFit.cover,
                                              width: 100,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) =>
                                                  const Center(
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
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    MyButton(
                      width: width * 0.8,
                      text: 'Confirm & Schedule',
                      isLoading: localScheduling, // OPT: use local flag here
                      onTap: () async {
                        try {
                          setState(() {
                            localScheduling = true;
                          });

                          final selected = await showFutureDateTimePicker(
                            context,
                          );
                          if (selected == null) {
                            setState(
                              () => localScheduling = false,
                            ); // OPT: reset on cancel
                            return;
                          }

                          final platforms = getEligiblePlatforms(
                            selectedTextImages.length,
                          );

                          final selectedPlatforms = await showPlatformPicker(
                            context,
                            platforms: platforms,
                          );
                          if (selectedPlatforms == null ||
                              selectedPlatforms.isEmpty) {
                            setState(() {
                              localScheduling = false;
                            });
                            return mySnackBar(context, 'Select Platforms');
                          }

                          final postTypeMap = getPostTypesFor(
                            selectedPlatforms,
                            selectedTextImages.length,
                          );
                          final selectedPostTypesMap = await showPostTypePicker(
                            context,
                            postTypeMap,
                          );
                          if (selectedPostTypesMap == null) {
                            setState(() {
                              localScheduling = false;
                            });
                            return mySnackBar(context, 'Select Post Types');
                          }

                          final mediaUrls = await uploadMedia(
                            selectedTextImages,
                          );

                          if (selectedTextImages.isNotEmpty &&
                              mediaUrls.isEmpty) {
                            setState(() {
                              localScheduling = false;
                            });
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
                        } catch (e) {
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

    setState(() {
      isLoading = true;
    });

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => isLoading = false);
      context.go('/login');
      return;
    }

    // OPT: only needed columns
    final profile = await supabase
        .from('brand_profiles')
        .select(
          'persona,category,subcategory,primary_goal,brand_name,brand_logo_path,primary_color,voice_tags,content_types,target_posts_per_week,timezone',
        )
        .eq('user_id', user.id)
        .maybeSingle();

    final profileData = {
      'persona': profile?['persona'],
      'category': profile?['category'],
      'subcategory': profile?['subcategory'],
      'primary_goal': profile?['primary_goal'],
      // 'first_platform': profile['first_platform'],
      'brand_name': profile?['brand_name'],
      'brand_logo_path': profile?['brand_logo_path'],
      'primary_color': profile?['primary_color'],
      'voice_tags': profile?['voice_tags'],
      'content_types': profile?['content_types'],
      'target_posts_per_week': profile?['target_posts_per_week'],
      'timezone': profile?['timezone'] ?? '',
    };

    try {
      final session = supabase.auth.currentSession;
      final accessToken = session?.accessToken;

      // OPT: retry + timeout
      final res = await _withRetry(() {
        return http
            .post(
              Uri.parse(
                'https://ehgginqelbgrzfrzbmis.functions.supabase.co/generate-caption',
              ),
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
      setState(() {
        generated = data['caption'] ?? 'Error generating';
        isLoading = false;
      });

      if (generated == 'No Major News in the Selected Time Range') {
        setState(() => isLoading = false);
        mySnackBar(context, 'No recent news found in selected time range');
        return;
      } else if (generated == 'Error Generating') {
        setState(() => isLoading = false);
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

      // OPT: parallel signed URL creation
      final urls = await Future.wait(
        paths.map((path) async {
          final res = await supabase.storage
              .from('brand-kits')
              .createSignedUrl(path, 60 * 60);

          return res;
        }),
      );

      return urls;
    } catch (e) {
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

      String defaultCat;
      if (userCat != null && categories.contains(userCat)) {
        defaultCat = userCat;
      } else {
        defaultCat = categories.isNotEmpty ? categories.first : '';
      }

      setState(() {
        selectedPrebuiltCategory = defaultCat;
        prebuiltBackgroundFuture = loadPrebuiltBackgroundUrls(defaultCat);
      });

      return categories;
    } catch (e) {
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

      if (category.isEmpty) {
        return [];
      }

      final response = await supabase
          .from('prebuilt_backgrounds')
          .select('path')
          .eq('category', category);
      final rows = List<Map<String, dynamic>>.from(response as List);

      final urls = <String>[];

      // OPT: parallelize signed URL fetches
      await Future.wait(
        rows.map((row) async {
          final path = row['path']?.toString().trim() ?? '';
          if (path.isEmpty) return;

          try {
            final signedUrl = await supabase.storage
                .from('backgrounds')
                .createSignedUrl(path, 3600);

            if (signedUrl.isNotEmpty) {
              urls.add(signedUrl);
            }
          } catch (e) {
            mySnackBar(context, 'Some error occured');
          }
        }),
      );

      return urls;
    } catch (e) {
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
      } catch (e) {
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
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
                const Icon(Icons.check, size: 18, color: Color(0xFF004aad)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? const Color(0xFF004aad) // primaryColor
                      : const Color(0xFF374151), // text gray
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backgroundPickerSection({
    required double width,
    required String title,
    required Future<List<String>>? future,
    required String? selectedUrl,
    required void Function(String) onSelect,
    Widget? categoryDropdown,
  }) {
    return Container(
      width: width,
      padding: EdgeInsets.all(width * 0.0125),
      margin: EdgeInsets.all(width * 0.0125),
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
              Text(title, style: TextStyle(fontSize: 20, color: darkColor)),
              if (categoryDropdown != null) categoryDropdown,
            ],
          ),
          const SizedBox(height: 12),
          future != null
              ? FutureBuilder<List<String>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      final itemW = width * 0.1225;
                      final margin = width * 0.006125;

                      return SizedBox(
                        width: width,
                        height: width * 0.125,
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
                            itemBuilder: (_, i) => Container(
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
                      return Text(
                        'Error: ${snapshot.error}',
                        style: TextStyle(color: darkColor, fontSize: 16),
                      );
                    }
                    final urls = snapshot.data ?? [];
                    if (urls.isEmpty) {
                      return const Text('No Backgrounds Found');
                    }
                    // inside your build where you currently: return SizedBox(...)
                    double _pixels = 0; // updated via ScrollNotification
                    double _maxExtent = 0; // updated via ScrollNotification

                    return StatefulBuilder(
                      builder: (context, setSBState) {
                        // match your layout
                        final itemW = width * 0.1225;
                        final margin = width * 0.006125;
                        final stride = itemW +
                            margin *
                                2; // one item's full width including margins

                        // initial guess for "canRight" before first scroll metrics arrive
                        final approxMax = (urls.length * stride - width);
                        final showLeft = _pixels > 1;
                        final showRight = _maxExtent > 0
                            ? _pixels < _maxExtent - 1
                            : approxMax > 1;

                        // fresh keys each build are fine here since items have no internal state
                        final itemKeys = List<GlobalKey>.generate(
                          urls.length,
                          (_) => GlobalKey(),
                        );

                        void step(int dir) {
                          // estimate current first visible index from pixels and stride
                          int guess = (_pixels / stride).round();
                          int next = (dir > 0 ? guess + 1 : guess - 1).clamp(
                            0,
                            urls.length - 1,
                          );
                          final ctx = itemKeys[next].currentContext;
                          if (ctx != null) {
                            Scrollable.ensureVisible(
                              ctx,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              alignment: 0.0, // align to left edge
                            );
                          }
                        }

                        return SizedBox(
                          width: width,
                          height: width * 0.125,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              NotificationListener<ScrollNotification>(
                                onNotification: (n) {
                                  if (n.metrics.axis == Axis.horizontal) {
                                    setSBState(() {
                                      _pixels = n.metrics.pixels;
                                      _maxExtent = n.metrics.maxScrollExtent;
                                    });
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  primary: false,
                                  scrollDirection: Axis.horizontal,
                                  physics: const ClampingScrollPhysics(),
                                  itemCount: urls.length,
                                  itemBuilder: (context, index) {
                                    final url = urls[index];
                                    final isSelected = selectedUrl == url;

                                    return KeyedSubtree(
                                      key: itemKeys[index],
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () => onSelect(url),
                                          child: Container(
                                            margin: EdgeInsets.all(margin),
                                            padding: EdgeInsets.all(
                                              isSelected ? 2 : 0,
                                            ),
                                            decoration: BoxDecoration(
                                              color: lightColor,
                                              border: Border.all(
                                                color: isSelected
                                                    ? darkColor
                                                    : Colors.transparent,
                                                width: isSelected ? 2 : 0,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                isSelected ? 20 : 18,
                                              ),
                                            ),
                                            width: itemW,
                                            height: itemW,
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              child: Image.network(
                                                url,
                                                fit: BoxFit.cover,
                                                width: width * 0.15,
                                                height: width * 0.15,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // left button
                              if (showLeft)
                                Positioned(
                                  left: 4,
                                  child: Material(
                                    elevation: 2,
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => step(-1),
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

                              // right button
                              if (showRight)
                                Positioned(
                                  right: 4,
                                  child: Material(
                                    elevation: 2,
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => step(1),
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
                      },
                    );
                  },
                )
              : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildSwitch(String label, bool value, void Function(bool) onChanged) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          MySwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildImageUploader(BuildContext context, double width) {
    final isEmpty = selectedTextImages.isEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lightColor.withOpacity(0.25),
        border: Border.all(width: 2, color: lightColor.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(100),
      ),
      padding: EdgeInsets.all(width * 0.006125),
      child: isEmpty
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Add Image', style: TextStyle(color: darkColor)),
                _addImageButton(context, width),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: width * 0.4,
                  height: 100,
                  child: selectedTextImages.isEmpty
                      ? const SizedBox.shrink()
                      : RepaintBoundary(
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
                                      margin: EdgeInsets.all(width * 0.00125),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          width: 0.5,
                                          color: darkColor.withOpacity(0.5),
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),
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
                                          () =>
                                              selectedTextImages.remove(image),
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          100,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Colors.black,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 12,
                                            color: Colors.white,
                                          ),
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
                _addImageButton(context, width),
              ],
            ),
    );
  }

  Widget _addImageButton(BuildContext context, double width) {
    return GestureDetector(
      onTap: () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
          allowMultiple: true,
        );

        if (result == null ||
            result.files.isEmpty ||
            result.files.first.bytes == null) {
          mySnackBar(context, 'No image selected');
          return;
        }

        // OPT: single setState to batch updates
        setState(() {
          selectedTextImages.addAll(result.files);
        });
      },
      child: Container(
        width: width * 0.0153125,
        height: width * 0.0153125,
        decoration: BoxDecoration(
          color: lightColor.withOpacity(0.25),
          border: Border.all(width: 2, color: darkColor.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Icon(Icons.add_rounded, color: darkColor, size: width * 0.0125),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(247, 249, 252, 1),
      appBar: PreferredSize(
        preferredSize: Size(MediaQuery.of(context).size.width, 136),
        child: Padding(
          padding: const EdgeInsets.all(12), // OPT: const to reduce allocs
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  buildTabChip('Image Generation', selectedTab == 'Image', () {
                    setState(() {
                      selectedTab = 'Image';
                    });
                  }),
                  const SizedBox(width: 16), // --space-4
                  buildTabChip('Text Generation', selectedTab == 'Text', () {
                    setState(() {
                      selectedTab = 'Text';
                    });
                  }),
                ],
              ),
              const SizedBox(height: 24), // --space-6

              if (selectedTab == 'Image') ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    buildTabChip('Quote', selectedImageTab == 'Quote', () {
                      setState(() {
                        if (selectedImageTab != 'Quote') {
                          resetImageTabState();
                        }
                        selectedImageTab = 'Quote';
                      });
                    }),
                    const SizedBox(width: 12), // --space-3

                    buildTabChip('Fact', selectedImageTab == 'Fact', () {
                      setState(() {
                        if (selectedImageTab != 'Fact') {
                          resetImageTabState();
                        }
                        selectedImageTab = 'Fact';
                      });
                    }),
                    const SizedBox(width: 12), // --space-3

                    buildTabChip('Tip', selectedImageTab == 'Tip', () {
                      setState(() {
                        if (selectedImageTab != 'Tip') {
                          resetImageTabState();
                        }
                        selectedImageTab = 'Tip';
                      });
                    }),
                  ],
                ),
              ] else
                const SizedBox(height: 44),
            ],
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: width * 0.0125),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectedTab == 'Text' && selectedTextIdea == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 12), // --space-3

                      Text(
                        'Step 1: Choose an Idea',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkColor,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Center(
                        child: SizedBox(
                          height: 66,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              MyTextField(
                                width: width * 0.5,
                                controller: textPromptController,
                                hintText: 'Enter my own Idea',
                                onChanged: (p0) {
                                  setState(() {
                                    currentlySelectedTextIdea = null;
                                  });
                                  _scheduleSavePreferences(); // OPT: debounce prefs
                                },
                              ),
                              if (availableIdeas != null &&
                                  availableIdeas!['Text'] != null &&
                                  availableIdeas!['Text']!.isEmpty &&
                                  textPromptController.text.isNotEmpty)
                                IconButton(
                                  tooltip: 'Next',
                                  iconSize: 36, // better fit than 40
                                  splashRadius: 20,
                                  onPressed: () async {
                                    if (currentlySelectedTextIdea == null &&
                                        textPromptController.text
                                            .trim()
                                            .isEmpty) {
                                      return mySnackBar(
                                        context,
                                        'Please generate idea or enter your own',
                                      );
                                    }

                                    setState(() {
                                      selectedTextIdea =
                                          textPromptController.text;
                                    });

                                    customBackgroundFuture =
                                        loadCustomBackgroundUrls();
                                    prebuiltBackgroundFuture =
                                        loadPrebuiltBackgroundUrls(null);
                                    prebuiltCategoryListFuture =
                                        loadPrebuiltBackgroundCategories();
                                  },
                                  icon: const Icon(
                                    Icons.arrow_circle_right_outlined,
                                    color: Color(0xFF002f6e), // darkColor
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16), // --space-4
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
                      const SizedBox(height: 12), // --space-3

                      Text(
                        'Step 1: Choose an Idea',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkColor,
                        ),
                      ),

                      const SizedBox(height: 12),
                      Center(
                        child: SizedBox(
                          height: 66,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              MyTextField(
                                width: width * 0.5,
                                controller: imagePromptController,
                                hintText:
                                    'Enter my own ${selectedImageTab == 'Quote' ? 'Quote' : selectedImageTab == 'Fact' ? 'Fact' : 'Tip'}',
                                onChanged: (p0) {
                                  setState(() {
                                    currentlySelectedImageIdea = null;
                                    currentlySelectedImageIdeaBackground = null;
                                    currentlySelectedImageIdeaSource = null;
                                    currentlySelectedImageIdeaCustomization =
                                        null;
                                  });
                                },
                              ), // --space-3

                              if (availableIdeas != null &&
                                  availableIdeas![selectedImageTab] != null &&
                                  availableIdeas![selectedImageTab]!.isEmpty &&
                                  imagePromptController.text.isNotEmpty)
                                IconButton(
                                  tooltip: 'Next',
                                  iconSize: 36,
                                  splashRadius: 20,
                                  onPressed: () async {
                                    if (currentlySelectedImageIdea == null &&
                                        imagePromptController.text
                                            .trim()
                                            .isEmpty) {
                                      return mySnackBar(
                                        context,
                                        'Please generate idea or enter your own',
                                      );
                                    }

                                    setState(() {
                                      selectedImageIdea =
                                          imagePromptController.text;
                                    });

                                    customBackgroundFuture =
                                        loadCustomBackgroundUrls();
                                    prebuiltBackgroundFuture =
                                        loadPrebuiltBackgroundUrls(null);
                                    prebuiltCategoryListFuture =
                                        loadPrebuiltBackgroundCategories();
                                  },
                                  icon: const Icon(
                                    Icons.arrow_circle_right_outlined,
                                    color: Color(0xFF002f6e), // darkColor
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16), // --space-4
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
                                height: 20,
                                width: width * 0.25,
                                color: lightColor,
                              ),
                              const SizedBox(height: 16),
                              ...List.generate(
                                4,
                                (i) => Padding(
                                  padding: EdgeInsets.only(
                                    bottom: i == 3 ? 0 : 12,
                                  ),
                                  child: Container(
                                    height: 56,
                                    width: width,
                                    color: lightColor,
                                  ),
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'No ideas available',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF002f6e),
                                        ),
                                      ),
                                      MyTextButton(
                                        onPressed: () =>
                                            context.go('/home/idea'),
                                        child: const Text(
                                          'Generate Ideas',
                                          style: TextStyle(
                                            color: Color(0xFF004aad),
                                            fontWeight: FontWeight.w600,
                                          ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Column(
                                          children: [
                                            const Text(
                                              'OR select from ideas',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF002f6e),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            SizedBox(
                                              width: width,
                                              height: height * 0.625,
                                              child: RepaintBoundary(
                                                // OPT: isolate long list repaints
                                                child: ListView.builder(
                                                  shrinkWrap: true,
                                                  physics:
                                                      const ClampingScrollPhysics(),
                                                  itemCount: availableIdeas![
                                                          selectedImageTab]!
                                                      .length,
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: width * 0.0125,
                                                  ).copyWith(
                                                      bottom: width * 0.0125),
                                                  itemBuilder:
                                                      (context, index) {
                                                    final idea = availableIdeas![
                                                            selectedImageTab]![
                                                        index];
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
                                                              idea[
                                                                  'background'];
                                                          currentlySelectedImageIdeaSource =
                                                              idea['source'];
                                                          currentlySelectedImageIdeaCustomization =
                                                              idea[
                                                                  'customization'];
                                                        });
                                                      },
                                                      onMarkUsed: () async {
                                                        await markIdeaUsed(
                                                          idea['id'],
                                                        );
                                                      },
                                                      width: width,
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        (currentlySelectedImageIdea != null ||
                                                imagePromptController
                                                    .text.isNotEmpty)
                                            ? MyButton(
                                                width: width * 0.155,
                                                text: 'Next',
                                                onTap: () async {
                                                  if (currentlySelectedImageIdea ==
                                                          null &&
                                                      imagePromptController.text
                                                          .trim()
                                                          .isEmpty) {
                                                    return mySnackBar(
                                                      context,
                                                      'Please select an idea OR enter your own',
                                                    );
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
                                                    null,
                                                  );
                                                  prebuiltCategoryListFuture =
                                                      loadPrebuiltBackgroundCategories();
                                                },
                                                isLoading: false,
                                              )
                                            : const SizedBox.shrink(),
                                      ],
                                    ),
                                  )
                                : selectedTab == 'Text'
                                    ? SizedBox(
                                        width: width,
                                        height: height * 0.75,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Column(
                                              children: [
                                                const Text(
                                                  'OR select from ideas',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Color(0xFF002f6e),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                SizedBox(
                                                  width: width,
                                                  height: height * 0.6125,
                                                  child: RepaintBoundary(
                                                    // OPT
                                                    child: ListView.builder(
                                                      shrinkWrap: true,
                                                      physics:
                                                          const ClampingScrollPhysics(),
                                                      itemCount:
                                                          availableIdeas![
                                                                  'Text']!
                                                              .length,
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                        horizontal:
                                                            width * 0.0125,
                                                      ).copyWith(
                                                              bottom: width *
                                                                  0.0125),
                                                      itemBuilder:
                                                          (context, index) {
                                                        final idea =
                                                            availableIdeas![
                                                                'Text']![index];
                                                        return IdeaCard(
                                                          text: idea['idea'],
                                                          source:
                                                              idea['source'],
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
                                                          onMarkUsed: () async {
                                                            await markIdeaUsed(
                                                              idea['id'],
                                                            );
                                                          },
                                                          width: width,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            (currentlySelectedTextIdea !=
                                                        null ||
                                                    textPromptController
                                                        .text.isNotEmpty)
                                                ? MyButton(
                                                    width: width * 0.155,
                                                    text: 'Next',
                                                    onTap: () async {
                                                      if (currentlySelectedTextIdea ==
                                                              null &&
                                                          textPromptController
                                                              .text
                                                              .trim()
                                                              .isEmpty) {
                                                        return mySnackBar(
                                                          context,
                                                          'Please select an idea OR enter your own',
                                                        );
                                                      }

                                                      setState(() {
                                                        if (currentlySelectedTextIdea !=
                                                            null) {
                                                          textPromptController
                                                                  .text =
                                                              currentlySelectedTextIdea!;
                                                          selectedTextIdea =
                                                              currentlySelectedTextIdea;
                                                          selectedTextIdeaId =
                                                              currentlySelectedTextIdeaId;
                                                        } else {
                                                          selectedTextIdea =
                                                              textPromptController
                                                                  .text;
                                                        }
                                                      });
                                                    },
                                                    isLoading: false,
                                                  )
                                                : const SizedBox.shrink(),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink())
                        : const SizedBox.shrink(),
                selectedTab == 'Image' &&
                        selectedImageIdea != null &&
                        selectedImageBackgroundUrl == null &&
                        !isSelectedAIGeneratedBackground
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            'Step 2: Select Background',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: darkColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 🔹 Custom Backgrounds
                          _backgroundPickerSection(
                            width: width,
                            title: 'Custom Backgrounds',
                            future: customBackgroundFuture,
                            selectedUrl: currentlySelectedImageBackgroundUrl,
                            onSelect: (url) {
                              setState(() {
                                currentlySelectedImageBackgroundUrl = url;
                                isCurrentlySelectedAIGeneratedBackground =
                                    false;
                              });
                            },
                          ),

                          // 🔹 Prebuilt Backgrounds with Category Filter
                          _backgroundPickerSection(
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
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                        );
                                      }

                                      if (snapshot.hasError) {
                                        return Text(
                                          'Error: ${snapshot.error}',
                                          style: TextStyle(color: darkColor),
                                        );
                                      }

                                      if (snapshot.hasData) {
                                        final items = snapshot.data ?? [];
                                        return MyDropDown(
                                          width: width * 0.2,
                                          height: 40,
                                          items: items,
                                          value: selectedPrebuiltCategory,
                                          onChanged: (value) async {
                                            setState(() {
                                              selectedPrebuiltCategory = value!;
                                            });
                                            prebuiltBackgroundFuture =
                                                loadPrebuiltBackgroundUrls(
                                              value,
                                            );
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
                                          color: lightColor,
                                        ),
                                      );
                                    },
                                  )
                                : null,
                            onSelect: (url) {
                              setState(() {
                                currentlySelectedImageBackgroundUrl = url;
                                isCurrentlySelectedAIGeneratedBackground =
                                    false;
                              });
                            },
                          ),

                          const SizedBox(height: 12),

                          // 🔹 OR Separator
                          Text(
                            'OR',
                            style: TextStyle(fontSize: 16, color: darkColor),
                          ),
                          const SizedBox(height: 12),

                          // 🔹 AI Background Option
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                isCurrentlySelectedAIGeneratedBackground =
                                    !isCurrentlySelectedAIGeneratedBackground;
                                currentlySelectedImageBackgroundUrl = null;
                              });
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Container(
                                alignment: Alignment.center,
                                width: width,
                                padding: EdgeInsets.all(width * 0.0125),
                                margin: EdgeInsets.all(width * 0.0125),
                                decoration: BoxDecoration(
                                  color: lightColor.withOpacity(
                                    isCurrentlySelectedAIGeneratedBackground
                                        ? 0.125
                                        : 0.06125,
                                  ),
                                  border: Border.all(
                                    color:
                                        isCurrentlySelectedAIGeneratedBackground
                                            ? darkColor
                                            : Colors.transparent,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    isCurrentlySelectedAIGeneratedBackground
                                        ? 20
                                        : 24,
                                  ),
                                ),
                                child: Text(
                                  'Generate Background using AI',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: darkColor,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 🔹 Continue Button
                          (isCurrentlySelectedAIGeneratedBackground ||
                                  currentlySelectedImageBackgroundUrl != null)
                              ? MyButton(
                                  width: width * 0.155,
                                  text: 'Next',
                                  onTap: () async {
                                    if (!isCurrentlySelectedAIGeneratedBackground &&
                                        currentlySelectedImageBackgroundUrl ==
                                            null) {
                                      return mySnackBar(
                                        context,
                                        'Please select a background or generate using AI',
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
                                )
                              : const SizedBox.shrink(),
                        ],
                      )
                    : const SizedBox.shrink(),
                selectedTab == 'Text' && selectedTextIdea != null
                    ? Center(
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
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // 🔹 Input Toggle Section
                              //
                              const SizedBox(height: 12),
                              Text(
                                'Step 2: Generate Caption',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: darkColor,
                                ),
                              ),
                              const SizedBox(height: 12),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 500),
                                    curve: Curves.easeInOut,
                                    width: isNewsSelected
                                        ? width * 0.10
                                        : width * 0.355,
                                    height: 48,
                                    child: GestureDetector(
                                      onTap: () {
                                        if (isNewsSelected) {
                                          setState(
                                            () => isNewsSelected = false,
                                          );
                                          _scheduleSavePreferences(); // OPT: debounce
                                        }
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            100,
                                          ),
                                          border: Border.all(
                                            color: darkColor,
                                            width: 1,
                                          ),
                                        ),
                                        child: TextFormField(
                                          controller: textPromptController,
                                          decoration: InputDecoration(
                                            hintText:
                                                'What do you want to post?',
                                            hintStyle: TextStyle(
                                              color: darkColor,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 15,
                                            ),
                                          ),
                                          onChanged: (val) {
                                            setState(
                                              () => isNewsSelected = false,
                                            );
                                            _scheduleSavePreferences(); // OPT
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () async {
                                      setState(() => isNewsSelected = true);
                                      _scheduleSavePreferences(); // OPT
                                      await Future.delayed(
                                        const Duration(milliseconds: 150),
                                      );
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 500,
                                      ),
                                      curve: Curves.easeInOut,
                                      width: isNewsSelected
                                          ? width * 0.355
                                          : width * 0.10,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isNewsSelected
                                            ? darkColor
                                            : const Color(0xFF004AAD),
                                        borderRadius: BorderRadius.circular(
                                          isNewsSelected ? 100 : 36,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Text(
                                        'Get Trending News',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),

                              // 🔹 Dropdowns
                              Row(
                                children: [
                                  Expanded(
                                    child: MyDropDown(
                                      items: const ['Short', 'Medium', 'Long'],
                                      value: length,
                                      onChanged: (val) {
                                        setState(() => length = val!);
                                        _scheduleSavePreferences(); // OPT
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: MyDropDown(
                                      items: const [
                                        'Professional',
                                        'Playful',
                                        'Casual',
                                      ],
                                      value: tone,
                                      onChanged: (val) {
                                        setState(() => tone = val!);
                                        _scheduleSavePreferences(); // OPT
                                      },
                                    ),
                                  ),
                                  if (isNewsSelected) ...[
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: MyDropDown(
                                        items: durationOptions
                                            .map((e) => 'Last $e')
                                            .toList(),
                                        value: 'Last $newsDuration',
                                        onChanged: (val) {
                                          setState(() {
                                            newsDuration = val!.replaceFirst(
                                              'Last ',
                                              '',
                                            );
                                          });
                                          _scheduleSavePreferences(); // OPT
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 18),

                              // 🔹 Switches
                              Padding(
                                padding: EdgeInsets.all(width * 0.0125),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildSwitch('Use Emojis', allowEmojis, (
                                      val,
                                    ) {
                                      setState(() => allowEmojis = val);
                                      _scheduleSavePreferences(); // OPT
                                    }),
                                    const SizedBox(width: 12),
                                    _buildSwitch(
                                      'Use Hashtags',
                                      allowHashtags,
                                      (val) {
                                        setState(() => allowHashtags = val);
                                        _scheduleSavePreferences(); // OPT
                                      },
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 18),

                              // 🔹 Platform Chip Selector
                              SizedBox(
                                height: 50,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: platforms.length,
                                  itemBuilder: (context, index) {
                                    final platform = platforms[index];
                                    final isSelected =
                                        selectedPlatforms.contains(platform);

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: buildTabChip(
                                        platform,
                                        isSelected,
                                        () {
                                          setState(() {
                                            if (isSelected) {
                                              selectedPlatforms.remove(
                                                platform,
                                              );
                                            } else {
                                              selectedPlatforms.add(platform);
                                            }
                                          });
                                          _scheduleSavePreferences(); // OPT
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),

                              const SizedBox(height: 18),

                              // 🔹 Image Upload / List View
                              _buildImageUploader(context, width),

                              const SizedBox(height: 18),

                              // 🔹 Generate Button
                              MyButton(
                                text: 'Generate Caption',
                                width: width * 0.5,
                                height: 48,
                                onTap: () async {
                                  await generateCaption(width);
                                },
                                isLoading: isLoading,
                                borderRadius: 100,
                              ),

                              const SizedBox(height: 12),

                              // 🔹 Schedule
                              Center(
                                child: MyTextButton(
                                  onPressed: () async {
                                    if (textPromptController.text
                                            .trim()
                                            .isEmpty &&
                                        !isNewsSelected) {
                                      return mySnackBar(
                                        context,
                                        'Please enter caption',
                                      );
                                    }
                                    setState(
                                      () =>
                                          generated = textPromptController.text,
                                    );
                                    await showScheduleBottomSheet(
                                      generated!,
                                      width,
                                    );
                                  },
                                  child: Text(
                                    'Schedule this',
                                    style: TextStyle(color: darkColor),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
                selectedTab == 'Image' &&
                        selectedImageIdea != null &&
                        selectedImageIdeaCustomization != null &&
                        selectedImageBackgroundUrl == null &&
                        isSelectedAIGeneratedBackground
                    ? BackgroundControlsPanel(
                        width: width * 0.5,
                        backgroundPrompt: selectedImageIdeaBackground,
                        imageTab: selectedImageTab,
                        customization: selectedImageIdeaCustomization,
                        onImageGenerated: (imageUrl) {
                          setState(() {
                            selectedImageBackgroundUrl = imageUrl;
                          });
                        },
                      )
                    : const SizedBox.shrink(),
                selectedTab == 'Image' &&
                        selectedImageIdea != null &&
                        selectedImageBackgroundUrl != null &&
                        !isSelectedAIGeneratedBackground
                    ? Text(
                        'Step 3: Edit Foreground',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: darkColor,
                        ),
                      )
                    : selectedTab == 'Image' &&
                            selectedImageIdea != null &&
                            selectedImageBackgroundUrl != null &&
                            isSelectedAIGeneratedBackground
                        ? Text(
                            'Step 4: Edit Foreground',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: darkColor,
                            ),
                          )
                        : const SizedBox.shrink(),
                selectedTab == 'Image' &&
                        selectedImageIdea != null &&
                        selectedImageBackgroundUrl != null
                    ? ForegroundControlPanel(
                        width: width,
                        idea: selectedImageIdea!,
                        source: selectedImageIdeaSource,
                        background: selectedImageBackgroundUrl!,
                        imageTab: selectedImageTab,
                        onDone: () {
                          context.read<ClearNotifier>().triggerClear();
                        },
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }
}
