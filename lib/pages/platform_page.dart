import 'dart:convert';

import 'package:blob/utils/my_snack_bar.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/edit_with_label_container.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:http/http.dart' as http;

class PlatformPage extends StatefulWidget {
  const PlatformPage({super.key, required this.name});

  final String name;

  @override
  State<PlatformPage> createState() => _PlatformPageState();
}

class _PlatformPageState extends State<PlatformPage> {
  String? accountId;
  String? accountFullName;
  String? accountEmail;
  String? accountImageUrl;
  String? accountPublicProfileUrl;
  DateTime? accountConnectedAt;
  int? accountNeedsReconnect;
  Map<String, dynamic> extraData = {};

  bool isLoading = true;
  bool isDisconnecting = false;

  static const String defaultAvatarUrl =
      'https://media.istockphoto.com/id/1223671392/vector/default-profile-picture-avatar-photo-placeholder-vector-illustration.jpg?s=612x612'; // OPT: const

  @override
  void initState() {
    super.initState();
    getAccountInfo();
  }

  // OPT: Lightweight retry with backoff + jitter for transient failures (5xx/429/timeout)
  Future<T> withRetry<T>(
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
        attempt += 1;
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

  Future<http.Response> httpGetWithRetry(
    Uri uri, {
    Map<String, String>? headers,
  }) {
    // OPT: 10s timeout + retry wrapper to avoid long UI stalls
    return withRetry<http.Response>(
      () => http.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
          ),
    );
  }

  Future<void> getAccountInfo() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        context.go('/login');
        return;
      }

      if (widget.name == 'linkedin') {
        final row = await withRetry<Map<String, dynamic>?>(
          () => supabase
              .from('social_accounts')
              .select('access_token, connected_at')
              .eq('user_id', userId)
              .eq('platform', 'linkedin')
              .eq('is_disconnected', false)
              .maybeSingle(),
        );

        if (row == null) {
          if (mounted) mySnackBar(context, "LinkedIn account not found");
          return;
        }

        final String accessToken = row['access_token'];
        final DateTime? connectedAt = DateTime.tryParse(row['connected_at']);
        final expiry = connectedAt?.add(const Duration(days: 60));
        final needsReconnectIn = expiry?.difference(DateTime.now()).inDays;

        final response = await withRetry(
          () => supabase.functions.invoke(
            'get-user-linkedin-info',
            body: {'accessToken': accessToken},
          ),
        );

        if (response.status != 200) {
          if (mounted) mySnackBar(context, 'Failed to fetch LinkedIn info');
          return;
        }

        final data = Map<String, dynamic>.from(response.data as Map);
        final sub = data['sub'];
        final name = data['name'];
        final email = data['email'];
        final picture = data['picture'];
        data.removeWhere(
          (k, v) => ['sub', 'name', 'email', 'picture'].contains(k),
        );

        if (mounted) {
          setState(() {
            accountId = sub;
            accountFullName = name;
            accountEmail = email;
            accountImageUrl = picture;
            accountConnectedAt = connectedAt?.toLocal();
            accountNeedsReconnect = needsReconnectIn;
            extraData = data;
          });
        }
        return;
      }

      if (widget.name == 'facebook') {
        final row = await withRetry<Map<String, dynamic>?>(
          () => supabase
              .from('social_accounts')
              .select('access_token, connected_at, page_id, page_name')
              .eq('user_id', userId)
              .eq('platform', 'facebook')
              .eq('is_disconnected', false)
              .maybeSingle(),
        );

        if (row == null) {
          if (mounted) mySnackBar(context, "Facebook account not found");
          return;
        }

        final String accessToken = row['access_token'];
        final DateTime? connectedAt = DateTime.tryParse(row['connected_at']);
        final expireAt = connectedAt?.add(const Duration(days: 60));
        final int? needsReconnectIn =
            expireAt?.difference(DateTime.now()).inDays;
        final String pageId = row['page_id'].toString();

        final uri = Uri.https('graph.facebook.com', '/v23.0/$pageId', {
          'fields': 'id,name,picture,link',
          'access_token': accessToken,
        });

        final fbResp = await httpGetWithRetry(uri);
        if (fbResp.statusCode != 200) {
          if (mounted) mySnackBar(context, 'Failed to fetch Facebook info');
          return;
        }

        final Map<String, dynamic> data = jsonDecode(fbResp.body);
        final String? id = data['id'] as String?;
        final String? name = data['name'] as String?;
        final String? pictureUrl = data['picture']?['data']?['url'] as String?;
        final String? linkUrl = data['link'] as String?;

        data.removeWhere(
          (k, v) => ['id', 'name', 'picture', 'link'].contains(k),
        );

        if (mounted) {
          setState(() {
            accountId = id;
            accountFullName = name ?? row['page_name']?.toString();
            accountImageUrl = pictureUrl;
            accountPublicProfileUrl =
                linkUrl ?? 'https://www.facebook.com/$pageId';
            accountConnectedAt = connectedAt?.toLocal();
            accountNeedsReconnect = needsReconnectIn;
            extraData = data;
          });
        }
        return;
      }

      if (widget.name == 'instagram') {
        final row = await withRetry<Map<String, dynamic>?>(
          () => supabase
              .from('social_accounts')
              .select('access_token, connected_at, page_id, ig_user_id')
              .eq('user_id', userId)
              .eq('platform', 'instagram')
              .eq('is_disconnected', false)
              .maybeSingle(),
        );

        if (row == null) {
          if (mounted) mySnackBar(context, "Instagram account not found");
          return;
        }

        final String pageToken = row['access_token'];
        final DateTime? connectedAt = DateTime.tryParse(row['connected_at']);
        final expireAt = connectedAt?.add(const Duration(days: 60));
        final needsReconnectIn = expireAt?.difference(DateTime.now()).inDays;
        final String igId = row['ig_user_id'];

        final igUri = Uri.https('graph.facebook.com', '/v23.0/$igId', {
          'fields':
              'id,username,name,profile_picture_url,followers_count,follows_count',
          'access_token': pageToken,
        });

        final igResp = await httpGetWithRetry(igUri);
        if (igResp.statusCode != 200) {
          if (mounted) mySnackBar(context, 'Failed to fetch Instagram info');
          return;
        }
        final Map<String, dynamic> data = Map<String, dynamic>.from(
          jsonDecode(igResp.body),
        );

        final String? id = data['id'] as String?;
        final String? username = data['username'] as String?;
        final String? name = data['name'] as String?;
        final String? pictureUrl = data['profile_picture_url'] as String?;

        data.removeWhere(
          (k, v) =>
              ['id', 'username', 'name', 'profile_picture_url'].contains(k),
        );

        if (mounted) {
          setState(() {
            accountId = id;
            accountFullName = name ?? username;
            accountImageUrl = pictureUrl;
            accountPublicProfileUrl = 'https://www.instagram.com/$username';
            accountConnectedAt = connectedAt?.toLocal();
            accountNeedsReconnect = needsReconnectIn;
            extraData = data;
          });
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        mySnackBar(context, 'Some error occurred');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> disconnectAccount(BuildContext context) async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      context.go('/login');
      return;
    }

    try {
      await withRetry(
        () => supabase
            .from('social_accounts')
            .update({'is_disconnected': true})
            .eq('user_id', userId)
            .eq('platform', widget.name)
            .eq('is_disconnected', false),
      );

      setState(() {
        isDisconnecting = false;
      });

      final revokeUrl = widget.name == 'linkedin'
          ? 'https://www.linkedin.com/psettings/permitted-services'
          : 'https://www.facebook.com/settings?tab=business_tools';
      final platformLabel = widget.name == 'linkedin'
          ? 'LinkedIn'
          : widget.name == 'facebook'
              ? 'Facebook'
              : 'Instagram';

      await showDialog(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (context) => AlertDialog(
          title: Text("$platformLabel Disconnected"),
          content: SizedBox(
            height: 140,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "We've disconnected your $platformLabel account from our side.\n\n"
                  "To fully revoke access, please visit:\n$revokeUrl",
                ),
                const SizedBox(height: 8),
                MyTextButton(
                  onPressed: () async {
                    if (await canLaunchUrlString(revokeUrl)) {
                      await launchUrlString(
                        revokeUrl,
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      if (context.mounted) {
                        mySnackBar(context, 'Could not launch URL');
                      }
                    }
                  },
                  child: const Text('Visit Now'),
                ),
              ],
            ),
          ),
          actions: [
            MyTextButton(
              onPressed: () => context.pop(),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        mySnackBar(context, 'Failed to disconnect, please try again');
      }
      setState(() {
        isDisconnecting = false;
      });
    }
  }

  String toTitleCase(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? ''
              : w[0].toUpperCase() + w.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final title = {
          'linkedin': 'LinkedIn',
          'facebook': 'Facebook',
          'instagram': 'Instagram',
        }[widget.name] ??
        'Connected Account';

    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: true),
      body: AutoSkeleton(
        enabled: isLoading,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width > 768;
            final entries = extraData.entries.toList();

            return SingleChildScrollView(
              padding: EdgeInsets.all(isWide ? 32 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Semantics(
                    label:
                        'Connected account avatar for ${accountFullName ?? 'user'}',
                    child: CircleAvatar(
                      radius: 48,
                      backgroundImage: NetworkImage(
                        accountImageUrl ?? defaultAvatarUrl,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (accountFullName != null)
                    EditWithLabelContainer(
                      width: width,
                      label: widget.name == 'linkedin'
                          ? 'Full Name'
                          : widget.name == 'facebook'
                              ? 'Page Name'
                              : 'Name',
                      description: widget.name == 'linkedin'
                          ? 'Your full name from LinkedIn'
                          : widget.name == 'facebook'
                              ? 'Your connected Facebook Page name'
                              : 'The name associated with this account',
                      child: Text(accountFullName!),
                    ),
                  if (widget.name == 'linkedin' && accountEmail != null)
                    const SizedBox(height: 16),
                  if (widget.name == 'linkedin' && accountEmail != null)
                    EditWithLabelContainer(
                      width: width,
                      label: 'Email',
                      description:
                          'The email address fetched from your LinkedIn profile',
                      child: Text(accountEmail!),
                    ),
                  if (accountId != null) const SizedBox(height: 16),
                  if (accountId != null)
                    EditWithLabelContainer(
                      width: width,
                      label: 'Account ID',
                      description:
                          'The unique identifier of your connected account',
                      child: Text(accountId!),
                    ),
                  if (accountConnectedAt != null) const SizedBox(height: 16),
                  if (accountConnectedAt != null)
                    EditWithLabelContainer(
                      width: width,
                      label: 'Connected At',
                      description:
                          'The date and time you last connected this account',
                      child: Text(
                        DateFormat(
                          'dd MMM yyyy – hh:mm a',
                        ).format(accountConnectedAt!),
                      ),
                    ),
                  if (accountNeedsReconnect != null) const SizedBox(height: 16),
                  if (accountNeedsReconnect != null)
                    EditWithLabelContainer(
                      width: width,
                      label: 'Re-connect In',
                      description:
                          'Days your token will expire in. Reconnect before it does to keep posting',
                      child: Text(
                        '${accountNeedsReconnect!} days',
                        style: TextStyle(
                          color: accountNeedsReconnect! <= 3
                              ? warningColor
                              : textColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (accountNeedsReconnect != null &&
                      accountNeedsReconnect! <= 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AnimatedScale(
                        scale: 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: MyTextButton(
                          onPressed: () {
                            context.go(
                              '/connect/${widget.name == 'linkedin' ? 'linkedin' : 'meta'}',
                            );
                          },
                          icon: const Icon(Icons.link),
                          child: const Text('Reconnect Now'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 32),
                  if (entries.isNotEmpty)
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isWide ? 2 : 1,
                        crossAxisSpacing: 24,
                        mainAxisSpacing: 24,
                        childAspectRatio: 6,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final entry = entries[i];
                        return EditWithLabelContainer(
                          width: width,
                          description:
                              'Additional data retrieved from your connected account',
                          label: toTitleCase(entry.key),
                          child: Text(entry.value?.toString() ?? ''),
                        );
                      },
                    ),
                  const SizedBox(height: 40),
                  MyTextButton(
                    onPressed: isDisconnecting
                        ? () {}
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Confirm Disconnect"),
                                content: const Text(
                                  "Are you sure you want to disconnect this account?\nThis can't be undone.",
                                ),
                                actions: [
                                  MyTextButton(
                                    onPressed: () => context.pop(false),
                                    child: const Text("Cancel"),
                                  ),
                                  MyTextButton(
                                    onPressed: () => context.pop(true),
                                    child: const Text(
                                      "Disconnect",
                                      style: TextStyle(color: errorColor),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              setState(() => isDisconnecting = true);
                              if (context.mounted) {
                                await disconnectAccount(context);
                              }
                            }
                          },
                    icon: isDisconnecting
                        ? null
                        : const Icon(
                            Icons.remove_circle_outline,
                            color: errorColor,
                          ),
                    child: isDisconnecting
                        ? AutoSkeleton(
                            key: const ValueKey('btn-skel'),
                            enabled: true,
                            preserveSize: true, // keep button width/height
                            baseColor: lightColor,
                            effectColor: darkColor,
                            borderRadius: 24,
                            child: const Text(
                              'Disconnect Account',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              isDisconnecting
                                  ? 'Disconnecting…'
                                  : 'Disconnect Account',
                              key: ValueKey(isDisconnecting),
                              style: const TextStyle(
                                color: errorColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
