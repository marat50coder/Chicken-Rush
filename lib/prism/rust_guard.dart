// Raw FFI binding to librust_guard. Keep this file *the only* place that
// touches `dart:ffi`; everything else goes through the typed helpers in
// sealed_bytes.dart / rust_math.dart.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

typedef _FetchNative = Uint32 Function(Uint32 id, Pointer<Uint8> out, Uint32 cap);
typedef _FetchDart   = int    Function(int id,    Pointer<Uint8> out, int cap);

typedef _PingNative  = Uint32 Function(Uint32 id);
typedef _PingDart    = int    Function(int id);

typedef _AbiNative   = Int32  Function();
typedef _AbiDart     = int    Function();

typedef _MultsNative = Uint32 Function(Uint32 diff, Pointer<Double> out, Uint32 cap);
typedef _MultsDart   = int    Function(int diff,    Pointer<Double> out, int cap);

typedef _DecideNative = Uint32 Function(Uint32 diff, Uint32 lane, Uint64 rand);
typedef _DecideDart   = int    Function(int diff,    int lane,    int rand);

typedef _CashoutNative = Uint64 Function(Uint32 diff, Uint32 lane, Uint64 bet);
typedef _CashoutDart   = int    Function(int diff,    int lane,    int bet);

typedef _RoundNative = Double Function(Double v);
typedef _RoundDart   = double Function(double v);

typedef _PackNative = Uint32 Function(
    Pointer<Uint8> body, Uint32 bodyLen, Pointer<Uint8> nonce,
    Pointer<Uint8> out, Uint32 outCap);
typedef _PackDart = int Function(
    Pointer<Uint8> body, int bodyLen, Pointer<Uint8> nonce,
    Pointer<Uint8> out, int outCap);

/// Low-level handle to librust_guard. Treat as a singleton via [instance].
class RustGuard {
  RustGuard._(DynamicLibrary lib)
      : _fetch   = lib.lookupFunction<_FetchNative,   _FetchDart>  ('rg_fetch'),
        _ping    = lib.lookupFunction<_PingNative,    _PingDart>   ('rg_ping'),
        _abi     = lib.lookupFunction<_AbiNative,     _AbiDart>    ('rg_abi'),
        _mults   = lib.lookupFunction<_MultsNative,   _MultsDart>  ('rg_mults'),
        _decide  = lib.lookupFunction<_DecideNative,  _DecideDart> ('rg_decide'),
        _cashout = lib.lookupFunction<_CashoutNative, _CashoutDart>('rg_cashout_cents'),
        _round   = lib.lookupFunction<_RoundNative,   _RoundDart>  ('rg_round_mult'),
        _pack    = lib.lookupFunction<_PackNative,    _PackDart>   ('rg_pack');

  static RustGuard? _instance;

  /// Opens the native lib; throws if it is missing or the ABI version is
  /// not what Dart expects — a loud failure is **required**: without the
  /// `.so` all sealed strings would be empty and the app would silently
  /// hand every user a broken experience.
  static RustGuard get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final lib = _open();
    final guard = RustGuard._(lib);
    final abi = guard._abi();
    if (abi != 1) {
      throw StateError('rust_guard ABI mismatch: expected 1, got $abi');
    }
    if (guard._ping(1) != 1) {
      throw StateError('rust_guard self-check failed');
    }
    _instance = guard;
    return guard;
  }

  final _FetchDart _fetch;
  final _PingDart _ping;
  final _AbiDart _abi;
  final _MultsDart _mults;
  final _DecideDart _decide;
  final _CashoutDart _cashout;
  final _RoundDart _round;
  final _PackDart _pack;

  static DynamicLibrary _open() {
    if (Platform.isAndroid) return DynamicLibrary.open('librust_guard.so');
    if (Platform.isLinux)   return DynamicLibrary.open('librust_guard.so');
    if (Platform.isMacOS)   return DynamicLibrary.open('librust_guard.dylib');
    if (Platform.isWindows) return DynamicLibrary.open('rust_guard.dll');
    // iOS: library is statically linked into the host binary.
    if (Platform.isIOS) return DynamicLibrary.process();
    throw UnsupportedError('rust_guard not configured for ${Platform.operatingSystem}');
  }

  /// Decrypt and return the sealed string with the given id.
  List<int> fetch(int id) {
    // Grow-on-demand: start small, retry if the real length doesn't fit.
    var cap = 256;
    while (true) {
      final buf = calloc<Uint8>(cap);
      try {
        final n = _fetch(id, buf, cap);
        if (n == 0) return const <int>[];
        if (n <= cap) {
          return buf.asTypedList(n).toList(growable: false);
        }
        cap = n;
      } finally {
        calloc.free(buf);
      }
    }
  }

  /// Convenience: fetch and decode as UTF-8.
  String fetchString(int id) => utf8.decode(fetch(id), allowMalformed: false);

  /// Fetch the 18-element multiplier ladder for a difficulty.
  List<double> mults(int diff) {
    const n = 18;
    final buf = calloc<Double>(n);
    try {
      final got = _mults(diff, buf, n);
      if (got != n) {
        throw StateError('rg_mults returned $got, expected $n');
      }
      return List<double>.generate(n, (i) => buf[i], growable: false);
    } finally {
      calloc.free(buf);
    }
  }

  /// Returns true if the chicken survives the hop. `rand64` must be a fresh
  /// uniform 64-bit value from the host RNG.
  bool decide(int diff, int lane, int rand64) =>
      _decide(diff, lane, rand64) == 1;

  int cashoutCents(int diff, int lane, int betCents) =>
      _cashout(diff, lane, betCents);

  double roundMult(double v) => _round(v);

  /// Pack a wire envelope for the sealed endpoint. `nonce` must be 16 bytes.
  List<int> pack(List<int> body, List<int> nonce) {
    if (nonce.length != 16) {
      throw ArgumentError('nonce must be 16 bytes');
    }
    final bodyPtr = calloc<Uint8>(body.length);
    final noncePtr = calloc<Uint8>(16);
    try {
      bodyPtr.asTypedList(body.length).setAll(0, body);
      noncePtr.asTypedList(16).setAll(0, nonce);
      var cap = body.length + 256;
      while (true) {
        final out = calloc<Uint8>(cap);
        try {
          final n = _pack(bodyPtr, body.length, noncePtr, out, cap);
          if (n == 0) return const <int>[];
          if (n <= cap) {
            return out.asTypedList(n).toList(growable: false);
          }
          cap = n;
        } finally {
          calloc.free(out);
        }
      }
    } finally {
      calloc.free(bodyPtr);
      calloc.free(noncePtr);
    }
  }
}
