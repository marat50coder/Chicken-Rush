import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_assets.dart';
import '../utils/format.dart';
import 'game_controller.dart';

class WorldView extends StatefulWidget {
  const WorldView({super.key, required this.controller});

  final GameController controller;

  @override
  State<WorldView> createState() => _WorldViewState();
}

class _WorldViewState extends State<WorldView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    widget.controller.update(dt);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final c = widget.controller;
      c.setLayout(constraints.maxWidth, constraints.maxHeight);
      final l = c.layout!;
      return ClipRect(
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ..._background(c, l),
            ..._hatches(c, l),
            ..._chicken(c, l),
            ..._cars(c, l),
            ..._barriers(c, l),
            ..._feathers(c, l),
          ],
        ),
      );
    });
  }

  double _sx(GameController c, double worldX) => worldX - c.cameraX;

  bool _visible(GameController c, WorldLayout l, double x, double w) {
    final sx = _sx(c, x);
    return sx + w > -2 && sx < l.width + 2;
  }

  Widget _img(String asset, double left, double top, double w, double h,
      {BoxFit fit = BoxFit.fill}) {
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Image.asset(
        asset,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  Iterable<double> _tileRows(WorldLayout l) sync* {
    final offset = (l.hatchY - l.tileH * 0.5) % l.tileH;
    for (var y = offset - l.tileH; y < l.height; y += l.tileH) {
      yield y;
    }
  }

  List<Widget> _background(GameController c, WorldLayout l) {
    final out = <Widget>[];
    final rows = _tileRows(l).toList();
    final overlap = 1.0;

    for (var i = 0; i <= c.laneCount; i++) {
      final x = l.roadStart + (i - 0.5) * l.laneW;
      if (!_visible(c, l, x, l.laneW)) continue;
      for (final y in rows) {
        out.add(_img(AppAssets.bgLines, _sx(c, x) - overlap, y - overlap,
            l.laneW + overlap * 2, l.tileH + overlap * 2));
      }
    }

    void piece(String asset, double x, double w) {
      if (!_visible(c, l, x, w)) return;
      for (final y in rows) {
        out.add(_img(asset, _sx(c, x) - overlap, y - overlap, w + overlap * 2,
            l.tileH + overlap * 2));
      }
    }

    piece(AppAssets.bgStart, 0, l.start1W);
    piece(AppAssets.bgStart2, l.start1W, l.start2W);
    piece(AppAssets.bgEnd, l.endX, l.endW);
    return out;
  }

  List<Widget> _hatches(GameController c, WorldLayout l) {
    final out = <Widget>[];
    final next = c.currentLane + 1;
    for (var i = 0; i < c.laneCount; i++) {
      final cx = l.laneCenter(i);
      final size = l.hatchSize;
      if (!_visible(c, l, cx - size / 2, size)) continue;

      final passed = c.inRound &&
          (i < c.currentLane ||
              (i == c.currentLane && c.phase != GamePhase.dead));
      final isNext = c.phase != GamePhase.dead &&
          c.phase != GamePhase.won &&
          i == next;
      var scale = 1.0;
      if (i == c.currentLane && c.landPop > 0 && passed) {
        scale = 1 + sin(c.landPop * pi) * 0.12;
      }
      if (isNext && c.inRound) {
        scale *= 1 + sin(c.time * 5) * 0.03;
      }
      final s = size * scale;
      final left = _sx(c, cx) - s / 2;
      final top = l.hatchY - s / 2;

      out.add(Positioned(
        left: left,
        top: top,
        width: s,
        height: s,
        child: Opacity(
          opacity: passed || isNext || !c.inRound ? 1 : 0.82,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                passed ? AppAssets.hatchGold : AppAssets.hatchGray,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
              if (!passed)
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: s * 0.08),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatMultiplier(c.multipliers[i]),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: l.laneW * 0.135,
                          shadows: const [
                            Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                                offset: Offset(0, 1)),
                            Shadow(color: Colors.black54, blurRadius: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ));
    }
    return out;
  }

  List<Widget> _chicken(GameController c, WorldLayout l) {
    final pos = c.chickenPosition;
    final x = l.xOfPosition(pos, c.laneCount);
    final dead = c.phase == GamePhase.dead;

    var w = l.chickenW;
    var h = l.chickenH;
    var lift = 0.0;
    var angle = 0.0;

    if (c.phase == GamePhase.jumping) {
      final t = c.jumpT.clamp(0.0, 1.0);
      lift = sin(t * pi) * l.laneW * 0.34;
      if (t < 0.15) {
        final k = t / 0.15;
        w *= 1 + 0.10 * (1 - k);
        h *= 1 - 0.10 * (1 - k);
      } else {
        w *= 0.97;
        h *= 1.04;
      }
      angle = sin(t * pi) * -0.08;
    } else if (!dead) {
      final squash = c.landPop > 0 ? sin(c.landPop * pi) * 0.12 : 0.0;
      final breath = sin(c.time * 3.2) * 0.018;
      w *= 1 + squash - breath * 0.5;
      h *= 1 - squash + breath;
    }

    // Alpha bounding box of the chicken sprite inside its 1132x1260 canvas.
    // Anchor the hen's body centre (not the canvas centre) to the manhole
    // centre, so she sits right in the middle of the hatch on every landing.
    const bboxCx = 0.4916;
    const bboxCy = 0.4985;
    final left = _sx(c, x) - w / 2 - (bboxCx - 0.5) * w;
    final top = l.hatchY - lift - bboxCy * h;
    final out = <Widget>[];

    out.add(Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: dead ? 0 : angle,
        child: Image.asset(
          dead ? AppAssets.chickenDead : AppAssets.chicken,
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      ),
    ));

    final showBadge = c.currentLane >= 0 &&
        !c.atFinish &&
        (c.phase == GamePhase.ready || c.phase == GamePhase.won);
    if (showBadge) {
      final bw = l.laneW * 0.62;
      final bh = l.laneW * 0.25;
      final pop = c.landPop > 0 ? 1 + sin(c.landPop * pi) * 0.1 : 1.0;
      out.add(Positioned(
        left: _sx(c, x) - bw / 2,
        top: l.hatchY + l.chickenH * 0.45,
        width: bw,
        height: bh,
        child: Transform.scale(
          scale: pop,
          child: _MultiplierBadge(
            text: formatMultiplier(c.currentMultiplier),
            fontSize: l.laneW * 0.13,
          ),
        ),
      ));
    }
    return out;
  }

  List<Widget> _cars(GameController c, WorldLayout l) {
    final out = <Widget>[];
    for (final car in c.cars) {
      final cx = l.laneCenter(car.lane);
      if (!_visible(c, l, cx - l.carW / 2, l.carW)) continue;
      out.add(_img(AppAssets.cars[car.sprite], _sx(c, cx) - l.carW / 2,
          car.front - l.carH, l.carW, l.carH));
    }
    return out;
  }

  List<Widget> _barriers(GameController c, WorldLayout l) {
    final out = <Widget>[];
    c.barriers.forEach((lane, t) {
      final cx = l.laneCenter(lane);
      if (!_visible(c, l, cx - l.barrierW / 2, l.barrierW)) return;
      final k = (t / 0.28).clamp(0.0, 1.0);
      final eased = Curves.easeOutBack.transform(k);
      final y = l.barrierY - l.barrierH / 2 - (1 - eased) * l.height * 0.35;
      out.add(Positioned(
        left: _sx(c, cx) - l.barrierW / 2,
        top: y,
        width: l.barrierW,
        height: l.barrierH,
        child: Opacity(
          opacity: k.clamp(0.0, 1.0),
          child: Image.asset(AppAssets.barrier,
              fit: BoxFit.fill, gaplessPlayback: true),
        ),
      ));
    });
    return out;
  }

  List<Widget> _feathers(GameController c, WorldLayout l) {
    final t = c.deathTime;
    if (t < 0 || t > 1.4) return const [];
    final x = l.xOfPosition(c.chickenPosition, c.laneCount);
    final k = t / 1.4;
    final size = l.chickenW * (0.7 + Curves.easeOut.transform(k) * 1.1);
    final opacity = k < 0.6 ? 1.0 : (1 - (k - 0.6) / 0.4);
    return [
      Positioned(
        left: _sx(c, x) - size / 2,
        top: l.chickenY - size / 2 - k * l.laneW * 0.15,
        width: size,
        height: size,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: k * 0.6,
            child: Image.asset(AppAssets.feathers, gaplessPlayback: true),
          ),
        ),
      ),
    ];
  }
}

class _MultiplierBadge extends StatelessWidget {
  const _MultiplierBadge({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF4A5778), Color(0xFF2E3A57)],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF5D6B8F), width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
