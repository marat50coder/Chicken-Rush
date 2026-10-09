// ===================================================================
// FabricPlan — all boot-time constants for the gray funnel.
//
// Rule: every numeric constant here must differ by ≥10% from any
// sibling project (portfolio_registry).
// ===================================================================

import '../../prism/sealed_bytes.dart';

/// All timing dials for the beacon pipeline.
///
/// Numbers are intentionally non-round. Do not share with other projects.
abstract final class FabricPlan {
  FabricPlan._();

  // ── wall-clock budgets ──────────────────────────────────────────
  /// Soft timeout for the verdict POST.
  static const Duration decreeDispatch = Duration(seconds: 19);

  /// Hard limit a first-install launch will wait for the verdict before
  /// falling through to the white game.
  static const Duration firstInstallHold = Duration(seconds: 33);

  /// Returning users: much tighter.
  static const Duration returningHold = Duration(seconds: 5);

  /// Extra time granted when a deep-link onelink URL is on the clipboard.
  static const Duration deepLinkHold = Duration(seconds: 5);

  // ── reach probe ─────────────────────────────────────────────────
  static const Duration reachProbeTimeout = Duration(seconds: 7);
  static const Duration reachDropDebounce = Duration(milliseconds: 940);

  // ── portal webview ──────────────────────────────────────────────
  /// Guard against ad-redirect loops.
  static const int redirectLoopRetries = 3;

  /// Cached landing URL lifetime in local prefs.
  static const Duration cachedUrlLifetime = Duration(hours: 147); // ~6.1 d

  // ── notification opt-in ─────────────────────────────────────────
  /// After a Skip, do not re-ask for this long.
  static const Duration permissionSnooze = Duration(hours: 81); // ~3.375 d

  // ── attribution ─────────────────────────────────────────────────
  /// Grace period for returning / foreground refresh before claiming the
  /// install is organic.
  static const Duration organicRescueDelay = Duration(seconds: 6);

  /// First-install GCD window. Fresh installs frequently take 8–14 s to
  /// receive the AppsFlyer conversion callback; a short wait races the
  /// verdict POST ahead with empty attribution and dumps a paid install
  /// into the white game. Kept under firstInstallHold so the POST that
  /// follows still fits the total boot budget.
  static const Duration gcdFirstInstallWait = Duration(seconds: 13);

  /// Verdict POST timeout used on the first-install path (leaves room for
  /// the GCD wait inside firstInstallHold: 13 + 19 = 32 s < 33 s).
  static const Duration firstInstallDispatch = Duration(seconds: 19);

  // ── identity (through Rust) ─────────────────────────────────────
  static String get bundleId  => Sealed.bundleId;
  static String get appName   => Sealed.appName;
  static String get endpoint  => Sealed.edgeEndpoint;

  // ── storage ─────────────────────────────────────────────────────
  /// Prefix used for every prefs/secure-storage key owned by the beacon
  /// layer. Deliberately short and project-specific.
  static const String storagePrefix = 'bq7_';

  // ── notification channel ────────────────────────────────────────
  /// Must stay stable across releases: Android remembers channel
  /// id → user preference.
  static const String notifChannelId   = 'cr_tide_news_v1';
  static const String notifChannelName = 'Promotions';
  static const String notifChannelDesc =
      'Occasional updates and rewards from Chicken Rush.';

  // ── method channels ─────────────────────────────────────────────
  /// Name used both in Dart and in MainActivity.kt — differs from any
  /// sibling to keep the fingerprint unique.
  static const String nativeChannel = 'beacon/portal_haul';
}

/// Boolean switch — the gray gate stays dormant until Rust ships real
/// AppsFlyer + Firebase credentials.
bool get fabricCredentialsLive => credentialsReady;
