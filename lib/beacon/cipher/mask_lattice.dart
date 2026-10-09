// ===================================================================
// MaskLattice — our build-time string obfuscator for Dart literals.
//
// Any plaintext still kept in Dart (dev builds only, placeholders) goes
// through this. The design is intentionally different from the sibling
// template: three independent rotor states advance by distinct update
// rules per step, and the output byte combines rotor outputs with a
// position-nibble rotation. This gives a very different control-flow
// footprint from classical RC4/FNV/Weyl constructions.
//
// NOTE: real secrets never live in Dart — they come from the Rust
// sealed slot. MaskLattice is only used for ancillary strings that
// benefit from not showing up in `strings libapp.so` greps.
// ===================================================================

class MaskLattice {
  /// Decode a lattice-ciphered buffer with a 4-byte salt.
  static String decode(List<int> salt, List<int> body) {
    assert(salt.length == 4);
    var r0 = _mix(salt[0] | (salt[1] << 8) | (salt[2] << 16) | (salt[3] << 24));
    var r1 = _mix(r0 ^ 0xA2C7_3F91);
    var r2 = _mix(r1 ^ 0x51D0_6B23);
    final out = <int>[];
    for (var i = 0; i < body.length; i++) {
      // Advance rotors — three different update laws.
      r0 = ((r0 ^ (r0 >> 7)) + 0xC2B2_AE3D) & 0xFFFF_FFFF;
      r1 = (r1 + ((r0 << 3) & 0xFFFF_FFFF)) & 0xFFFF_FFFF;
      r2 = (_rotl32(r2, 11) ^ (r1 >> 5)) & 0xFFFF_FFFF;

      final mix = (r0 ^ r1 ^ r2) & 0xFF;
      final nib = i & 7;
      final b = _rotr8(body[i] ^ mix, nib);
      out.add(b);
    }
    return String.fromCharCodes(out);
  }

  /// Encode (host side — used by build helpers / tests only).
  static List<int> encode(List<int> salt, String plain) {
    assert(salt.length == 4);
    var r0 = _mix(salt[0] | (salt[1] << 8) | (salt[2] << 16) | (salt[3] << 24));
    var r1 = _mix(r0 ^ 0xA2C7_3F91);
    var r2 = _mix(r1 ^ 0x51D0_6B23);
    final out = <int>[];
    final data = plain.codeUnits;
    for (var i = 0; i < data.length; i++) {
      r0 = ((r0 ^ (r0 >> 7)) + 0xC2B2_AE3D) & 0xFFFF_FFFF;
      r1 = (r1 + ((r0 << 3) & 0xFFFF_FFFF)) & 0xFFFF_FFFF;
      r2 = (_rotl32(r2, 11) ^ (r1 >> 5)) & 0xFFFF_FFFF;
      final mix = (r0 ^ r1 ^ r2) & 0xFF;
      final nib = i & 7;
      out.add(_rotl8(data[i], nib) ^ mix);
    }
    return out;
  }

  static int _mix(int x) {
    x = (x ^ (x >> 16)) & 0xFFFF_FFFF;
    x = (x * 0x7FEB_352D) & 0xFFFF_FFFF;
    x = (x ^ (x >> 15)) & 0xFFFF_FFFF;
    x = (x * 0x846C_A68B) & 0xFFFF_FFFF;
    x = (x ^ (x >> 16)) & 0xFFFF_FFFF;
    return x;
  }

  static int _rotl32(int v, int n) =>
      ((v << n) | (v >> (32 - n))) & 0xFFFF_FFFF;

  static int _rotl8(int v, int n) {
    n &= 7;
    return ((v << n) | (v >> (8 - n))) & 0xFF;
  }

  static int _rotr8(int v, int n) {
    n &= 7;
    return ((v >> n) | (v << (8 - n))) & 0xFF;
  }
}
