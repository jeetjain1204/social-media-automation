// ignore_for_file: non_constant_identifier_names
import 'package:blob/brand_profile_draft.dart';
import 'package:blob/provider/profile_provider.dart';
import 'package:blob/utils/pick_color.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/circle_avatar_edit.dart';
import 'package:blob/widgets/color_dot.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/my_button.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/profile_box.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:blob/services/database_service.dart';

const double kDesktopBreak = 900;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final backgroundScrollController = ScrollController();
  final brandNameController = TextEditingController();
  final brandNameFocusNode = FocusNode();

  Map<String, dynamic>? profile;
  Map<String, dynamic>? brandKit;

  bool isCreatingBrandKit = false;
  bool isChangingLogo = false;
  bool isChangingTransparentLogo = false;
  bool isAddingBackground = false;
  bool isEditingName = false;
  bool isUpdatingName = false;

  List imageStyleSuggestions = ['Minimal', 'Realistic', 'Sci - fi'];
  List fontSuggestions = ['Playful'];
  List<String> signedBackgroundUrls = [];
  List<Map<String, String>>? backgrounds;

  List? connectedPlatforms;
  List? canConnectPlatforms;

  final Map<String, Future<String?>> _signedUrlCache = {};

  @override
  void initState() {
    super.initState();
    fetchProfile();
    getConnectedPlatforms();
    context.read<ProfileNotifier>().addListener(fetchProfile);
  }

  @override
  void dispose() {
    backgroundScrollController.dispose();
    brandNameController.dispose();
    brandNameFocusNode.dispose();
    super.dispose();
  }

  Future<T> _withRetry<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 250),
  }) async {
    int attempt = 0;
    Object? lastError;
    while (attempt < maxAttempts) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        attempt++;
        if (attempt >= maxAttempts) break;
        final factor = 1 << (attempt - 1);
        final jitterMs = baseDelay.inMilliseconds ~/ 2;
        final delay = Duration(
                milliseconds: baseDelay.inMilliseconds * factor) +
            Duration(milliseconds: DateTime.now().microsecond % (jitterMs + 1));
        await Future.delayed(delay);
      }
    }
    throw lastError ?? Exception('Unknown error');
  }

  Future<void> fetchProfile({String? field}) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final results = await Future.wait([
        _withRetry<Map<String, dynamic>?>(
          () => supabase
              .from('brand_profiles')
              .select()
              .eq('user_id', userId)
              .maybeSingle()
              .timeout(const Duration(seconds: 12)),
        ),
        _withRetry<Map<String, dynamic>?>(
          () => supabase
              .schema('brand_kit')
              .from('brand_kits')
              .select()
              .eq('user_id', userId)
              .maybeSingle()
              .timeout(const Duration(seconds: 12)),
        ),
      ]);

      if (!mounted) return;
      final profileRes = results[0];
      final brandRes = results[1];

      if (field == null) {
        setState(() {
          profile = profileRes;
          brandKit = brandRes;
        });
        await loadSignedBackgrounds();
      } else {
        setState(() {
          profile?[field] = profileRes?[field];
          brandKit?[field] = brandRes?[field];
        });
        if (field == 'backgrounds') await loadSignedBackgrounds();
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> getConnectedPlatforms() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final List allPlatforms = ['linkedin', 'facebook', 'instagram'];
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final response = await _withRetry<List<dynamic>>(
        () => supabase
            .from('social_accounts')
            .select('platform')
            .eq('user_id', userId)
            .eq('is_disconnected', false)
            .timeout(const Duration(seconds: 12)),
      );

      final myConnected = List<String>.from(response.map((row) {
        final p = row['platform']?.toString().toLowerCase() ?? '';
        return p.isNotEmpty ? p : '';
      }));

      if (!mounted) return;
      setState(() {
        connectedPlatforms = myConnected;
        canConnectPlatforms =
            allPlatforms.where((p) => !myConnected.contains(p)).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        connectedPlatforms = [];
        canConnectPlatforms = allPlatforms;
      });
    }
  }

  Future<void> createBrandKit() async {
    setState(() => isCreatingBrandKit = true);
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      final newKitRes = await _withRetry<Map<String, dynamic>?>(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .insert({'user_id': userId, 'brand_name': profile!['brand_name']})
            .select('id')
            .maybeSingle()
            .timeout(const Duration(seconds: 12)),
      );
      if (newKitRes == null || newKitRes['id'] == null) {
        mySnackBar(context, 'Failed to create Brand Kit');
      } else {
        setState(() => brandKit = newKitRes);
      }
    } finally {
      if (mounted) setState(() => isCreatingBrandKit = false);
    }
  }

  Future<String?> getSignedImageUrl(String? p) async {
    if (p == null) return null;
    if (_signedUrlCache.containsKey(p)) return _signedUrlCache[p]!;
    final future = _withRetry<String?>(
      () => Supabase.instance.client.storage
          .from('brand-kits')
          .createSignedUrl(p, 60 * 60)
          .timeout(const Duration(seconds: 10)),
    ).then((res) {
      if ((res ?? '').isEmpty) {
        mySnackBar(context, 'Some error occured while fetching Brand Logo');
        return null;
      }
      return res;
    });
    _signedUrlCache[p] = future;
    return future;
  }

  Future<void> pickLogo(bool isBrandKit) async {
    setState(() {
      if (isBrandKit) {
        isChangingTransparentLogo = true;
      } else {
        isChangingLogo = true;
      }
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;

    if (file == null || file.path == null || file.bytes == null) {
      setState(() {
        isChangingTransparentLogo = false;
        isChangingLogo = false;
      });
      mySnackBar(
        context,
        result?.count == 0 ? 'No Image Selected' : 'Some error occurred',
      );
      return;
    }

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      mySnackBar(context, 'User not authenticated');
      return;
    }

    final storage = supabase.storage;
    final draft = context.read<BrandProfileDraft>();

    final brandKitRes = await _withRetry<Map<String, dynamic>?>(
      () => supabase
          .schema('brand_kit')
          .from('brand_kits')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 12)),
    );

    String brandKitId;
    if (brandKitRes == null) {
      final insertRes = await _withRetry<Map<String, dynamic>?>(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .insert({'user_id': userId, 'brand_name': draft.brand_name})
            .select('id')
            .maybeSingle()
            .timeout(const Duration(seconds: 12)),
      );
      if (insertRes == null) {
        mySnackBar(
            context, 'Failed to create Brand Kit. Please contact support!');
        return;
      }
      brandKitId = insertRes['id'];
    } else {
      brandKitId = brandKitRes['id'];
    }

    final uploadKey =
        'users/$userId/kits/$brandKitId/logo/${path.basename(file.path!)}';

    await _withRetry<void>(
      () => storage
          .from('brand-kits')
          .uploadBinary(uploadKey, file.bytes!,
              fileOptions: const FileOptions(upsert: true))
          .timeout(const Duration(seconds: 20)),
    );

    if (isBrandKit) {
      await _withRetry(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .update({'transparent_logo_path': uploadKey})
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 12)),
      );
    } else {
      await DatabaseService.updateProfile(
        userId,
        {'brand_logo_path': uploadKey},
        brandKitUpdates: {'brand_logo_path': uploadKey},
      );
    }

    setState(() {
      if (isBrandKit) {
        brandKit ??= {};
        brandKit!['transparent_logo_path'] = uploadKey;
        isChangingTransparentLogo = false;
      } else {
        profile ??= {};
        profile!['brand_logo_path'] = uploadKey;
        isChangingLogo = false;
      }
      _signedUrlCache.remove(uploadKey);
    });
    mySnackBar(context,
        '${isBrandKit ? 'Headshot Logo' : 'Brand Logo'} uploaded successfully!');
  }

  Future<void> updateName() async {
    final brandName = brandNameController.text.trim();
    if (brandName.isEmpty) {
      mySnackBar(context, 'Enter Brand Name');
      return;
    }
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      mySnackBar(context, 'User not authenticated');
      return;
    }
    try {
      await DatabaseService.updateProfile(userId, {'brand_name': brandName});
      if (!mounted) return;
      context.read<ProfileNotifier>().notifyProfileUpdated();
      setState(() {
        isUpdatingName = false;
        isEditingName = false;
        brandNameFocusNode.unfocus();
      });
      mySnackBar(context, 'Brand Name Updated!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isUpdatingName = false;
        isEditingName = false;
        brandNameFocusNode.unfocus();
      });
      mySnackBar(context, 'Error updating name: $e');
    }
  }

  List normalizeJsonList(dynamic value) {
    if (value == null) return [];
    if (value is Map) return value.values.map((e) => e.toString()).toList();
    if (value is List) return value.map((e) => e.toString()).toList();
    return [];
  }

  Future<void> updateListField(String key, List? updatedList) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await DatabaseService.updateProfile(
      userId,
      {},
      brandKitUpdates: {key: updatedList},
    );

    final updatedKit = await _withRetry<Map<String, dynamic>?>(
      () => supabase
          .schema('brand_kit')
          .from('brand_kits')
          .select()
          .eq('user_id', userId)
          .maybeSingle(),
    );

    if (mounted) setState(() => brandKit = updatedKit);
  }

  Future<void> toggleTag({
    required String tag,
    required List list,
    required List suggestionList,
    required String key,
  }) async {
    final isRemoving = list.contains(tag);
    setState(() => isRemoving ? list.remove(tag) : list.add(tag));
    await updateListField(key, list);
  }

  Future<void> loadSignedBackgrounds() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final paths = (brandKit?['backgrounds'] as List?)?.cast<String>() ?? [];
    final signed = await Future.wait(
      paths.map((p) async {
        try {
          final url = await getSignedImageUrl(p);
          return (url != null && url.isNotEmpty)
              ? {'path': p, 'url': url}
              : null;
        } catch (_) {
          return null;
        }
      }),
    );

    final newBackgrounds =
        signed.where((e) => e != null).cast<Map<String, String>>().toList();
    final validPaths = newBackgrounds.map((e) => e['path']!).toList();

    if (validPaths.length != paths.length) {
      final kitId = brandKit?['id'];
      if (kitId != null) {
        await _withRetry(
          () => supabase
              .schema('brand_kit')
              .from('brand_kits')
              .update({'backgrounds': validPaths}).eq('id', kitId),
        );
      }
    }
    if (mounted) setState(() => backgrounds = newBackgrounds);
  }

  Future<void> pickAndAddBackground(BuildContext context) async {
    setState(() => isAddingBackground = true);
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final storage = supabase.storage;

    if (userId == null) {
      mySnackBar(context, 'User not logged in');
      setState(() => isAddingBackground = false);
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.first.bytes == null) {
        mySnackBar(context, 'No file selected');
        return;
      }

      final file = result.files.first;
      final fileName = path.basename(file.name);

      final kitRes = await _withRetry<Map<String, dynamic>?>(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .select('id, backgrounds')
            .eq('user_id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 12)),
      );
      if (kitRes == null || kitRes['id'] == null) {
        mySnackBar(context, 'No Brand Kit found. Create one first');
        return;
      }

      final brandKitId = kitRes['id'];
      final folderPath = 'users/$userId/kits/$brandKitId/backgrounds';
      final existingPaths = (kitRes['backgrounds'] as List?) ?? [];
      final uploadKey = 'users/$userId/kits/$brandKitId/backgrounds/$fileName';

      final existingFiles = await _withRetry<List<FileObject>>(
        () => storage
            .from('brand-kits')
            .list(path: folderPath)
            .timeout(const Duration(seconds: 12)),
      );
      final alreadyExists = existingFiles.any((f) => f.name == fileName);
      if (alreadyExists) {
        mySnackBar(context, 'File already added!');
        return;
      }

      await _withRetry<void>(
        () => storage
            .from('brand-kits')
            .uploadBinary(uploadKey, file.bytes!,
                fileOptions: const FileOptions(upsert: true))
            .timeout(const Duration(seconds: 20)),
      );

      final updatedPaths = [...existingPaths, uploadKey];

      await _withRetry(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .update({'backgrounds': updatedPaths}).eq('id', brandKitId),
      );

      final updatedKit = await _withRetry<Map<String, dynamic>?>(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .select()
            .eq('user_id', userId)
            .maybeSingle(),
      );

      if (!mounted) return;
      setState(() => brandKit = updatedKit);

      final newSignedUrls = await Future.wait(
        updatedPaths.map((p) async => (await getSignedImageUrl(p)) ?? ''),
      );
      if (mounted) {
        setState(() => signedBackgroundUrls =
            newSignedUrls.where((u) => u.isNotEmpty).toList());
      }

      await loadSignedBackgrounds();
      await refreshSignedBackgrounds(updatedPaths);
      mySnackBar(context, 'Background added!');
    } catch (e) {
      mySnackBar(context, 'Failed to upload background: $e');
    } finally {
      if (mounted) setState(() => isAddingBackground = false);
    }
  }

  Future<void> removeBackground(
      BuildContext context, String pathToDelete) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    final storage = supabase.storage;
    if (userId == null) {
      mySnackBar(context, 'User not logged in');
      return;
    }

    try {
      final kitRes = await _withRetry<Map<String, dynamic>?>(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .select('id, backgrounds')
            .eq('user_id', userId)
            .maybeSingle(),
      );
      if (kitRes == null || kitRes['id'] == null) {
        mySnackBar(context, 'Brand Kit not found');
        return;
      }

      final brandKitId = kitRes['id'];
      final existingPaths = (kitRes['backgrounds'] as List?) ?? [];
      final updatedPaths =
          existingPaths.where((p) => p != pathToDelete).toList();

      await _withRetry(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .update({'backgrounds': updatedPaths}).eq('id', brandKitId),
      );

      final cleanPath = Uri.decodeFull(pathToDelete.trim());
      await _withRetry<void>(() => storage
          .from('brand-kits')
          .remove([cleanPath]).timeout(const Duration(seconds: 12)));

      final updatedKit = await _withRetry<Map<String, dynamic>?>(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .select()
            .eq('user_id', userId)
            .maybeSingle(),
      );
      if (mounted) setState(() => brandKit = updatedKit);

      final newSignedUrls = await Future.wait(
        updatedPaths.map((p) async => (await getSignedImageUrl(p)) ?? ''),
      );
      if (mounted)
        setState(() => signedBackgroundUrls =
            newSignedUrls.where((u) => u.isNotEmpty).toList());

      await loadSignedBackgrounds();
      await refreshSignedBackgrounds(updatedPaths);
      mySnackBar(context, 'Background removed successfully!');
    } on StorageException catch (se) {
      if (se.statusCode != '404') {
        mySnackBar(context, 'Failed to remove background: ${se.message}');
      }
    } catch (e) {
      mySnackBar(context, 'Failed to remove background: $e');
    }
  }

  Future<void> refreshSignedBackgrounds(List updatedPaths) async {
    final urls =
        await Future.wait(updatedPaths.map((p) => getSignedImageUrl(p)));
    if (mounted)
      setState(() => signedBackgroundUrls = urls.whereType<String>().toList());
  }

  Widget skeletonBox({double? w, double? h, double r = 24, Widget? child}) {
    return SizedBox(
      width: w,
      height: h,
      child: AutoSkeleton(
        enabled: true,
        preserveSize: true,
        baseColor: lightColor,
        effectColor: darkColor,
        borderRadius: r,
        child: child ?? const SizedBox.expand(),
      ),
    );
  }

  // ------------------------------- UI -------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final isDesktop = w >= kDesktopBreak;
        final hPad = isDesktop ? 24.0 : 12.0;
        final vPad = isDesktop ? 24.0 : 12.0;
        final sectionGap = isDesktop ? 24.0 : 16.0;
        final nameFont = isDesktop ? 28.0 : 20.0;

        return Scaffold(
          backgroundColor: const Color(0xFFF7F9FC),
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: profile == null
                ? SingleChildScrollView(
                    padding:
                        EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                    child: Column(
                      children: [
                        skeletonBox(
                            w: isDesktop ? w * 0.12 : 100,
                            h: isDesktop ? w * 0.12 : 100,
                            r: 100),
                        SizedBox(height: sectionGap * 1.5),
                        skeletonBox(w: isDesktop ? w * 0.30 : w * 0.6, h: 22),
                        SizedBox(height: sectionGap * 2),
                        skeletonBox(w: w, h: 120),
                        SizedBox(height: sectionGap),
                        skeletonBox(w: w, h: 120),
                        SizedBox(height: sectionGap),
                        skeletonBox(w: w, h: 100),
                        SizedBox(height: sectionGap),
                        skeletonBox(w: w, h: 205, r: 16),
                        SizedBox(height: sectionGap),
                        skeletonBox(w: w, h: 56, r: 100),
                        SizedBox(height: sectionGap * 0.75),
                        skeletonBox(w: w, h: 56, r: 100),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding:
                        EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // -------- Avatar / Brand name --------
                        Tooltip(
                          message: 'Logo',
                          child: FutureBuilder(
                            key: ValueKey(profile!['brand_logo_path']),
                            future:
                                getSignedImageUrl(profile!['brand_logo_path']),
                            builder: (context, snap) {
                              if (snap.hasError) {
                                return CircleAvatarEdit(
                                  width: w,
                                  icon: Icons.error_outline_rounded,
                                  onTap: () async => pickLogo(false),
                                );
                              }
                              if (snap.hasData) {
                                return CircleAvatarEdit(
                                  width: w,
                                  imageUrl: snap.data,
                                  onTap: () async => pickLogo(false),
                                );
                              }
                              return CircleAvatarEdit(
                                  width: w, onTap: () async => pickLogo(false));
                            },
                          ),
                        ),
                        SizedBox(height: sectionGap * 1.5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            isUpdatingName
                                ? skeletonBox(
                                    w: isDesktop ? w * 0.30 : w * 0.6, h: 22)
                                : IntrinsicWidth(
                                    child: EditableText(
                                      textAlign: TextAlign.center,
                                      controller: brandNameController
                                        ..text = (profile!['brand_name'] ?? '')
                                            .toString(),
                                      readOnly: !isEditingName,
                                      autocorrect: false,
                                      focusNode: brandNameFocusNode,
                                      style: TextStyle(
                                        color: darkColor,
                                        fontSize: nameFont,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      cursorColor: darkColor,
                                      backgroundCursorColor: lightColor,
                                      onSubmitted: (_) async {
                                        setState(() {
                                          isUpdatingName = true;
                                          isEditingName = false;
                                        });
                                        await updateName();
                                      },
                                      onTapOutside: (_) async {
                                        if (!isEditingName) return;
                                        setState(() {
                                          isUpdatingName = true;
                                          isEditingName = false;
                                        });
                                        await updateName();
                                      },
                                    ),
                                  ),
                            if (!isUpdatingName) ...[
                              SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  brandNameFocusNode.unfocus();
                                  if (!isEditingName) {
                                    setState(() => isEditingName = true);
                                    brandNameFocusNode.requestFocus();
                                  } else {
                                    setState(() {
                                      isUpdatingName = true;
                                      isEditingName = false;
                                    });
                                    updateName();
                                  }
                                },
                                icon: Icon(
                                    isEditingName
                                        ? Icons.check_rounded
                                        : Icons.edit_outlined,
                                    color: darkColor.withOpacity(0.35)),
                                splashRadius: 20,
                                tooltip: isEditingName ? 'Save' : 'Edit',
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: sectionGap * 2),

                        // -------- Profile facts (responsive) --------
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            ProfileBox(
                                width: w,
                                label: 'Persona',
                                value: profile!['persona'],
                                editPath: '/onboarding/persona'),
                            ProfileBox(
                                width: w,
                                label: 'Category',
                                value: profile!['category']),
                            ProfileBox(
                                width: w,
                                label: 'Subcategory',
                                value: profile!['subcategory'],
                                editPath: '/onboarding/subcategory'),
                            ProfileBox(
                                width: w,
                                label: 'Primary Goal',
                                value: profile!['primary_goal'],
                                editPath: '/onboarding/primary-goal'),
                            ProfileBox(
                                width: w,
                                label: 'Primary Color',
                                value: profile!['primary_color'],
                                editPath: '/onboarding/primary-color'),
                            ProfileBox(
                                width: w,
                                label: 'Target Posts Per Week',
                                value: (profile!['target_posts_per_week'])
                                    .toString(),
                                editPath: '/onboarding/target-posts-per-week'),
                            ProfileBox(
                                width: w,
                                label: 'Timezone',
                                value: profile!['timezone'],
                                editPath: '/onboarding/timezone'),
                            ProfileBox(
                                width: w,
                                label: 'Voice Tags',
                                items: profile!['voice_tags'],
                                editPath: '/onboarding/voice-tags'),
                            ProfileBox(
                                width: w,
                                label: 'Content Types',
                                items: profile!['content_types'],
                                editPath: '/onboarding/content-types'),
                          ],
                        ),

                        SizedBox(height: sectionGap),

                        // -------- Brand Kit --------
                        if (brandKit == null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: MyButton(
                              width: isDesktop ? (w * 0.2) : w,
                              text: 'Create your Brand Kit',
                              onTap: () async => createBrandKit(),
                              isLoading: isCreatingBrandKit,
                            ),
                          )
                        else
                          Column(
                            children: [
                              SizedBox(height: sectionGap),
                              Tooltip(
                                message: 'Headshot Image',
                                child: FutureBuilder(
                                  key: ValueKey(
                                      brandKit!['transparent_logo_path']),
                                  future: getSignedImageUrl(
                                      brandKit!['transparent_logo_path']),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasError) {
                                      return CircleAvatarEdit(
                                        width: w,
                                        icon: Icons.error_outline_rounded,
                                        onTap: () async => pickLogo(true),
                                      );
                                    }
                                    if (snapshot.hasData) {
                                      return CircleAvatarEdit(
                                        width: w,
                                        imageUrl: snapshot.data!,
                                        onTap: () async => pickLogo(true),
                                      );
                                    }
                                    return CircleAvatarEdit(
                                      width: w,
                                      icon: Icons.camera_alt,
                                      onTap: () async => pickLogo(true),
                                    );
                                  },
                                ),
                              ),
                              SizedBox(height: sectionGap),

                              // Colors row
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: lightColor.withOpacity(0.125),
                                  border: Border.all(
                                      width: 1,
                                      color: lightColor.withOpacity(0.25)),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Colors',
                                        style: TextStyle(
                                            color: darkColor,
                                            fontSize: isDesktop ? 18 : 16,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 12,
                                      children: [
                                        ColorDot(
                                          color: brandKit!['colors']
                                              ?['primary'],
                                          label: 'Primary',
                                          onTap: () async {
                                            await pickColor(
                                              context: context,
                                              initialColor: Color(int.parse(
                                                  (brandKit!['colors']
                                                              ?['primary'] ??
                                                          '#004AAD')
                                                      .replaceFirst(
                                                          '#', '0xFF'))),
                                              onColorSelected:
                                                  (selectedColor) async {
                                                final hex =
                                                    '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                final userId = Supabase
                                                    .instance
                                                    .client
                                                    .auth
                                                    .currentUser
                                                    ?.id;
                                                if (userId != null) {
                                                  await DatabaseService
                                                      .updateProfile(
                                                    userId,
                                                    {},
                                                    brandKitUpdates: {
                                                      'colors': {
                                                        ...?brandKit!['colors'],
                                                        'primary': hex
                                                      }
                                                    },
                                                  );
                                                }
                                                if (!mounted) return;
                                                setState(() =>
                                                    brandKit!['colors']
                                                        ['primary'] = hex);
                                                mySnackBar(context,
                                                    'PRIMARY Color Updated!');
                                              },
                                            );
                                          },
                                        ),
                                        ColorDot(
                                          color: brandKit!['colors']
                                              ?['secondary'],
                                          label: 'Secondary',
                                          onTap: () async {
                                            await pickColor(
                                              context: context,
                                              initialColor: Color(int.parse(
                                                  (brandKit!['colors']
                                                              ?['secondary'] ??
                                                          '#BDE2FF')
                                                      .replaceFirst(
                                                          '#', '0xFF'))),
                                              onColorSelected:
                                                  (selectedColor) async {
                                                final hex =
                                                    '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                await Supabase.instance.client
                                                    .schema('brand_kit')
                                                    .from('brand_kits')
                                                    .update({
                                                  'colors': {
                                                    ...?brandKit!['colors'],
                                                    'secondary': hex
                                                  }
                                                }).eq('id', brandKit!['id']);
                                                if (!mounted) return;
                                                setState(() =>
                                                    brandKit!['colors']
                                                        ['secondary'] = hex);
                                                mySnackBar(context,
                                                    'SECONDARY Color Updated!');
                                              },
                                            );
                                          },
                                        ),
                                        ColorDot(
                                          color: brandKit!['colors']?['accent'],
                                          label: 'Accent',
                                          onTap: () async {
                                            await pickColor(
                                              context: context,
                                              initialColor: Color(int.parse(
                                                  (brandKit!['colors']
                                                              ?['accent'] ??
                                                          '#111827')
                                                      .replaceFirst(
                                                          '#', '0xFF'))),
                                              onColorSelected:
                                                  (selectedColor) async {
                                                final hex =
                                                    '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                await Supabase.instance.client
                                                    .schema('brand_kit')
                                                    .from('brand_kits')
                                                    .update({
                                                  'colors': {
                                                    ...?brandKit!['colors'],
                                                    'accent': hex
                                                  }
                                                }).eq('id', brandKit!['id']);
                                                if (!mounted) return;
                                                setState(() =>
                                                    brandKit!['colors']
                                                        ['accent'] = hex);
                                                mySnackBar(context,
                                                    'ACCENT Color Updated!');
                                              },
                                            );
                                          },
                                        ),
                                        ColorDot(
                                          color: brandKit!['colors']
                                              ?['background'],
                                          label: 'Background',
                                          onTap: () async {
                                            await pickColor(
                                              context: context,
                                              initialColor: Color(int.parse(
                                                  (brandKit!['colors']
                                                              ?['background'] ??
                                                          '#F7F9FC')
                                                      .replaceFirst(
                                                          '#', '0xFF'))),
                                              onColorSelected:
                                                  (selectedColor) async {
                                                final hex =
                                                    '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                await Supabase.instance.client
                                                    .schema('brand_kit')
                                                    .from('brand_kits')
                                                    .update({
                                                  'colors': {
                                                    ...?brandKit!['colors'],
                                                    'background': hex
                                                  }
                                                }).eq('id', brandKit!['id']);
                                                if (!mounted) return;
                                                setState(() =>
                                                    brandKit!['colors']
                                                        ['background'] = hex);
                                                mySnackBar(context,
                                                    'BACKGROUND Color Updated!');
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: sectionGap),

                              // Backgrounds picker
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: lightColor.withOpacity(0.125),
                                  border: Border.all(
                                      width: 1,
                                      color: lightColor.withOpacity(0.25)),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Backgrounds',
                                        style: TextStyle(
                                            color: darkColor,
                                            fontSize: isDesktop ? 18 : 16,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 12),
                                    if (backgrounds == null)
                                      skeletonBox(
                                          w: double.infinity, h: 100, r: 16)
                                    else if (backgrounds!.isEmpty)
                                      const Text('No Backgrounds added')
                                    else
                                      SizedBox(
                                        height: isDesktop ? 120 : 100,
                                        child: ListView.separated(
                                          controller:
                                              backgroundScrollController,
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const ClampingScrollPhysics(),
                                          itemCount: backgrounds!.length,
                                          separatorBuilder: (_, __) =>
                                              const SizedBox(width: 10),
                                          itemBuilder: (context, index) {
                                            final bg = backgrounds![index];
                                            final url = bg['url']!;
                                            final pathToDelete = bg['path']!;
                                            return AspectRatio(
                                              aspectRatio: 1,
                                              child: Stack(
                                                children: [
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                          width: 0.5,
                                                          color: darkColor
                                                              .withOpacity(
                                                                  0.5)),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                      child: Image.network(
                                                        url,
                                                        fit: BoxFit.cover,
                                                        width: double.infinity,
                                                        height: double.infinity,
                                                        loadingBuilder:
                                                            (context, child,
                                                                progress) {
                                                          if (progress == null)
                                                            return child;
                                                          return Shimmer
                                                              .fromColors(
                                                            baseColor: lightColor
                                                                .withOpacity(
                                                                    0.1),
                                                            highlightColor:
                                                                lightColor
                                                                    .withOpacity(
                                                                        0.25),
                                                            child: Container(
                                                              decoration:
                                                                  BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            16),
                                                                color:
                                                                    lightColor,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        errorBuilder: (_, __,
                                                                ___) =>
                                                            const Center(
                                                                child: Icon(Icons
                                                                    .broken_image)),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    top: 4,
                                                    right: 4,
                                                    child: Tooltip(
                                                      message: 'Remove',
                                                      child: InkWell(
                                                        onTap: () async =>
                                                            removeBackground(
                                                                context,
                                                                pathToDelete),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(20),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(4),
                                                          decoration:
                                                              BoxDecoration(
                                                                  color:
                                                                      darkColor,
                                                                  shape: BoxShape
                                                                      .circle),
                                                          child: const Icon(
                                                              Icons.close,
                                                              size: 16,
                                                              color:
                                                                  Colors.white),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: isDesktop
                                          ? Alignment.centerRight
                                          : Alignment.center,
                                      child: GestureDetector(
                                        onTap: () async {
                                          if (!isAddingBackground)
                                            await pickAndAddBackground(context);
                                        },
                                        child: Container(
                                          width: isDesktop ? 64 : 56,
                                          height: isDesktop ? 64 : 56,
                                          decoration: BoxDecoration(
                                            color:
                                                lightColor.withOpacity(0.125),
                                            border: Border.all(
                                                width: 2,
                                                color:
                                                    darkColor.withOpacity(0.5)),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: isAddingBackground
                                              ? skeletonBox()
                                              : Icon(Icons.add_rounded,
                                                  color: darkColor,
                                                  size: isDesktop ? 40 : 32),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                        SizedBox(height: sectionGap),

                        // -------- Connected Accounts --------
                        if (connectedPlatforms != null) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Connected Accounts',
                                style: TextStyle(
                                    color: darkColor,
                                    fontSize: isDesktop ? 18 : 16,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 8),
                          if (connectedPlatforms!.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'No Platforms Connected',
                                style: TextStyle(
                                    color: darkColor.withOpacity(0.75),
                                    fontWeight: FontWeight.w600),
                              ),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.start,
                              children: connectedPlatforms!.map((item) {
                                final label = _platformLabel(item.toString());
                                return GestureDetector(
                                  onTap: () => context.push(
                                      '/platform/${item.toString().toLowerCase()}'),
                                  child: Chip(
                                    label: Text(label,
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    backgroundColor: darkColor,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                  ),
                                );
                              }).toList(),
                            ),
                          if (canConnectPlatforms != null &&
                              canConnectPlatforms!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Can Connect',
                                  style: TextStyle(
                                      color: darkColor,
                                      fontSize: isDesktop ? 18 : 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: canConnectPlatforms!.map((item) {
                                final label = _platformLabel(item.toString());
                                return GestureDetector(
                                  onTap: () {
                                    if (item.toString().toLowerCase() ==
                                        'linkedin') {
                                      context.push('/connect/linkedin');
                                    } else {
                                      context.push('/connect/meta');
                                    }
                                  },
                                  child: Chip(
                                    label: Text(label,
                                        style: const TextStyle(
                                            color: Colors.white)),
                                    backgroundColor: darkColor,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                        SizedBox(height: sectionGap),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  String _platformLabel(String raw) {
    final k = raw.toLowerCase();
    if (k == 'linkedin') return 'LinkedIn';
    if (k == 'facebook') return 'Facebook';
    if (k == 'instagram') return 'Instagram';
    if (k == 'youtube') return 'YouTube';
    if (k == 'twitter') return 'Twitter';
    return 'Unknown Platform';
  }
}
