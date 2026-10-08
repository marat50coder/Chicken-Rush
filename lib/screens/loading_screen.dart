import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_assets.dart';
import '../prism/rust_guard.dart';
import 'main_menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with SingleTickerProviderStateMixin {
  static const _minDuration = Duration(milliseconds: 3200);

  late final Ticker _ticker;
  double _progress = 0;
  bool _assetsReady = false;
  bool _finishing = false;
  int _dots = 0;
  Timer? _dotsTimer;
  String? _guardError;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      setState(() => _dots = (_dots + 1) % 4);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    // Prime librust_guard eagerly: if the .so wasn't packed into the APK the
    // getter throws and we fall through to _showGuardMissing() so the user
    // sees a clear error screen instead of silently losing the sealed URLs.
    try {
      RustGuard.instance;
    } catch (e) {
      _guardError = e.toString();
    }
    await Future.wait([
      for (final a in AppAssets.gameplay)
        precacheImage(AssetImage(a), context).catchError((_) {}),
    ]);
    _assetsReady = true;
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMilliseconds / _minDuration.inMilliseconds;
    if (!_finishing) {
      // Approaches 92% but never completes until loading is actually done.
      final target = 0.92 * (1 - pow(1 - min(t, 1.0), 2.2));
      _progress = max(_progress, target);
      if (_assetsReady && t >= 1) {
        _finishing = true;
        _finish();
      }
    }
    setState(() {});
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
    if (!mounted) return;
    // Guard missing → hard-stop with a visible error. Silently falling into
    // the menu would ship a broken build where Privacy/Support go nowhere.
    if (_guardError != null) {
      setState(() {});
      return;
    }
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, _, _) => const MainMenuScreen(),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

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
    if (err != null) {
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
                        Shadow(
                            color: Colors.black,
                            blurRadius: 2,
                            offset: Offset(0, 1)),
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
