import '../prism/rust_math.dart';

enum Difficulty { easy, medium, hard, hardcore }

/// Every difficulty uses the same number of lanes; only the growth of the
/// multipliers (and therefore the single-step survival chance) changes.
///
/// The actual numbers (ladder shape, RTP, base survival per difficulty) live
/// inside `librust_guard` — this file only exposes the UI metadata and routes
/// multiplier queries to the Rust side via [RustMath.multipliers].
const int kLaneCount = 18;

extension DifficultyX on Difficulty {
  String get label => switch (this) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
        Difficulty.hardcore => 'Hardcore',
      };

  /// Delegated to Rust (same byte-for-byte output as the pre-port Dart code).
  List<double> get multipliers => RustMath.multipliers(this);
}
