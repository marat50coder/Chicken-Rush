// ShellPalette — tiny palette used by the beacon-era screens (Boot,
// Permission, Offline, Portal). The white game keeps its own palette.
//
// Design is DIFFERENT from any sibling: warm cream + fire-orange, pill
// buttons with a soft inner highlight. This is on purpose so another
// portfolio project cannot be visually confused with Chicken Rush.

import 'package:flutter/material.dart';

abstract final class ShellPalette {
  ShellPalette._();

  // Night-time starting background (behind the gameplay-asset image).
  static const Color backdrop     = Color(0xFF161318);

  // Primary CTA — reads clearly on the dark backdrop.
  static const Color flame        = Color(0xFFFF7A1A);
  static const Color flameLight   = Color(0xFFFFB063);
  static const Color flameDeep    = Color(0xFFD95400);

  // Secondary / "Skip" look — never grey (grey = disabled).
  static const Color coal         = Color(0xFF2E2730);
  static const Color coalLight    = Color(0xFF463A48);

  static const Color ink          = Color(0xFFFFE9CF);
  static const Color inkSubtle    = Color(0xFFB89E89);
}
