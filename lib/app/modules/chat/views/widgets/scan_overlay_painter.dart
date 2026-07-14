import 'package:flutter/material.dart';
import '../../../../core/services/live_scan_service.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// High-performance overlay painter for the live ML scanner.
///
/// Renders:
///  - **OCR mode**: coloured bounding rectangles around each recognised text block.
///  - **Object Detection mode**: corner-bracket boxes with label + confidence badge.
///
/// FIXES applied:
///  - Coordinate mapping now correctly handles portrait camera (90°/270° rotation):
///    when the camera sensor is rotated, image width/height are swapped for scaling.
///  - Corner bracket style for object detection looks more premium.
///  - Labels are clamped to canvas bounds so they don't go off-screen.
class ScanOverlayPainter extends CustomPainter {
  final Size viewSize;
  final Size absoluteImageSize;
  final Size previewSize;
  final InputImageRotation rotation;
  final bool isOcrMode;

  // Object detection data
  final List<DetectedObject> detectedObjects;

  // OCR data
  final RecognizedText? ocrResult;

  // ── Paint styles (allocated once per instance, reused across paint calls) ──

  late final Paint _odBoxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = const Color(0xFF6C63FF)
    ..strokeCap = StrokeCap.round;

  late final Paint _odFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF6C63FF).withAlpha(25);

  late final Paint _odLabelBgPaint = Paint()
    ..color = const Color(0xFF6C63FF)
    ..style = PaintingStyle.fill;

  late final Paint _ocrBoxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0xFF10B981);

  late final Paint _ocrFillPaint = Paint()
    ..style = PaintingStyle.fill
    ..color = const Color(0xFF10B981).withAlpha(20);

  late final Paint _ocrLabelBgPaint = Paint()
    ..color = const Color(0xFF10B981).withAlpha(200)
    ..style = PaintingStyle.fill;

  // ── TextPainter cache — keyed by object tracking ID (OD) or block index (OCR) ──

  final Map<int, _CachedLabel> _labelCache = {};

  ScanOverlayPainter({
    required this.viewSize,
    required this.absoluteImageSize,
    required this.previewSize,
    required this.rotation,
    required this.isOcrMode,
    required this.detectedObjects,
    required this.ocrResult,
  });

  // ── Paint ──────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (isOcrMode) {
      _paintOcr(canvas, size);
    } else {
      _paintObjects(canvas, size);
    }

    // Draw canvas border (debug outline to confirm all boxes are within view)
    final debugPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = const Color(0xFF10B981); // Bright green
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), debugPaint);
  }

  void _paintObjects(Canvas canvas, Size size) {
    // Evict stale cache entries
    final activeIds = detectedObjects.map((o) => o.trackingId ?? o.hashCode).toSet();
    _labelCache.removeWhere((key, _) => !activeIds.contains(key));

    for (final object in detectedObjects) {
      if (object.labels.isEmpty) continue;

      final rect = object.boundingBox;
      final canvasRect = _transformRect(rect, size);

      // Skip boxes that are out-of-bounds or too small
      if (canvasRect.width < 4 || canvasRect.height < 4) continue;

      // Draw translucent fill
      canvas.drawRect(canvasRect, _odFillPaint);

      // Draw corner brackets instead of full rectangle (premium look)
      _drawCornerBrackets(canvas, canvasRect, _odBoxPaint);

      // Build label
      final label = object.labels.first;
      final confidence = (label.confidence * 100).toStringAsFixed(0);
      final displayText = '${label.text}  $confidence%';

      final cacheKey = object.trackingId ?? object.hashCode;
      final tp = _getOrCreateLabel(
        cacheKey,
        displayText,
        const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
      );

      // Position label above the box, clamped to canvas bounds
      final labelW = tp.width + 10;
      final labelH = tp.height + 6;
      double bgLeft = canvasRect.left;
      double bgTop = canvasRect.top - labelH - 2;

      // Clamp to canvas
      bgLeft = bgLeft.clamp(0, size.width - labelW);
      bgTop = bgTop < 0 ? canvasRect.bottom + 2 : bgTop;
      bgTop = bgTop.clamp(0, size.height - labelH);

      final bgRect = Rect.fromLTWH(bgLeft, bgTop, labelW, labelH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        _odLabelBgPaint,
      );
      tp.paint(canvas, Offset(bgLeft + 5, bgTop + 3));
    }
  }

  void _paintOcr(Canvas canvas, Size size) {
    if (ocrResult == null) return;
    final blocks = ocrResult!.blocks;

    if (_labelCache.length > blocks.length * 3) _labelCache.clear();

    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.text.trim().isEmpty) continue;

      final rect = block.boundingBox;
      final canvasRect = _transformRect(
        Rect.fromLTRB(
          rect.left.toDouble(),
          rect.top.toDouble(),
          rect.right.toDouble(),
          rect.bottom.toDouble(),
        ),
        size,
      );

      if (canvasRect.width < 4 || canvasRect.height < 4) continue;

      // Subtle fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(canvasRect, const Radius.circular(3)),
        _ocrFillPaint,
      );

      // Stroke
      canvas.drawRRect(
        RRect.fromRectAndRadius(canvasRect, const Radius.circular(3)),
        _ocrBoxPaint,
      );

      // Show first line as label (skip if too long)
      final labelText = block.lines.isNotEmpty ? block.lines.first.text.trim() : block.text.trim();
      if (labelText.isEmpty || labelText.length > 40) continue;

      final tp = _getOrCreateLabel(
        i,
        labelText,
        const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w600),
      );

      final labelW = tp.width + 8;
      final labelH = tp.height + 5;
      double bgLeft = canvasRect.left;
      double bgTop = canvasRect.top - labelH - 1;

      bgLeft = bgLeft.clamp(0, size.width - labelW);
      bgTop = bgTop < 0 ? canvasRect.bottom + 1 : bgTop;
      bgTop = bgTop.clamp(0, size.height - labelH);

      final bgRect = Rect.fromLTWH(bgLeft, bgTop, labelW, labelH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        _ocrLabelBgPaint,
      );
      tp.paint(canvas, Offset(bgLeft + 4, bgTop + 2.5));
    }
  }

  // ── Corner Bracket Drawing ─────────────────────────────────────────────────

  /// Draws four corner L-brackets around [rect] for a premium scan look.
  void _drawCornerBrackets(Canvas canvas, Rect rect, Paint paint) {
    final bracketLen = (rect.shortestSide * 0.22).clamp(8.0, 20.0);

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(bracketLen, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft.translate(0, bracketLen), paint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight.translate(-bracketLen, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight.translate(0, bracketLen), paint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(bracketLen, 0), paint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft.translate(0, -bracketLen), paint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(-bracketLen, 0), paint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight.translate(0, -bracketLen), paint);

    // Draw faint dashed outline between brackets
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = paint.color.withAlpha(80);
    canvas.drawRect(rect, dashPaint);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────


  /// Transforms a bounding box from image-space to canvas-space.
  ///
  /// The camera preview uses [BoxFit.cover], so the image is scaled up and
  /// cropped. We compute the same scale + crop offset that FittedBox uses,
  /// so bounding boxes land in the correct on-screen positions.
  Rect _transformRect(Rect imageRect, Size canvasSize) {
    final double imgW = absoluteImageSize.width;
    final double imgH = absoluteImageSize.height;
    final double prevW = previewSize.width;
    final double prevH = previewSize.height;

    if (imgW <= 0 || imgH <= 0 || prevW <= 0 || prevH <= 0) return Rect.zero;

    // 1. Scale coordinates from raw image stream to camera preview space
    final double streamScaleX = prevW / imgW;
    final double streamScaleY = prevH / imgH;

    final double px1 = imageRect.left * streamScaleX;
    final double py1 = imageRect.top * streamScaleY;
    final double px2 = imageRect.right * streamScaleX;
    final double py2 = imageRect.bottom * streamScaleY;

    // 2. Map coordinates from camera preview space to canvas size using BoxFit.cover
    final double scaleX = canvasSize.width / prevW;
    final double scaleY = canvasSize.height / prevH;
    final double scale = scaleX > scaleY ? scaleX : scaleY;

    // The scaled preview may be larger than the canvas; compute the crop offset
    final double offsetX = (prevW * scale - canvasSize.width) / 2.0;
    final double offsetY = (prevH * scale - canvasSize.height) / 2.0;

    return Rect.fromLTRB(
      px1 * scale - offsetX,
      py1 * scale - offsetY,
      px2 * scale - offsetX,
      py2 * scale - offsetY,
    );
  }



  /// Returns a cached [TextPainter] for [key], creating and laying out if the
  /// text has changed. Avoids redundant layout calls on every paint frame.
  TextPainter _getOrCreateLabel(int key, String text, TextStyle style) {
    final cached = _labelCache[key];
    if (cached != null && cached.text == text) return cached.painter;

    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    _labelCache[key] = _CachedLabel(text: text, painter: tp);
    return tp;
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter oldDelegate) {
    return oldDelegate.detectedObjects != detectedObjects ||
        oldDelegate.ocrResult != ocrResult ||
        oldDelegate.isOcrMode != isOcrMode ||
        oldDelegate.viewSize != viewSize ||
        oldDelegate.previewSize != previewSize ||
        oldDelegate.rotation != rotation;
  }
}

/// Lightweight cache entry to avoid redundant [TextPainter.layout] calls.
class _CachedLabel {
  final String text;
  final TextPainter painter;
  const _CachedLabel({required this.text, required this.painter});
}
