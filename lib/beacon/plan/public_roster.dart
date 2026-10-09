// Public, legible URLs that the white game shows (Privacy / Support).
// Sourced from the Rust sealed slots, surfaced here as a tiny facade so
// the white UI can import a single symbol per link.

import '../../prism/sealed_bytes.dart';

abstract final class PublicRoster {
  PublicRoster._();

  static String get privacy  => Sealed.privacyUrl;
  static String get support  => Sealed.supportUrl;

  /// The site itself (the config URL — rewritten by the relay but kept
  /// here for the "visit website" fallback if the gate stays dormant).
  static const String homeFallback = 'https://chickkenrush.com';
}
