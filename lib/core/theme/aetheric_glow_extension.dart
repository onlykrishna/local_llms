import 'dart:ui';
import 'package:flutter/material.dart';

class AethericGlowExtension extends ThemeExtension<AethericGlowExtension> {
  final Color? glassSurface;
  final Color? glassStroke;
  final double? blurAmount;

  const AethericGlowExtension({
    required this.glassSurface,
    required this.glassStroke,
    this.blurAmount = 15.0,
  });

  @override
  AethericGlowExtension copyWith({
    Color? glassSurface,
    Color? glassStroke,
    double? blurAmount,
  }) {
    return AethericGlowExtension(
      glassSurface: glassSurface ?? this.glassSurface,
      glassStroke: glassStroke ?? this.glassStroke,
      blurAmount: blurAmount ?? this.blurAmount,
    );
  }

  @override
  AethericGlowExtension lerp(ThemeExtension<AethericGlowExtension>? other, double t) {
    if (other is! AethericGlowExtension) return this;
    return AethericGlowExtension(
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t),
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t),
      blurAmount: lerpDouble(blurAmount, other.blurAmount, t),
    );
  }

  static AethericGlowExtension of(BuildContext context) =>
      Theme.of(context).extension<AethericGlowExtension>()!;
}
