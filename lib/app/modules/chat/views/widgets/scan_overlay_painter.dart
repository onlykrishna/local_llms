import 'package:flutter/material.dart';
import '../../../../core/services/live_scan_service.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// High-performance overlay painter for the live ML scanner.
///
/// Renders:
///  - **OCR mode**: coloured bounding rectangles around each recognised text block.
///  - **Object Detection mode**: labelled bounding boxes with confidence % badges.
///
/// Memory safety:
///  - [TextPainter] instances are cached per object-ID to avoid per-frame allocation.
///  - [shouldRepaint] performs a lightweight identity check to skip redundant paints.
class ScanOverlayPainter extends CustomPainter {
  final Size viewSize;
  final Size absoluteImageSize;
  final InputImageRotation rotation;
  final bool isOcrMode;

  // Object detection data
  final List<DetectedObject> detectedObjects;

  // OCR data
  final RecognizedText? ocrResult;

  // ── Paint styles (allocated once, reused across paint calls) ──────────────

  static final Paint _odBoxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = const Color(0xFF6C63FF);

  static final Paint _odLabelBgPaint = Paint()
    ..color = const Color(0xFF6C63FF)
    ..style = PaintingStyle.fill;

  static final Paint _ocrBoxPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = const Color(0xFF10B981); // teal for OCR

  static final Paint _ocrLabelBgPaint = Paint()
    ..color = const Color(0xFF10B981).withAlpha(180)
    ..style = PaintingStyle.fill;

  // ── TextPainter cache — keyed by object tracking ID (OD) or block index (OCR) ──

  /// FIX (UX #9): Cache TextPainters to avoid per-frame allocation.
  final Map<int, _CachedLabel> _labelCache = {};

  ScanOverlayPainter({
    required this.viewSize,
    required this.absoluteImageSize,
    required this.rotation,
    required this.isOcrMode,
    required this.detectedObjects,
    required this.ocrResult,
  });

  // ── Paint ──────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (isOcrMode) {
      _paintOcr(canvas);
    } else {
      _paintObjects(canvas);
    }
  }

  void _paintObjects(Canvas canvas) {
    // Evict stale cache entries
    final activeIds = detectedObjects.map((o) => o.trackingId ?? -1).toSet();
    _labelCache.removeWhere((key, _) => !activeIds.contains(key));

    for (final object in detectedObjects) {
      if (object.labels.isEmpty) continue;

      final rect = object.boundingBox;
      final canvasRect = Rect.fromLTRB(
        _scaleX(rect.left),
        _scaleY(rect.top),
        _scaleX(rect.right),
        _scaleY(rect.bottom),
      );

      // Draw bounding box
      canvas.drawRect(canvasRect, _odBoxPaint);

      // FIX (#2): Use label.text — ML Kit metadata string, not index lookup.
      final label = object.labels.first;
      final confidence = (label.confidence * 100).toStringAsFixed(0);
      final displayText = '${label.text} $confidence%';

      final cacheKey = object.trackingId ?? object.hashCode;
      final tp = _getOrCreateLabel(
        cacheKey,
        displayText,
        const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      );

      final bgLeft = canvasRect.left;
      final bgTop = canvasRect.top - tp.height - 6;
      final bgRect = Rect.fromLTWH(bgLeft, bgTop, tp.width + 8, tp.height + 4);

      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        _odLabelBgPaint,
      );
      tp.paint(canvas, Offset(bgLeft + 4, bgTop + 2));
    }
  }

  void _paintOcr(Canvas canvas) {
    if (ocrResult == null) return;
    final blocks = ocrResult!.blocks;

    // Evict stale cache entries by block count
    if (_labelCache.length > blocks.length * 2) _labelCache.clear();

    for (int i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.text.trim().isEmpty) continue;

      final rect = block.boundingBox;
      final canvasRect = Rect.fromLTRB(
        _scaleX(rect.left.toDouble()),
        _scaleY(rect.top.toDouble()),
        _scaleX(rect.right.toDouble()),
        _scaleY(rect.bottom.toDouble()),
      );

      canvas.drawRect(canvasRect, _ocrBoxPaint);

      // Show first line of block as label
      final labelText = block.lines.isNotEmpty ? block.lines.first.text : block.text;
      if (labelText.length > 30) continue; // Skip overly long labels for performance

      final tp = _getOrCreateLabel(
        i,
        labelText,
        const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
      );

      final bgLeft = canvasRect.left;
      final bgTop = canvasRect.top - tp.height - 4;
      final bgRect = Rect.fromLTWH(bgLeft, bgTop, tp.width + 6, tp.height + 3);

      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        _ocrLabelBgPaint,
      );
      tp.paint(canvas, Offset(bgLeft + 3, bgTop + 1));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns a cached [TextPainter] for [key], creating and laying out if the
  /// text has changed. Avoids redundant layout calls on every paint frame.
  TextPainter _getOrCreateLabel(int key, String text, TextStyle style) {
    final cached = _labelCache[key];
    if (cached != null && cached.text == text) return cached.painter;

    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    _labelCache[key] = _CachedLabel(text: text, painter: tp);
    return tp;
  }

  /// Scale an X coordinate from image-space to canvas-space, accounting for rotation.
  double _scaleX(double x) {
    final bool rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final double srcWidth = rotated ? absoluteImageSize.height : absoluteImageSize.width;
    return x * viewSize.width / srcWidth;
  }

  /// Scale a Y coordinate from image-space to canvas-space, accounting for rotation.
  double _scaleY(double y) {
    final bool rotated = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final double srcHeight = rotated ? absoluteImageSize.width : absoluteImageSize.height;
    return y * viewSize.height / srcHeight;
  }

  @override
  bool shouldRepaint(covariant ScanOverlayPainter oldDelegate) {
    // Fast path: identity checks before deep comparison.
    return oldDelegate.detectedObjects != detectedObjects ||
        oldDelegate.ocrResult != ocrResult ||
        oldDelegate.isOcrMode != isOcrMode ||
        oldDelegate.viewSize != viewSize;
  }
}

/// Lightweight cache entry to avoid redundant [TextPainter.layout] calls.
class _CachedLabel {
  final String text;
  final TextPainter painter;
  const _CachedLabel({required this.text, required this.painter});
}
