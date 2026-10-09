// TideScout — connectivity verification used before the beacon decides.
//
// We do NOT trust connectivity_plus alone: Android labels any active VPN
// tunnel as `vpn` and that would otherwise be treated as offline, which
// is wrong (plenty of players route through a VPN).
//
// After seeing *any* candidate interface, we hit a short DNS lookup
// against two sealed probe hosts (ids 50/51) with a hard timeout. If
// both lookups fail we are truly offline.

import 'dart:async';
import 'dart:io' show InternetAddress, SocketException;

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../prism/sealed_bytes.dart';
import '../plan/fabric_plan.dart';

class TideScout {
  TideScout._();
  static final TideScout instance = TideScout._();

  final _conn = Connectivity();

  Future<bool> isReachable() async {
    final results = await _conn.checkConnectivity();
    if (!_hasAnyUplink(results)) return false;
    return _dnsProbe();
  }

  bool _hasAnyUplink(List<ConnectivityResult> r) {
    for (final it in r) {
      if (it == ConnectivityResult.wifi
          || it == ConnectivityResult.mobile
          || it == ConnectivityResult.ethernet
          || it == ConnectivityResult.vpn) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _dnsProbe() async {
    Future<bool> lookup(String host) async {
      try {
        final addrs = await InternetAddress
            .lookup(host)
            .timeout(FabricPlan.reachProbeTimeout);
        return addrs.isNotEmpty && addrs.first.rawAddress.isNotEmpty;
      } on TimeoutException {
        return false;
      } on SocketException {
        return false;
      } catch (_) {
        return false;
      }
    }

    // Race the two probes — first winner counts.
    final a = lookup(Sealed.reachHostA);
    final b = lookup(Sealed.reachHostB);
    final either = Completer<bool>();
    void settle(bool ok) {
      if (!either.isCompleted && ok) either.complete(true);
    }
    a.then(settle);
    b.then(settle);
    Future.wait([a, b]).then((both) {
      if (!either.isCompleted) either.complete(both.any((v) => v));
    });
    return either.future;
  }

  /// Debounced listener: emits only after `debounce` of silence so a brief
  /// handover (e.g., LTE → wifi) doesn't bounce the user into Becalmed.
  Stream<bool> watch() async* {
    final events = _conn.onConnectivityChanged;
    bool? last;
    Timer? pending;
    final controller = StreamController<bool>();
    final sub = events.listen((list) {
      pending?.cancel();
      pending = Timer(FabricPlan.reachDropDebounce, () async {
        final ok = _hasAnyUplink(list) && await _dnsProbe();
        if (ok != last) {
          last = ok;
          controller.add(ok);
        }
      });
    });
    yield* controller.stream;
    await sub.cancel();
  }
}
