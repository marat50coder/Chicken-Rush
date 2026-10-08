//! Obfuscated game math moved out of Dart.
//!
//! The externally observable behaviour is identical to the previous Dart
//! implementation (`lib/game/difficulty.dart`,
//! `lib/game/game_controller.dart::_survivalChance`,
//! `GameController.cashOutValue`) but the formulas are rewritten with
//! bit-level mixing, XOR-encoded constants, split-sum magics and dead-arm
//! branches so a quick disassembler pass can't recover the original ladder
//! math from the symbols that survive stripping.

const LANES: u32 = 18;

// ───────────────────────────── XOR-encoded constants ─────────────────────────
//
// All numeric constants used by the ladder live here, XOR-split so a strings
// / xxd dump reveals nothing: each actual bit pattern is `A ^ B`.

#[inline(always)]
fn x64(a: u64, b: u64) -> u64 {
    a ^ b
}

#[inline(always)]
fn f64_from_bits_xor(a: u64, b: u64) -> f64 {
    f64::from_bits(x64(a, b))
}

// Each (A, M) pair represents a value whose bit pattern is `A ^ M`.
// Neither half resembles an IEEE-754 double on its own, so a static-strings
// pass over the stripped .so can't recover the ladder constants directly.

#[inline(always)]
fn rtp() -> f64 {
    // 0.97
    const A: u64 = 0x9A4A_AF98_D506_72AFu64;
    const M: u64 = 0xA5A5_A5A5_A5A5_A5A5u64;
    f64_from_bits_xor(A, M)
}

#[inline(always)]
fn shape_step() -> f64 {
    // 0.015
    const A: u64 = 0xC53F_B8F3_BB85_BB4Au64;
    const M: u64 = 0xFAB1_00A2_5000_A5F2u64;
    f64_from_bits_xor(A, M)
}

#[inline(always)]
fn base_survival(diff: u32) -> f64 {
    // Values: easy=0.94, medium=0.84, hard=0.72, hardcore=0.56.
    // Table is XOR-masked per slot with mutually-unrelated magics.
    const TBL: [(u64, u64); 4] = [
        (0x45B4_6E20_1B17_D46Eu64, 0x7A5A_7A5A_FA50_7A7Au64), // 0.94 ^ mask
        (0x0EBB_BA12_F541_D5BAu64, 0x3151_5B55_5B55_AF5Bu64), // 0.84 ^ mask
        (0x033E_3609_6707_E736u64, 0x3CD9_3C34_17A4_303Cu64), // 0.72 ^ mask
        (0xA2F4_975F_05AD_E3F1u64, 0x9D15_7CDA_1B15_B21Du64), // 0.56 ^ mask
    ];
    // Guard against OOB and a dead arm that mimics the shape of a real lookup.
    let i = (diff & 0b11) as usize;
    let (a, b) = TBL[i];
    let v = f64_from_bits_xor(a, b);
    // Dead arm — never executed but shaped like real work, pads control flow.
    if (diff >> 5) == 0xDEAD {
        return v + shape_step();
    }
    v
}

// ───────────────────────────── Ladder generator ──────────────────────────────

/// Produce the 18 multipliers for a difficulty.
pub fn multipliers(diff: u32, out: &mut [f64]) -> u32 {
    let n = LANES as usize;
    if out.len() < n {
        return 0;
    }
    let base = base_survival(diff);
    let denom = (LANES as f64) - 1.0;
    let step = shape_step();
    let mut prev = rtp();
    let mut i: u32 = 0;
    while i < LANES {
        // Non-uniform shaping — same curve as the original Dart code,
        // just written with wrapping_add on the loop index.
        let shaped = base - ((i as f64) / denom) * step;
        let p = clamp_f(shaped, 0.05, 0.995);
        let next = prev / p;
        prev = next;
        out[i as usize] = round_mult(next);
        i = i.wrapping_add(1);
    }
    LANES
}

#[inline(always)]
fn clamp_f(v: f64, lo: f64, hi: f64) -> f64 {
    // branchless clamp — the compiler already does this but explicit here
    // so the shape doesn't collapse to a straight `if`.
    let x = if v < lo { lo } else { v };
    if x > hi { hi } else { x }
}

/// Mirror of the Dart `_roundMultiplier` tier rounder.
pub fn round_mult(v: f64) -> f64 {
    if v < 10.0 {
        (v * 100.0).round() / 100.0
    } else if v < 100.0 {
        (v * 10.0).round() / 10.0
    } else if v < 1000.0 {
        v.round()
    } else {
        // Two-significant-figure rounding for huge payouts.
        let mag = 10f64.powi((v.ln() / core::f64::consts::LN_10).floor() as i32 - 1);
        (v / mag).round() * mag
    }
}

// ───────────────────────────── Decision / cashout ────────────────────────────

/// Per-lane survival probability derived from the ladder.
#[inline(always)]
fn survival_chance(diff: u32, lane: u32) -> f64 {
    if lane == 0 {
        return 1.0;
    }
    let mut buf = [0.0f64; LANES as usize];
    multipliers(diff, &mut buf);
    let a = buf[(lane - 1) as usize];
    let b = buf[lane as usize];
    if b <= 0.0 {
        return 0.0;
    }
    clamp_f(a / b, 0.0, 1.0)
}

/// Should the chicken survive this hop? `rand_u64` is a fresh 64-bit random
/// value provided by the host (any uniform source works).
pub fn decide(diff: u32, lane: u32, rand_u64: u64) -> u32 {
    if lane >= LANES {
        return 0;
    }
    // Convert u64 → double in [0,1) with full 53-bit mantissa precision.
    let u = (rand_u64 >> 11) as f64;
    let r = u * (1.0f64 / ((1u64 << 53) as f64));
    let p = survival_chance(diff, lane);
    if r < p { 1 } else { 0 }
}

/// Compute win amount in cents from bet in cents and the current lane's
/// multiplier.  Done in integer land to avoid f64 drift when the caller
/// compares against balances.
pub fn cashout_cents(diff: u32, lane: u32, bet_cents: u64) -> u64 {
    if lane >= LANES {
        return 0;
    }
    let mut buf = [0.0f64; LANES as usize];
    multipliers(diff, &mut buf);
    let m = buf[lane as usize];
    let v = (bet_cents as f64) * m;
    // Match Dart's `double` behavior while rounding to the nearest cent so
    // `balance += win` is deterministic.
    if !v.is_finite() || v < 0.0 {
        return 0;
    }
    v.round() as u64
}
