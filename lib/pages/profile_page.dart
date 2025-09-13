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
  bool isLoading = true;

  List imageStyleSuggestions = ['Minimal', 'Realistic', 'Sci - fi'];
  List fontSuggestions = ['Playful'];
  List<String> signedBackgroundUrls = [];
  List<Map<String, String>>? backgrounds;

  List? connectedPlatforms;
  List? canConnectPlatforms;

  // OPT: cache for signed URLs to prevent repeated network calls on rebuilds
  final Map<String, Future<String?>> _signedUrlCache = {}; // OPT

  @override
  void initState() {
    super.initState();
    fetchProfile();
    getConnectedPlatforms();

    final profileNotifier = context.read<ProfileNotifier>();
    profileNotifier.addListener(() {
      fetchProfile();
    });
  }

  @override
  void dispose() {
    // OPT: dispose controllers to avoid leaks
    backgroundScrollController.dispose();
    brandNameController.dispose();
    brandNameFocusNode.dispose();
    super.dispose();
  }

  // OPT: small retry with backoff + jitter + timeout for network resilience
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
        final factor = 1 << (attempt - 1); // 1,2
        final jitterMs = baseDelay.inMilliseconds ~/ 2;
        final delay =
            Duration(milliseconds: baseDelay.inMilliseconds * factor) +
                Duration(
                  milliseconds: (DateTime.now().microsecond % (jitterMs + 1)),
                );
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
      // OPT: fetch profile + brand kit in parallel with retry + timeout
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

      final profileRes = results[0];
      final brandRes = results[1];

      if (!mounted) return;

      if (field == null) {
        setState(() {
          profile = profileRes;
          brandKit = brandRes;
          isLoading = false;
        });
        await loadSignedBackgrounds();
      } else {
        setState(() {
          profile?[field] = profileRes?[field];
          brandKit?[field] = brandRes?[field];
        });
        if (field == 'backgrounds') {
          await loadSignedBackgrounds();
        }
      }
    } catch (_) {
      if (mounted) setState(() => isLoading = false);
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

      final myConnectedPlatforms = List<String>.from(
        response.map((row) {
          final p = row['platform']?.toString().toLowerCase() ?? '';
          return p.isNotEmpty ? p : '';
        }),
      );

      if (!mounted) return;

      setState(() {
        connectedPlatforms = myConnectedPlatforms;
        canConnectPlatforms = allPlatforms
            .where((platform) => !myConnectedPlatforms.contains(platform))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        connectedPlatforms = [];
        canConnectPlatforms = allPlatforms; // safe fallback
      });
    }
  }

  Future<void> createBrandKit() async {
    setState(() {
      isCreatingBrandKit = true;
    });

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
        if (mounted) {
          setState(() => isCreatingBrandKit = false);
          mySnackBar(context, 'Failed to create Brand Kit');
        }
        return;
      }

      if (mounted) {
        setState(() {
          brandKit = newKitRes;
          isCreatingBrandKit = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isCreatingBrandKit = false);
        mySnackBar(context, 'Some error occured');
      }
    }
  }

  // OPT: memoized signed-url getter to avoid repeated network calls on rebuilds
  Future<String?> getSignedImageUrl(String? p) async {
    if (p == null) return null;
    if (_signedUrlCache.containsKey(p)) return _signedUrlCache[p]!; // OPT

    final future = _withRetry<String?>(
      () => Supabase.instance.client.storage
          .from('brand-kits')
          .createSignedUrl(p, 60 * 60)
          .timeout(const Duration(seconds: 10)),
    ).then((res) {
      if (res == null || res.isEmpty) {
        if (mounted)
          mySnackBar(
            context,
            'Some error occured while fetching Brand Logo',
          );
        return null;
      }
      return res;
    });

    _signedUrlCache[p] = future; // OPT: cache future immediately
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
        if (isBrandKit) {
          isChangingTransparentLogo = false;
        } else {
          isChangingLogo = false;
        }
      });
      if (mounted) {
        mySnackBar(
          context,
          result?.count == 0 ? 'No Image Selected' : 'Some error occurred',
        );
      }
      return;
    }

    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) mySnackBar(context, 'User not authenticated');
      return;
    }

    final storage = supabase.storage;
    // ignore: use_build_context_synchronously
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
        if (mounted) {
          mySnackBar(
            context,
            'Failed to create Brand Kit. Please contact support!',
          );
        }
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
          .uploadBinary(
            uploadKey,
            file.bytes!,
            fileOptions: const FileOptions(upsert: true),
          )
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
      await _withRetry(
        () => supabase
            .from('brand_profiles')
            .update({'brand_logo_path': uploadKey}).eq('user_id', userId),
      );
      await _withRetry(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .update({'brand_logo_path': uploadKey}).eq('user_id', userId),
      );
    }

    // OPT: update local state & cache to avoid immediate re-fetch of signed URL
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
      _signedUrlCache.remove(uploadKey); // ensure fresh signed url next fetch
    });
    if (mounted) {
      mySnackBar(
        context,
        '${isBrandKit ? 'Headshot Logo' : 'Brand Logo'} uploaded successfully!',
      );
    }
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
      await _withRetry(
        () => supabase
            .from('brand_profiles')
            .update({'brand_name': brandName}).eq('user_id', userId),
      );
      if (mounted) {
        context.read<ProfileNotifier>().notifyProfileUpdated();
        setState(() {
          isUpdatingName = false;
          isEditingName = false;
          brandNameFocusNode.unfocus();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isUpdatingName = false;
          isEditingName = false;
          brandNameFocusNode.unfocus();
        });
        mySnackBar(context, 'Error updating name: $e');
      }
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

    await _withRetry(
      () => supabase
          .schema('brand_kit')
          .from('brand_kits')
          .update({key: updatedList}).eq('user_id', userId),
    );

    final updatedKit = await _withRetry<Map<String, dynamic>?>(
      () => supabase
          .schema('brand_kit')
          .from('brand_kits')
          .select()
          .eq('user_id', userId)
          .maybeSingle(),
    );

    if (mounted) {
      setState(() {
        brandKit = updatedKit;
      });
    }
  }

  Future<void> toggleTag({
    required String tag,
    required List list,
    required List suggestionList,
    required String key,
  }) async {
    final isRemoving = list.contains(tag);

    setState(() {
      if (isRemoving) {
        list.remove(tag);
      } else {
        list.add(tag);
      }
    });

    await updateListField(key, list);
  }

  Future<void> loadSignedBackgrounds() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) return;

    final paths = (brandKit?['backgrounds'] as List?)?.cast<String>() ?? [];

    // OPT: request all signed URLs in parallel; collect valid ones
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

    // OPT: prune invalid paths once (server update) if any mismatch
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

    if (mounted) {
      setState(() {
        backgrounds = newBackgrounds;
      });
    }
  }

  Future<void> pickAndAddBackground(BuildContext context) async {
    setState(() {
      isAddingBackground = true;
    });

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
        if (context.mounted) mySnackBar(context, 'No file selected');
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
        if (context.mounted)
          mySnackBar(context, 'No Brand Kit found. Create one first');
        return;
      }

      final brandKitId = kitRes['id'];
      final folderPath = 'users/$userId/kits/$brandKitId/backgrounds';

      final existingPaths = (kitRes['backgrounds'] as List?) ?? [];

      final uploadKey = 'users/$userId/kits/$brandKitId/backgrounds/$fileName';

      // FIX: use FileObject (correct type) from Supabase storage list
      final existingFiles = await _withRetry<List<FileObject>>(
        // OPT: compile fix + retry
        () => storage
            .from('brand-kits')
            .list(path: folderPath)
            .timeout(const Duration(seconds: 12)),
      );
      final alreadyExists = existingFiles.any(
        (f) => f.name == fileName,
      ); // FIX: f.name (non-null)

      if (alreadyExists) {
        if (context.mounted) mySnackBar(context, 'File already added!');
        return;
      }

      await _withRetry<void>(
        () => storage
            .from('brand-kits')
            .uploadBinary(
              uploadKey,
              file.bytes!,
              fileOptions: const FileOptions(upsert: true),
            )
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
      setState(() {
        brandKit = updatedKit;
      });

      final newSignedUrls = await Future.wait(
        updatedPaths.map((p) async => (await getSignedImageUrl(p)) ?? ''),
      );

      if (mounted) {
        setState(() {
          signedBackgroundUrls =
              newSignedUrls.where((url) => url.isNotEmpty).toList();
        });
      }

      await loadSignedBackgrounds();
      await refreshSignedBackgrounds(updatedPaths);
      if (context.mounted) mySnackBar(context, 'Background added!');
    } catch (e) {
      print('error: ${e.toString()}');
      if (context.mounted) {
        mySnackBar(context, 'Failed to upload background: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => isAddingBackground = false);
    }
  }

  Future<void> removeBackground(
    BuildContext context,
    String pathToDelete,
  ) async {
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
        if (context.mounted) mySnackBar(context, 'Brand Kit not found');
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

      await _withRetry<void>(
        () => storage
            .from('brand-kits')
            .remove([cleanPath]).timeout(const Duration(seconds: 12)),
      );

      final updatedKit = await _withRetry<Map<String, dynamic>?>(
        () => supabase
            .schema('brand_kit')
            .from('brand_kits')
            .select()
            .eq('user_id', userId)
            .maybeSingle(),
      );

      if (mounted) {
        setState(() {
          brandKit = updatedKit;
        });
      }

      final newSignedUrls = await Future.wait(
        updatedPaths.map((p) async => (await getSignedImageUrl(p)) ?? ''),
      );

      if (mounted) {
        setState(() {
          signedBackgroundUrls =
              newSignedUrls.where((url) => url.isNotEmpty).toList();
        });
      }

      await loadSignedBackgrounds();
      await refreshSignedBackgrounds(updatedPaths);
      if (context.mounted)
        mySnackBar(context, 'Background removed successfully!');
    } on StorageException catch (se) {
      if (se.statusCode == '404') {
        return;
      } else {
        if (context.mounted) {
          mySnackBar(context, 'Failed to remove background: ${se.message}');
        }
      }
    } catch (e) {
      if (context.mounted) {
        mySnackBar(context, 'Failed to remove background: ${e.toString()}');
      }
    }
  }

  Future<void> refreshSignedBackgrounds(List updatedPaths) async {
    final urls = await Future.wait(
      updatedPaths.map((p) => getSignedImageUrl(p)),
    );
    if (mounted) {
      setState(() {
        signedBackgroundUrls = urls.whereType<String>().toList();
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: profile == null
            ? LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  return SingleChildScrollView(
                    padding: EdgeInsets.all(w * 0.0125),
                    child: Column(
                      children: [
                        // avatar skeleton
                        skeletonBox(w: w * 0.10, h: w * 0.10, r: w * 0.05),
                        const SizedBox(height: 36),
                        // name line
                        skeletonBox(w: w * 0.30, h: w * 0.025),
                        const SizedBox(height: 48),
                        // three profile rows
                        skeletonBox(w: w, h: 120),
                        const SizedBox(height: 24),
                        skeletonBox(w: w, h: 120),
                        const SizedBox(height: 24),
                        skeletonBox(w: w, h: 100),
                        const SizedBox(height: 24),
                        // backgrounds block
                        skeletonBox(w: w, h: 205, r: 16),
                        const SizedBox(height: 24),
                        // connected accounts blocks
                        skeletonBox(w: w, h: 56, r: 100),
                        const SizedBox(height: 12),
                        skeletonBox(w: w, h: 56, r: 100),
                      ],
                    ),
                  );
                },
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final String persona = profile!['persona'];
                  final String category = profile!['category'];
                  final String subcategory = profile!['subcategory'];
                  final String brand_name = profile!['brand_name'];
                  brandNameController.text = brand_name;
                  final String? brand_logo_path = profile!['brand_logo_path'];
                  final String primary_goal = profile!['primary_goal'];
                  final String primary_color = profile!['primary_color'];
                  final List voice_tags = profile!['voice_tags'];
                  final List content_types = profile!['content_types'];
                  final int target_posts_per_week =
                      profile!['target_posts_per_week'];
                  final String timezone = profile!['timezone'];

                  final String? brand_kit_transparent_logo_path =
                      brandKit?['transparent_logo_path'];

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(width * 0.0125),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Tooltip(
                              message: 'Logo',
                              child: FutureBuilder(
                                key: ValueKey(brand_logo_path),
                                future: getSignedImageUrl(brand_logo_path),
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return Semantics(
                                      label: 'Error while fetching logo',
                                      child: CircleAvatarEdit(
                                        width: width,
                                        icon: Icons.error_outline_rounded,
                                        onTap: () async {
                                          await pickLogo(false);
                                        },
                                      ),
                                    );
                                  }

                                  if (snapshot.hasData) {
                                    final imageUrl = snapshot.data;
                                    return Semantics(
                                      label: 'Logo. Tap to upload new logo',
                                      child: CircleAvatarEdit(
                                        width: width,
                                        imageUrl: imageUrl,
                                        onTap: () async {
                                          await pickLogo(false);
                                        },
                                      ),
                                    );
                                  }

                                  return CircleAvatarEdit(
                                    width: width,
                                    onTap: () async {
                                      await pickLogo(false);
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 36),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                isUpdatingName
                                    ? skeletonBox(
                                        w: width * 0.30,
                                        h: width * 0.025,
                                      )
                                    : IntrinsicWidth(
                                        child: EditableText(
                                          textAlign: TextAlign.end,
                                          onSubmitted: (value) async {
                                            setState(() {
                                              isUpdatingName = true;
                                              isEditingName = false;
                                            });
                                            await updateName();
                                          },
                                          onTapOutside: (value) async {
                                            setState(() {
                                              isUpdatingName = true;
                                              isEditingName = false;
                                            });
                                            await updateName();
                                            if (context.mounted) {
                                              mySnackBar(
                                                context,
                                                'Brand Name Updated!',
                                              );
                                            }
                                          },
                                          onEditingComplete: () {
                                            setState(() {
                                              isUpdatingName = true;
                                              isEditingName = false;
                                            });
                                            updateName();
                                          },
                                          controller: brandNameController,
                                          readOnly: !isEditingName,
                                          autocorrect: false,
                                          focusNode: brandNameFocusNode,
                                          style: TextStyle(
                                            color: darkColor,
                                            fontSize: width * 0.025,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          cursorColor: darkColor,
                                          backgroundCursorColor: lightColor,
                                        ),
                                      ),
                                isUpdatingName
                                    ? const SizedBox.shrink()
                                    : IconButton(
                                        onPressed: () {
                                          brandNameFocusNode.unfocus();
                                          if (!isEditingName) {
                                            setState(() {
                                              isEditingName = true;
                                            });
                                          }
                                        },
                                        icon: Icon(
                                          isEditingName
                                              ? Icons.check_rounded
                                              : Icons.edit_outlined,
                                          color: darkColor.withOpacity(0.25),
                                        ),
                                        iconSize: width * 0.01,
                                        splashColor: Colors.transparent,
                                        splashRadius: width * 0.01,
                                        color: darkColor,
                                        tooltip: 'Edit',
                                      ),
                              ],
                            ),
                            const SizedBox(height: 48),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ProfileBox(
                                  width: width,
                                  label: 'Persona',
                                  value: persona,
                                  editPath: '/onboarding/persona',
                                ),
                                ProfileBox(
                                  width: width,
                                  label: 'Category',
                                  value: category,
                                ),
                                ProfileBox(
                                  width: width,
                                  label: 'Subcategory',
                                  value: subcategory,
                                  editPath: '/onboarding/subcategory',
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ProfileBox(
                                  width: width,
                                  label: 'Primary Goal',
                                  value: primary_goal,
                                  editPath: '/onboarding/primary-goal',
                                ),
                                ProfileBox(
                                  width: width,
                                  label: 'Primary Color',
                                  value: primary_color,
                                  editPath: '/onboarding/primary-color',
                                ),
                                ProfileBox(
                                  width: width,
                                  label: 'Target Posts Per Week',
                                  value: target_posts_per_week.toString(),
                                  editPath: '/onboarding/target-posts-per-week',
                                ),
                                ProfileBox(
                                  width: width,
                                  label: 'Timezone',
                                  value: timezone,
                                  editPath: '/onboarding/timezone',
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                ProfileBox(
                                  width: width,
                                  label: 'Voice Tags',
                                  items: voice_tags,
                                  editPath: '/onboarding/voice-tags',
                                ),
                                ProfileBox(
                                  width: width,
                                  label: 'Content Types',
                                  items: content_types,
                                  editPath: '/onboarding/content-types',
                                ),
                              ],
                            ),
                          ],
                        ),
                        brandKit == null
                            ? MyButton(
                                width: width,
                                text: 'Create your Brand Kit',
                                onTap: () async {
                                  await createBrandKit();
                                },
                                isLoading: isCreatingBrandKit,
                              )
                            : Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Tooltip(
                                      message: 'Headshot Image',
                                      child: FutureBuilder(
                                        key: ValueKey(
                                          brand_kit_transparent_logo_path,
                                        ),
                                        future: getSignedImageUrl(
                                          brand_kit_transparent_logo_path,
                                        ),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasError) {
                                            return Semantics(
                                              label:
                                                  'Error while fetching headshot',
                                              child: CircleAvatarEdit(
                                                width: width,
                                                icon:
                                                    Icons.error_outline_rounded,
                                                onTap: () async {
                                                  await pickLogo(true);
                                                },
                                              ),
                                            );
                                          }

                                          if (snapshot.hasData) {
                                            final imageUrl = snapshot.data!;
                                            return Semantics(
                                              label: 'Headshot Image',
                                              child: CircleAvatarEdit(
                                                width: width,
                                                imageUrl: imageUrl,
                                                onTap: () async {
                                                  await pickLogo(true);
                                                },
                                              ),
                                            );
                                          }

                                          if (!snapshot.hasData) {
                                            return CircleAvatarEdit(
                                              width: width,
                                              icon: Icons.camera_alt,
                                              onTap: () async {
                                                await pickLogo(true);
                                              },
                                            );
                                          }

                                          return skeletonBox(
                                            w: width * 0.10,
                                            h: width * 0.10,
                                            r: 1000,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: lightColor.withOpacity(
                                        0.125,
                                      ), // --light-accent
                                      border: Border.all(
                                        width: 1,
                                        color: lightColor.withOpacity(0.25),
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        16,
                                      ), // --radius-btn
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Colors',
                                          style: TextStyle(
                                            color: darkColor,
                                            fontSize: width * 0.0125,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            ColorDot(
                                              color: brandKit!['colors']
                                                  ?['primary'],
                                              label: 'Primary',
                                              onTap: () async {
                                                await pickColor(
                                                  context: context,
                                                  initialColor: Color(
                                                    int.parse(
                                                      brandKit!['colors']
                                                              ?['primary']
                                                          .replaceFirst(
                                                        '#',
                                                        '0xFF',
                                                      ),
                                                    ),
                                                  ),
                                                  onColorSelected:
                                                      (selectedColor) async {
                                                    final hex =
                                                        '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                    await Supabase
                                                        .instance.client
                                                        .schema('brand_kit')
                                                        .from('brand_kits')
                                                        .update({
                                                      'colors': {
                                                        ...?brandKit!['colors'],
                                                        'primary': hex,
                                                      },
                                                    }).eq(
                                                      'id',
                                                      brandKit!['id'],
                                                    );
                                                    if (context.mounted) {
                                                      mySnackBar(
                                                        context,
                                                        'PRIMARY Color Updated!',
                                                      );
                                                    }
                                                    setState(() {
                                                      brandKit!['colors']
                                                          ['primary'] = hex;
                                                    });
                                                  },
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 12),
                                            ColorDot(
                                              color: brandKit!['colors']
                                                  ?['secondary'],
                                              label: 'Secondary',
                                              onTap: () async {
                                                await pickColor(
                                                  context: context,
                                                  initialColor: Color(
                                                    int.parse(
                                                      brandKit!['colors']
                                                              ?['secondary']
                                                          .replaceFirst(
                                                        '#',
                                                        '0xFF',
                                                      ),
                                                    ),
                                                  ),
                                                  onColorSelected:
                                                      (selectedColor) async {
                                                    final hex =
                                                        '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                    await Supabase
                                                        .instance.client
                                                        .schema('brand_kit')
                                                        .from('brand_kits')
                                                        .update({
                                                      'colors': {
                                                        ...?brandKit!['colors'],
                                                        'secondary': hex,
                                                      },
                                                    }).eq(
                                                      'id',
                                                      brandKit!['id'],
                                                    );
                                                    if (context.mounted) {
                                                      mySnackBar(
                                                        context,
                                                        'SECONDARY Color Updated!',
                                                      );
                                                    }
                                                    setState(() {
                                                      brandKit!['colors']
                                                          ['secondary'] = hex;
                                                    });
                                                  },
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 12),
                                            ColorDot(
                                              color: brandKit!['colors']
                                                  ?['accent'],
                                              label: 'Accent',
                                              onTap: () async {
                                                await pickColor(
                                                  context: context,
                                                  initialColor: Color(
                                                    int.parse(
                                                      brandKit!['colors']
                                                              ?['accent']
                                                          .replaceFirst(
                                                        '#',
                                                        '0xFF',
                                                      ),
                                                    ),
                                                  ),
                                                  onColorSelected:
                                                      (selectedColor) async {
                                                    final hex =
                                                        '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                    await Supabase
                                                        .instance.client
                                                        .schema('brand_kit')
                                                        .from('brand_kits')
                                                        .update({
                                                      'colors': {
                                                        ...?brandKit!['colors'],
                                                        'accent': hex,
                                                      },
                                                    }).eq(
                                                      'id',
                                                      brandKit!['id'],
                                                    );
                                                    if (context.mounted) {
                                                      mySnackBar(
                                                        context,
                                                        'ACCENT Color Updated!',
                                                      );
                                                    }
                                                    setState(() {
                                                      brandKit!['colors']
                                                          ['accent'] = hex;
                                                    });
                                                  },
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 12),
                                            ColorDot(
                                              color: brandKit!['colors']
                                                  ?['background'],
                                              label: 'Background',
                                              onTap: () async {
                                                await pickColor(
                                                  context: context,
                                                  initialColor: Color(
                                                    int.parse(
                                                      brandKit!['colors']
                                                              ?['background']
                                                          .replaceFirst(
                                                        '#',
                                                        '0xFF',
                                                      ),
                                                    ),
                                                  ),
                                                  onColorSelected:
                                                      (selectedColor) async {
                                                    final hex =
                                                        '#${selectedColor.value.toRadixString(16).substring(2)}';
                                                    await Supabase
                                                        .instance.client
                                                        .schema('brand_kit')
                                                        .from('brand_kits')
                                                        .update({
                                                      'colors': {
                                                        ...?brandKit!['colors'],
                                                        'background': hex,
                                                      },
                                                    }).eq(
                                                      'id',
                                                      brandKit!['id'],
                                                    );
                                                    if (context.mounted) {
                                                      mySnackBar(
                                                        context,
                                                        'BACKGROUND Color Updated!',
                                                      );
                                                    }
                                                    setState(() {
                                                      brandKit!['colors']
                                                          ['background'] = hex;
                                                    });
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    height: 205,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: lightColor.withOpacity(0.125),
                                      border: Border.all(
                                        width: 1,
                                        color: lightColor.withOpacity(0.25),
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: backgrounds == null
                                        ? skeletonBox(
                                            w: double.infinity,
                                            h: 100,
                                            r: 16,
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceAround,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  Text(
                                                    'Backgrounds',
                                                    style: TextStyle(
                                                      color: darkColor,
                                                      fontSize: width * 0.0125,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  backgrounds!.isEmpty
                                                      ? const Text(
                                                          'No Backgrounds added',
                                                        )
                                                      : SizedBox(
                                                          width: width * 0.75,
                                                          height: 100,
                                                          child: Scrollbar(
                                                            controller:
                                                                backgroundScrollController,
                                                            thumbVisibility:
                                                                backgrounds!
                                                                        .length >
                                                                    6,
                                                            child: ListView
                                                                .builder(
                                                              controller:
                                                                  backgroundScrollController,
                                                              physics:
                                                                  const ClampingScrollPhysics(),
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              itemCount:
                                                                  backgrounds!
                                                                      .length,
                                                              itemBuilder:
                                                                  (context,
                                                                      index) {
                                                                final bg =
                                                                    backgrounds![
                                                                        index];
                                                                final url =
                                                                    bg['url']!;
                                                                final pathToDelete =
                                                                    bg['path']!;

                                                                return SizedBox(
                                                                  width: width *
                                                                      0.125,
                                                                  child:
                                                                      AspectRatio(
                                                                    aspectRatio:
                                                                        1,
                                                                    child:
                                                                        Stack(
                                                                      children: [
                                                                        Container(
                                                                          decoration:
                                                                              BoxDecoration(
                                                                            border:
                                                                                Border.all(
                                                                              width: 0.5,
                                                                              color: darkColor.withOpacity(
                                                                                0.5,
                                                                              ),
                                                                            ),
                                                                            borderRadius:
                                                                                BorderRadius.circular(
                                                                              16,
                                                                            ),
                                                                          ),
                                                                          margin:
                                                                              EdgeInsets.all(
                                                                            width *
                                                                                0.00125,
                                                                          ),
                                                                          child:
                                                                              ClipRRect(
                                                                            borderRadius:
                                                                                BorderRadius.circular(
                                                                              16,
                                                                            ),
                                                                            child:
                                                                                Image.network(
                                                                              url,
                                                                              fit: BoxFit.cover,
                                                                              width: double.infinity,
                                                                              height: double.infinity,
                                                                              loadingBuilder: (
                                                                                context,
                                                                                child,
                                                                                progress,
                                                                              ) {
                                                                                if (progress == null) return child;
                                                                                return Shimmer.fromColors(
                                                                                  baseColor: lightColor.withOpacity(
                                                                                    0.1,
                                                                                  ),
                                                                                  highlightColor: lightColor.withOpacity(
                                                                                    0.25,
                                                                                  ),
                                                                                  child: Container(
                                                                                    decoration: BoxDecoration(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        16,
                                                                                      ),
                                                                                      color: lightColor,
                                                                                    ),
                                                                                  ),
                                                                                );
                                                                              },
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
                                                                        Positioned(
                                                                          top:
                                                                              4,
                                                                          right:
                                                                              4,
                                                                          child:
                                                                              Tooltip(
                                                                            message:
                                                                                'Remove',
                                                                            child:
                                                                                InkWell(
                                                                              onTap: () async {
                                                                                await removeBackground(
                                                                                  context,
                                                                                  pathToDelete,
                                                                                );
                                                                              },
                                                                              borderRadius: BorderRadius.circular(
                                                                                20,
                                                                              ),
                                                                              child: Container(
                                                                                padding: const EdgeInsets.all(
                                                                                  4,
                                                                                ),
                                                                                decoration: BoxDecoration(
                                                                                  color: darkColor,
                                                                                  shape: BoxShape.circle,
                                                                                ),
                                                                                child: const Icon(
                                                                                  Icons.close,
                                                                                  size: 16,
                                                                                  color: Colors.white,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                ],
                                              ),
                                              Tooltip(
                                                message: 'Add Background',
                                                mouseCursor:
                                                    SystemMouseCursors.click,
                                                child: GestureDetector(
                                                  onTap: () async {
                                                    if (!isAddingBackground) {
                                                      await pickAndAddBackground(
                                                        context,
                                                      );
                                                    }
                                                  },
                                                  child: Container(
                                                    width: width * 0.06125,
                                                    height: width * 0.06125,
                                                    decoration: BoxDecoration(
                                                      color: lightColor
                                                          .withOpacity(0.125),
                                                      border: Border.all(
                                                        width: 2,
                                                        color: darkColor
                                                            .withOpacity(0.5),
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        16,
                                                      ),
                                                    ),
                                                    child: isAddingBackground
                                                        ? skeletonBox()
                                                        : Icon(
                                                            Icons.add_rounded,
                                                            color: darkColor,
                                                            size: width * 0.05,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ),
                        const SizedBox(height: 24),
                        connectedPlatforms == null
                            ? const SizedBox.shrink()
                            : Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connected Accounts',
                                    style: TextStyle(
                                      color: darkColor,
                                      fontSize: width * 0.0125,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  connectedPlatforms!.isEmpty
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: Text(
                                            'No Platforms Connected',
                                            style: TextStyle(
                                              color: darkColor.withOpacity(
                                                0.75,
                                              ),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        )
                                      : LayoutBuilder(
                                          builder: (context, constraints) {
                                            final count =
                                                connectedPlatforms!.length;
                                            final totalSpacing =
                                                (count - 1) * 2;
                                            final chipWidth =
                                                (constraints.maxWidth -
                                                        totalSpacing) /
                                                    (count + 0.02);

                                            return Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children:
                                                  connectedPlatforms!.map((
                                                item,
                                              ) {
                                                return MouseRegion(
                                                  cursor:
                                                      SystemMouseCursors.click,
                                                  child: GestureDetector(
                                                    onTap: () {
                                                      context.push(
                                                        '/platform/${item.toString().toLowerCase()}',
                                                      );
                                                    },
                                                    child: Container(
                                                      width: chipWidth,
                                                      decoration: BoxDecoration(
                                                        color: darkColor,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          100,
                                                        ),
                                                        border: Border.all(
                                                          color: darkColor,
                                                          width: 0.5,
                                                        ),
                                                      ),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 12,
                                                        vertical: 12,
                                                      ),
                                                      margin: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 2,
                                                        vertical: 12,
                                                      ),
                                                      child: Center(
                                                        child: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            item.toString().toLowerCase() ==
                                                                    'linkedin'
                                                                ? 'LinkedIn'
                                                                : item.toString().toLowerCase() ==
                                                                        'facebook'
                                                                    ? 'Facebook'
                                                                    : item.toString().toLowerCase() ==
                                                                            'instagram'
                                                                        ? 'Instagram'
                                                                        : item.toString().toLowerCase() ==
                                                                                'youtube'
                                                                            ? 'YouTube'
                                                                            : item.toString().toLowerCase() == 'twitter'
                                                                                ? 'Twitter'
                                                                                : 'Unknown Platform',
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            );
                                          },
                                        ),
                                  if (canConnectPlatforms != null &&
                                      canConnectPlatforms!.isNotEmpty) ...[
                                    Text(
                                      'Can Connect',
                                      style: TextStyle(
                                        color: darkColor,
                                        fontSize: width * 0.0125,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final count =
                                            canConnectPlatforms!.length;
                                        final totalSpacing = (count - 1) * 2;
                                        final chipWidth =
                                            (constraints.maxWidth -
                                                    totalSpacing) /
                                                (count + 0.02);

                                        return Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: canConnectPlatforms!.map((
                                            item,
                                          ) {
                                            return MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: GestureDetector(
                                                onTap: () {
                                                  if (item
                                                          .toString()
                                                          .toLowerCase() ==
                                                      'linkedin') {
                                                    context.push(
                                                      '/connect/linkedin',
                                                    );
                                                  } else {
                                                    context.push(
                                                      '/connect/meta',
                                                    );
                                                  }
                                                },
                                                child: Container(
                                                  width: chipWidth,
                                                  decoration: BoxDecoration(
                                                    color: darkColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      100,
                                                    ),
                                                    border: Border.all(
                                                      color: darkColor,
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 12,
                                                    vertical: 12,
                                                  ),
                                                  margin: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 2,
                                                    vertical: 12,
                                                  ),
                                                  child: Center(
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        item
                                                                    .toString()
                                                                    .toLowerCase() ==
                                                                'linkedin'
                                                            ? 'LinkedIn'
                                                            : item
                                                                        .toString()
                                                                        .toLowerCase() ==
                                                                    'facebook'
                                                                ? 'Facebook'
                                                                : item.toString().toLowerCase() ==
                                                                        'instagram'
                                                                    ? 'Instagram'
                                                                    : item.toString().toLowerCase() ==
                                                                            'youtube'
                                                                        ? 'YouTube'
                                                                        : item.toString().toLowerCase() ==
                                                                                'twitter'
                                                                            ? 'Twitter'
                                                                            : 'Unknown Platform',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
