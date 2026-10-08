import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prism/rust_math.dart';
import 'difficulty.dart';

enum GamePhase { idle, ready, jumping, dead, won }

class Car {
  Car({
    required this.lane,
    required this.front,
    required this.speed,
    required this.sprite,
    this.deadly = false,
  });

  final int lane;

  /// Y of the car's front bumper (cars drive top -> bottom).
  double front;
  double speed;
  final int sprite;

  /// If true, the car is scripted to run the chicken over at impact time.
  final bool deadly;

  /// Set when the car has to brake in front of a barrier.
  double? stopAt;
}

/// Metric helpers for the current viewport.
class WorldLayout {
  WorldLayout(this.width, this.height) {
    scale = width * 0.37 / 526;
    laneW = 526 * scale;
    tileH = 1024 * scale;
    start1W = 609 * scale;
    start2W = 589 * scale;
    endW = 1149 * scale;
    roadStart = start1W + start2W + 3 * scale;
    endX = roadStart + kLaneCount * laneW - 50 * scale;
    worldW = endX + endW;
    startX = start1W + 420 * scale;
    finishX = endX + 205 * scale;
    hatchY = height * 0.58;
    hatchSize = laneW * 0.64;
    chickenW = laneW * 0.66;
    chickenH = chickenW * 1260 / 1132;
    // Centre the chicken's visual bounding box on the manhole so it lands
    // perfectly centered on every tile.
    chickenY = hatchY;
    barrierW = laneW * 0.86;
    barrierH = barrierW * 236 / 571;
    barrierY = hatchY - laneW * 0.56;
    carW = laneW * 0.74;
    carH = carW * 1336 / 768;
  }

  final double width;
  final double height;
  late final double scale;
  late final double laneW;
  late final double tileH;
  late final double start1W;
  late final double start2W;
  late final double endW;
  late final double roadStart;
  late final double endX;
  late final double worldW;
  late final double startX;
  late final double finishX;
  late final double hatchY;
  late final double hatchSize;
  late final double chickenW;
  late final double chickenH;
  late final double chickenY;
  late final double barrierW;
  late final double barrierH;
  late final double barrierY;
  late final double carW;
  late final double carH;

  double laneCenter(int lane) => roadStart + (lane + 0.5) * laneW;

  /// Horizontal position for the chicken.
  /// -1 = start sidewalk, 0..n-1 = lanes, n = finish sidewalk.
  double xOfPosition(double p, int lanes) {
    if (p <= -1) return startX;
    if (p >= lanes) return finishX;
    if (p < 0) return startX + (laneCenter(0) - startX) * (p + 1);
    if (p > lanes - 1) {
      return laneCenter(lanes - 1) +
          (finishX - laneCenter(lanes - 1)) * (p - (lanes - 1));
    }
    return laneCenter(0) + p * laneW;
  }
}

class GameController extends ChangeNotifier {
  GameController() {
    _load();
  }

  static const double minBet = 1;
  static const double maxBet = 200;
  static const double startBalance = 1000;
  static const double jumpDuration = 0.38;

  /// Chance that an incoming car on a lane with a barrier brakes right in
  /// front of it (otherwise it just keeps rolling off the top of the lane).
  static const double _barrierStopChance = 0.55;

  final _rng = Random();

  double balance = startBalance;
  double bet = 10;
  Difficulty difficulty = Difficulty.hardcore;
  GamePhase phase = GamePhase.idle;

  int currentLane = -1;
  int targetLane = -1;
  double jumpT = 0;
  bool _pendingSafe = true;
  bool atFinish = false;

  double winAmount = 0;
  double phaseTime = 0;
  double landPop = 0;
  double deathTime = -1;

  final List<Car> cars = [];
  final Map<int, double> barriers = {};
  double _spawnTimer = 0.6;
  double time = 0;

  WorldLayout? layout;
  double cameraX = 0;
  bool _cameraSnapped = false;

  List<double> get multipliers => difficulty.multipliers;
  int get laneCount => kLaneCount;

  bool get inRound =>
      phase == GamePhase.ready ||
      phase == GamePhase.jumping ||
      phase == GamePhase.dead ||
      phase == GamePhase.won;

  double get currentMultiplier =>
      currentLane >= 0 ? multipliers[min(currentLane, laneCount - 1)] : 0;

  double get cashOutValue {
    if (phase == GamePhase.dead) return 0;
    if (phase == GamePhase.won) return winAmount;
    return currentLane >= 0 ? bet * currentMultiplier : 0;
  }

  bool get canGo => phase == GamePhase.ready;
  bool get canCashOut => phase == GamePhase.ready && currentLane >= 0;
  bool get canPlay => phase == GamePhase.idle && bet <= balance + 1e-9;

  /// Chicken position index used by the renderer.
  double get chickenPosition {
    if (phase == GamePhase.jumping) {
      final from = currentLane.toDouble();
      final to = targetLane.toDouble();
      return from + (to - from) * _easeInOut(jumpT);
    }
    if (atFinish) return laneCount.toDouble();
    return currentLane.toDouble();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    balance = prefs.getDouble('balance') ?? startBalance;
    bet = prefs.getDouble('bet') ?? bet;
    final d = prefs.getInt('difficulty');
    if (d != null && d >= 0 && d < Difficulty.values.length) {
      difficulty = Difficulty.values[d];
    }
    if (balance < minBet) balance = startBalance;
    bet = bet.clamp(minBet, maxBet);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('balance', balance);
    await prefs.setDouble('bet', bet);
    await prefs.setInt('difficulty', difficulty.index);
  }

  void setLayout(double width, double height) {
    final l = layout;
    if (l != null && l.width == width && l.height == height) return;
    layout = WorldLayout(width, height);
    _cameraSnapped = false;
    cars.clear();
  }

  // ---------------------------------------------------------------- betting

  void setBet(double value) {
    if (phase != GamePhase.idle) return;
    bet = double.parse(value.clamp(minBet, maxBet).toStringAsFixed(2));
    _save();
    notifyListeners();
  }

  void setMinBet() => setBet(minBet);
  void setMaxBet() => setBet(min(maxBet, max(minBet, balance)));

  void setDifficulty(Difficulty d) {
    if (phase != GamePhase.idle || d == difficulty) return;
    difficulty = d;
    _save();
    notifyListeners();
  }

  void refill() {
    balance = startBalance;
    _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- round

  void play() {
    if (!canPlay) return;
    balance -= bet;
    phase = GamePhase.ready;
    currentLane = -1;
    atFinish = false;
    barriers.clear();
    _save();
    go();
  }

  void go() {
    if (!canGo) return;
    final next = currentLane + 1;
    if (next >= laneCount) return;
    targetLane = next;
    // Decision math lives in Rust (obfuscated ladder + survival derivation).
    // The host only has to provide a fresh 64-bit uniform random value.
    final r64 = (_rng.nextInt(1 << 32) & 0xFFFFFFFF) |
        ((_rng.nextInt(1 << 32) & 0xFFFFFFFF) << 32);
    _pendingSafe = RustMath.survives(difficulty, next, r64);
    _startJump();
  }

  void _startJump() {
    final l = layout!;
    phase = GamePhase.jumping;
    jumpT = 0;
    if (_pendingSafe) {
      _rushAwayCarsFor(targetLane, l);
    } else {
      _spawnDeathCar(l);
    }
    notifyListeners();
  }

  /// For a safe jump: make sure every car on the target lane is either
  /// already past the chicken by the time she lands, or ramped up enough to
  /// visibly race out of the way during the jump. Cars that would need an
  /// unrealistic speed are quietly removed - on a winning tile the hen is
  /// never run over, no matter how close traffic was.
  void _rushAwayCarsFor(int lane, WorldLayout l) {
    final clearBy = l.chickenY + l.chickenH * 0.55 + l.carH * 0.3;
    final timeLeft = jumpDuration * 0.9;
    final maxRealistic = l.height * 4.2;
    cars.removeWhere((c) {
      if (c.lane != lane) return false;
      if (c.front >= clearBy) return false; // already past the hen
      final needed = (clearBy - c.front) / timeLeft;
      if (needed > maxRealistic) return true; // too close, teleport away
      c.stopAt = null;
      c.speed = max(c.speed, needed * 1.1);
      return false;
    });
  }

  void _spawnDeathCar(WorldLayout l) {
    cars.removeWhere((c) => c.lane == targetLane && c.front < l.height * 0.2);
    final speed = l.height * 2.6;
    final impactFront = l.chickenY - l.chickenH * 0.1;
    final front = impactFront - speed * (jumpDuration + 0.08);
    cars.add(Car(
      lane: targetLane,
      front: front,
      speed: speed,
      sprite: _rng.nextInt(4),
      deadly: true,
    ));
  }

  void cashOut() {
    if (!canCashOut) return;
    _win();
  }

  void _win() {
    // Cashout cents come from Rust so the win amount stays exactly in sync
    // with the ladder it keeps internally — no f64 drift against balance.
    if (currentLane >= 0) {
      final betCents = (bet * 100).round();
      final winCents =
          RustMath.cashoutCents(difficulty, currentLane, betCents);
      winAmount = winCents / 100.0;
    } else {
      winAmount = 0;
    }
    balance += winAmount;
    phase = GamePhase.won;
    phaseTime = 0;
    _save();
    notifyListeners();
  }

  void _land() {
    currentLane = targetLane;
    jumpT = 0;
    landPop = 1;
    if (_pendingSafe) {
      final l = layout!;
      // Every safe landing drops a barrier - including on the very first
      // manhole - so the lane is permanently blocked from above.
      barriers[currentLane] = 0;
      // Any car still coming down this lane now hits the brakes at the
      // fence instead of running over the chicken.
      final stopAt = _barrierStopY(l);
      for (final c in cars) {
        if (c.lane != currentLane) continue;
        if (c.front >= stopAt) continue;
        c.stopAt = stopAt;
        c.speed = min(c.speed, l.height * 1.1);
      }
      if (currentLane >= laneCount - 1) {
        atFinish = true;
        _win();
        return;
      }
      phase = GamePhase.ready;
    } else {
      phase = GamePhase.ready;
    }
    notifyListeners();
  }

  /// Y of the stopped car's front bumper so it visually touches the barrier.
  double _barrierStopY(WorldLayout l) => l.barrierY - l.barrierH * 0.45;

  void _die() {
    phase = GamePhase.dead;
    phaseTime = 0;
    deathTime = 0;
    notifyListeners();
  }

  void _resetRound() {
    phase = GamePhase.idle;
    currentLane = -1;
    targetLane = -1;
    jumpT = 0;
    deathTime = -1;
    winAmount = 0;
    atFinish = false;
    barriers.clear();
    cars.removeWhere((c) => c.deadly);
    for (final c in cars) {
      if (c.stopAt != null) {
        c.stopAt = null;
        c.speed = layout!.height * (1.3 + _rng.nextDouble() * 0.6);
      }
    }
    _cameraSnapped = false;
    if (balance < minBet) balance = startBalance;
    if (bet > balance) bet = max(minBet, min(bet, balance));
    _save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- tick

  void update(double dt) {
    final l = layout;
    if (l == null) return;
    dt = min(dt, 1 / 20);
    time += dt;
    phaseTime += dt;
    if (landPop > 0) landPop = max(0, landPop - dt * 4);
    if (deathTime >= 0) deathTime += dt;
    barriers.updateAll((_, t) => t + dt);

    if (phase == GamePhase.jumping) {
      jumpT += dt / jumpDuration;
      if (jumpT >= 1) _land();
    }

    _updateCars(dt, l);
    _updateCamera(dt, l);

    if (phase == GamePhase.dead && phaseTime > 2.0) _resetRound();
    if (phase == GamePhase.won && phaseTime > 2.0) _resetRound();
  }

  void _updateCars(double dt, WorldLayout l) {
    for (final c in cars) {
      c.front += c.speed * dt;
      final stop = c.stopAt;
      if (stop != null && c.front > stop) {
        c.front = stop;
        c.speed = 0;
      }
      if (c.deadly &&
          deathTime < 0 &&
          phase != GamePhase.jumping &&
          currentLane == c.lane &&
          c.front >= l.chickenY - l.chickenH * 0.1) {
        _die();
      }
    }
    cars.removeWhere((c) => c.front - l.carH > l.height + 20);

    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
      _spawnTimer = 0.22 + _rng.nextDouble() * 0.55;
      _spawnAmbient(l);
    }
  }

  void _spawnAmbient(WorldLayout l) {
    final firstVisible = ((cameraX - l.roadStart) / l.laneW).floor();
    final lastVisible = ((cameraX + l.width - l.roadStart) / l.laneW).floor();
    final candidates = <int>[];
    for (var i = max(0, firstVisible);
        i <= min(laneCount - 1, lastVisible + 1);
        i++) {
      // Never spawn on the lane the chicken is standing/jumping to:
      // the stationary barrier/manhole takes care of visuals, and no new
      // car may run her over on a safe tile.
      if (i == currentLane) continue;
      if (phase == GamePhase.jumping && i == targetLane) continue;
      // Spacing: only block the lane if a previous car's rear is still
      // offscreen at the top. Once a car has fully entered the viewport the
      // next one can trail behind it, so two cars share a lane naturally.
      final tooClose = cars.any((c) =>
          c.lane == i && c.front < l.carH * 1.1 && c.stopAt == null);
      if (tooClose) continue;
      candidates.add(i);
    }
    if (candidates.isEmpty) return;
    final lane = candidates[_rng.nextInt(candidates.length)];
    final onBarrier = barriers.containsKey(lane);
    // Lanes with a barrier emit cars less often, but every car that does
    // appear ALWAYS brakes in front of the fence - traffic can never slip
    // through a barrier onto the chicken.
    if (onBarrier && _rng.nextDouble() > _barrierStopChance) return;
    final speed = l.height * (1.3 + _rng.nextDouble() * 0.7);
    cars.add(Car(
      lane: lane,
      front: -l.carH * 0.2,
      speed: speed,
      sprite: _rng.nextInt(4),
    )..stopAt = onBarrier ? _barrierStopY(l) : null);
  }

  void _updateCamera(double dt, WorldLayout l) {
    final chickenX = l.xOfPosition(chickenPosition, laneCount);
    final target = (chickenX - l.width * 0.185).clamp(0.0, l.worldW - l.width);
    if (!_cameraSnapped) {
      cameraX = target;
      _cameraSnapped = true;
      return;
    }
    final k = 1 - exp(-dt * 9);
    cameraX += (target - cameraX) * k;
  }
}

double _easeInOut(double t) {
  t = t.clamp(0.0, 1.0);
  return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2;
}
