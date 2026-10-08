// Typed accessors for every sealed string shipped in librust_guard.
//
// IDs must stay in sync with `rust/build.rs`. Dart never embeds a plaintext
// copy — every call goes through Rust.

import 'rust_guard.dart';

/// Numeric ids match `rust/build.rs`.
abstract final class SealedIds {
  static const privacyUrl   = 1;
  static const supportUrl   = 2;
  static const defaultUa    = 3;
  static const edgeEndpoint = 4;
  static const fieldSchema  = 5;
  static const fieldNonce   = 6;
  static const fieldPayload = 7;
  static const fieldTag     = 8;
  static const schemaRev    = 9;
  // 10 is the HMAC/keystream secret — intentionally not exposed to Dart;
  //    it is consumed only inside `rg_pack`.
  static const bundleId     = 11;
  static const appName      = 12;
}

/// Thin facade over [RustGuard.fetchString] so callers don't take a direct
/// dependency on the raw FFI handle.
abstract final class Sealed {
  static String get privacyUrl   => RustGuard.instance.fetchString(SealedIds.privacyUrl);
  static String get supportUrl   => RustGuard.instance.fetchString(SealedIds.supportUrl);
  static String get defaultUa    => RustGuard.instance.fetchString(SealedIds.defaultUa);
  static String get edgeEndpoint => RustGuard.instance.fetchString(SealedIds.edgeEndpoint);
  static String get bundleId     => RustGuard.instance.fetchString(SealedIds.bundleId);
  static String get appName      => RustGuard.instance.fetchString(SealedIds.appName);
}

/// Returns true once librust_guard loaded and self-checked. If this is false
/// the app refuses to show menus that depend on sealed URLs — rather than
/// silently sending users to about:blank.
bool get guardReady {
  try {
    return RustGuard.instance.fetchString(SealedIds.privacyUrl).isNotEmpty;
  } catch (_) {
    return false;
  }
}
