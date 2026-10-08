//! rust_guard — Flutter FFI surface.
//!
//! All exported `rg_*` symbols take raw pointers so the Dart side only needs
//! `dart:ffi`. Short cryptic names on purpose: they survive `strip = symbols`
//! and shouldn't hint at what they do.

pub mod math;
pub mod pack;
pub mod sealed;

use std::os::raw::{c_int, c_uchar};

// ─────────────────────────────── string unsealing ────────────────────────────

/// Write the plaintext bytes for `id` into `out[..cap]`. Returns the actual
/// plaintext length (which may exceed `cap` — in that case nothing is written
/// and the caller should re-allocate). Returns 0 on unknown id.
///
/// # Safety
/// `out` must be valid for writes of `cap` bytes (or null if cap == 0).
#[no_mangle]
pub unsafe extern "C" fn rg_fetch(id: u32, out: *mut c_uchar, cap: u32) -> u32 {
    let bytes = match sealed::unseal(id) {
        Some(b) => b,
        None => return 0,
    };
    let n = bytes.len();
    if n <= cap as usize && !out.is_null() {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), out, n);
    }
    n as u32
}

/// Returns 1 iff the sealed blob round-trips for the id (plaintext decrypts to
/// the expected length). Dart uses this as a canary to prove the .so loaded
/// correctly, and to crash loud if someone shipped an APK without the lib.
#[no_mangle]
pub extern "C" fn rg_ping(id: u32) -> u32 {
    match sealed::unseal(id) {
        Some(b) if !b.is_empty() => 1,
        _ => 0,
    }
}

// ───────────────────────────────── game math ─────────────────────────────────

/// Write the 18 ladder multipliers for `diff` into `out`.
/// Returns the count written (0 if `cap` < 18 or diff is OOB).
///
/// # Safety
/// `out` must be valid for `cap` f64 writes.
#[no_mangle]
pub unsafe extern "C" fn rg_mults(diff: u32, out: *mut f64, cap: u32) -> u32 {
    if out.is_null() || cap < 18 {
        return 0;
    }
    let slice = std::slice::from_raw_parts_mut(out, cap as usize);
    math::multipliers(diff, slice)
}

/// Returns 1 if the chicken survives a hop onto `lane` under `diff`, else 0.
/// `rand_u64` is a fresh uniform 64-bit value supplied by the host.
#[no_mangle]
pub extern "C" fn rg_decide(diff: u32, lane: u32, rand_u64: u64) -> u32 {
    math::decide(diff, lane, rand_u64)
}

/// Cash-out amount in integer cents for `(diff, lane, bet_cents)`.
#[no_mangle]
pub extern "C" fn rg_cashout_cents(diff: u32, lane: u32, bet_cents: u64) -> u64 {
    math::cashout_cents(diff, lane, bet_cents)
}

/// Round a multiplier to the ladder's tiered precision.
#[no_mangle]
pub extern "C" fn rg_round_mult(v: f64) -> f64 {
    math::round_mult(v)
}

// ────────────────────────────── envelope packer ──────────────────────────────

/// Pack `body` (verbatim JSON bytes) + `nonce[16]` into an edge/sync wire
/// envelope using sealed field names/schema/secret. Returns the written
/// length; if the envelope is bigger than `out_cap`, nothing is written and
/// the caller must retry with a larger buffer. Returns 0 on failure.
///
/// # Safety
/// `body`, `nonce` and `out` must point to valid buffers of the stated sizes.
#[no_mangle]
pub unsafe extern "C" fn rg_pack(
    body: *const c_uchar,
    body_len: u32,
    nonce: *const c_uchar,
    out: *mut c_uchar,
    out_cap: u32,
) -> u32 {
    if body.is_null() || nonce.is_null() {
        return 0;
    }
    let body_slice = std::slice::from_raw_parts(body, body_len as usize);
    let mut nonce_arr = [0u8; 16];
    nonce_arr.copy_from_slice(std::slice::from_raw_parts(nonce, 16));
    let envelope = match pack::pack_envelope(body_slice, &nonce_arr) {
        Some(v) => v,
        None => return 0,
    };
    let n = envelope.len();
    if n <= out_cap as usize && !out.is_null() {
        std::ptr::copy_nonoverlapping(envelope.as_ptr(), out, n);
    }
    n as u32
}

/// ABI/version marker. Bump when the FFI surface changes so a mismatched
/// `.so` is caught at startup rather than silently corrupted.
#[no_mangle]
pub extern "C" fn rg_abi() -> c_int {
    1
}
