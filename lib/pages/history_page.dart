import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/widgets/my_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  //––– filter state ––––––––––––––––––––––––––––––––––––––––––––––
  final List<String> filters = const ['All', 'Scheduled', 'Posted', 'Failed'];
  final List<String> platforms = const [
    'All',
    'LinkedIn',
    'Facebook',
    'Instagram',
  ];
  final List<String> postTypes = const ['All', 'Text', 'Insight Cards'];

  String selectedFilter = 'All';
  String selectedPlatform = 'All';
  String selectedPostType = 'All';

  //––– pagination state ––––––––––––––––––––––––––––––––––––––––––
  static const int _pageSize = 20;
  final List<Map<String, dynamic>> _allPosts = [];

  bool isFetchingInitial = true;
  bool isFetchingMore = false;
  bool hasMoreRows = true;

  final ScrollController _scroll = ScrollController();

  // OPT: throttle to avoid multiple loadMore calls within a tight window.
  DateTime _lastLoadMoreAt = DateTime.fromMillisecondsSinceEpoch(0); // OPT

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _fetchPosts(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore); // OPT: cleanliness
    _scroll.dispose();
    super.dispose();
  }

  //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  /* Retry helper (lightweight) */
  Future<T> _withRetry<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 200),
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

  //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  /* DB PULL */
  Future<void> _fetchPosts({required bool reset}) async {
    if (reset) {
      if (mounted) {
        setState(() {
          isFetchingInitial = true;
          hasMoreRows = true;
          _allPosts.clear();
        });
      }
    } else {
      if (mounted) setState(() => isFetchingMore = true);
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    final userId = user.id;
    final from = _allPosts.length;
    final to = from + _pageSize - 1;

    try {
      // OPT: Parallelise both reads to cut latency.
      final results = await Future.wait([
        _withRetry(
          () => supabase
              .from('scheduled_posts')
              .select()
              .eq('user_id', userId)
              .order('scheduled_at', ascending: false)
              .range(from, to),
        ),
        _withRetry(
          () => supabase
              .from('scheduled_insight_card_posts')
              .select()
              .eq('user_id', userId)
              .order('scheduled_at', ascending: false)
              .range(from, to),
        ),
      ]);

      final textRows = results[0];
      final cardRows = results[1];

      final newText = List<Map<String, dynamic>>.from(textRows);
      final newCards = List<Map<String, dynamic>>.from(cardRows);

      for (final r in newText) {
        r['type'] = 'text';
        _attachParsedTime(r); // OPT: precompute parsed time and header key
      }
      for (final r in newCards) {
        r['type'] = 'insight_card';
        _attachParsedTime(r);
      }

      final merged = [...newText, ...newCards]..sort(
          (a, b) => (b['parsedTime'] as DateTime).compareTo(
            a['parsedTime'] as DateTime,
          ),
        );

      if (mounted) {
        setState(() {
          _allPosts.addAll(merged);
          isFetchingInitial = false;
          // NOTE: Preserve existing behavior exactly.
          hasMoreRows = merged.length == _pageSize; // OPT: unchanged by design
        });
      }
    } catch (e) {
      // Keep UX: show something rather than spinner forever
      if (mounted) {
        setState(() {
          isFetchingInitial = false;
        });
      }
    } finally {
      if (mounted) setState(() => isFetchingMore = false);
    }
  }

  // OPT: Also store a precomputed header key to reduce formatting in build.
  void _attachParsedTime(Map<String, dynamic> row) {
    final raw = row['scheduled_at'] ?? row['posted_at'];
    final parsed =
        DateTime.tryParse(raw?.toString() ?? '')?.toLocal() ?? DateTime.now();
    row['parsedTime'] = parsed; // same field used in sort
    row['dateHeaderKey'] = _dateHeaderKey(parsed); // OPT: cache header bucket
  }

  //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  /* INFINITE SCROLL */
  void _maybeLoadMore() {
    if (!hasMoreRows || isFetchingMore) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      // OPT: debounce to prevent storm of calls at the edge
      final now = DateTime.now();
      if (now.difference(_lastLoadMoreAt).inMilliseconds < 200) return; // OPT
      _lastLoadMoreAt = now; // OPT
      _fetchPosts(reset: false);
    }
  }

  //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  /* FILTERS */
  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> list) {
    return list.where((p) {
      // platform
      if (selectedPlatform != 'All' &&
          (p['platform'] as String?)?.toLowerCase() !=
              selectedPlatform.toLowerCase()) {
        return false;
      }

      // type
      if (selectedPostType == 'Text' && p['type'] != 'text') return false;
      if (selectedPostType == 'Insight Cards' && p['type'] != 'insight_card') {
        return false;
      }

      // status
      final status = (p['status'] ?? '').toString();
      if (selectedFilter == 'Scheduled' && status != 'scheduled') return false;
      if (selectedFilter == 'Posted' && status != 'success') return false;
      if (selectedFilter == 'Failed' && status != 'failed') return false;

      return true;
    }).toList();
  }

  //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  /* DATE HEADER HELPERS */
  String _dateHeaderKey(DateTime dt) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(dt, now)) return 'Today';
    if (DateUtils.isSameDay(dt, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return DateFormat('dd MMM yyyy').format(dt);
  }

  bool shouldShowHeader(int idx, List<Map<String, dynamic>> list) {
    if (idx == 0) return true;
    return (list[idx]['dateHeaderKey'] as String) !=
        (list[idx - 1]['dateHeaderKey'] as String);
  }

  //––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
  /* UI */
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final visiblePosts = _applyFilters(_allPosts);

    return Scaffold(
      backgroundColor: backgroundColor,
      // OPT: Use a single CustomScrollView (no nested scroll/shrinkWrap)
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Text(
                  'Post later deleted by you will not be reflected here',
                  style: TextStyle(
                    color: darkColor.withOpacity(.25),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 16),

                // ––– FILTER BAR –––
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.012),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Wrap(
                        spacing: width * 0.012,
                        runSpacing: 8,
                        children: [
                          MyDropDown(
                            width: width * 0.2,
                            items: platforms,
                            value: selectedPlatform,
                            onChanged: (v) =>
                                setState(() => selectedPlatform = v!),
                          ),
                          MyDropDown(
                            width: width * 0.2,
                            items: postTypes,
                            value: selectedPostType,
                            onChanged: (v) =>
                                setState(() => selectedPostType = v!),
                          ),
                          MyDropDown(
                            width: width * 0.2,
                            items: filters,
                            value: selectedFilter,
                            onChanged: (v) =>
                                setState(() => selectedFilter = v!),
                          ),
                        ],
                      ),
                      if (selectedPlatform != 'All' ||
                          selectedPostType != 'All' ||
                          selectedFilter != 'All')
                        IconButton(
                          tooltip: 'Reset Filters',
                          icon: const Icon(Icons.restart_alt_outlined),
                          iconSize: 24,
                          color: darkColor,
                          onPressed: () => setState(() {
                            selectedPlatform = 'All';
                            selectedPostType = 'All';
                            selectedFilter = 'All';
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // ––– SKELETON –––
          if (isFetchingInitial)
            SliverList.separated(
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 0),
              itemBuilder: (_, __) {
                return Shimmer.fromColors(
                  baseColor: lightColor,
                  highlightColor: darkColor,
                  period: const Duration(milliseconds: 1500),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.all(16),
                    height: 120,
                    decoration: BoxDecoration(
                      color: lightColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                );
              },
            )
          else if (visiblePosts.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'You haven’t posted anything yet.\nSchedule your first post to see it here!',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: visiblePosts.length + (hasMoreRows ? 1 : 0),
              itemBuilder: (_, idx) {
                if (idx >= visiblePosts.length) {
                  final template =
                      visiblePosts.isNotEmpty ? visiblePosts.last : null;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    child: AutoSkeleton(
                      enabled: true,
                      baseColor: lightColor,
                      effectColor: darkColor,
                      borderRadius: 24,
                      child: template != null
                          ? PostCard(post: template)
                          : Container(height: 180),
                    ),
                  );
                }

                final post = visiblePosts[idx];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shouldShowHeader(idx, visiblePosts))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          post['dateHeaderKey'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: darkColor,
                          ),
                        ),
                      ),
                    PostCard(post: post),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

// OPT: Extracted widget to reduce rebuild cost and respect "no inline widget functions".
class PostCard extends StatelessWidget {
  const PostCard({super.key, required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final DateTime timestamp = post['parsedTime'] as DateTime;
    final String caption = post['caption']?.toString() ?? '[No caption]';
    final String platform = (post['platform'] ?? '').toString().toLowerCase();
    final String status = (post['status'] ?? '').toString().toLowerCase();
    final dynamic likes = post['likes'];
    final dynamic reach = post['reach'];

    final Color statusColor = ({
          'scheduled': darkColor,
          'success': successColor,
          'failed': errorColor,
        }[status]) ??
        grey400;

    IconData platformIcon;
    String platformName;
    switch (platform) {
      case 'linkedin':
        platformIcon = Icons.business_center;
        platformName = 'LinkedIn';
        break;
      case 'facebook':
        platformIcon = Icons.facebook;
        platformName = 'Facebook';
        break;
      case 'instagram':
        platformIcon = Icons.camera_alt;
        platformName = 'Instagram';
        break;
      case 'youtube':
        platformIcon = Icons.ondemand_video;
        platformName = 'YouTube';
        break;
      case 'twitter':
        platformIcon = Icons.alternate_email;
        platformName = 'Twitter';
        break;
      default:
        platformIcon = Icons.public;
        platformName = 'Unknown';
    }

    return Semantics(
      label:
          'Post on $platformName, status: $status, posted at ${DateFormat.yMMMd().add_jm().format(timestamp)}. Tap to view details',
      child: InkWell(
        onTap: (status == 'scheduled' || status == 'failed')
            ? null
            : () {
                context.push(
                  '/home/history/post/${post['type']}/${post['id']}',
                  extra: post,
                );
              },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: whiteColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: grey200),
            boxShadow: const [
              BoxShadow(
                color: shadowColor,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Timestamp + Status ───
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat.MMMd().add_jm().format(timestamp),
                    style: const TextStyle(
                      fontSize: 12,
                      color: grey500,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Tooltip(
                    message: 'Status: ${status.toUpperCase()}',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── Caption ───
              Text(
                caption.length > 200
                    ? '${caption.substring(0, 200)}…'
                    : caption,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  height: 1.5,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),

              // ─── Platform + Stats ───
              Row(
                children: [
                  // Platform chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: lightColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Tooltip(
                          message: platformName,
                          child: Icon(platformIcon, size: 14, color: darkColor),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          platformName,
                          style: TextStyle(
                            fontSize: 12,
                            color: darkColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (status != 'scheduled') ...[
                    if (likes != null) ...[
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.thumb_up_alt_outlined,
                        size: 14,
                        color: grey600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likes',
                        style: const TextStyle(
                          fontSize: 12,
                          color: grey700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (reach != null) ...[
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.remove_red_eye_outlined,
                        size: 14,
                        color: grey600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$reach',
                        style: const TextStyle(
                          fontSize: 12,
                          color: grey700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
