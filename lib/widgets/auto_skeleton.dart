import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:blob/utils/colors.dart';

class AutoSkeleton extends StatefulWidget {
  const AutoSkeleton({
    super.key,
    required this.enabled,
    required this.child,
    this.baseColor,
    this.effectColor,
    this.borderRadius = 24,
    this.duration = const Duration(milliseconds: 1200),
    this.minBlock = const Size(24, 8),
    this.maxBlocks = 200,
    this.preserveSize = false,
    this.clipPadding = EdgeInsets.zero, // NEW: outer inset for paint
  });

  final bool enabled;
  final Widget child;
  final Color? baseColor;
  final Color? effectColor;
  final double borderRadius;
  final Duration duration;
  final Size minBlock;
  final int maxBlocks;
  final bool preserveSize;
  final EdgeInsets clipPadding;

  @override
  AutoSkeletonState createState() => AutoSkeletonState();
}

class AutoSkeletonState extends State<AutoSkeleton>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey rootKey = GlobalKey(debugLabel: 'auto_skeleton_root');

  late AnimationController controller;
  late Animation<double> slide;

  Path? maskPath;
  Size? lastRootSize;
  Offset? lastOrigin;

  bool collectScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = AnimationController(vsync: this, duration: widget.duration);
    slide = CurvedAnimation(parent: controller, curve: Curves.linear);
    _scheduleCollect();
  }

  @override
  void didUpdateWidget(covariant AutoSkeleton old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) {
      controller.duration = widget.duration;
    }
    _syncTicker();
    _scheduleCollect();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
    _scheduleCollect();
  }

  @override
  void didChangeMetrics() => _scheduleCollect();
  @override
  void didChangeTextScaleFactor() => _scheduleCollect();

  void _syncTicker() {
    if (!mounted) return;
    final tickerOn = TickerMode.of(context);
    final active = widget.enabled && tickerOn;
    if (active && !controller.isAnimating) controller.repeat();
    if (!active && controller.isAnimating) controller.stop();
  }

  void _scheduleCollect() {
    if (collectScheduled) return;
    collectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      collectScheduled = false;
      _collectBlocks();
    });
  }

  void _collectBlocks() {
    final ctx = rootKey.currentContext;
    if (ctx == null) return;
    final renderRoot = ctx.findRenderObject();
    if (renderRoot is! RenderBox) return;

    final originNow = renderRoot.localToGlobal(Offset.zero);
    final sizeNow = renderRoot.size;
    final maxW = sizeNow.width;
    final maxH = sizeNow.height;

    if (maskPath != null &&
        lastRootSize == sizeNow &&
        lastOrigin == originNow) {
      return;
    }

    final path = Path();
    int count = 0;

    void visit(RenderObject node) {
      if (count >= widget.maxBlocks) return;

      bool hasChild = false;
      node.visitChildren((c) {
        hasChild = true;
        visit(c);
      });

      if (node is RenderBox) {
        if (identical(node, renderRoot)) return;

        final size = node.size;

        if (size.width >= maxW * 0.98 || size.height >= maxH * 0.98) return;

        if (node is RenderRepaintBoundary ||
            node is RenderSemanticsAnnotations ||
            node is RenderIgnorePointer ||
            node is RenderPointerListener ||
            node is RenderPhysicalModel ||
            node is RenderClipRRect ||
            node is RenderClipPath) {
          return;
        }

        final isLeaf =
            !hasChild || node is RenderParagraph || node is RenderImage;

        if (isLeaf &&
            size.width >= widget.minBlock.width &&
            size.height >= widget.minBlock.height) {
          final topLeft = node.localToGlobal(Offset.zero);
          final rect = Rect.fromLTWH(
            topLeft.dx - originNow.dx,
            topLeft.dy - originNow.dy,
            size.width,
            size.height,
          );
          path.addRRect(
            RRect.fromRectAndRadius(
              rect,
              Radius.circular(widget.borderRadius),
            ),
          );
          count++;
        }
      }
    }

    renderRoot.visitChildren(visit);

    setState(() {
      maskPath = path;
      lastRootSize = sizeNow;
      lastOrigin = originNow;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? lightColor.withOpacity(0.5);
    final effect = widget.effectColor ?? lightColor;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.preserveSize
            ? Opacity(
                opacity: widget.enabled ? 0.0 : 1.0,
                child: KeyedSubtree(key: rootKey, child: widget.child),
              )
            : Offstage(
                offstage: widget.enabled,
                child: KeyedSubtree(key: rootKey, child: widget.child),
              ),
        if (widget.enabled)
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: slide,
                builder: (context, _) => CustomPaint(
                  painter: _SkeletonPainter(
                    path: maskPath,
                    base: base,
                    effect: effect,
                    slide: (slide.value * 2.0) - 1.0,
                    clipPadding: widget.clipPadding,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SkeletonPainter extends CustomPainter {
  const _SkeletonPainter({
    required this.path,
    required this.base,
    required this.effect,
    required this.slide,
    required this.clipPadding,
  });

  final Path? path;
  final Color base;
  final Color effect;
  final double slide;
  final EdgeInsets clipPadding;

  @override
  void paint(Canvas canvas, Size size) {
    final p = path;
    if (p == null || p.computeMetrics().isEmpty) return;

    final rect = Rect.fromLTWH(
      clipPadding.left,
      clipPadding.top,
      size.width - clipPadding.horizontal,
      size.height - clipPadding.vertical,
    );
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(0));

    canvas.save();
    canvas.clipRRect(outer);

    canvas.drawPath(p, Paint()..color = base);

    final sweepWidth = size.width * 0.35;
    final x = ((slide + 1) * 0.5) * (size.width + sweepWidth) - sweepWidth;
    final shimmerRect = Rect.fromLTWH(x, rect.top, sweepWidth, rect.height);
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.transparent,
        effect.withOpacity(0.30),
        effect.withOpacity(0.55),
        effect.withOpacity(0.30),
        Colors.transparent,
      ],
      stops: [0.0, 0.25, 0.50, 0.75, 1.0],
    ).createShader(shimmerRect);

    canvas.save();
    canvas.clipPath(p);
    canvas.drawRect(shimmerRect, Paint()..shader = shader);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SkeletonPainter old) {
    return old.path != path ||
        old.base != base ||
        old.effect != effect ||
        old.slide != slide ||
        old.clipPadding != clipPadding;
  }
}
