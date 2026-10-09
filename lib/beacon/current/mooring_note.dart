// MooringNote — short-lived rendez-vous between the launching activity
// and the beacon pipeline:
//   • a cold boot via push notification arrives here first;
//   • app_links / deep-link URLs are forwarded here too.
//
// BeaconHelm consumes it exactly once before falling through to its
// usual decide() path.

import 'dart:async';

import 'package:app_links/app_links.dart';

import 'chime_bridge.dart';

class MooringNote {
  MooringNote._();
  static final MooringNote instance = MooringNote._();

  String? _earlyUrl;
  StreamSubscription<String>? _pushSub;
  StreamSubscription<Uri>? _deepSub;

  Future<void> wire() async {
    _pushSub ??= ChimeBridge.instance.pushUrls.listen((u) {
      _earlyUrl ??= u;
    });

    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) _earlyUrl ??= initial.toString();
      _deepSub ??= links.uriLinkStream.listen((u) {
        _earlyUrl ??= u.toString();
      });
    } catch (_) {/* plugin missing / channel error — ignore */}
  }

  /// Reads AND clears the pending URL.
  String? takeUrl() {
    final u = _earlyUrl;
    _earlyUrl = null;
    return u;
  }
}
