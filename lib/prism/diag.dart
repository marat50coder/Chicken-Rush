// Diagnostic logger — survives release builds on purpose.
//
// Every message is tagged `CR.<component>` so logcat / Debug Console can
// grep them easily:
//
//   adb logcat -c && adb logcat | rg "CR\\."
//
// Flip `_kDiag` to false once the gray-part pipeline is stable to silence
// the stream in release builds without touching call sites.

import 'dart:developer' as developer;

const bool _kDiag = true;

/// Emit a diagnostic line. Appears in:
///   • VSCode / Cursor Debug Console (via developer.log)
///   • `adb logcat` under tag `flutter` with `[CR.<tag>]` prefix
///   • `flutter logs` output
///
/// NOT wrapped in assert, so it survives `--release`.
void diag(String tag, String msg) {
  if (!_kDiag) return;
  final line = '[CR.$tag] $msg';
  developer.log(line, name: 'CR.$tag');
  // ignore: avoid_print
  print(line);
}
