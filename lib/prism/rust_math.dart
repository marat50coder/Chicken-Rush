// Game math pipe: all ladder arithmetic goes through librust_guard.
//
// The Difficulty enum stays in Dart (it is just a UI label), but every
// numeric answer — multipliers, kill probabilities, cashout amounts — is
// delegated to the Rust side.

import '../game/difficulty.dart';
import 'rust_guard.dart';

abstract final class RustMath {
  /// 18 ladder multipliers for the given difficulty.
  static List<double> multipliers(Difficulty d) =>
      RustGuard.instance.mults(d.index);

  /// Returns true if the chicken survives the hop onto [lane] under [d].
  /// Pass a fresh 64-bit random value (any uniform source works).
  static bool survives(Difficulty d, int lane, int rand64) =>
      RustGuard.instance.decide(d.index, lane, rand64);

  /// Cashout value for landing on [lane] with [betCents] staked.
  /// Returns an integer cent count to avoid f64 drift when added to balance.
  static int cashoutCents(Difficulty d, int lane, int betCents) =>
      RustGuard.instance.cashoutCents(d.index, lane, betCents);

  /// Tier-rounded multiplier (used by display helpers if ever needed).
  static double roundMult(double v) => RustGuard.instance.roundMult(v);
}
