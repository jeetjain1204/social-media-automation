import 'dart:convert';
import 'package:blob/widgets/auto_skeleton.dart';
import 'package:blob/utils/colors.dart';
import 'package:blob/utils/my_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';

class PostPage extends StatefulWidget {
  const PostPage({super.key, required this.postId, required this.type});

  final String postId;
  final String? type;

  @override
  State<PostPage> createState() => _PostPageState();
}

class _PostPageState extends State<PostPage> {
  Map<String, dynamic>? post;
  bool? isEligibleForStats = false;
  String? organizationUrn;
  bool isLoadingMetrics = true;

  int viewsData = 0;
  int likesData = 0;
  int sharesData = 0;
  int commentsData = 0;
  int totalEngagement = 0;
  int totalUniqueImpressions = 0;
  List<String> xLabels = [];

  // OPT: prevent duplicate fetches (hot reload / route re-entry)
  bool metricsRequested = false; // OPT: follow naming rule (no underscores)
  bool detailsRequested = false; // OPT

  @override
  void initState() {
    super.initState();
    fetchPostDetails();
  }

  // OPT: Lightweight retry with backoff + jitter for transient 5xx/429
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

  Future<void> fetchPostDetails() async {
    if (detailsRequested) return; // OPT: guard multiple calls
    detailsRequested = true; // OPT

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      Map<String, dynamic>? postRes;

      if (widget.type != null && widget.type == 'insight_card') {
        postRes = await withRetry<Map<String, dynamic>>(
          () => client
              .from('scheduled_insight_card_posts')
              .select()
              .eq('user_id', user.id)
              .eq('id', widget.postId)
              .single()
              .timeout(const Duration(seconds: 12)),
        );
      } else {
        postRes = await withRetry<Map<String, dynamic>>(
          () => client
              .from('scheduled_posts')
              .select()
              .eq('user_id', user.id)
              .eq('id', widget.postId)
              .single()
              .timeout(const Duration(seconds: 12)),
        );
      }

      post = postRes;

      // Fetch social account for org eligibility
      final social = await withRetry<Map<String, dynamic>?>(
        () => client
            .from('social_accounts')
            .select()
            .eq('user_id', user.id)
            .eq('platform', 'linkedin')
            .eq('is_disconnected', false)
            .maybeSingle()
            .timeout(const Duration(seconds: 12)),
      );

      final isOrg = (social?['account_type'] ?? '').toLowerCase() == 'org';
      if (isOrg) {
        organizationUrn = (social?['author_urn'] as String?);
        if (mounted) {
          setState(() {
            isEligibleForStats = true;
          });
        }
        await fetchMetrics(); // OPT: single call via guard
      } else {
        if (mounted) {
          setState(() {
            isLoadingMetrics = false;
            isEligibleForStats = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          isLoadingMetrics = false;
        });
      }
    }
  }

  List<String> generateXLabels(String duration, DateTime startDate) {
    final now = DateTime.now();
    final labels = <String>[];
    switch (duration) {
      case 'Day':
        for (int i = 0; i < 12; i++) {
          final time = startDate.add(Duration(hours: i * 2));
          labels.add(DateFormat('ha').format(time));
        }
        break;
      case 'Week':
        for (int i = 0; i < 7; i++) {
          final day = startDate.add(Duration(days: i));
          labels.add(DateFormat('EEE').format(day));
        }
        break;
      case 'Month':
        for (int i = 0; i < 4; i++) {
          final weekStart = startDate.add(Duration(days: i * 7));
          labels.add(DateFormat('MMM d').format(weekStart));
        }
        break;
      case 'Year':
        for (int i = 0; i < 12; i++) {
          final month = DateTime(startDate.year, i + 1);
          labels.add(DateFormat('MMM').format(month));
        }
        break;
      case 'Lifetime':
        labels.add(DateFormat('MMM d').format(startDate));
        labels.add(DateFormat('MMM d').format(now));
        break;
    }
    return labels;
  }

  Future<void> fetchMetrics() async {
    if (metricsRequested) return; // OPT: guard
    metricsRequested = true; // OPT

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    final accessToken = session?.accessToken;

    // Guard: need both org and post URNs
    final postUrn = (post?['post_urn'] as String?);
    final orgUrn = organizationUrn;
    if (postUrn == null || orgUrn == null) {
      if (mounted) setState(() => isLoadingMetrics = false);
      return;
    }

    try {
      if (mounted) setState(() => isLoadingMetrics = true);

      final response = await withRetry(
        () => client.functions.invoke(
          'get-post-analytics',
          body: {
            'orgId': orgUrn.split(':').last,
            'postId': postUrn.split(':').last,
          },
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 12)),
      );

      if (response.status == 200 && response.data != null) {
        final List<dynamic> analytics =
            response.data is String ? jsonDecode(response.data) : response.data;

        // Reset data
        viewsData = 0;
        likesData = 0;
        sharesData = 0;
        commentsData = 0;
        xLabels = [];
        totalEngagement = 0;
        totalUniqueImpressions = 0;

        for (final bucket in analytics) {
          // NOTE: Keep original behavior (values overwritten by the last bucket)
          viewsData = (bucket['views'] ?? 0) as int;
          likesData = (bucket['likes'] ?? 0) as int;
          sharesData = (bucket['shares'] ?? 0) as int;
          commentsData = (bucket['comments'] ?? 0) as int;

          totalEngagement += ((bucket['engagement'] ?? 0) as num).round();
          totalUniqueImpressions +=
              ((bucket['uniqueImpressionsCount'] ?? 0) as num).round();
        }

        if (mounted) setState(() => isLoadingMetrics = false);
      } else {
        if (mounted) setState(() => isLoadingMetrics = false);
        if (mounted) mySnackBar(context, 'Failed to fetch analytics');
      }
    } catch (_) {
      if (mounted) setState(() => isLoadingMetrics = false);
    }
  }

  String toTitleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .toLowerCase()
        .split(' ')
        .map(
          (word) =>
              word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    if (post == null && !isLoadingMetrics) {
      return const Scaffold(body: Center(child: Text('Post not found')));
    } else if (post == null) {
      return const Scaffold(
        backgroundColor: const Color(0xFFFBFBFF),
        body: const _PostDetailsSkeleton(),
      );
    }

    final dynamic captionDyn = post!['caption'] ?? '';
    final String caption =
        captionDyn is String ? captionDyn : captionDyn.toString();

    final dynamic mediaField = widget.type == 'insight_card'
        ? post!['image_url']
        : (post!['media_urls'] is List &&
                (post!['media_urls'] as List).isNotEmpty
            ? (post!['media_urls'] as List).first
            : null);
    final String? imageUrlVal = mediaField?.toString();

    final String platform = (post!['platform'] ?? 'Unknown').toString();
    final String status = (post!['status'] ?? 'unknown').toString();
    final DateTime? timestamp = DateTime.tryParse(
      (post![widget.type == 'insight_card' ? 'scheduled_at' : 'posted_at'] ??
              '')
          .toString(),
    )?.toLocal();

    final Color statusColor = ({
          'success': const Color(0xFF33cc66),
          'failed': const Color(0xFFe74c3c),
          'unknown': Colors.grey,
        }[status]) ??
        Colors.grey;

    final String timeLabel =
        timestamp != null ? DateFormat.MMMd().add_jm().format(timestamp) : '-';

    final Map<String, int> metricsMap = {
      'views': viewsData,
      'likes': likesData,
      'shares': sharesData,
      'comments': commentsData,
    };

    // OPT: precompute text styles to avoid repeated GoogleFonts calls
    final inter600_16 = GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    );
    final inter500 = GoogleFonts.inter(
      fontWeight: FontWeight.w500,
      color: darkColor,
    );
    final inter13Bold = GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: Colors.green[800],
    );
    final interBody = GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.6,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFF),
      // OPT: Single scrollable with slivers (no nested scroll)
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (context.canPop())
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        }
                      },
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Text(timeLabel, style: inter600_16),
                        const SizedBox(width: 12),
                        Chip(
                          label: Text(platform),
                          backgroundColor: lightColor.withOpacity(0.5),
                          labelStyle: inter500,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(status, style: inter13Bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),

          // Image + Caption block
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double width = constraints.maxWidth;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (imageUrlVal != null)
                        Container(
                          width: width * 0.32,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: darkColor.withOpacity(0.2),
                            ),
                          ),
                          child: Semantics(
                            label: 'Post image',
                            image: true,
                            child: _PostImage(
                              imageUrl: imageUrlVal,
                            ), // OPT: extracted widget
                          ),
                        ),
                      if (imageUrlVal != null) const SizedBox(width: 24),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: darkColor.withOpacity(0.2),
                            ),
                          ),
                          child: Text(caption, style: interBody),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),

          // Analytics section (skeleton while loading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: isLoadingMetrics
                  ? const _AnalyticsSkeleton() // OPT: shimmer
                  : _AnalyticsGrid(
                      metricsMap: metricsMap,
                      totalEngagement: totalEngagement,
                      totalUniqueImpressions: totalUniqueImpressions,
                    ),
            ),
          ),

          if (platform == 'linkedin')
            const SliverToBoxAdapter(child: SizedBox(height: 40)),

          if (platform == 'linkedin')
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Center(
                  child: Text(
                    "LinkedIn does not support day-by-day stats,\nbut we’ll add it in future.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.black.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

// OPT: Extracted post image widget
class _PostImage extends StatelessWidget {
  const _PostImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(imageUrl, fit: BoxFit.cover),
      ),
    );
  }
}

// OPT: Extracted analytics grid (no logic change)
class _AnalyticsGrid extends StatelessWidget {
  const _AnalyticsGrid({
    required this.metricsMap,
    required this.totalEngagement,
    required this.totalUniqueImpressions,
  });

  final Map<String, int> metricsMap;
  final int totalEngagement;
  final int totalUniqueImpressions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            _MetricCard(title: 'Views', value: metricsMap['views'].toString()),
            _MetricCard(title: 'Likes', value: metricsMap['likes'].toString()),
            _MetricCard(
              title: 'Shares',
              value: metricsMap['shares'].toString(),
            ),
            _MetricCard(
              title: 'Comments',
              value: metricsMap['comments'].toString(),
            ),
            _MetricCard(
              title: 'Engagement',
              value: totalEngagement.toString(),
              wide: true,
            ),
            _MetricCard(
              title: 'Unique Impressions',
              value: totalUniqueImpressions.toString(),
              wide: true,
            ),
          ],
        );
      },
    );
  }
}

// OPT: Shimmer skeleton while analytics load (keeps layout stable; CLS↓)
class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget card() => Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade100,
          period: const Duration(milliseconds: 1200),
          child: Container(
            height: 96,
            width: MediaQuery.of(context).size.width * 0.31,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        return Wrap(
          spacing: 24,
          runSpacing: 24,
          children: [
            card(),
            card(),
            card(),
            card(),
            Container(height: 96, width: width * 0.64, child: card()),
            Container(height: 96, width: width * 0.64, child: card()),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final bool wide;

  const _MetricCard({
    required this.title,
    required this.value,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Container(
      width: wide ? (width * 0.64) : (width * 0.31),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Colors.black.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value == 'null' || value == '0' || value.isEmpty ? '-' : value,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostDetailsSkeleton extends StatelessWidget {
  const _PostDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return AutoSkeleton(
      enabled: true,
      preserveSize: true,
      clipPadding: const EdgeInsets.symmetric(vertical: 24),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          children: [
            // Back button placeholder
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header bar (time, platform chip, status)
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Image + caption block
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Image card
                    Container(
                      width: width * 0.32,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: darkColor.withOpacity(0.2)),
                      ),
                    ),
                    const SizedBox(width: 24),

                    // Caption card
                    Expanded(
                      child: Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: darkColor.withOpacity(0.2)),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),

            // Analytics cards row (4 blocks)
            Row(
              children: [
                Expanded(child: _metricBlock()),
                const SizedBox(width: 16),
                Expanded(child: _metricBlock()),
                const SizedBox(width: 16),
                Expanded(child: _metricBlock()),
                const SizedBox(width: 16),
                Expanded(child: _metricBlock()),
              ],
            ),

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _metricBlock() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: darkColor.withOpacity(0.2)),
      ),
    );
  }
}
