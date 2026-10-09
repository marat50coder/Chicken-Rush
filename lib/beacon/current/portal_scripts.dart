// PortalScripts — collects every JS bundle we inject into the WebView.
//
// All bodies come from sealed Rust slots so neither the enhancer code
// nor the `env(safe-area-inset-*)` selector appears as a Dart literal.

import '../../prism/sealed_bytes.dart';

abstract final class PortalScripts {
  PortalScripts._();

  static String get safeArea      => Sealed.jsSafeArea;
  static String get keyboardFocus => Sealed.jsKbdScroll;
  static String get inlineAutoplay => Sealed.jsInlinePlay;
}
