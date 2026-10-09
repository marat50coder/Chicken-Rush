// KernelDeck — the one and only startup surface.
//
// Flow:
//   1. Pump animated loader + preload gameplay assets (same visuals as
//      the previous LoadingScreen so returning users recognise it).
//   2. In parallel, run BeaconHelm.decide() with a hard ceiling.
//   3. Route according to the Harbor:
//        GameHarbor      → push MainMenuScreen (white game).
//        WebHarbor       → ChimeDock (if permission not snoozed) →
//                          PortalDeck(url).
//        BecalmedHarbor  → BecalmedDeck.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_assets.dart';
import '../beacon/compass/beacon_helm.dart';
import '../beacon/compass/harbor.dart';
import '../beacon/current/anchor_vault.dart';
import '../beacon/current/chime_bridge.dart';
import '../beacon/current/mesh_telemetry.dart';
import '../beacon/current/mooring_note.dart';
import '../beacon/current/tide_scout.dart';
import '../beacon/dock/becalmed_deck.dart';
import '../beacon/dock/chime_dock.dart';
import '../beacon/dock/portal_deck.dart';
import '../beacon/plan/fabric_plan.dart';
import '../prism/rust_guard.dart';
import '../screens/main_menu_screen.dart';

class KernelDeck extends StatefulWidget {
  const KernelDeck({super.key});
  @override
  State<KernelDeck> createState() => _KernelDeckState();
}

class _KernelDeckState extends State<KernelDeck>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _progress = 0;
  int _dots = 0;
  bool _assetsReady = false;
  bool _routed = false;
  bool _finishing = false;
  Harbor? _harbor;
  String? _guardError;
  Timer? _dotsTimer;

  static const _minDuration = Duration(milliseconds: 3200);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _dots = (_dots + 1) % 4);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _work());
  }

  Future<void> _work() async {
    try { RustGuard.instance; }
    catch (e) { _guardError = e.toString(); }

    // Pre-wire everything the beacon needs; cheap if gate dormant.
    unawaited(MeshTelemetry.instance.boot());
    unawaited(ChimeBridge.instance.boot());
    unawaited(MooringNote.instance.wire());

    await Future.wait([
      _preloadAssets(),
      _decide(),
    ]);
    _assetsReady = true;
  }

  Future<void> _preloadAssets() async {
    if (!mounted) return;
    for (final a in AppAssets.gameplay) {
      if (!mounted) return;
      try { await precacheImage(AssetImage(a), context); } catch (_) {}
    }
  }

  Future<void> _decide() async {
    if (_guardError != null) {
      _harbor = const GameHarbor(mark: TrailMark.firstBoot);
      return;
    }
    try {
      _harbor = await BeaconHelm.instance
          .decide()
          .timeout(FabricPlan.firstInstallHold + const Duration(seconds: 2));
    } catch (_) {
      _harbor = const GameHarbor(mark: TrailMark.firstBoot);
    }
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMilliseconds / _minDuration.inMilliseconds;
    if (!_finishing) {
      final target = 0.92 * (1 - pow(1 - min(t, 1.0), 2.2));
      _progress = max(_progress, target);
      if (_assetsReady && t >= 1 && _harbor != null) {
        _finishing = true;
        _finish();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _finish() async {
    final start = _progress;
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 22));
      if (!mounted) return;
      setState(() => _progress = start + (1 - start) * i / steps);
    }
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || _routed) return;
    _routed = true;
    await _route();
  }

  Future<void> _route() async {
    final h = _harbor ?? const GameHarbor(mark: TrailMark.firstBoot);
    final nav = Navigator.of(context);
    switch (h) {
      case GameHarbor():
        nav.pushReplacement(_fade(const MainMenuScreen()));
      case WebHarbor(:final url, :final injectKeyboardScroll,
                     :final injectAutoplay):
        final snoozed = await AnchorVault.instance.permissionSnoozed();
        final granted = await AnchorVault.instance.permissionGranted();
        if (!snoozed && !granted) {
          nav.pushReplacement(_fade(ChimeDock(
            onDone: () {
              Navigator.of(context).pushReplacement(_fade(PortalDeck(
                url: url,
                injectKeyboardScroll: injectKeyboardScroll,
                injectAutoplay: injectAutoplay,
              )));
            },
          )));
        } else {
          nav.pushReplacement(_fade(PortalDeck(
            url: url,
            injectKeyboardScroll: injectKeyboardScroll,
            injectAutoplay: injectAutoplay,
          )));
        }
      case BecalmedHarbor():
        nav.pushReplacement(_fade(BecalmedDeck(onRetry: _retryFromOffline)));
    }
  }

  Future<void> _retryFromOffline() async {
    if (!mounted) return;
    final reachable = await TideScout.instance.isReachable();
    if (!reachable || !mounted) return;
    Navigator.of(context).pushReplacement(_fade(const KernelDeck()));
  }

  PageRouteBuilder<void> _fade(Widget page) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
  );

  @override
  void dispose() {
    _ticker.dispose();
    _dotsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final barW = min(size.width * (landscape ? 0.45 : 0.72), 520.0);
    final bottomGap = landscape ? size.height * 0.08 : size.height * 0.09;

    final err = _guardError;
    if (err != null && _progress < 0.05) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Native component failed to load.\n$err',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            landscape ? AppAssets.loadingHorizontal : AppAssets.loadingVertical,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomGap + MediaQuery.paddingOf(context).bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: barW,
                  child: Text(
                    'Loading${'.' * _dots}',
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(color: Colors.black, blurRadius: 6),
                        Shadow(color: Colors.black,
                            blurRadius: 2, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _ProgressBar(width: barW, value: _progress),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.width, required this.value});
  final double width;
  final double value;

  @override
  Widget build(BuildContext context) {
    const h = 18.0;
    return Container(
      width: width,
      height: h,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xCC1A1A1A),
        borderRadius: BorderRadius.circular(h / 2),
        border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(h / 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFE57F), Color(0xFFFFB300)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
