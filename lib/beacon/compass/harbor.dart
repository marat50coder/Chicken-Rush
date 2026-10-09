// ===================================================================
// Harbor — sealed outcome of the beacon decision pipeline.
//
// Three variants:
//   • GameHarbor   — play the white game (always safe to reach).
//   • WebHarbor    — show a WebView at [url].
//   • BecalmedHarbor — no connectivity: show the offline screen.
// ===================================================================

/// How the current session arrived at its decision.
///
/// This feeds analytics and the next-boot cache so a returning user hits
/// their landing path faster.
enum TrailMark {
  firstBoot,        // fresh install, no cached outcome
  cachedWebReturn,  // previously decided → WebHarbor, cache still fresh
  cachedGameReturn, // previously decided → GameHarbor
  pushRelaunch,     // app relaunched from a push notification
  deepLink,         // launched via a deep link / clipboard capture
  reachLost,        // connectivity probe failed
}

sealed class Harbor {
  const Harbor();
}

class GameHarbor extends Harbor {
  const GameHarbor({required this.mark});
  final TrailMark mark;
}

class WebHarbor extends Harbor {
  const WebHarbor({
    required this.url,
    required this.mark,
    this.injectKeyboardScroll = true,
    this.injectAutoplay = true,
  });

  final String url;
  final TrailMark mark;
  final bool injectKeyboardScroll;
  final bool injectAutoplay;
}

class BecalmedHarbor extends Harbor {
  const BecalmedHarbor({required this.mark});
  final TrailMark mark;
}

/// A single, atomic decision from the backend verdict.
///
/// `url == null && openWeb == false` ⇒ play the game.
class Decree {
  const Decree({required this.openWeb, this.url, this.expiresAt});

  final bool openWeb;
  final String? url;
  final DateTime? expiresAt;

  bool get valid =>
      !openWeb || (url != null && url!.startsWith('http'));
}
